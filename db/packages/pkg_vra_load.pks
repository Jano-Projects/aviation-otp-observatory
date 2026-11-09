create or replace package pkg_vra_load authid definer as
  /*
   * Moves ANAC VRA data from STAGING to CORE.
   *
   * Transaction contract: process_file does NOT commit. The caller decides
   * (the Python loader commits per file; unit tests roll back). The run row in
   * CORE_LOAD_RUN is created in an autonomous transaction, so failed attempts
   * are always visible even after a rollback.
   */

  e_no_ref_month      exception;
  e_no_staged_rows    exception;
  pragma exception_init(e_no_ref_month,   -20001);
  pragma exception_init(e_no_staged_rows, -20002);

  /*
   * Validates, deduplicates and loads one staged file into CORE_FLIGHT,
   * replacing whatever was previously loaded for the same reference month.
   *
   * p_src_file   file name used in STG_VRA.SRC_FILE
   * p_ref_month  any date inside the reference month; when NULL it is derived
   *              from the file name (VRA_20267.csv -> July 2026)
   * returns      the RUN_ID registered in CORE_LOAD_RUN
   *
   * raises ORA-20001 when the reference month cannot be determined
   *        ORA-20002 when there are no staged lines for p_src_file
   */
  function process_file(
    p_src_file   in varchar2,
    p_ref_month  in date default null
  ) return number;

end pkg_vra_load;
/
