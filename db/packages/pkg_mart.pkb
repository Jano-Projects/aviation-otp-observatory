create or replace package body pkg_mart as

  ------------------------------------------------------------------------------
  procedure build_dim_date(p_from in date, p_to in date) is
    l_from  date := trunc(p_from);
    l_to    date := trunc(p_to);
  begin
    if l_from is null or l_to is null or l_to < l_from then
      return;
    end if;

    -- One row per day generated with CONNECT BY LEVEL; every attribute is computed
    -- with NLS-independent expressions ('IW', 'Q', date arithmetic), never with
    -- to_char(..., 'DAY'), whose result depends on the session language.
    merge into dim_date d
    using (
      select to_number(to_char(dt, 'YYYYMMDD'))  as date_key,
             dt                                  as full_date,
             extract(year from dt)               as year_num,
             to_number(to_char(dt, 'Q'))         as quarter_num,
             extract(month from dt)              as month_num,
             trunc(dt, 'MM')                     as month_start,
             extract(day from dt)                as day_of_month,
             trunc(dt) - trunc(dt, 'IW') + 1     as iso_day_of_week,
             to_number(to_char(dt, 'IW'))        as iso_week
        from (select l_from + level - 1 as dt
                from dual
             connect by level <= l_to - l_from + 1)
    ) s
       on (d.date_key = s.date_key)
     when not matched then insert (
            date_key, full_date, year_num, quarter_num, month_num, month_name_pt, month_start,
            day_of_month, iso_day_of_week, day_name_pt, is_weekend, iso_week)
          values (
            s.date_key, s.full_date, s.year_num, s.quarter_num, s.month_num,
            case s.month_num
              when 1 then 'janeiro'  when 2 then 'fevereiro' when 3 then 'março'
              when 4 then 'abril'    when 5 then 'maio'      when 6 then 'junho'
              when 7 then 'julho'    when 8 then 'agosto'    when 9 then 'setembro'
              when 10 then 'outubro' when 11 then 'novembro' else 'dezembro'
            end,
            s.month_start, s.day_of_month, s.iso_day_of_week,
            case s.iso_day_of_week
              when 1 then 'segunda-feira' when 2 then 'terça-feira' when 3 then 'quarta-feira'
              when 4 then 'quinta-feira'  when 5 then 'sexta-feira' when 6 then 'sábado'
              else 'domingo'
            end,
            case when s.iso_day_of_week >= 6 then 1 else 0 end,
            s.iso_week);
  end build_dim_date;

  ------------------------------------------------------------------------------
  function refresh_dimensions return pls_integer is
    l_rows pls_integer := 0;
  begin
    merge into dim_hour h
    using (select level - 1 as hour_key,
                  case
                    when level - 1 < 6  then 'madrugada'
                    when level - 1 < 12 then 'manhã'
                    when level - 1 < 18 then 'tarde'
                    else 'noite'
                  end as period_pt
             from dual
          connect by level <= 24) s
       on (h.hour_key = s.hour_key)
     when matched then update set h.period_pt = s.period_pt
     when not matched then insert (hour_key, period_pt) values (s.hour_key, s.period_pt);
    l_rows := l_rows + sql%rowcount;

    merge into dim_airline d
    using (select c.airline_icao,
                  coalesce(r.airline_name, c.airline_name) as airline_name,
                  r.nationality
             from core_airline c
             left join ref_airline r on r.airline_icao = c.airline_icao) s
       on (d.airline_icao = s.airline_icao)
     when matched then update
          set d.airline_name = s.airline_name,
              d.nationality  = s.nationality
     when not matched then insert (airline_icao, airline_name, nationality)
          values (s.airline_icao, s.airline_name, s.nationality);
    l_rows := l_rows + sql%rowcount;

    merge into dim_airport d
    using (select c.airport_icao,
                  coalesce(r.airport_name, c.airport_name) as airport_name,
                  r.city, r.state_uf, r.country_name,
                  coalesce(r.iso_country, c.country_code)  as iso_country,
                  r.continent, r.iata_code, r.latitude, r.longitude,
                  case
                    when coalesce(r.iso_country, c.country_code) = 'BR' or r.country_name = 'BRASIL' then 1
                    else 0
                  end                                      as is_brazil
             from core_airport c
             left join ref_airport r on r.airport_icao = c.airport_icao) s
       on (d.airport_icao = s.airport_icao)
     when matched then update
          set d.airport_name = s.airport_name,
              d.city         = s.city,
              d.state_uf     = s.state_uf,
              d.country_name = s.country_name,
              d.iso_country  = s.iso_country,
              d.continent    = s.continent,
              d.iata_code    = s.iata_code,
              d.latitude     = s.latitude,
              d.longitude    = s.longitude,
              d.is_brazil    = s.is_brazil
     when not matched then insert (
            airport_icao, airport_name, city, state_uf, country_name, iso_country,
            continent, iata_code, latitude, longitude, is_brazil)
          values (
            s.airport_icao, s.airport_name, s.city, s.state_uf, s.country_name, s.iso_country,
            s.continent, s.iata_code, s.latitude, s.longitude, s.is_brazil);
    l_rows := l_rows + sql%rowcount;

    return l_rows;
  end refresh_dimensions;

  ------------------------------------------------------------------------------
  function refresh_month(p_month in date) return number is
    l_month    date := trunc(p_month, 'MM');
    l_run_id   number;
    l_core     pls_integer;
    l_loaded   pls_integer;
    l_first    date;
    l_last     date;
    l_dims     pls_integer;
    l_error    varchar2(4000);
  begin
    l_run_id := pkg_load_log.start_run('MART ' || to_char(l_month, 'YYYY-MM'), l_month);
    savepoint sp_refresh_month;

    begin
      select count(*),
             min(trunc(coalesce(f.dep_sched, f.dep_actual))),
             max(trunc(coalesce(f.dep_sched, f.dep_actual)))
        into l_core, l_first, l_last
        from core_flight f
       where f.ref_month = l_month;

      l_dims := refresh_dimensions;
      build_dim_date(l_first, l_last);

      delete from fact_flight where month_start = l_month;

      -- Inner joins: a flight whose airline or airport has no dimension row would be
      -- left out and show up as "rejected" in the run log (core count - loaded).
      insert into fact_flight (
        month_start, flight_id, date_key, dep_hour, airline_key, orig_airport_key, dest_airport_key,
        flight_no, line_type, is_flown, is_cancelled, is_measurable, on_time_15,
        dep_delay_min, arr_delay_min)
      select f.ref_month,
             f.flight_id,
             to_number(to_char(coalesce(f.dep_sched, f.dep_actual), 'YYYYMMDD')),
             to_number(to_char(coalesce(f.dep_sched, f.dep_actual), 'HH24')),
             a.airline_key,
             o.airport_key,
             d.airport_key,
             f.flight_no,
             f.line_type,
             case when f.status = 'REALIZADO' then 1 else 0 end,
             f.is_cancelled,
             case when f.on_time_15 is not null then 1 else 0 end,
             f.on_time_15,
             f.dep_delay_min,
             f.arr_delay_min
        from core_flight f
        join dim_airline a on a.airline_icao = f.airline_icao
        join dim_airport o on o.airport_icao = f.orig_icao
        join dim_airport d on d.airport_icao = f.dest_icao
       where f.ref_month = l_month;
      l_loaded := sql%rowcount;

      pkg_load_log.mark_success(
        p_run_id    => l_run_id,
        p_staged    => l_core,
        p_loaded    => l_loaded,
        p_rejected  => l_core - l_loaded,
        p_duplicate => 0);

      return l_run_id;
    exception
      when others then
        l_error := substr(sqlerrm || chr(10) || dbms_utility.format_error_backtrace, 1, 4000);
        rollback to savepoint sp_refresh_month;
        pkg_load_log.mark_failed(l_run_id, l_error);
        raise;
    end;
  end refresh_month;

  ------------------------------------------------------------------------------
  function refresh_all return pls_integer is
    l_run_id  number;
    l_months  pls_integer := 0;
  begin
    for m in (select distinct ref_month from core_flight order by ref_month) loop
      l_run_id := refresh_month(m.ref_month);
      l_months := l_months + 1;
    end loop;
    return l_months;
  end refresh_all;

end pkg_mart;
/
