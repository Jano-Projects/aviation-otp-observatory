--------------------------------------------------------------------------------
-- MART layer: a star schema for analysis, built from CORE and REF by pkg_mart.
--
--                    DIM_DATE     DIM_HOUR
--                         \         /
--   DIM_AIRLINE ------ FACT_FLIGHT ------ DIM_AIRPORT (origin)
--                           |
--                     DIM_AIRPORT (destination)
--
-- Dimensions use surrogate keys (identity columns) and are overwritten in place
-- when a name changes (slowly changing dimension, type 1).
-- Foreign keys on the fact are declared RELY DISABLE NOVALIDATE: the optimizer
-- may trust them, but they are not checked row by row, because integrity is
-- guaranteed by the load itself (facts are built from inner joins to the
-- dimensions). This is the usual data warehouse practice.
-- A RELY foreign key may only reference a RELY primary key (ORA-25158), so the
-- dimension primary keys are RELY too.
--------------------------------------------------------------------------------

create table if not exists dim_date (
  date_key         number(8)          not null,
  full_date        date               not null,
  year_num         number(4)          not null,
  quarter_num      number(1)          not null,
  month_num        number(2)          not null,
  month_name_pt    varchar2(12 char)  not null,
  month_start      date               not null,
  day_of_month     number(2)          not null,
  iso_day_of_week  number(1)          not null,
  day_name_pt      varchar2(15 char)  not null,
  is_weekend       number(1)          not null,
  iso_week         number(2)          not null,
  constraint dim_date_pk primary key (date_key) rely,
  constraint dim_date_uk unique (full_date)
);

comment on table  dim_date                 is 'Calendar: one row per day, key YYYYMMDD. Names in Portuguese, independent of NLS settings.';
comment on column dim_date.iso_day_of_week is '1 = Monday ... 7 = Sunday (ISO 8601)';

create table if not exists dim_hour (
  hour_key   number(2)          not null,
  period_pt  varchar2(12 char)  not null,
  constraint dim_hour_pk primary key (hour_key) rely,
  constraint dim_hour_ck check (hour_key between 0 and 23)
);

comment on table dim_hour is 'Hour of the scheduled departure (Brasilia time) and its period of the day: madrugada, manhã, tarde, noite.';

create table if not exists dim_airline (
  airline_key   number generated always as identity,
  airline_icao  varchar2(3 char)    not null,
  airline_name  varchar2(200 char),
  nationality   varchar2(20 char),
  constraint dim_airline_pk primary key (airline_key) rely,
  constraint dim_airline_uk unique (airline_icao)
);

comment on table dim_airline is 'Airline dimension (SCD type 1): surrogate key, ICAO code, name and nationality from REF_AIRLINE.';

create table if not exists dim_airport (
  airport_key   number generated always as identity,
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
  is_brazil     number(1)           not null,
  constraint dim_airport_pk primary key (airport_key) rely,
  constraint dim_airport_uk unique (airport_icao)
);

comment on table dim_airport is 'Airport dimension (SCD type 1), used twice by the fact: origin and destination.';

-- Dimensions created before their keys were declared RELY get the property here
-- (re-running these statements is harmless).
alter table dim_date    modify constraint dim_date_pk    rely;
alter table dim_hour    modify constraint dim_hour_pk    rely;
alter table dim_airline modify constraint dim_airline_pk rely;
alter table dim_airport modify constraint dim_airport_pk rely;

create table if not exists fact_flight (
  month_start       date               not null,
  flight_id         number             not null,
  date_key          number(8)          not null,
  dep_hour          number(2)          not null,
  airline_key       number             not null,
  orig_airport_key  number             not null,
  dest_airport_key  number             not null,
  flight_no         varchar2(10 char)  not null,
  line_type         varchar2(10 char),
  is_flown          number(1)          not null,
  is_cancelled      number(1)          not null,
  is_measurable     number(1)          not null,
  on_time_15        number(1),
  dep_delay_min     number,
  arr_delay_min     number,
  constraint fact_flight_date_fk    foreign key (date_key)         references dim_date (date_key)       rely disable novalidate,
  constraint fact_flight_hour_fk    foreign key (dep_hour)         references dim_hour (hour_key)       rely disable novalidate,
  constraint fact_flight_airline_fk foreign key (airline_key)      references dim_airline (airline_key) rely disable novalidate,
  constraint fact_flight_orig_fk    foreign key (orig_airport_key) references dim_airport (airport_key) rely disable novalidate,
  constraint fact_flight_dest_fk    foreign key (dest_airport_key) references dim_airport (airport_key) rely disable novalidate
)
partition by range (month_start) interval (numtoyminterval(1, 'MONTH'))
( partition p_before_2000 values less than (date '2000-01-01') );

comment on table  fact_flight               is 'One row per flight leg (grain = CORE_FLIGHT row). Partitioned by month like CORE_FLIGHT.';
comment on column fact_flight.flight_id     is 'Degenerate dimension: CORE_FLIGHT.FLIGHT_ID, for drill-through';
comment on column fact_flight.date_key      is 'Scheduled departure date, or actual departure date when the flight had no schedule';
comment on column fact_flight.is_measurable is '1 when the arrival delay can be measured (flown, with scheduled and actual arrival)';

-- Local indexes, one segment per month. The unique index guarantees one fact per flight.
create unique index if not exists fact_flight_uk          on fact_flight (month_start, flight_id) local;
create index if not exists        fact_flight_date_ix     on fact_flight (date_key) local;
create index if not exists        fact_flight_airline_ix  on fact_flight (airline_key, month_start) local;
create index if not exists        fact_flight_orig_ix     on fact_flight (orig_airport_key) local;
create index if not exists        fact_flight_dest_ix     on fact_flight (dest_airport_key) local;
