create or replace package pkg_load_log authid definer as
  /*
   * Audit log of every load (CORE_LOAD_RUN), shared by all load packages.
   *
   *   start_run     autonomous: the RUNNING row survives a rollback of the load
   *   mark_success  NOT autonomous: SUCCESS is committed (or rolled back) with the data
   *   mark_failed   autonomous: the failure is recorded even though the load is undone
   */

  function start_run(
    p_src_file   in varchar2,
    p_ref_month  in date default null
  ) return number;

  procedure mark_success(
    p_run_id     in number,
    p_staged     in number,
    p_loaded     in number,
    p_rejected   in number,
    p_duplicate  in number
  );

  procedure mark_failed(
    p_run_id     in number,
    p_error      in varchar2
  );

end pkg_load_log;
/
