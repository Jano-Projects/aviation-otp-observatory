--------------------------------------------------------------------------------
-- Typed view over the staging table, with the validation verdict per line.
-- Single place where raw text becomes typed data: the load package reads
-- only from here.
--------------------------------------------------------------------------------
create or replace view stg_vra_v as
select s.src_file,
       s.line_no,
       upper(trim(s.airline_icao))              as airline_icao,
       trim(s.flight_no)                        as flight_no,
       substr(trim(s.di_code), 1, 10)           as di_code,
       substr(upper(trim(s.line_type)), 1, 10)  as line_type,
       upper(trim(s.orig_icao))                 as orig_icao,
       upper(trim(s.dest_icao))                 as dest_icao,
       pkg_vra_util.to_ts(s.dep_sched)          as dep_sched,
       pkg_vra_util.to_ts(s.dep_actual)         as dep_actual,
       pkg_vra_util.to_ts(s.arr_sched)          as arr_sched,
       pkg_vra_util.to_ts(s.arr_actual)         as arr_actual,
       upper(trim(s.status))                    as status,
       pkg_vra_util.reject_reason(
         p_airline_icao => s.airline_icao,
         p_flight_no    => s.flight_no,
         p_orig_icao    => s.orig_icao,
         p_dest_icao    => s.dest_icao,
         p_dep_sched    => s.dep_sched,
         p_dep_actual   => s.dep_actual,
         p_arr_sched    => s.arr_sched,
         p_arr_actual   => s.arr_actual,
         p_status       => s.status)            as reject_reason,
       s.airline_icao || ';' || s.flight_no  || ';' || s.di_code    || ';' || s.line_type  || ';' ||
       s.orig_icao    || ';' || s.dest_icao  || ';' || s.dep_sched  || ';' || s.dep_actual || ';' ||
       s.arr_sched    || ';' || s.arr_actual || ';' || s.status     || ';' || s.justification_code
                                                as raw_line
  from stg_vra s;

comment on table stg_vra_v is 'STG_VRA typed and validated. REJECT_REASON is NULL for valid lines.';
