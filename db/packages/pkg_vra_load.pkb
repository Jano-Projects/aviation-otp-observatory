create or replace package body pkg_vra_load as

  -- The run log (CORE_LOAD_RUN) is written through pkg_load_log, shared with pkg_ref_load.

  ------------------------------------------------------------------------------
  -- Load steps
  ------------------------------------------------------------------------------
  function reject_invalid_lines(p_run_id in number, p_src_file in varchar2) return pls_integer is
  begin
    insert into core_vra_reject (run_id, src_file, line_no, reason, raw_line)
    select p_run_id, v.src_file, v.line_no, v.reject_reason, v.raw_line
      from stg_vra_v v
     where v.src_file = p_src_file
       and v.reject_reason is not null;
    return sql%rowcount;
  end reject_invalid_lines;

  procedure register_airlines(p_src_file in varchar2, p_ref_month in date) is
  begin
    merge into core_airline a
    using (select distinct v.airline_icao
             from stg_vra_v v
            where v.src_file = p_src_file
              and v.reject_reason is null) s
       on (a.airline_icao = s.airline_icao)
     when matched then update
          set a.first_month = least(a.first_month, p_ref_month),
              a.last_month  = greatest(a.last_month, p_ref_month)
     when not matched then insert (airline_icao, first_month, last_month)
          values (s.airline_icao, p_ref_month, p_ref_month);
  end register_airlines;

  procedure register_airports(p_src_file in varchar2, p_ref_month in date) is
  begin
    merge into core_airport a
    using (select v.orig_icao as airport_icao
             from stg_vra_v v
            where v.src_file = p_src_file
              and v.reject_reason is null
           union
           select v.dest_icao
             from stg_vra_v v
            where v.src_file = p_src_file
              and v.reject_reason is null) s
       on (a.airport_icao = s.airport_icao)
     when matched then update
          set a.first_month = least(a.first_month, p_ref_month),
              a.last_month  = greatest(a.last_month, p_ref_month)
     when not matched then insert (airport_icao, first_month, last_month)
          values (s.airport_icao, p_ref_month, p_ref_month);
  end register_airports;

  -- ANAC republishes old files, so a month is always replaced as a whole.
  -- DISTINCT drops exact duplicate lines (they exist in the published data).
  function replace_month(
    p_run_id     in number,
    p_src_file   in varchar2,
    p_ref_month  in date
  ) return pls_integer is
  begin
    delete from core_flight where ref_month = p_ref_month;

    insert into core_flight (
      ref_month, run_id, airline_icao, flight_no, di_code, line_type,
      orig_icao, dest_icao, dep_sched, dep_actual, arr_sched, arr_actual, status)
    select distinct
           p_ref_month, p_run_id, v.airline_icao, v.flight_no, v.di_code, v.line_type,
           v.orig_icao, v.dest_icao, v.dep_sched, v.dep_actual, v.arr_sched, v.arr_actual, v.status
      from stg_vra_v v
     where v.src_file = p_src_file
       and v.reject_reason is null;

    return sql%rowcount;
  end replace_month;

  ------------------------------------------------------------------------------
  -- Public API
  ------------------------------------------------------------------------------
  function process_file(
    p_src_file   in varchar2,
    p_ref_month  in date default null
  ) return number is
    l_ref_month  date := trunc(coalesce(p_ref_month, pkg_vra_util.ref_month_from_file(p_src_file)), 'MM');
    l_run_id     number;
    l_staged     pls_integer;
    l_rejected   pls_integer;
    l_loaded     pls_integer;
    l_error      varchar2(4000);
  begin
    if l_ref_month is null then
      raise_application_error(-20001,
        'Cannot derive the reference month from file name "' || p_src_file || '". Pass p_ref_month.');
    end if;

    l_run_id := pkg_load_log.start_run(p_src_file, l_ref_month);
    savepoint sp_process_file;

    begin
      select count(*) into l_staged from stg_vra where src_file = p_src_file;
      if l_staged = 0 then
        raise_application_error(-20002, 'No staged lines for file "' || p_src_file || '".');
      end if;

      l_rejected := reject_invalid_lines(l_run_id, p_src_file);
      register_airlines(p_src_file, l_ref_month);
      register_airports(p_src_file, l_ref_month);
      l_loaded   := replace_month(l_run_id, p_src_file, l_ref_month);

      pkg_load_log.mark_success(
        p_run_id    => l_run_id,
        p_staged    => l_staged,
        p_loaded    => l_loaded,
        p_rejected  => l_rejected,
        p_duplicate => l_staged - l_rejected - l_loaded);

      return l_run_id;
    exception
      when others then
        l_error := substr(sqlerrm || chr(10) || dbms_utility.format_error_backtrace, 1, 4000);
        rollback to savepoint sp_process_file;
        pkg_load_log.mark_failed(l_run_id, l_error);
        raise;
    end;
  end process_file;

end pkg_vra_load;
/
