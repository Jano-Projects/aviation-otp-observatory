"""Downloading monthly VRA files from ANAC's open data server."""

from __future__ import annotations

import re
import time
import urllib.error
import urllib.request
from html import unescape
from pathlib import Path
from urllib.parse import quote, urljoin

BASE_URL = "https://sistemas.anac.gov.br/dadosabertos/Voos e operações aéreas/Voo Regular Ativo (VRA)/"
DATASET_PAGE = (
    "https://www.gov.br/anac/pt-br/acesso-a-informacao/dados-abertos/"
    "areas-de-atuacao/voos-e-operacoes-aereas/voo-regular-ativo-vra"
)
MONTHS_PT = (
    "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
    "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro",
)
USER_AGENT = "aviation-otp-observatory/0.1 (open-source portfolio project)"


class DownloadError(RuntimeError):
    pass


def _url(path: str) -> str:
    return quote(path, safe=":/()")


def month_folder_url(year: int, month: int) -> str:
    """.../Voo Regular Ativo (VRA)/2026/07 - Julho/ (URL-encoded)."""
    return _url(f"{BASE_URL}{year}/{month:02d} - {MONTHS_PT[month - 1]}/")


def candidate_file_names(year: int, month: int) -> list[str]:
    # Current naming is VRA_20267.csv (month without zero padding); keep the others as fallbacks.
    return [f"VRA_{year}{month}.csv", f"VRA_{year}{month:02d}.csv", f"VRA_{year}_{month:02d}.csv"]


def _request(url: str, timeout: int = 60) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def _get(url: str, attempts: int = 3) -> bytes:
    """GET with retries for network hiccups; a 404 is returned immediately."""
    for attempt in range(1, attempts + 1):
        try:
            return _request(url)
        except urllib.error.HTTPError as exc:
            if exc.code == 404 or attempt == attempts:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == attempts:
                raise
        time.sleep(2 * attempt)
    raise AssertionError("unreachable")


def find_csv_links(listing_html: str) -> list[str]:
    """Extracts '*.csv' links containing 'VRA' from a directory listing page."""
    links = re.findall(r'href="([^"]+)"', listing_html, flags=re.IGNORECASE)
    return [unescape(l) for l in links if l.lower().endswith(".csv") and "vra" in l.lower()]


def download_month(year: int, month: int, dest_dir: Path, force: bool = False) -> Path:
    """Downloads one month and returns the local path. Reuses an existing file unless force=True."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    folder = month_folder_url(year, month)

    for name in candidate_file_names(year, month):
        target = dest_dir / name
        if target.exists() and not force:
            return target

    errors = []
    for name in candidate_file_names(year, month):
        url = folder + quote(name)
        try:
            content = _get(url)
        except urllib.error.HTTPError as exc:
            errors.append(f"{url} -> HTTP {exc.code}")
            continue
        except (urllib.error.URLError, TimeoutError) as exc:
            raise DownloadError(f"Network error while downloading {url}: {exc}") from exc
        return _save(dest_dir / name, content)

    # Fallback: read the folder listing and take whatever VRA CSV is there.
    try:
        listing = _get(folder).decode("utf-8", errors="replace")
        for link in find_csv_links(listing):
            url = urljoin(folder, link)
            name = Path(urllib.request.url2pathname(link)).name
            return _save(dest_dir / name, _get(url))
        errors.append(f"{folder} -> no VRA .csv link in the listing")
    except (urllib.error.URLError, TimeoutError) as exc:
        errors.append(f"{folder} -> {exc}")

    raise DownloadError(
        f"Could not download VRA for {year}-{month:02d}. Tried:\n  " + "\n  ".join(errors)
        + f"\nThe month may not be published yet. You can also download it manually from\n  {DATASET_PAGE}\n"
        "and load it with: python tasks.py load --file <path>"
    )


def _save(target: Path, content: bytes) -> Path:
    partial = target.with_suffix(target.suffix + ".part")
    partial.write_bytes(content)
    partial.replace(target)
    return target
