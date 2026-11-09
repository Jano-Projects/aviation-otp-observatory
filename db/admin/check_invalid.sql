--------------------------------------------------------------------------------
-- SQL*Plus reports PL/SQL compilation errors as warnings, not as SQL errors,
-- so "whenever sqlerror" would not stop on them. This script shows the errors
-- and fails explicitly when any object is invalid.
--------------------------------------------------------------------------------
-- First recompile whatever is invalid only because something it depends on was
-- missing or changed earlier (for example a test package compiled before a new
-- table existed). Objects with real errors stay invalid and are reported below.
begin
  dbms_utility.compile_schema(schema => user, compile_all => false);
end;
/

set heading on feedback off pagesize 100 linesize 200
column name format a30
column type format a14
column text format a120

select name, type, line, position, text
  from user_errors
 order by name, type, sequence;

declare
  l_invalid varchar2(4000);
begin
  for r in (select object_type, object_name
              from user_objects
             where status <> 'VALID'
             order by object_name) loop
    l_invalid := substr(l_invalid || ' ' || r.object_type || ' ' || r.object_name || ';', 1, 3900);
  end loop;
  if l_invalid is not null then
    raise_application_error(-20999, 'Invalid objects after install:' || l_invalid);
  end if;
end;
/
