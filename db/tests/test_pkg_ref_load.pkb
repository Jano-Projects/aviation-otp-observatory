create or replace package body test_pkg_ref_load as

  -- Invented codes (ZZA, ZZZA, ZZZB) and file names, so tests never touch real data.
  c_anac  constant varchar2(30) := 'UT_REF_ANAC.csv';
  c_oa    constant varchar2(30) := 'UT_REF_OA.csv';

  procedure stage_airline(p_code in varchar2, p_name in varchar2, p_year in varchar2) is
  begin
    insert into stg_ref_airline (src_file, airline_icao, airline_name, nationality, ref_year)
    values (c_anac, p_code, p_name, 'BRASILEIRA', p_year);
  end stage_airline;

  procedure stage_oa(
    p_line in number, p_ident in varchar2, p_icao in varchar2, p_gps in varchar2,
    p_name in varchar2, p_type in varchar2, p_lat in varchar2, p_lon in varchar2
  ) is
  begin
    insert into stg_ref_airport_oa (
      src_file, line_no, ident, icao_code, gps_code, iata_code, airport_name,
      municipality, iso_country, latitude, longitude, airport_type)
    values (
      c_oa, p_line, p_ident, p_icao, p_gps, 'ZZA', p_name,
      'Cidade Alfa', 'BR', p_lat, p_lon, p_type);
  end stage_oa;

  ------------------------------------------------------------------------------
  procedure stage_sample_sources is
  begin
    -- ANAC airlines: the same code in two years, plus one invalid code
    stage_airline('ZZA', 'NOME ANTIGO S.A.', '2019');
    stage_airline('ZZA', 'NOME NOVO LINHAS AÉREAS S.A.', '2025');
    stage_airline('XX',  'CÓDIGO INVÁLIDO', '2025');

    -- ANAC airport ZZZA (city, state, country in Portuguese)
    insert into stg_ref_airport_anac (src_file, airport_icao, airport_name, state_uf, country_name, continent, ref_year)
    values (c_anac, 'ZZZA', 'CIDADE ALFA', 'SP', 'BRASIL', 'AMÉRICA DO SUL', '2025');

    -- OurAirports: ZZZA by ident (a large airport), a heliport that claims ZZZA as gps_code,
    -- and ZZZB known only by gps_code
    stage_oa(1, 'ZZZA',    null, 'ZZZA', 'Alfa International Airport', 'large_airport', '-23.435556', '-46.473056');
    stage_oa(2, 'BR-9999', null, 'ZZZA', 'Alfa Hospital Heliport',     'heliport',      '-23.5',      '-46.6');
    stage_oa(3, 'BR-9998', null, 'ZZZB', 'Bravo Field',                'small_airport', '10.5',       '-20.25');

    -- Core dimensions as a VRA load would have left them (codes, no names yet)
    insert into core_airline (airline_icao, first_month, last_month)
    values ('ZZA', date '2099-01-01', date '2099-01-01');
    insert into core_airport (airport_icao, first_month, last_month)
    values ('ZZZA', date '2099-01-01', date '2099-01-01');
  end stage_sample_sources;

  ------------------------------------------------------------------------------
  procedure to_coord_parses_numbers is
  begin
    ut.expect(pkg_ref_load.to_coord('-74.933689')).to_equal(-74.933689);
    ut.expect(pkg_ref_load.to_coord('40.07098388671875')).to_equal(40.070984);
    ut.expect(pkg_ref_load.to_coord('10')).to_equal(10);
    ut.expect(pkg_ref_load.to_coord(' 0.5 ')).to_equal(0.5);
  end to_coord_parses_numbers;

  procedure to_coord_rejects_text is
  begin
    ut.expect(pkg_ref_load.to_coord(null)).to_be_null();
    ut.expect(pkg_ref_load.to_coord('')).to_be_null();
    ut.expect(pkg_ref_load.to_coord('abc')).to_be_null();
    ut.expect(pkg_ref_load.to_coord('12,5')).to_be_null();
    ut.expect(pkg_ref_load.to_coord('1234.5')).to_be_null();
  end to_coord_rejects_text;

  procedure airline_latest_year_wins is
    l_run_id  number;
    l_name    ref_airline.airline_name%type;
    l_year    ref_airline.last_year%type;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, c_oa);

    select airline_name, last_year into l_name, l_year
      from ref_airline where airline_icao = 'ZZA';

    ut.expect(l_name).to_equal('NOME NOVO LINHAS AÉREAS S.A.');
    ut.expect(l_year).to_equal(2025);
  end airline_latest_year_wins;

  procedure invalid_airline_rejected is
    l_run_id  number;
    l_count   number;
    l_run     core_load_run%rowtype;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, c_oa);

    select count(*) into l_count from ref_airline where airline_icao = 'XX';
    select * into l_run from core_load_run where run_id = l_run_id;

    ut.expect(l_count).to_equal(0);
    ut.expect(l_run.rows_rejected).to_equal(1);
  end invalid_airline_rejected;

  procedure airport_combines_sources is
    l_run_id  number;
    l_row     ref_airport%rowtype;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, c_oa);

    select * into l_row from ref_airport where airport_icao = 'ZZZA';

    ut.expect(l_row.airport_name).to_equal('Alfa International Airport');
    ut.expect(l_row.city).to_equal('CIDADE ALFA');
    ut.expect(l_row.state_uf).to_equal('SP');
    ut.expect(l_row.country_name).to_equal('BRASIL');
    ut.expect(l_row.iso_country).to_equal('BR');
    ut.expect(l_row.iata_code).to_equal('ZZA');
    ut.expect(l_row.latitude).to_equal(-23.435556);
    ut.expect(l_row.name_source).to_equal('ANAC+OURAIRPORTS');
  end airport_combines_sources;

  procedure airport_from_gps_code is
    l_run_id  number;
    l_row     ref_airport%rowtype;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, c_oa);

    select * into l_row from ref_airport where airport_icao = 'ZZZB';

    ut.expect(l_row.airport_name).to_equal('Bravo Field');
    ut.expect(l_row.city).to_equal('Cidade Alfa');      -- no ANAC row: OurAirports municipality
    ut.expect(l_row.longitude).to_equal(-20.25);
    ut.expect(l_row.name_source).to_equal('OURAIRPORTS');
  end airport_from_gps_code;

  procedure ident_beats_gps_code is
    l_run_id  number;
    l_name    ref_airport.airport_name%type;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, c_oa);

    select airport_name into l_name from ref_airport where airport_icao = 'ZZZA';

    ut.expect(l_name).not_to_equal('Alfa Hospital Heliport');
  end ident_beats_gps_code;

  procedure names_reach_core is
    l_run_id   number;
    l_airline  core_airline.airline_name%type;
    l_airport  core_airport.airport_name%type;
    l_country  core_airport.country_code%type;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, c_oa);

    select airline_name into l_airline from core_airline where airline_icao = 'ZZA';
    select airport_name, country_code into l_airport, l_country
      from core_airport where airport_icao = 'ZZZA';

    ut.expect(l_airline).to_equal('NOME NOVO LINHAS AÉREAS S.A.');
    ut.expect(l_airport).to_equal('Alfa International Airport');
    ut.expect(l_country).to_equal('BR');
  end names_reach_core;

  procedure records_run_summary is
    l_run_id  number;
    l_run     core_load_run%rowtype;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, c_oa);

    select * into l_run from core_load_run where run_id = l_run_id;

    ut.expect(l_run.status).to_equal('SUCCESS');
    ut.expect(l_run.rows_staged).to_equal(7);     -- 3 airlines + 1 ANAC airport + 3 OurAirports lines
    ut.expect(l_run.rows_rejected).to_equal(1);   -- airline 'XX'
    ut.expect(l_run.rows_loaded).to_equal(3);     -- ZZA, ZZZA, ZZZB
  end records_run_summary;

  procedure fails_without_staged_files is
    l_run_id number;
  begin
    l_run_id := pkg_ref_load.process_reference(c_anac, 'UT_REF_MISSING.csv');
  end fails_without_staged_files;

end test_pkg_ref_load;
/
