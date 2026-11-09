create or replace package body test_pkg_vra_load as

  -- A month far in the future, so tests never touch real data.
  c_file   constant varchar2(30) := 'VRA_209901_ut.csv';
  c_month  constant date         := date '2099-01-01';

  procedure stage(
    p_line        in number,
    p_airline     in varchar2,
    p_flight      in varchar2,
    p_orig        in varchar2,
    p_dest        in varchar2,
    p_dep_sched   in varchar2,
    p_dep_actual  in varchar2,
    p_arr_sched   in varchar2,
    p_arr_actual  in varchar2,
    p_status      in varchar2
  ) is
  begin
    insert into stg_vra (
      src_file, line_no, airline_icao, flight_no, di_code, line_type,
      orig_icao, dest_icao, dep_sched, dep_actual, arr_sched, arr_actual,
      status, justification_code)
    values (
      c_file, p_line, p_airline, p_flight, '0', 'N',
      p_orig, p_dest, p_dep_sched, p_dep_actual, p_arr_sched, p_arr_actual,
      p_status, 'N/A');
  end stage;

  function flights_in_month return number is
    l_count number;
  begin
    select count(*) into l_count from core_flight where ref_month = c_month;
    return l_count;
  end flights_in_month;

  ------------------------------------------------------------------------------
  -- Six lines: 3 distinct valid flights, 1 exact duplicate, 2 invalid.
  procedure stage_sample_file is
  begin
    -- 1. On time: arrived 15 minutes early
    stage(1, 'GLO', '1015', 'SBRJ', 'SBSP',
          '2099-01-10 10:30:00', '2099-01-10 10:24:00', '2099-01-10 11:35:00', '2099-01-10 11:20:00', 'REALIZADO');
    -- 2. Late: 45 minutes, new airline and airports, with the ".1" fraction ANAC sometimes publishes
    stage(2, 'ZZU', '4000', 'ZZZA', 'ZZZB',
          '2099-01-10 08:00:00.100000000', '2099-01-10 08:40:00',
          '2099-01-10 11:00:00.100000000', '2099-01-10 11:45:00', 'REALIZADO');
    -- 3. Cancelled
    stage(3, 'TAM', '3000', 'SBGR', 'LPPT',
          '2099-01-11 15:30:00', 'null', '2099-01-12 01:25:00', 'null', 'CANCELADO');
    -- 4. Exact duplicate of line 1
    stage(4, 'GLO', '1015', 'SBRJ', 'SBSP',
          '2099-01-10 10:30:00', '2099-01-10 10:24:00', '2099-01-10 11:35:00', '2099-01-10 11:20:00', 'REALIZADO');
    -- 5. Invalid origin
    stage(5, 'GLO', '1016', 'XX', 'SBRJ',
          '2099-01-10 12:30:00', '2099-01-10 12:31:00', '2099-01-10 13:35:00', '2099-01-10 13:30:00', 'REALIZADO');
    -- 6. No departure time at all
    stage(6, 'AZU', '4001', 'SBKP', 'SBCF',
          'null', 'null', 'null', 'null', 'CANCELADO');
  end stage_sample_file;

  ------------------------------------------------------------------------------
  procedure loads_valid_lines is
    l_run_id      number;
    l_delay       number;
    l_on_time     number;
    l_cancelled   number;
  begin
    l_run_id := pkg_vra_load.process_file(c_file);

    ut.expect(flights_in_month()).to_equal(3);

    select arr_delay_min, on_time_15 into l_delay, l_on_time
      from core_flight
     where ref_month = c_month and airline_icao = 'GLO' and flight_no = '1015';
    ut.expect(l_delay).to_equal(-15);
    ut.expect(l_on_time).to_equal(1);

    select arr_delay_min, on_time_15 into l_delay, l_on_time
      from core_flight
     where ref_month = c_month and airline_icao = 'ZZU';
    ut.expect(l_delay).to_equal(45);
    ut.expect(l_on_time).to_equal(0);

    select is_cancelled, on_time_15 into l_cancelled, l_on_time
      from core_flight
     where ref_month = c_month and airline_icao = 'TAM';
    ut.expect(l_cancelled).to_equal(1);
    ut.expect(l_on_time).to_be_null();
  end loads_valid_lines;

  procedure rejects_invalid_lines is
    l_run_id   number;
    l_reasons  varchar2(200);
  begin
    l_run_id := pkg_vra_load.process_file(c_file);

    select listagg(line_no || ':' || reason, ',') within group (order by line_no)
      into l_reasons
      from core_vra_reject
     where run_id = l_run_id;

    ut.expect(l_reasons).to_equal('5:INVALID_ORIGIN,6:NO_DEPARTURE_TIME');
  end rejects_invalid_lines;

  procedure drops_exact_duplicates is
    l_run_id  number;
    l_count   number;
  begin
    l_run_id := pkg_vra_load.process_file(c_file);

    select count(*) into l_count
      from core_flight
     where ref_month = c_month and airline_icao = 'GLO' and flight_no = '1015';
    ut.expect(l_count).to_equal(1);
  end drops_exact_duplicates;

  procedure reprocessing_is_idempotent is
    l_run_id number;
  begin
    l_run_id := pkg_vra_load.process_file(c_file);
    l_run_id := pkg_vra_load.process_file(c_file);

    ut.expect(flights_in_month()).to_equal(3);
  end reprocessing_is_idempotent;

  procedure registers_airlines_and_airports is
    l_run_id    number;
    l_airlines  number;
    l_airports  number;
  begin
    l_run_id := pkg_vra_load.process_file(c_file);

    select count(*) into l_airlines
      from core_airline
     where airline_icao = 'ZZU' and first_month = c_month;
    select count(*) into l_airports
      from core_airport
     where airport_icao in ('ZZZA', 'ZZZB') and first_month = c_month;

    ut.expect(l_airlines).to_equal(1);
    ut.expect(l_airports).to_equal(2);
  end registers_airlines_and_airports;

  procedure records_run_summary is
    l_run_id  number;
    l_run     core_load_run%rowtype;
  begin
    l_run_id := pkg_vra_load.process_file(c_file);

    select * into l_run from core_load_run where run_id = l_run_id;

    ut.expect(l_run.status).to_equal('SUCCESS');
    ut.expect(l_run.ref_month).to_equal(c_month);
    ut.expect(l_run.rows_staged).to_equal(6);
    ut.expect(l_run.rows_rejected).to_equal(2);
    ut.expect(l_run.rows_loaded).to_equal(3);
    ut.expect(l_run.rows_duplicate).to_equal(1);
  end records_run_summary;

  procedure fails_without_staged_lines is
    l_run_id number;
  begin
    l_run_id := pkg_vra_load.process_file('VRA_209902_ut.csv');
  end fails_without_staged_lines;

  procedure fails_without_reference_month is
    l_run_id number;
  begin
    l_run_id := pkg_vra_load.process_file('flights.csv');
  end fails_without_reference_month;

end test_pkg_vra_load;
/
