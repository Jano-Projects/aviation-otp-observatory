"""Reading ANAC VRA files.

This module is pure Python (no database, no network) so it can be unit-tested
with pytest. Values are kept as raw text on purpose: typing and validation
happen in the database (pkg_vra_util / stg_vra_v), the single source of truth.

Measured format of the current files (2026):
  * UTF-8 with BOM, CRLF line endings, ';' separator, every field quoted;
  * line 1 is 'Atualizado em: YYYY-MM-DD', the header is on line 2;
  * missing values are the literal text 'null';
  * timestamps are 'YYYY-MM-DD HH:MM:SS', sometimes with '.100000000'.
Older files (published on siros.anac.gov.br) use other column names and
'dd/mm/yyyy HH:MM' dates; the aliases below accept both.
"""

from __future__ import annotations

import csv
import io
import re
import unicodedata
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Iterator

# Staging column -> accepted header names (normalised: lowercase, no accents, alphanumeric only)
COLUMN_ALIASES: dict[str, tuple[str, ...]] = {
    "airline_icao": ("icaoempresaaerea", "siglaicaoempresaaerea"),
    "flight_no": ("numerovoo",),
    "di_code": ("codigoautorizacaodi", "codigodi"),
    "line_type": ("codigotipolinha",),
    "orig_icao": ("icaoaerodromoorigem", "siglaicaoaeroportoorigem"),
    "dest_icao": ("icaoaerodromodestino", "siglaicaoaeroportodestino"),
    "dep_sched": ("partidaprevista",),
    "dep_actual": ("partidareal",),
    "arr_sched": ("chegadaprevista",),
    "arr_actual": ("chegadareal",),
    "status": ("situacaovoo",),
    "justification_code": ("codigojustificativa", "justificativa"),
}
OPTIONAL_COLUMNS = {"di_code", "justification_code"}
STAGING_COLUMNS = tuple(COLUMN_ALIASES)
MAX_VALUE_LENGTH = 50  # width of the STG_VRA columns

_FILE_MONTH = re.compile(r"VRA_(\d{4})_?(\d{1,2})(?:\D|$)", re.IGNORECASE)


class VraFormatError(ValueError):
    """The file does not look like a VRA file."""


@dataclass(frozen=True)
class VraFile:
    path: Path
    header_line: int                  # 1-based line number of the header
    column_index: dict[str, int]      # staging column -> position in the CSV row

    @property
    def name(self) -> str:
        return self.path.name


def normalise(name: str) -> str:
    """'Código Autorização (DI)' -> 'codigoautorizacaodi'."""
    without_accents = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]", "", without_accents.lower())


def ref_month_from_name(file_name: str) -> date | None:
    """'VRA_20267.csv' -> date(2026, 7, 1). Same rule as pkg_vra_util.ref_month_from_file."""
    match = _FILE_MONTH.search(Path(file_name).name)
    if not match:
        return None
    year, month = int(match.group(1)), int(match.group(2))
    if not 1 <= month <= 12:
        return None
    return date(year, month, 1)


def _decode(raw: bytes) -> str:
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        return raw.decode("latin-1")


def _map_header(fields: list[str]) -> dict[str, int] | None:
    position = {normalise(f): i for i, f in enumerate(fields)}
    mapping: dict[str, int] = {}
    for column, aliases in COLUMN_ALIASES.items():
        for alias in aliases:
            if alias in position:
                mapping[column] = position[alias]
                break
    required = set(STAGING_COLUMNS) - OPTIONAL_COLUMNS
    return mapping if required <= mapping.keys() else None


def _reader(text: str) -> Iterator[list[str]]:
    return csv.reader(io.StringIO(text, newline=""), delimiter=";", quotechar='"')


def open_vra(path: str | Path, max_header_line: int = 5) -> tuple[VraFile, str]:
    """Finds the header (it is not always on line 1) and maps its columns."""
    path = Path(path)
    text = _decode(path.read_bytes())
    for line_no, fields in enumerate(_reader(text), start=1):
        if line_no > max_header_line:
            break
        mapping = _map_header(fields)
        if mapping:
            return VraFile(path, line_no, mapping), text
    raise VraFormatError(
        f"{path.name}: VRA header not found in the first {max_header_line} lines "
        f"(expected columns such as 'Número Voo' and 'Partida Prevista')."
    )


def iter_staging_rows(path: str | Path) -> tuple[VraFile, Iterator[tuple]]:
    """Returns the file description and an iterator of tuples ready for STG_VRA:
    (src_file, line_no, airline_icao, flight_no, ..., justification_code).
    line_no counts data lines (1 = first line after the header)."""
    vra, text = open_vra(path)

    def rows() -> Iterator[tuple]:
        data_line = 0
        for physical_line, fields in enumerate(_reader(text), start=1):
            if physical_line <= vra.header_line or not any(f.strip() for f in fields):
                continue
            data_line += 1
            values = []
            for column in STAGING_COLUMNS:
                index = vra.column_index.get(column)
                value = fields[index] if index is not None and index < len(fields) else None
                values.append(value[:MAX_VALUE_LENGTH] if value is not None else None)
            yield (vra.name, data_line, *values)

    return vra, rows()
