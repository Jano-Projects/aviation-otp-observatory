"""Unit tests for the reference readers. No database and no network."""

from pathlib import Path

import pytest

from loader.reference import ANAC_STATS_URL, OURAIRPORTS_URL, iter_anac_reference, iter_ourairports
from loader.vra_file import VraFormatError

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
ANAC = FIXTURES / "anac_stats_sample.csv"
OA = FIXTURES / "ourairports_sample.csv"


def test_anac_header_is_found_after_the_updated_at_line():
    airlines, airports = iter_anac_reference(ANAC)
    assert airlines and airports


def test_anac_airlines_are_distinct_text_tuples():
    airlines, _ = iter_anac_reference(ANAC)
    assert len(airlines) == len(set(airlines))
    gol = [a for a in airlines if a[1] == "GLO"]
    assert gol
    src, code, name, nationality, year = gol[0]
    assert src == "anac_stats_sample.csv"
    assert name.startswith("GOL LINHAS AÉREAS")      # accents kept
    assert nationality == "BRASILEIRA"
    assert year.isdigit()                               # still text: the database converts


def test_anac_airports_come_from_both_sides_of_a_route():
    _, airports = iter_anac_reference(ANAC)
    codes = {a[1] for a in airports}
    assert "LFBO" in codes and "GCLP" in codes          # origin and destination of the first line
    assert "" not in codes                              # empty origin/destination is skipped


def test_anac_rejects_a_file_without_its_header(tmp_path):
    other = tmp_path / "x.csv"
    other.write_text("a;b\n1;2\n3;4\n5;6\n7;8\n9;10\n", encoding="utf-8")
    with pytest.raises(VraFormatError):
        iter_anac_reference(other)


def test_ourairports_rows_are_staged_as_text():
    rows = list(iter_ourairports(OA))
    assert len(rows) == 10
    sbgr = next(r for r in rows if r[3] == "SBGR")       # icao_code
    src, line_no, ident, icao, gps, iata, name, city, country, lat, lon, kind = sbgr
    assert src == "ourairports_sample.csv"
    assert iata == "GRU"
    assert country == "BR"
    assert lat.startswith("-23.")                       # text, not float
    assert kind == "large_airport"


def test_ourairports_empty_values_become_none():
    rows = list(iter_ourairports(OA))
    heliport = next(r for r in rows if r[4] == "SJBM")   # gps_code only
    assert heliport[3] is None                          # no icao_code


def test_ourairports_rejects_another_csv(tmp_path):
    other = tmp_path / "airports.csv"
    other.write_text("id,name\n1,x\n", encoding="utf-8")
    with pytest.raises(VraFormatError):
        list(iter_ourairports(other))


def test_source_urls():
    assert ANAC_STATS_URL.startswith("https://sistemas.anac.gov.br/dadosabertos/")
    assert OURAIRPORTS_URL.endswith("/airports.csv")
