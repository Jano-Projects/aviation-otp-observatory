--------------------------------------------------------------------------------
-- Installs (or upgrades in place) the OTP schema. Run as user OTP:
--   python tasks.py install
-- Safe to re-run: tables use IF NOT EXISTS, code uses CREATE OR REPLACE.
--------------------------------------------------------------------------------
whenever sqlerror exit failure rollback
whenever oserror  exit failure rollback
set define off feedback on echo off serveroutput on

prompt ==> Staging tables
@@ddl/010_staging.sql

prompt ==> Core tables
@@ddl/020_core.sql

prompt ==> Package specifications
@@packages/pkg_vra_util.pks
@@packages/pkg_vra_load.pks

prompt ==> Views
@@views/stg_vra_v.sql

prompt ==> Package bodies
@@packages/pkg_vra_util.pkb
@@packages/pkg_vra_load.pkb

prompt ==> Checking for invalid objects
@@admin/check_invalid.sql

prompt ==> OTP schema installed.
exit
