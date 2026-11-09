create or replace package pkg_vra_util authid definer as
  /*
   * Pure functions that interpret raw values from ANAC VRA files.
   * No table access here: everything is deterministic and unit-tested
   * (see db/tests/test_pkg_vra_util).
   */

  c_status_done       constant varchar2(10) := 'REALIZADO';
  c_status_cancelled  constant varchar2(10) := 'CANCELADO';

  /*
   * Converts a raw VRA timestamp to DATE (minute precision).
   * Accepts the current layout ('2026-07-18 10:30:00', optionally with a
   * '.100000000' fraction) and the legacy one ('18/07/2026 10:30').
   * Returns NULL for empty values, the literal 'null', unknown formats and
   * impossible calendar values such as 30 February.
   */
  function to_ts(p_value in varchar2) return date deterministic;

  /*
   * First day of the reference month encoded in a file name:
   * 'VRA_20267.csv' and 'VRA_2025_07.csv' -> 1st of that month. NULL if not found.
   */
  function ref_month_from_file(p_file_name in varchar2) return date deterministic;

  /*
   * Validation rule for one staged line. Returns NULL when the line is valid,
   * otherwise a short reason code (INVALID_AIRLINE, INVALID_ORIGIN, ...).
   */
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
  ) return varchar2 deterministic;

end pkg_vra_util;
/
