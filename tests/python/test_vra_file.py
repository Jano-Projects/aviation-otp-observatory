"""Unit tests for the file reader. No database and no network."""

from datetime import date
from pathlib import Path

import pytest

from loader.download import candidate_file_names, find_csv_links, month_folder_url
from loader.vra_file import (
    VraFormatError,
    iter_staging_rows,
    normalise,
    open_vra,
    ref_month_from_name,
)

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "VRA_20267_sample.csv"


def test_header_is_found_after_the_updated_at_line():
    vra, _ = open_vra(FIXTURE)
    assert vra.header_line == 2
    assert vra.column_index["airline_icao"] == 0
    assert vra.column_index["status"] == 10


def test_real_sample_is_read_as_raw_text():
    vra, rows = iter_staging_rows(FIXTURE)
    rows = list(rows)
    assert len(rows) == 22
    first = rows[0]
    assert first[:4] == ("VRA_20267_sample.csv", 1, "GLO", "1015")
    assert first[8] == "2026-07-18 10:30:00"          # dep_sched kept as text
    assert [r[1] for r in rows] == list(range(1, 23))  # line numbers are consecutive


def test_null_and_fraction_are_left_for_the_database():
    _, rows = iter_staging_rows(FIXTURE)
    values = {v for row in rows for v in row[8:12]}
    assert "null" in values
    assert any(v.endswith(".100000000") for v in values if v)


def test_legacy_header_is_accepted(tmp_path):
    legacy = tmp_path / "VRA_2025_01.csv"
    legacy.write_text(
        "Sigla ICAO Empresa Aérea;Empresa Aérea;Número Voo;Código DI;Código Tipo Linha;"
        "Sigla ICAO Aeroporto Origem;Partida Prevista;Partida Real;Sigla ICAO Aeroporto Destino;"
        "Chegada Prevista;Chegada Real;Situação Voo;Justificativa;Referência\n"
        "GLO;GOL;0904;0;N;SBGR;01/01/2025 10:00;01/01/2025 10:05;SBRJ;01/01/2025 11:00;"
        "01/01/2025 11:02;REALIZADO;;01/01/2025 00:00:00\n",
        encoding="utf-8",
    )
    vra, rows = iter_staging_rows(legacy)
    row = next(rows)
    assert vra.header_line == 1
    assert row[2:4] == ("GLO", "0904")                  # leading zero preserved
    assert row[6:8] == ("SBGR", "SBRJ")
    assert row[12] == "REALIZADO"


def test_file_without_header_is_rejected(tmp_path):
    other = tmp_path / "VRA_20261.csv"
    other.write_text("a;b;c\n1;2;3\n", encoding="utf-8")
    with pytest.raises(VraFormatError):
        open_vra(other)


@pytest.mark.parametrize(
    "name, expected",
    [
        ("VRA_20267.csv", date(2026, 7, 1)),
        ("VRA_202612.csv", date(2026, 12, 1)),
        ("VRA_2025_03.csv", date(2025, 3, 1)),
        ("VRA_20267_sample.csv", date(2026, 7, 1)),
        ("VRA_202613.csv", None),
        ("flights.csv", None),
    ],
)
def test_ref_month_from_name(name, expected):
    assert ref_month_from_name(name) == expected


def test_normalise_removes_accents_and_symbols():
    assert normalise("Código Autorização (DI)") == "codigoautorizacaodi"


def test_month_folder_url_is_encoded():
    url = month_folder_url(2026, 3)
    assert url.endswith("/2026/03%20-%20Mar%C3%A7o/")
    assert " " not in url


def test_candidate_names_start_with_current_convention():
    assert candidate_file_names(2026, 7)[0] == "VRA_20267.csv"


def test_find_csv_links_in_listing():
    html = '<a href="../">..</a><a href="VRA_20267.csv">VRA_20267.csv</a><a href="leia-me.pdf">x</a>'
    assert find_csv_links(html) == ["VRA_20267.csv"]
