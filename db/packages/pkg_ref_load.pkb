create or replace package body pkg_ref_load as

  ------------------------------------------------------------------------------
  function to_coord(p_value in varchar2) return number deterministic is
    l_value     varchar2(60) := trim(p_value);
    l_negative  boolean;
    l_number    number;
  begin
    if l_value is null or not regexp_like(l_value, '^-?\d{1,3}(\.\d+)?$') then
      return null;
    end if;

    -- The sign is handled apart, so the number format below only ever sees digits.
    l_negative := substr(l_value, 1, 1) = '-';
    l_value    := ltrim(l_value, '-');
    -- At most 10 decimals: enough for any coordinate, and it keeps the format fixed.
    l_value    := regexp_substr(l_value, '^\d{1,3}(\.\d{1,10})?');

    -- Explicit NLS: '.' is the decimal separator whatever the session says.
    l_number := to_number(l_value, '999D9999999999', 'NLS_NUMERIC_CHARACTERS=''.,''');
    return round(case when l_negative then -l_number else l_number end, 6);
  end to_coord;

  ------------------------------------------------------------------------------
  function count_rejected(p_anac_file in varchar2) return pls_integer is
    l_airlines  pls_integer;
    l_airports  pls_integer;
  begin
    select count(*) into l_airlines
      from stg_ref_airline s
     where s.src_file = p_anac_file
       and (not regexp_like(nvl(upper(trim(s.airline_icao)), '#'), '^[A-Z0-9]{3}$')
            or trim(s.airline_name) is null);

    select count(*) into l_airports
      from stg_ref_airport_anac s
     where s.src_file = p_anac_file
       and not regexp_like(nvl(upper(trim(s.airport_icao)), '#'), '^[A-Z0-9]{4}$');

    return l_airlines + l_airports;
  end count_rejected;

  ------------------------------------------------------------------------------
  -- Airlines: one row per ICAO code, with the name of the most recent year.
  function refresh_airlines(p_anac_file in varchar2) return pls_integer is
  begin
    merge into ref_airline r
    using (
      select airline_icao, airline_name, nationality, ref_year
        from (select upper(trim(s.airline_icao))              as airline_icao,
                     substr(trim(s.airline_name), 1, 200)      as airline_name,
                     substr(upper(trim(s.nationality)), 1, 20) as nationality,
                     case when regexp_like(trim(s.ref_year), '^\d{4}$')
                          then to_number(trim(s.ref_year)) end as ref_year,
                     row_number() over (
                       partition by upper(trim(s.airline_icao))
                       order by case when regexp_like(trim(s.ref_year), '^\d{4}$')
                                     then to_number(trim(s.ref_year)) end desc nulls last,
                                trim(s.airline_name)) as rn
                from stg_ref_airline s
               where s.src_file = p_anac_file
                 and regexp_like(upper(trim(s.airline_icao)), '^[A-Z0-9]{3}$')
                 and trim(s.airline_name) is not null)
       where rn = 1
    ) s
       on (r.airline_icao = s.airline_icao)
     when matched then update
          set r.airline_name = s.airline_name,
              r.nationality  = s.nationality,
              r.last_year    = s.ref_year,
              r.updated_at   = systimestamp
     when not matched then insert (airline_icao, airline_name, nationality, last_year)
          values (s.airline_icao, s.airline_name, s.nationality, s.ref_year);

    return sql%rowcount;
  end refresh_airlines;

  ------------------------------------------------------------------------------
  -- Airports: ANAC (latest year per code) full outer join OurAirports (best row per code).
  function refresh_airports(p_anac_file in varchar2, p_oa_file in varchar2) return pls_integer is
  begin
    merge into ref_airport r
    using (
      with anac as (
        select airport_icao, city, state_uf, country_name, continent
          from (select upper(trim(s.airport_icao))            as airport_icao,
                       substr(trim(s.airport_name), 1, 200)    as city,
                       case when regexp_like(upper(trim(s.state_uf)), '^[A-Z]{2}$')
                            then upper(trim(s.state_uf)) end   as state_uf,
                       substr(trim(s.country_name), 1, 100)    as country_name,
                       substr(trim(s.continent), 1, 30)        as continent,
                       row_number() over (
                         partition by upper(trim(s.airport_icao))
                         order by case when regexp_like(trim(s.ref_year), '^\d{4}$')
                                       then to_number(trim(s.ref_year)) end desc nulls last,
                                  trim(s.airport_name)) as rn
                  from stg_ref_airport_anac s
                 where s.src_file = p_anac_file
                   and regexp_like(upper(trim(s.airport_icao)), '^[A-Z0-9]{4}$'))
         where rn = 1
      ),
      oa as (
        select s.line_no, s.iata_code, s.airport_name, s.municipality, s.iso_country,
               s.latitude, s.longitude, s.airport_type,
               upper(trim(s.icao_code)) as code_icao,
               upper(trim(s.ident))     as code_ident,
               upper(trim(s.gps_code))  as code_gps
          from stg_ref_airport_oa s
         where s.src_file = p_oa_file
      ),
      -- One candidate per (row, code it could be known by), with the strength of the match.
      oa_codes as (
        select oa.code_icao as airport_icao, 1 as priority, oa.*
          from oa where regexp_like(oa.code_icao, '^[A-Z0-9]{4}$')
        union all
        select oa.code_ident, 2, oa.*
          from oa where regexp_like(oa.code_ident, '^[A-Z0-9]{4}$')
        union all
        select oa.code_gps, 3, oa.*
          from oa where regexp_like(oa.code_gps, '^[A-Z0-9]{4}$')
      ),
      oa_best as (
        select b.airport_icao,
               substr(trim(b.airport_name), 1, 200)              as airport_name,
               substr(trim(b.municipality), 1, 200)              as municipality,
               case when regexp_like(upper(trim(b.iso_country)), '^[A-Z]{2}$')
                    then upper(trim(b.iso_country)) end          as iso_country,
               case when regexp_like(upper(trim(b.iata_code)), '^[A-Z0-9]{3}$')
                    then upper(trim(b.iata_code)) end            as iata_code,
               pkg_ref_load.to_coord(b.latitude)                 as latitude,
               pkg_ref_load.to_coord(b.longitude)                as longitude
          from (select c.*,
                       row_number() over (
                         partition by c.airport_icao
                         order by c.priority,
                                  case c.airport_type
                                    when 'large_airport'  then 1
                                    when 'medium_airport' then 2
                                    when 'small_airport'  then 3
                                    else 4
                                  end,
                                  c.line_no) as rn
                  from oa_codes c) b
         where b.rn = 1
      )
      select coalesce(a.airport_icao, o.airport_icao)  as airport_icao,
             o.airport_name,
             coalesce(a.city, o.municipality)          as city,
             a.state_uf,
             a.country_name,
             o.iso_country,
             a.continent,
             o.iata_code,
             o.latitude,
             o.longitude,
             case
               when a.airport_icao is not null and o.airport_icao is not null then 'ANAC+OURAIRPORTS'
               when a.airport_icao is not null then 'ANAC'
               else 'OURAIRPORTS'
             end                                       as name_source
        from anac a
        full outer join oa_best o on o.airport_icao = a.airport_icao
    ) s
       on (r.airport_icao = s.airport_icao)
     when matched then update
          set r.airport_name = s.airport_name,
              r.city         = s.city,
              r.state_uf     = s.state_uf,
              r.country_name = s.country_name,
              r.iso_country  = s.iso_country,
              r.continent    = s.continent,
              r.iata_code    = s.iata_code,
              r.latitude     = s.latitude,
              r.longitude    = s.longitude,
              r.name_source  = s.name_source,
              r.updated_at   = systimestamp
     when not matched then insert (
            airport_icao, airport_name, city, state_uf, country_name, iso_country,
            continent, iata_code, latitude, longitude, name_source)
          values (
            s.airport_icao, s.airport_name, s.city, s.state_uf, s.country_name, s.iso_country,
            s.continent, s.iata_code, s.latitude, s.longitude, s.name_source);

    return sql%rowcount;
  end refresh_airports;

  ------------------------------------------------------------------------------
  function sync_core return pls_integer is
    l_airlines pls_integer;
  begin
    merge into core_airline c
    using ref_airline r
       on (c.airline_icao = r.airline_icao)
     when matched then update
          set c.airline_name = substrb(r.airline_name, 1, 200);
    l_airlines := sql%rowcount;

    -- CORE_AIRPORT keeps one display name: the official one, else the city.
    merge into core_airport c
    using ref_airport r
       on (c.airport_icao = r.airport_icao)
     when matched then update
          set c.airport_name = substrb(coalesce(r.airport_name, r.city), 1, 200),
              c.country_code = r.iso_country;

    return l_airlines + sql%rowcount;
  end sync_core;

  ------------------------------------------------------------------------------
  function process_reference(
    p_anac_file  in varchar2,
    p_oa_file    in varchar2
  ) return number is
    l_run_id     number;
    l_staged     pls_integer;
    l_staged_oa  pls_integer;
    l_rejected   pls_integer;
    l_airlines   pls_integer;
    l_airports   pls_integer;
    l_synced     pls_integer;
    l_error      varchar2(4000);
  begin
    l_run_id := pkg_load_log.start_run(substr(p_anac_file || ' + ' || p_oa_file, 1, 100));
    savepoint sp_process_reference;

    begin
      select count(*) into l_staged from stg_ref_airline where src_file = p_anac_file;
      select l_staged + count(*) into l_staged from stg_ref_airport_anac where src_file = p_anac_file;
      select count(*) into l_staged_oa from stg_ref_airport_oa where src_file = p_oa_file;

      if l_staged = 0 or l_staged_oa = 0 then
        raise_application_error(-20002,
          'Both reference files must be staged: "' || p_anac_file || '" and "' || p_oa_file || '".');
      end if;

      l_rejected := count_rejected(p_anac_file);
      l_airlines := refresh_airlines(p_anac_file);
      l_airports := refresh_airports(p_anac_file, p_oa_file);
      l_synced   := sync_core;

      pkg_load_log.mark_success(
        p_run_id    => l_run_id,
        p_staged    => l_staged + l_staged_oa,
        p_loaded    => l_airlines + l_airports,
        p_rejected  => l_rejected,
        p_duplicate => 0);

      return l_run_id;
    exception
      when others then
        l_error := substr(sqlerrm || chr(10) || dbms_utility.format_error_backtrace, 1, 4000);
        rollback to savepoint sp_process_reference;
        pkg_load_log.mark_failed(l_run_id, l_error);
        raise;
    end;
  end process_reference;

end pkg_ref_load;
/
