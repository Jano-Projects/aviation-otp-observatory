"""Reading the two reference sources: ANAC statistics and OurAirports.

Like vra_file.py, this module never interprets values: it only reads the files
and hands text to the database, where pkg_ref_load applies the rules.

ANAC "Dados Estatísticos" has about 1.1 million lines (one per airline, route
and month since 2000) but only a few thousand distinct (code, name, ...) tuples.
The reader streams the file and keeps each distinct tuple once: this reduces
volume without deciding anything (choosing the latest name is done in SQL).
"""

from __future__ import annotations

import csv
import io
from pathlib import Path
from typing import Iterator

from .vra_file import VraFormatError, normalise

ANAC_STATS_URL = (
    "https://sistemas.anac.gov.br/dadosabertos/Voos e operações aéreas/"
    "Dados Estatísticos do Transporte Aéreo/Dados_Estatisticos.csv"
)
OURAIRPORTS_URL = "https://raw.githubusercontent.com/davidmegginson/ourairports-data/main/airports.csv"

# ANAC statistics columns used (normalised header names)
ANAC_AIRLINE = ("empresasigla", "empresanome", "empresanacionalidade", "ano")
ANAC_AIRPORT_SIDES = ("origem", "destino")
ANAC_AIRPORT_FIELDS = ("sigla", "nome", "uf", "pais", "continente")

# OurAirports columns staged, in STG_REF_AIRPORT_OA order
OA_COLUMNS = (
    "ident", "icao_code", "gps_code", "iata_code", "name",
    "municipality", "iso_country", "latitude_deg", "longitude_deg", "type",
)
MAX_TEXT = 300  # width of the staging text columns


def _cut(value: str | None) -> str | None:
    return value[:MAX_TEXT] if value else value


def _open_text(path: Path) -> io.TextIOWrapper:
    """Opens a UTF-8 file (with or without BOM), falling back to Latin-1."""
    raw = path.open("rb")
    sample = raw.read(1 << 16)
    raw.seek(0)
    try:
        sample.decode("utf-8-sig")
        encoding = "utf-8-sig"
    except UnicodeDecodeError:
        encoding = "latin-1"
    return io.TextIOWrapper(raw, encoding=encoding, newline="")


def iter_anac_reference(path: str | Path) -> tuple[list[tuple], list[tuple]]:
    """Returns (airline tuples, airport tuples), each distinct, ready for staging:
    airline: (src_file, code, name, nationality, year)
    airport: (src_file, code, city name, state, country, continent, year)
    The header may come after an 'Atualizado em' line, as in the VRA files."""
    path = Path(path)
    airlines: set[tuple] = set()
    airports: set[tuple] = set()

    with _open_text(path) as handle:
        reader = csv.reader(handle, delimiter=";", quotechar='"')
        position = None
        for line_no, fields in enumerate(reader, start=1):
            if position is None:
                names = [normalise(f) for f in fields]
                if "empresasigla" in names:
                    position = {n: i for i, n in enumerate(names)}
                    required = list(ANAC_AIRLINE) + [
                        f"aeroportode{side}{f}" for side in ANAC_AIRPORT_SIDES for f in ANAC_AIRPORT_FIELDS]
                    missing = [c for c in required if c not in position]
                    if missing:
                        raise VraFormatError(f"{path.name}: missing columns {missing}")
                elif line_no >= 5:
                    raise VraFormatError(f"{path.name}: ANAC statistics header not found in the first 5 lines.")
                continue
            if len(fields) < len(position):
                continue  # blank or truncated line

            airlines.add((path.name, *(_cut(fields[position[c]]) for c in ANAC_AIRLINE)))
            year = fields[position["ano"]]
            for side in ANAC_AIRPORT_SIDES:
                values = [fields[position[f"aeroportode{side}{f}"]] for f in ANAC_AIRPORT_FIELDS]
                if values[0]:  # no airport on this side of the line
                    airports.add((path.name, *(_cut(v) for v in values), year))

    if position is None:
        raise VraFormatError(f"{path.name}: empty file.")
    return sorted(airlines), sorted(airports)


def iter_ourairports(path: str | Path) -> Iterator[tuple]:
    """Yields (src_file, line_no, ident, icao_code, gps_code, iata_code, name,
    municipality, iso_country, latitude, longitude, type) for each data line."""
    path = Path(path)
    with _open_text(path) as handle:
        reader = csv.DictReader(handle)
        missing = [c for c in OA_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            raise VraFormatError(f"{path.name}: not an OurAirports airports.csv (missing {missing}).")
        for line_no, row in enumerate(reader, start=1):
            yield (path.name, line_no, *(_cut(row[c]) or None for c in OA_COLUMNS))
