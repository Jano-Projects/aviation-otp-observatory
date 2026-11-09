create or replace package body test_pkg_vra_util as

  -- Shortcut: a valid line where only the given fields are overridden.
  function reason(
    p_airline    in varchar2 default 'GLO',
    p_flight     in varchar2 default '1015',
    p_orig       in varchar2 default 'SBRJ',
    p_dest       in varchar2 default 'SBSP',
    p_dep_sched  in varchar2 default '2026-07-18 10:30:00',
    p_dep_actual in varchar2 default '2026-07-18 10:24:00',
    p_arr_sched  in varchar2 default '2026-07-18 11:35:00',
    p_arr_actual in varchar2 default '2026-07-18 11:20:00',
    p_status     in varchar2 default 'REALIZADO'
  ) return varchar2 is
  begin
    return pkg_vra_util.reject_reason(
      p_airline, p_flight, p_orig, p_dest,
      p_dep_sched, p_dep_actual, p_arr_sched, p_arr_actual, p_status);
  end reason;

  ------------------------------------------------------------------------------
  procedure to_ts_iso_with_fraction is
  begin
    ut.expect(pkg_vra_util.to_ts('2026-07-18 10:30:00'))
      .to_equal(to_date('2026-07-18 10:30', 'YYYY-MM-DD HH24:MI'));
    ut.expect(pkg_vra_util.to_ts('2026-07-19 15:15:00.100000000'))
      .to_equal(to_date('2026-07-19 15:15', 'YYYY-MM-DD HH24:MI'));
  end to_ts_iso_with_fraction;

  procedure to_ts_legacy_layout is
  begin
    ut.expect(pkg_vra_util.to_ts('01/02/2025 23:05'))
      .to_equal(to_date('2025-02-01 23:05', 'YYYY-MM-DD HH24:MI'));
  end to_ts_legacy_layout;

  procedure to_ts_null_tokens is
  begin
    ut.expect(pkg_vra_util.to_ts('null')).to_be_null();
    ut.expect(pkg_vra_util.to_ts('NULL')).to_be_null();
    ut.expect(pkg_vra_util.to_ts('N/A')).to_be_null();
    ut.expect(pkg_vra_util.to_ts('   ')).to_be_null();
    ut.expect(pkg_vra_util.to_ts(null)).to_be_null();
    ut.expect(pkg_vra_util.to_ts('yesterday')).to_be_null();
  end to_ts_null_tokens;

  procedure to_ts_impossible_date is
  begin
    ut.expect(pkg_vra_util.to_ts('2026-02-30 10:00:00')).to_be_null();
    ut.expect(pkg_vra_util.to_ts('2026-07-18 25:00:00')).to_be_null();
  end to_ts_impossible_date;

  procedure ref_month_from_file_names is
  begin
    ut.expect(pkg_vra_util.ref_month_from_file('VRA_20267.csv')).to_equal(date '2026-07-01');
    ut.expect(pkg_vra_util.ref_month_from_file('VRA_202612.csv')).to_equal(date '2026-12-01');
    ut.expect(pkg_vra_util.ref_month_from_file('VRA_2025_03.csv')).to_equal(date '2025-03-01');
    ut.expect(pkg_vra_util.ref_month_from_file('data/raw/vra_20265_sample.csv')).to_equal(date '2026-05-01');
  end ref_month_from_file_names;

  procedure ref_month_from_file_invalid is
  begin
    ut.expect(pkg_vra_util.ref_month_from_file('VRA_202613.csv')).to_be_null();
    ut.expect(pkg_vra_util.ref_month_from_file('flights.csv')).to_be_null();
    ut.expect(pkg_vra_util.ref_month_from_file(null)).to_be_null();
  end ref_month_from_file_invalid;

  procedure reject_reason_accepts_valid is
  begin
    ut.expect(reason()).to_be_null();
    ut.expect(reason(p_dep_actual => 'null', p_arr_actual => 'null', p_status => 'CANCELADO')).to_be_null();
    -- Unscheduled flights (no planned times) are valid when they actually flew.
    ut.expect(reason(p_dep_sched => 'null', p_arr_sched => 'null')).to_be_null();
  end reject_reason_accepts_valid;

  procedure reject_reason_identification is
  begin
    ut.expect(reason(p_airline => 'GOL1')).to_equal('INVALID_AIRLINE');
    ut.expect(reason(p_flight  => 'null')).to_equal('INVALID_FLIGHT_NO');
    ut.expect(reason(p_orig    => 'XX')).to_equal('INVALID_ORIGIN');
    ut.expect(reason(p_dest    => null)).to_equal('INVALID_DESTINATION');
    ut.expect(reason(p_status  => 'ATRASADO')).to_equal('INVALID_STATUS');
  end reject_reason_identification;

  procedure reject_reason_no_departure is
  begin
    ut.expect(reason(p_dep_sched => 'null', p_dep_actual => 'null', p_status => 'CANCELADO'))
      .to_equal('NO_DEPARTURE_TIME');
  end reject_reason_no_departure;

  procedure reject_reason_bad_timestamp is
  begin
    ut.expect(reason(p_arr_actual => '2026-02-30 10:00:00')).to_equal('INVALID_ARR_ACTUAL');
    ut.expect(reason(p_dep_actual => 'null')).to_equal('DONE_WITHOUT_ACTUALS');
  end reject_reason_bad_timestamp;

end test_pkg_vra_util;
/
