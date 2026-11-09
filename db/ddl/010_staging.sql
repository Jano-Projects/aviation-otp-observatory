--------------------------------------------------------------------------------
-- STAGING layer: the ANAC file exactly as received, one row per CSV line.
-- Every column is VARCHAR2 on purpose: typing on read would hide format errors
-- (and, in older layouts, strip leading zeros from flight numbers).
--------------------------------------------------------------------------------
create table if not exists stg_vra (
  src_file            varchar2(100)  not null,
  line_no             number(9)      not null,
  airline_icao        varchar2(50),
  flight_no           varchar2(50),
  di_code             varchar2(50),
  line_type           varchar2(50),
  orig_icao           varchar2(50),
  dest_icao           varchar2(50),
  dep_sched           varchar2(50),
  dep_actual          varchar2(50),
  arr_sched           varchar2(50),
  arr_actual          varchar2(50),
  status              varchar2(50),
  justification_code  varchar2(50),
  loaded_at           timestamp default systimestamp not null,
  constraint stg_vra_pk primary key (src_file, line_no)
);

comment on table  stg_vra           is 'Raw lines of ANAC VRA (Voo Regular Ativo) files. Never transformed in place.';
comment on column stg_vra.src_file  is 'File name as published by ANAC, e.g. VRA_20267.csv';
comment on column stg_vra.line_no   is 'Data line number inside the file (1 = first line after the header)';
comment on column stg_vra.di_code   is 'Codigo Autorizacao (DI): authorisation type of the flight';
comment on column stg_vra.line_type is 'Codigo Tipo Linha: N domestic, I international, C cargo, G general/charter';
