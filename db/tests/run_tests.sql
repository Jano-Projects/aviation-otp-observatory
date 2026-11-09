--------------------------------------------------------------------------------
-- Runs every utPLSQL suite in schema OTP and exits with a non-zero code if any
-- test failed or errored (so CI goes red).
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
whenever oserror  exit failure rollback
set serveroutput on size unlimited format wrapped
set define off feedback off verify off linesize 200

declare
  l_summary varchar2(400);

  function count_of(p_word in varchar2) return number is
  begin
    return to_number(regexp_substr(l_summary, '(\d+) ' || p_word, 1, 1, null, 1));
  end count_of;
begin
  for r in (select column_value as line from table(ut.run())) loop
    dbms_output.put_line(r.line);
    if regexp_like(r.line, '\d+ tests?, \d+ failed, \d+ errored') then
      l_summary := regexp_substr(r.line, '\d+ tests?, \d+ failed, \d+ errored');
    end if;
  end loop;

  if l_summary is null then
    raise_application_error(-20900, 'utPLSQL summary line not found: did the tests run?');
  end if;
  if count_of('failed') > 0 or count_of('errored') > 0 then
    raise_application_error(-20901, 'Unit tests failed -> ' || l_summary);
  end if;
end;
/

exit
