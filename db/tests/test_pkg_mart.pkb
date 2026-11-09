create or replace package body test_pkg_mart as

  -- Invented codes in a month far in the future: tests never touch real data.
  c_month constant date := date '2099-01-01';

  procedure core_flight_row(
    p_flight     in varchar2,
    p_orig       in varchar2,
    p_dest       in varchar2,
    p_dep_sched  in date,
    p_dep_actual in date,
    p_arr_sched  in date,
    p_arr_actual in date,
    p_status     in varchar2
  ) is
  begin
    insert into core_flight (
      ref_month, run_id, airline_icao, flight_no, di_code, line_type,
      orig_icao, dest_icao, dep_sched, dep_actual, arr_sched, arr_actual, status)
    values (
      c_month, 0, 'ZZA', p_flight, '0', 'N',
      p_orig, p_dest, p_dep_sched, p_dep_actual, p_arr_sched, p_arr_actual, p_status);
  end core_flight_row;

  function ts(p_value in varchar2) return date is
  begin
    return to_date(p_value, 'YYYY-MM-DD HH24:MI');
  end ts;

  ------------------------------------------------------------------------------
  -- Four flights in January 2099: on time, 45 min late, cancelled, unscheduled.
  procedure stage_core_month is
  begin
    insert into core_airline (airline_icao, first_month, last_month) values ('ZZA', c_month, c_month);
    insert into core_airport (airport_icao, first_month, last_month) values ('ZZZA', c_month, c_month);
    insert into core_airport (airport_icao, first_month, last_month) values ('ZZZB', c_month, c_month);

    insert into ref_airline (airline_icao, airline_name, nationality, last_year)
    values ('ZZA', 'NOME NOVO S.A.', 'BRASILEIRA', 2025);
    insert into ref_airport (airport_icao, airport_name, city, state_uf, country_name, iso_country,
                             continent, iata_code, latitude, longitude, name_source)
    values ('ZZZA', 'Alfa International Airport', 'CIDADE ALFA', 'SP', 'BRASIL', 'BR',
            'AMÉRICA DO SUL', 'ZZA', -23.435556, -46.473056, 'ANAC+OURAIRPORTS');

    core_flight_row('100', 'ZZZA', 'ZZZB', ts('2099-01-03 07:10'), ts('2099-01-03 07:15'),
                    ts('2099-01-03 08:10'), ts('2099-01-03 08:20'), 'REALIZADO');
    core_flight_row('101', 'ZZZB', 'ZZZA', ts('2099-01-04 18:00'), ts('2099-01-04 18:30'),
                    ts('2099-01-04 19:00'), ts('2099-01-04 19:45'), 'REALIZADO');
    core_flight_row('102', 'ZZZA', 'ZZZB', ts('2099-01-05 12:00'), null,
                    ts('2099-01-05 13:00'), null, 'CANCELADO');
    core_flight_row('Z900', 'ZZZB', 'ZZZA', null, ts('2099-01-31 23:50'),
                    null, ts('2099-02-01 01:00'), 'REALIZADO');
  end stage_core_month;

  function facts_in_month return number is
    l_count number;
  begin
    select count(*) into l_count from fact_flight where month_start = c_month;
    return l_count;
  end facts_in_month;

  ------------------------------------------------------------------------------
  procedure dim_date_attributes is
    l_row dim_date%rowtype;
  begin
    pkg_mart.build_dim_date(date '2099-01-01', date '2099-01-07');

    select * into l_row from dim_date where date_key = 20990103;

    ut.expect(l_row.full_date).to_equal(date '2099-01-03');
    ut.expect(l_row.day_name_pt).to_equal('sábado');
    ut.expect(l_row.iso_day_of_week).to_equal(6);
    ut.expect(l_row.is_weekend).to_equal(1);
    ut.expect(l_row.month_name_pt).to_equal('janeiro');
    ut.expect(l_row.quarter_num).to_equal(1);
    ut.expect(l_row.iso_week).to_equal(1);
    ut.expect(l_row.month_start).to_equal(date '2099-01-01');
  end dim_date_attributes;

  procedure dim_date_is_idempotent is
    l_count number;
  begin
    pkg_mart.build_dim_date(date '2099-01-01', date '2099-01-07');
    pkg_mart.build_dim_date(date '2099-01-01', date '2099-01-07');

    select count(*) into l_count from dim_date where date_key between 20990101 and 20990107;
    ut.expect(l_count).to_equal(7);
  end dim_date_is_idempotent;

  procedure dim_hour_periods is
    l_rows    pls_integer;
    l_count   number;
    l_period  dim_hour.period_pt%type;
  begin
    l_rows := pkg_mart.refresh_dimensions;

    select count(*) into l_count from dim_hour;
    ut.expect(l_count).to_equal(24);

    select period_pt into l_period from dim_hour where hour_key = 0;
    ut.expect(l_period).to_equal('madrugada');
    select period_pt into l_period from dim_hour where hour_key = 7;
    ut.expect(l_period).to_equal('manhã');
    select period_pt into l_period from dim_hour where hour_key = 18;
    ut.expect(l_period).to_equal('noite');
  end dim_hour_periods;

  procedure dimensions_take_reference_names is
    l_rows     pls_integer;
    l_airline  dim_airline%rowtype;
    l_alfa     dim_airport%rowtype;
    l_bravo    dim_airport%rowtype;
  begin
    l_rows := pkg_mart.refresh_dimensions;

    select * into l_airline from dim_airline where airline_icao = 'ZZA';
    select * into l_alfa    from dim_airport where airport_icao = 'ZZZA';
    select * into l_bravo   from dim_airport where airport_icao = 'ZZZB';

    ut.expect(l_airline.airline_name).to_equal('NOME NOVO S.A.');
    ut.expect(l_airline.nationality).to_equal('BRASILEIRA');
    ut.expect(l_alfa.city).to_equal('CIDADE ALFA');
    ut.expect(l_alfa.is_brazil).to_equal(1);
    ut.expect(l_bravo.airport_name).to_be_null();     -- no reference row: code only
    ut.expect(l_bravo.is_brazil).to_equal(0);
  end dimensions_take_reference_names;

  procedure refresh_month_loads_facts is
    l_run_id  number;
    l_fact    fact_flight%rowtype;
    l_key     dim_airline.airline_key%type;
  begin
    l_run_id := pkg_mart.refresh_month(c_month);

    ut.expect(facts_in_month()).to_equal(4);

    select * into l_fact from fact_flight where month_start = c_month and flight_no = '101';
    select airline_key into l_key from dim_airline where airline_icao = 'ZZA';

    ut.expect(l_fact.airline_key).to_equal(l_key);
    ut.expect(l_fact.date_key).to_equal(20990104);
    ut.expect(l_fact.dep_hour).to_equal(18);
    ut.expect(l_fact.arr_delay_min).to_equal(45);
    ut.expect(l_fact.on_time_15).to_equal(0);
    ut.expect(l_fact.is_measurable).to_equal(1);
    ut.expect(l_fact.is_flown).to_equal(1);
  end refresh_month_loads_facts;

  procedure cancelled_flight_measures is
    l_run_id  number;
    l_fact    fact_flight%rowtype;
  begin
    l_run_id := pkg_mart.refresh_month(c_month);

    select * into l_fact from fact_flight where month_start = c_month and flight_no = '102';

    ut.expect(l_fact.is_cancelled).to_equal(1);
    ut.expect(l_fact.is_flown).to_equal(0);
    ut.expect(l_fact.is_measurable).to_equal(0);
    ut.expect(l_fact.on_time_15).to_be_null();
  end cancelled_flight_measures;

  procedure unscheduled_flight_dates is
    l_run_id  number;
    l_fact    fact_flight%rowtype;
    l_count   number;
  begin
    l_run_id := pkg_mart.refresh_month(c_month);

    select * into l_fact from fact_flight where month_start = c_month and flight_no = 'Z900';
    select count(*) into l_count from dim_date where date_key = 20990131;

    ut.expect(l_fact.date_key).to_equal(20990131);
    ut.expect(l_fact.dep_hour).to_equal(23);
    ut.expect(l_fact.is_measurable).to_equal(0);
    ut.expect(l_count).to_equal(1);                   -- the calendar was extended for it
  end unscheduled_flight_dates;

  procedure refresh_is_idempotent is
    l_run_id number;
  begin
    l_run_id := pkg_mart.refresh_month(c_month);
    l_run_id := pkg_mart.refresh_month(c_month);

    ut.expect(facts_in_month()).to_equal(4);
  end refresh_is_idempotent;

  procedure records_run_summary is
    l_run_id  number;
    l_run     core_load_run%rowtype;
  begin
    l_run_id := pkg_mart.refresh_month(date '2099-01-15');

    select * into l_run from core_load_run where run_id = l_run_id;

    ut.expect(l_run.src_file).to_equal('MART 2099-01');
    ut.expect(l_run.ref_month).to_equal(c_month);
    ut.expect(l_run.status).to_equal('SUCCESS');
    ut.expect(l_run.rows_staged).to_equal(4);
    ut.expect(l_run.rows_loaded).to_equal(4);
    ut.expect(l_run.rows_rejected).to_equal(0);
  end records_run_summary;

end test_pkg_mart;
/
