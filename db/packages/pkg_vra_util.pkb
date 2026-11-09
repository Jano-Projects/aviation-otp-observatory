create or replace package body pkg_vra_util as

  -- ANAC writes missing values as an empty field, 'null' or 'N/A' depending on the layout.
  function is_null_token(p_value in varchar2) return boolean is
  begin
    return p_value is null or lower(trim(p_value)) in ('null', 'n/a', '-');
  end is_null_token;

  function matches(p_value in varchar2, p_pattern in varchar2) return boolean is
  begin
    return p_value is not null and regexp_like(p_value, p_pattern);
  end matches;

  ------------------------------------------------------------------------------
  function to_ts(p_value in varchar2) return date deterministic is
    l_value varchar2(64) := trim(substr(p_value, 1, 64));
  begin
    if is_null_token(l_value) then
      return null;
    end if;

    if matches(l_value, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}') then
      return to_date(substr(l_value, 1, 16), 'YYYY-MM-DD HH24:MI');
    elsif matches(l_value, '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}') then
      return to_date(substr(l_value, 1, 16), 'DD/MM/YYYY HH24:MI');
    end if;

    return null;
  exception
    when others then
      -- ORA-01800..ORA-01899 are datetime conversion errors (e.g. ORA-01839 for
      -- 30 February). The shape was right but the value is impossible: treat as
      -- unparseable. Anything else is unexpected and must surface.
      if sqlcode between -1899 and -1800 then
        return null;
      end if;
      raise;
  end to_ts;

  ------------------------------------------------------------------------------
  function ref_month_from_file(p_file_name in varchar2) return date deterministic is
    c_pattern constant varchar2(40) := 'VRA_(\d{4})_?(\d{1,2})(\D|$)';
    l_name    varchar2(400) := upper(p_file_name);
    l_year    varchar2(4);
    l_month   varchar2(2);
  begin
    l_year  := regexp_substr(l_name, c_pattern, 1, 1, null, 1);
    l_month := regexp_substr(l_name, c_pattern, 1, 1, null, 2);

    if l_year is null or l_month is null then
      return null;
    end if;
    if to_number(l_month) not between 1 and 12 then
      return null;
    end if;

    return to_date(l_year || lpad(l_month, 2, '0') || '01', 'YYYYMMDD');
  end ref_month_from_file;

  ------------------------------------------------------------------------------
  function reject_reason(
    p_airline_icao  in varchar2,
    p_flight_no     in varchar2,
    p_orig_icao     in varchar2,
    p_dest_icao     in varchar2,
    p_dep_sched     in varchar2,
    p_dep_actual    in varchar2,
    p_arr_sched     in varchar2,
    p_arr_actual    in varchar2,
    p_status        in varchar2
  ) return varchar2 deterministic is
    l_status varchar2(50) := upper(trim(p_status));
  begin
    -- 1. Identification
    if not matches(upper(trim(p_airline_icao)), '^[A-Z0-9]{3}$') then
      return 'INVALID_AIRLINE';
    elsif is_null_token(p_flight_no) or length(trim(p_flight_no)) > 10 then
      return 'INVALID_FLIGHT_NO';
    elsif not matches(upper(trim(p_orig_icao)), '^[A-Z0-9]{4}$') then
      return 'INVALID_ORIGIN';
    elsif not matches(upper(trim(p_dest_icao)), '^[A-Z0-9]{4}$') then
      return 'INVALID_DESTINATION';
    elsif l_status is null or l_status not in (c_status_done, c_status_cancelled) then
      return 'INVALID_STATUS';

    -- 2. Timestamps: present values must be parseable
    elsif not is_null_token(p_dep_sched) and to_ts(p_dep_sched) is null then
      return 'INVALID_DEP_SCHED';
    elsif not is_null_token(p_dep_actual) and to_ts(p_dep_actual) is null then
      return 'INVALID_DEP_ACTUAL';
    elsif not is_null_token(p_arr_sched) and to_ts(p_arr_sched) is null then
      return 'INVALID_ARR_SCHED';
    elsif not is_null_token(p_arr_actual) and to_ts(p_arr_actual) is null then
      return 'INVALID_ARR_ACTUAL';

    -- 3. Consistency
    elsif to_ts(p_dep_sched) is null and to_ts(p_dep_actual) is null then
      return 'NO_DEPARTURE_TIME';
    elsif l_status = c_status_done
          and (to_ts(p_dep_actual) is null or to_ts(p_arr_actual) is null) then
      return 'DONE_WITHOUT_ACTUALS';
    end if;

    return null;
  end reject_reason;

end pkg_vra_util;
/
