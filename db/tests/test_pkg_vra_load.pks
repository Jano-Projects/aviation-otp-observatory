create or replace package test_pkg_vra_load as

  --%suite(pkg_vra_load - from staging to core)
  --%suitepath(otp.load)
  --%rollback(auto)

  --%beforeeach
  procedure stage_sample_file;

  --%test(Loads valid lines and derives delays and on-time flags)
  procedure loads_valid_lines;

  --%test(Sends invalid lines to CORE_VRA_REJECT with the reason)
  procedure rejects_invalid_lines;

  --%test(Drops exact duplicate lines)
  procedure drops_exact_duplicates;

  --%test(Reprocessing the same file replaces the month instead of duplicating it)
  procedure reprocessing_is_idempotent;

  --%test(Registers airlines and airports seen for the first time)
  procedure registers_airlines_and_airports;

  --%test(Records a SUCCESS run with consistent row counts)
  procedure records_run_summary;

  --%test(Fails with ORA-20002 when no lines are staged for the file)
  --%throws(-20002)
  procedure fails_without_staged_lines;

  --%test(Fails with ORA-20001 when the month cannot be derived)
  --%throws(-20001)
  procedure fails_without_reference_month;

end test_pkg_vra_load;
/
