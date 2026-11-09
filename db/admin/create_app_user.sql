--------------------------------------------------------------------------------
-- Creates the application schema OTP (idempotent).
-- Run as SYS, connected to the pluggable database FREEPDB1.
-- Argument 1: password for OTP.
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
set verify off feedback off serveroutput on

declare
  l_count pls_integer;
begin
  select count(*) into l_count from dba_users where username = 'OTP';
  if l_count = 0 then
    execute immediate 'create user otp identified by "&1" '
                   || 'default tablespace users quota unlimited on users';
    dbms_output.put_line('User OTP created.');
  else
    dbms_output.put_line('User OTP already exists.');
  end if;
end;
/

grant create session,
      create table,
      create view,
      create procedure,
      create sequence,
      create type,
      create synonym,
      create materialized view
   to otp;

exit
