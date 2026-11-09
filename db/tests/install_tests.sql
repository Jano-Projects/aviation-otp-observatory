--------------------------------------------------------------------------------
-- Compiles the utPLSQL test packages into schema OTP.
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
whenever oserror  exit failure rollback
set define off feedback on echo off

prompt ==> Test packages
@@test_pkg_vra_util.pks
@@test_pkg_vra_util.pkb
@@test_pkg_vra_load.pks
@@test_pkg_vra_load.pkb

prompt ==> Checking for invalid objects
@@../admin/check_invalid.sql

exit
