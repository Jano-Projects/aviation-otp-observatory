# Changelog

All notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (phase 2.1: reference data)
- Airline and airport names from two sources with explicit precedence rules: ANAC statistics
  (official names in Portuguese, state, country) and OurAirports (official airport name, IATA,
  coordinates). New tables `REF_AIRLINE`, `REF_AIRPORT` and their staging tables.
- `pkg_ref_load` (merge, precedence, copy of names to the core dimensions) with 10 utPLSQL tests.
- `pkg_load_log`: the run log, now shared by every load package (refactored out of `pkg_vra_load`).
- `python tasks.py load-ref`; `load` now gives names to codes that new months add; `status`
  shows how many airlines and airports have a name.
- Streaming download for large files; 8 pytest tests for the reference readers.

### Changed
- README rewritten for first-time visitors: results, testing, documentation index, roadmap.
- Documentation reorganised: English reference in `docs/`, Portuguese guides in `docs/pt/`.

### Added
- `docs/architecture.md`: data model, PL/SQL API, load sequence and testing strategy.
- `docs/pt/como-funciona.md`: every file of the project explained (Portuguese).
- `CHANGELOG.md`.

### Removed
- A patch file committed to the repository root by mistake; `*.patch` is now ignored.

## [0.1.0] - 2026-11-09 (phase 1)

### Added
- Oracle Database 23ai Free in Docker (`docker-compose.yml`) and a cross-platform command
  runner (`tasks.py`).
- Staging and core schema, with `CORE_FLIGHT` interval-partitioned by month and delays as
  virtual columns.
- `pkg_vra_util` (parsing and validation rules) and `pkg_vra_load` (idempotent monthly load
  with audit log and reject table).
- Python loader for ANAC VRA files, supporting the current (2026) and legacy layouts.
- 18 utPLSQL tests, 15 pytest tests, and a GitHub Actions pipeline running both against a real
  Oracle container.

### Fixed
- utPLSQL and project scripts are now run from their own folders (the utPLSQL installer
  failed when started elsewhere); an incomplete utPLSQL install is detected and reinstalled.
- Audit rows created by unit tests are removed after the test run; `status` shows one decimal.
