"""Staging a VRA file in Oracle and asking pkg_vra_load to process it."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import oracledb

from .reference import iter_anac_reference, iter_ourairports
from .vra_file import STAGING_COLUMNS, iter_staging_rows, ref_month_from_name

BATCH_SIZE = 10_000

_INSERT = (
    f"insert into stg_vra (src_file, line_no, {', '.join(STAGING_COLUMNS)}) "
    f"values (:1, :2, {', '.join(f':{i}' for i in range(3, len(STAGING_COLUMNS) + 3))})"
)


@dataclass
class RunSummary:
    run_id: int
    src_file: str
    ref_month: date
    status: str
    staged: int
    loaded: int
    rejected: int
    duplicate: int
    seconds: float

    def __str__(self) -> str:
        return (
            f"{self.src_file}  month={self.ref_month:%Y-%m}  status={self.status}  "
            f"staged={self.staged:,}  loaded={self.loaded:,}  rejected={self.rejected:,}  "
            f"duplicates={self.duplicate:,}  run_id={self.run_id}  ({self.seconds:.1f}s)"
        )


def connect(user: str, password: str, port: int, service: str = "FREEPDB1") -> oracledb.Connection:
    return oracledb.connect(user=user, password=password, dsn=f"localhost:{port}/{service}")


def load_file(conn: oracledb.Connection, path: Path, ref_month: date | None = None) -> RunSummary:
    """Replaces the staged copy of the file, processes it and commits once at the end."""
    started = datetime.now()
    vra, rows = iter_staging_rows(path)
    ref_month = ref_month or ref_month_from_name(vra.name)
    if ref_month is None:
        raise ValueError(f"Cannot tell the month of '{vra.name}'. Use --month YYYY-MM.")

    with conn.cursor() as cur:
        cur.execute("delete from stg_vra where src_file = :1", [vra.name])

        batch: list[tuple] = []
        for row in rows:
            batch.append(row)
            if len(batch) == BATCH_SIZE:
                cur.executemany(_INSERT, batch)
                batch.clear()
        if batch:
            cur.executemany(_INSERT, batch)

        try:
            run_id = cur.callfunc("pkg_vra_load.process_file", int, [vra.name, ref_month])
            conn.commit()
        except oracledb.DatabaseError:
            conn.rollback()
            raise

        cur.execute(
            "select status, rows_staged, rows_loaded, rows_rejected, rows_duplicate "
            "from core_load_run where run_id = :1",
            [run_id],
        )
        status, staged, loaded, rejected, duplicate = cur.fetchone()

    return RunSummary(
        run_id=run_id, src_file=vra.name, ref_month=ref_month, status=status,
        staged=staged or 0, loaded=loaded or 0, rejected=rejected or 0, duplicate=duplicate or 0,
        seconds=(datetime.now() - started).total_seconds(),
    )


_INSERT_REF_AIRLINE = (
    "insert into stg_ref_airline (src_file, airline_icao, airline_name, nationality, ref_year) "
    "values (:1, :2, :3, :4, :5)"
)
_INSERT_REF_AIRPORT_ANAC = (
    "insert into stg_ref_airport_anac "
    "(src_file, airport_icao, airport_name, state_uf, country_name, continent, ref_year) "
    "values (:1, :2, :3, :4, :5, :6, :7)"
)
_INSERT_REF_AIRPORT_OA = (
    "insert into stg_ref_airport_oa (src_file, line_no, ident, icao_code, gps_code, iata_code, "
    "airport_name, municipality, iso_country, latitude, longitude, airport_type) "
    "values (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12)"
)


@dataclass
class ReferenceSummary:
    run_id: int
    status: str
    staged: int
    loaded: int
    rejected: int
    airlines_named: str
    airports_named: str
    seconds: float

    def __str__(self) -> str:
        return (
            f"status={self.status}  staged={self.staged:,}  merged={self.loaded:,}  "
            f"rejected={self.rejected:,}  run_id={self.run_id}  ({self.seconds:.1f}s)\n"
            f"   names in core: airlines {self.airlines_named}, airports {self.airports_named}"
        )


def _insert_batches(cur, sql: str, rows) -> None:
    batch: list[tuple] = []
    for row in rows:
        batch.append(row)
        if len(batch) == BATCH_SIZE:
            cur.executemany(sql, batch)
            batch.clear()
    if batch:
        cur.executemany(sql, batch)


def names_coverage(cur) -> tuple[str, str]:
    """('85/87', '289/289'): core codes that have a name / all core codes."""
    cur.execute(
        "select (select count(airline_name) || '/' || count(*) from core_airline), "
        "       (select count(airport_name) || '/' || count(*) from core_airport) from dual"
    )
    return cur.fetchone()


def load_reference(conn: oracledb.Connection, anac_path: Path, oa_path: Path) -> ReferenceSummary:
    """Stages both reference files, merges them (pkg_ref_load) and commits once."""
    started = datetime.now()
    airlines, airports = iter_anac_reference(anac_path)

    with conn.cursor() as cur:
        cur.execute("delete from stg_ref_airline where src_file = :1", [anac_path.name])
        cur.execute("delete from stg_ref_airport_anac where src_file = :1", [anac_path.name])
        cur.execute("delete from stg_ref_airport_oa where src_file = :1", [oa_path.name])
        _insert_batches(cur, _INSERT_REF_AIRLINE, airlines)
        _insert_batches(cur, _INSERT_REF_AIRPORT_ANAC, airports)
        _insert_batches(cur, _INSERT_REF_AIRPORT_OA, iter_ourairports(oa_path))

        try:
            run_id = cur.callfunc("pkg_ref_load.process_reference", int, [anac_path.name, oa_path.name])
            conn.commit()
        except oracledb.DatabaseError:
            conn.rollback()
            raise

        cur.execute(
            "select status, rows_staged, rows_loaded, rows_rejected from core_load_run where run_id = :1",
            [run_id],
        )
        status, staged, loaded, rejected = cur.fetchone()
        airlines_named, airports_named = names_coverage(cur)

    return ReferenceSummary(
        run_id=run_id, status=status, staged=staged or 0, loaded=loaded or 0, rejected=rejected or 0,
        airlines_named=airlines_named, airports_named=airports_named,
        seconds=(datetime.now() - started).total_seconds(),
    )


def sync_names(conn: oracledb.Connection) -> None:
    """Copies reference names onto codes that new VRA loads may have added."""
    with conn.cursor() as cur:
        cur.callfunc("pkg_ref_load.sync_core", int)
    conn.commit()
