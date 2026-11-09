create or replace package test_pkg_mart as

  --%suite(pkg_mart - star schema)
  --%suitepath(otp.mart)
  --%rollback(auto)

  --%beforeeach
  procedure stage_core_month;

  --%test(DIM_DATE attributes are computed in Portuguese, independent of NLS)
  procedure dim_date_attributes;

  --%test(DIM_DATE is idempotent: building the same days twice adds nothing)
  procedure dim_date_is_idempotent;

  --%test(DIM_HOUR has 24 hours mapped to periods of the day)
  procedure dim_hour_periods;

  --%test(Dimensions take names and countries from the reference tables)
  procedure dimensions_take_reference_names;

  --%test(A month becomes one fact per flight, with keys and measures)
  procedure refresh_month_loads_facts;

  --%test(A cancelled flight is not measurable and not flown)
  procedure cancelled_flight_measures;

  --%test(A flight without schedule is dated by its actual departure)
  procedure unscheduled_flight_dates;

  --%test(Refreshing the same month twice gives the same facts)
  procedure refresh_is_idempotent;

  --%test(Records a SUCCESS run named after the month)
  procedure records_run_summary;

end test_pkg_mart;
/
