--------------------------------------------------------------------------------
-- Compiles the utPLSQL test packages into schema OTP. Run from the db/ folder.
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
whenever oserror  exit failure rollback
set define off feedback on echo off

prompt ==> Test packages
@tests/test_pkg_vra_util.pks
@tests/test_pkg_vra_util.pkb
@tests/test_pkg_vra_load.pks
@tests/test_pkg_vra_load.pkb
@tests/test_pkg_ref_load.pks
@tests/test_pkg_ref_load.pkb
@tests/test_pkg_mart.pks
@tests/test_pkg_mart.pkb

prompt ==> Checking for invalid objects
@admin/check_invalid.sql

exit
