create or replace package test_pkg_ref_load as

  --%suite(pkg_ref_load - airline and airport reference data)
  --%suitepath(otp.ref)
  --%rollback(auto)

  --%beforeeach
  procedure stage_sample_sources;

  --%test(to_coord parses coordinates regardless of sign and decimals)
  procedure to_coord_parses_numbers;

  --%test(to_coord returns NULL for anything that is not a plain number)
  procedure to_coord_rejects_text;

  --%test(An airline takes the name of its most recent year)
  procedure airline_latest_year_wins;

  --%test(Invalid airline codes are counted as rejected, not loaded)
  procedure invalid_airline_rejected;

  --%test(An airport combines ANAC city and country with OurAirports name and coordinates)
  procedure airport_combines_sources;

  --%test(An airport known only by its OurAirports gps_code is loaded)
  procedure airport_from_gps_code;

  --%test(A match by ident beats a match by gps_code for the same code)
  procedure ident_beats_gps_code;

  --%test(Names are copied to the core dimensions)
  procedure names_reach_core;

  --%test(Records a SUCCESS run with consistent row counts)
  procedure records_run_summary;

  --%test(Fails with ORA-20002 when a reference file is not staged)
  --%throws(-20002)
  procedure fails_without_staged_files;

end test_pkg_ref_load;
/
