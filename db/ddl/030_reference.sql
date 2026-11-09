--------------------------------------------------------------------------------
-- REFERENCE data: names and attributes of airlines and airports.
-- Two sources, each staged as text exactly like the VRA files:
--   * ANAC "Dados Estatísticos": official names in Portuguese (airlines, airport
--     cities, state, country, continent). Distinct tuples only (see loader).
--   * OurAirports (public domain): worldwide airports with official name, IATA
--     code, ISO country and coordinates.
-- pkg_ref_load merges them into REF_AIRLINE / REF_AIRPORT with explicit
-- precedence rules, then copies names to CORE_AIRLINE / CORE_AIRPORT.
--
-- Text columns use CHAR length semantics: ANAC names carry accents, and with the
-- default (BYTE) semantics "AÉREAS" takes more bytes than letters.
--------------------------------------------------------------------------------

create table if not exists stg_ref_airline (
  src_file      varchar2(100 char) not null,
  airline_icao  varchar2(50 char),
  airline_name  varchar2(300 char),
  nationality   varchar2(50 char),
  ref_year      varchar2(10 char),
  loaded_at     timestamp default systimestamp not null
);

comment on table stg_ref_airline is 'Distinct airline tuples from ANAC statistics (code, name, nationality, year), as text.';

create table if not exists stg_ref_airport_anac (
  src_file      varchar2(100 char) not null,
  airport_icao  varchar2(50 char),
  airport_name  varchar2(300 char),
  state_uf      varchar2(50 char),
  country_name  varchar2(100 char),
  continent     varchar2(100 char),
  ref_year      varchar2(10 char),
  loaded_at     timestamp default systimestamp not null
);

comment on table stg_ref_airport_anac is 'Distinct airport tuples from ANAC statistics (code, city name, state, country, continent, year), as text.';

create table if not exists stg_ref_airport_oa (
  src_file      varchar2(100 char) not null,
  line_no       number(9)     not null,
  ident         varchar2(50 char),
  icao_code     varchar2(50 char),
  gps_code      varchar2(50 char),
  iata_code     varchar2(50 char),
  airport_name  varchar2(300 char),
  municipality  varchar2(300 char),
  iso_country   varchar2(50 char),
  latitude      varchar2(50 char),
  longitude     varchar2(50 char),
  airport_type  varchar2(50 char),
  loaded_at     timestamp default systimestamp not null,
  constraint stg_ref_airport_oa_pk primary key (src_file, line_no)
);

comment on table stg_ref_airport_oa is 'OurAirports airports.csv, one row per line, as text.';

create table if not exists ref_airline (
  airline_icao  varchar2(3 char)    not null,
  airline_name  varchar2(200 char)  not null,
  nationality   varchar2(20 char),
  last_year     number(4),
  updated_at    timestamp      default systimestamp not null,
  constraint ref_airline_pk primary key (airline_icao)
);

comment on table  ref_airline             is 'Airline reference: the most recent name ANAC published for each ICAO code.';
comment on column ref_airline.nationality is 'BRASILEIRA or ESTRANGEIRA, as published by ANAC';
comment on column ref_airline.last_year   is 'Latest year in which ANAC reported this code (the name comes from that year)';

create table if not exists ref_airport (
  airport_icao  varchar2(4 char)    not null,
  airport_name  varchar2(200 char),
  city          varchar2(200 char),
  state_uf      varchar2(2 char),
  country_name  varchar2(100 char),
  iso_country   varchar2(2 char),
  continent     varchar2(30 char),
  iata_code     varchar2(3 char),
  latitude      number(9,6),
  longitude     number(9,6),
  name_source   varchar2(20 char)   not null,
  updated_at    timestamp      default systimestamp not null,
  constraint ref_airport_pk        primary key (airport_icao),
  constraint ref_airport_source_ck check (name_source in ('ANAC', 'OURAIRPORTS', 'ANAC+OURAIRPORTS'))
);

comment on table  ref_airport              is 'Airport reference: ANAC (Portuguese city, state, country) combined with OurAirports (name, IATA, coordinates).';
comment on column ref_airport.city         is 'City as ANAC writes it (Portuguese, upper case); OurAirports municipality when ANAC has none';
comment on column ref_airport.country_name is 'Country name in Portuguese, from ANAC';
comment on column ref_airport.name_source  is 'Which sources contributed to this row';
