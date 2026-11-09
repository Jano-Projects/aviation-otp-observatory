create or replace package pkg_mart authid definer as
  /*
   * Builds the star schema (DIM_* and FACT_FLIGHT) from CORE and REF.
   *
   * Refresh strategy (phase 2.2): a month is rebuilt with DELETE + INSERT inside
   * the caller's transaction, so it is atomic and unit-testable. Phase 2.4
   * measures it and compares it with a partition exchange.
   *
   * Transaction contract: nothing here commits.
   */

  /*
   * Adds every day between p_from and p_to that DIM_DATE does not have yet.
   * Set-based (one MERGE), idempotent.
   */
  procedure build_dim_date(p_from in date, p_to in date);

  /*
   * DIM_HOUR (24 rows), DIM_AIRLINE and DIM_AIRPORT from the core codes and
   * the reference names. New codes get a new surrogate key; existing rows are
   * updated in place. Returns rows merged.
   */
  function refresh_dimensions return pls_integer;

  /*
   * Rebuilds the facts of one month (any date inside it). Returns the RUN_ID
   * logged in CORE_LOAD_RUN as 'MART YYYY-MM'.
   */
  function refresh_month(p_month in date) return number;

  /*
   * Rebuilds every month present in CORE_FLIGHT. Returns the number of months.
   */
  function refresh_all return pls_integer;

end pkg_mart;
/
