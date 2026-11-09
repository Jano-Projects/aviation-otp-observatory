create or replace package body pkg_load_log as

  function start_run(
    p_src_file   in varchar2,
    p_ref_month  in date default null
  ) return number is
    pragma autonomous_transaction;
    l_run_id core_load_run.run_id%type;
  begin
    insert into core_load_run (src_file, ref_month)
    values (p_src_file, p_ref_month)
    returning run_id into l_run_id;
    commit;
    return l_run_id;
  end start_run;

  procedure mark_success(
    p_run_id     in number,
    p_staged     in number,
    p_loaded     in number,
    p_rejected   in number,
    p_duplicate  in number
  ) is
  begin
    update core_load_run
       set status         = 'SUCCESS',
           finished_at    = systimestamp,
           rows_staged    = p_staged,
           rows_loaded    = p_loaded,
           rows_rejected  = p_rejected,
           rows_duplicate = p_duplicate
     where run_id = p_run_id;
  end mark_success;

  procedure mark_failed(
    p_run_id     in number,
    p_error      in varchar2
  ) is
    pragma autonomous_transaction;
  begin
    update core_load_run
       set status        = 'FAILED',
           finished_at   = systimestamp,
           error_message = substr(p_error, 1, 4000)
     where run_id = p_run_id;
    commit;
  end mark_failed;

end pkg_load_log;
/
