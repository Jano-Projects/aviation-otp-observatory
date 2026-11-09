"""Staging a VRA file in Oracle and asking pkg_vra_load to process it."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import oracledb

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
