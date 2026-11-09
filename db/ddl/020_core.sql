--------------------------------------------------------------------------------
-- CORE layer: typed, validated, deduplicated data.
-- Uses Oracle 23ai "IF NOT EXISTS" so the install script can be re-run safely.
--------------------------------------------------------------------------------

-- Every execution of pkg_vra_load.process_file is recorded here.
create table if not exists core_load_run (
  run_id          number generated always as identity,
  src_file        varchar2(100)  not null,
  ref_month       date,
  status          varchar2(10)   default 'RUNNING' not null,
  started_at      timestamp      default systimestamp not null,
  finished_at     timestamp,
  rows_staged     number,
  rows_loaded     number,
  rows_rejected   number,
  rows_duplicate  number,
  error_message   varchar2(4000),
  constraint core_load_run_pk        primary key (run_id),
  constraint core_load_run_status_ck check (status in ('RUNNING', 'SUCCESS', 'FAILED'))
);

comment on table core_load_run is 'Audit log: one row per processed file. RUNNING means the caller never committed.';

-- Lines that failed validation, with the reason, so nothing disappears silently.
create table if not exists core_vra_reject (
  run_id    number         not null,
  src_file  varchar2(100)  not null,
  line_no   number(9)      not null,
  reason    varchar2(30)   not null,
  raw_line  varchar2(1000),
  constraint core_vra_reject_pk     primary key (run_id, line_no),
  constraint core_vra_reject_run_fk foreign key (run_id) references core_load_run (run_id)
);

comment on table core_vra_reject is 'Staged lines rejected by pkg_vra_util.reject_reason, per load run.';

create table if not exists core_airline (
  airline_icao  varchar2(3)    not null,
  airline_name  varchar2(200),
  first_month   date           not null,
  last_month    date           not null,
  constraint core_airline_pk primary key (airline_icao)
);

comment on table core_airline is 'Airlines seen in VRA files (names are enriched in a later phase).';

create table if not exists core_airport (
  airport_icao  varchar2(4)    not null,
  airport_name  varchar2(200),
  country_code  varchar2(2),
  first_month   date           not null,
  last_month    date           not null,
  constraint core_airport_pk primary key (airport_icao)
);

comment on table core_airport is 'Aerodromes seen in VRA files (names/countries are enriched in a later phase).';

-- One row per flight leg. Partitioned by reference month: reloading a month only
-- touches its own partition, and queries filtered by month prune the rest.
create table if not exists core_flight (
  flight_id      number generated always as identity,
  ref_month      date           not null,
  run_id         number         not null,
  airline_icao   varchar2(3)    not null,
  flight_no      varchar2(10)   not null,
  di_code        varchar2(10),
  line_type      varchar2(10),
  orig_icao      varchar2(4)    not null,
  dest_icao      varchar2(4)    not null,
  dep_sched      date,
  dep_actual     date,
  arr_sched      date,
  arr_actual     date,
  status         varchar2(10)   not null,
  -- Derived values live in the table definition, so every query computes them the same way.
  dep_delay_min  number generated always as (round((dep_actual - dep_sched) * 1440)) virtual,
  arr_delay_min  number generated always as (round((arr_actual - arr_sched) * 1440)) virtual,
  is_cancelled   number(1)  generated always as (case when status = 'CANCELADO' then 1 else 0 end) virtual,
  on_time_15     number(1)  generated always as (
                   case
                     when status = 'REALIZADO' and arr_sched is not null and arr_actual is not null then
                       case when round((arr_actual - arr_sched) * 1440) <= 15 then 1 else 0 end
                   end) virtual,
  constraint core_flight_pk         primary key (flight_id),
  constraint core_flight_status_ck  check (status in ('REALIZADO', 'CANCELADO')),
  constraint core_flight_month_ck   check (ref_month = trunc(ref_month, 'MM')),
  constraint core_flight_airline_fk foreign key (airline_icao) references core_airline (airline_icao),
  constraint core_flight_orig_fk    foreign key (orig_icao)    references core_airport (airport_icao),
  constraint core_flight_dest_fk    foreign key (dest_icao)    references core_airport (airport_icao)
)
partition by range (ref_month) interval (numtoyminterval(1, 'MONTH'))
( partition p_before_2000 values less than (date '2000-01-01') );

comment on table  core_flight               is 'Flight legs from ANAC VRA. Times are as published by ANAC (Brasilia time, minute precision).';
comment on column core_flight.ref_month     is 'First day of the month of the source file (partition key)';
comment on column core_flight.arr_delay_min is 'Actual minus scheduled arrival, in minutes (negative = early)';
comment on column core_flight.on_time_15    is '1 = arrived up to 15 min late; 0 = later; NULL = not measurable (cancelled or no schedule)';

-- Local indexes: one segment per partition, maintained independently.
create index if not exists core_flight_route_ix   on core_flight (orig_icao, dest_icao, ref_month) local;
create index if not exists core_flight_airline_ix on core_flight (airline_icao, ref_month) local;
create index if not exists core_flight_dest_ix    on core_flight (dest_icao) local;
