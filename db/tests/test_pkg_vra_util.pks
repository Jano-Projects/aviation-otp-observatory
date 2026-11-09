create or replace package test_pkg_vra_util as

  --%suite(pkg_vra_util - interpreting raw VRA values)
  --%suitepath(otp.util)

  --%test(to_ts parses the current ISO layout and ignores the nanosecond fraction)
  procedure to_ts_iso_with_fraction;

  --%test(to_ts parses the legacy dd/mm/yyyy layout)
  procedure to_ts_legacy_layout;

  --%test(to_ts returns NULL for the literal 'null', N/A and empty values)
  procedure to_ts_null_tokens;

  --%test(to_ts returns NULL for an impossible calendar date instead of failing)
  procedure to_ts_impossible_date;

  --%test(ref_month_from_file understands current and legacy file names)
  procedure ref_month_from_file_names;

  --%test(ref_month_from_file returns NULL when the name has no valid month)
  procedure ref_month_from_file_invalid;

  --%test(reject_reason accepts a completed flight and a cancelled flight)
  procedure reject_reason_accepts_valid;

  --%test(reject_reason flags malformed identification fields)
  procedure reject_reason_identification;

  --%test(reject_reason flags a line without any departure time)
  procedure reject_reason_no_departure;

  --%test(reject_reason flags an unparseable timestamp)
  procedure reject_reason_bad_timestamp;

end test_pkg_vra_util;
/
