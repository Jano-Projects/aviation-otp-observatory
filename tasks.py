#!/usr/bin/env python3
"""Project commands. Works the same on Windows, macOS and Linux.

    python tasks.py up        start the Oracle container and wait until it is ready
    python tasks.py install   create the OTP schema, install utPLSQL and the project objects
    python tasks.py test      compile and run the utPLSQL unit tests
    python tasks.py load      download and load VRA months (or a local file)
    python tasks.py load-ref  download and load airline/airport names (ANAC + OurAirports)
    python tasks.py mart      rebuild the star schema (DIM_*, FACT_FLIGHT) for every month
    python tasks.py status    show the latest load runs and flights per month
    python tasks.py sql       open an interactive SQL*Plus session as OTP
    python tasks.py down      stop the container (data is kept)
    python tasks.py reset     stop the container AND delete the database volume

Run "python tasks.py <command> --help" for options.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ENV_FILE = ROOT / ".env"
ENV_EXAMPLE = ROOT / ".env.example"
UTPLSQL_DIR = ROOT / ".cache" / "utplsql"
RAW_DIR = ROOT / "data" / "raw"
REF_DIR = ROOT / "data" / "reference"
SERVICE = "oracle"
DB_DIR = "/workspace/db"  # where ./db is mounted inside the container
PDB = "FREEPDB1"


# --------------------------------------------------------------------------- helpers
def info(message: str) -> None:
    print(f"\n==> {message}", flush=True)


def fail(message: str) -> None:
    print(f"\nERROR: {message}", file=sys.stderr)
    sys.exit(1)


def env() -> dict[str, str]:
    if not ENV_FILE.exists():
        shutil.copyfile(ENV_EXAMPLE, ENV_FILE)
        print(f"Created {ENV_FILE.name} from {ENV_EXAMPLE.name} (edit it to change passwords).")
    values = {}
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=ROOT, **kwargs)


def compose(*args: str, **kwargs) -> subprocess.CompletedProcess:
    return run(["docker", "compose", *args], **kwargs)


def require_docker() -> None:
    if shutil.which("docker") is None:
        fail("Docker not found. Install it first (see \"Quick start\" in README.md).")
    result = run(["docker", "info"], capture_output=True, text=True)
    if result.returncode != 0:
        if "permission denied" in (result.stderr or "").lower():
            fail("Your user cannot talk to Docker. Run: sudo usermod -aG docker $USER "
                 "and then log out and back in (or reboot).")
        fail("Docker is installed but not running. Linux: sudo systemctl start docker. "
             "Windows/macOS: open Docker Desktop.")


def container_health() -> str:
    result = run(
        ["docker", "inspect", "--format", "{{.State.Health.Status}}", "otp-oracle"],
        capture_output=True, text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else "missing"


def require_running() -> None:
    if container_health() != "healthy":
        fail("The database is not running. Start it with: python tasks.py up")


def sqlplus(logon: str, script: str, capture: bool = False, workdir: str = "/tmp") -> subprocess.CompletedProcess:
    """Runs SQL*Plus inside the container, feeding the script through stdin.
    Scripts are started from `workdir`, so their relative @ paths resolve there."""
    cmd = ["docker", "compose", "exec", "-T", "-w", workdir, SERVICE, "sqlplus", "-s", "-L", logon]
    return run(cmd, input=script, text=True, encoding="utf-8", errors="replace", capture_output=capture)


def sys_logon(cfg: dict[str, str]) -> str:
    return f'sys/"{cfg["ORACLE_PASSWORD"]}"@//localhost:1521/{PDB} as sysdba'


def otp_logon(cfg: dict[str, str]) -> str:
    return f'otp/"{cfg["OTP_PASSWORD"]}"@//localhost:1521/{PDB}'


def check(result: subprocess.CompletedProcess, what: str) -> None:
    if result.returncode != 0:
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        fail(f"{what} failed (exit code {result.returncode}).")


# --------------------------------------------------------------------------- commands
def cmd_up(args: argparse.Namespace) -> None:
    env()
    require_docker()
    UTPLSQL_DIR.mkdir(parents=True, exist_ok=True)  # must exist before Docker mounts it

    info("Starting Oracle Database Free (the first start takes a few minutes)")
    check(compose("up", "-d"), "docker compose up")

    deadline = time.monotonic() + args.timeout
    last = ""
    while time.monotonic() < deadline:
        status = container_health()
        if status == "healthy":
            info("Database is ready")
            return
        if status != last:
            print(f"   status: {status}", flush=True)
            last = status
        time.sleep(5)
    fail(f"Database not ready after {args.timeout}s. Check the logs: docker compose logs {SERVICE}")


def cmd_down(args: argparse.Namespace) -> None:
    require_docker()
    check(compose("down"), "docker compose down")


def cmd_reset(args: argparse.Namespace) -> None:
    require_docker()
    if not args.yes:
        answer = input("This deletes ALL data in the local database. Type 'yes' to continue: ")
        if answer.strip().lower() != "yes":
            print("Cancelled.")
            return
    check(compose("down", "-v"), "docker compose down -v")


def ensure_utplsql_source(version: str) -> Path:
    target = UTPLSQL_DIR / version
    if (target / "source" / "install_headless.sql").exists():
        return target
    if shutil.which("git") is None:
        fail("git not found: it is needed to download utPLSQL.")
    info(f"Downloading utPLSQL {version}")
    check(
        run(["git", "-c", "advice.detachedHead=false", "clone", "--depth", "1", "--branch", version,
             "https://github.com/utPLSQL/utPLSQL.git", str(target)]),
        "git clone utPLSQL",
    )
    return target


def utplsql_state(cfg: dict[str, str]) -> str:
    """'ok' (installed and valid), 'broken' (UT3 exists but install did not finish) or 'absent'."""
    result = sqlplus(
        sys_logon(cfg),
        "set heading off feedback off pagesize 0\n"
        "select case\n"
        "         when exists (select 1 from dba_objects where owner = 'UT3' and object_name = 'UT'\n"
        "                       and object_type = 'PACKAGE BODY' and status = 'VALID') then 'ok'\n"
        "         when exists (select 1 from dba_users where username = 'UT3') then 'broken'\n"
        "         else 'absent'\n"
        "       end from dual;\nexit\n",
        capture=True,
    )
    check(result, "Checking utPLSQL")
    return result.stdout.strip().splitlines()[-1].strip() if result.stdout.strip() else "absent"


def cmd_install(args: argparse.Namespace) -> None:
    cfg = env()
    require_docker()
    require_running()

    info("Creating schema OTP")
    check(
        sqlplus(sys_logon(cfg), f"@/workspace/db/admin/create_app_user.sql {cfg['OTP_PASSWORD']}\n"),
        "Creating schema OTP",
    )

    version = cfg.get("UTPLSQL_VERSION", "v3.1.14")
    ensure_utplsql_source(version)
    state = utplsql_state(cfg)
    if state == "broken":
        info("Removing an incomplete utPLSQL installation")
        check(
            sqlplus(sys_logon(cfg), "whenever sqlerror exit failure\ndrop user ut3 cascade;\nexit\n"),
            "Removing incomplete utPLSQL",
        )
    if state == "ok":
        info("utPLSQL already installed")
    else:
        info(f"Installing utPLSQL {version} (takes about a minute)")
        # The utPLSQL installer must run from its own "source" folder and writes a log
        # there, so it runs from a writable copy inside the container.
        check(
            compose("exec", "-T", SERVICE, "bash", "-c",
                    f"rm -rf /tmp/utplsql && cp -r /workspace/utplsql/{version}/source /tmp/utplsql"),
            "Preparing utPLSQL sources",
        )
        check(
            sqlplus(sys_logon(cfg), "@install_headless.sql\n", workdir="/tmp/utplsql"),
            "Installing utPLSQL",
        )

    info("Installing project objects")
    check(sqlplus(otp_logon(cfg), "@install.sql\n", workdir=DB_DIR), "Installing project objects")


def cmd_test(args: argparse.Namespace) -> None:
    cfg = env()
    require_docker()
    require_running()
    info("Compiling test packages")
    check(sqlplus(otp_logon(cfg), "@tests/install_tests.sql\n", workdir=DB_DIR), "Compiling tests")
    info("Running utPLSQL")
    check(sqlplus(otp_logon(cfg), "@tests/run_tests.sql\n", workdir=DB_DIR), "Unit tests")


def parse_month(value: str) -> date:
    try:
        year, month = value.split("-")
        return date(int(year), int(month), 1)
    except ValueError:
        raise argparse.ArgumentTypeError(f"'{value}' is not a month in the format YYYY-MM")


def month_range(start: date, end: date) -> list[date]:
    months, current = [], start
    while current <= end:
        months.append(current)
        current = date(current.year + current.month // 12, current.month % 12 + 1, 1)
    return months


def cmd_load(args: argparse.Namespace) -> None:
    from loader.db import connect, load_file, refresh_mart, sync_names
    from loader.download import DownloadError, download_month

    cfg = env()
    require_docker()
    require_running()

    files: list[tuple[Path, date | None]] = []
    if args.file:
        for name in args.file:
            path = Path(name)
            if not path.exists():
                fail(f"File not found: {path}")
            files.append((path, args.month))
    else:
        if not args.start:
            fail("Say what to load: --from YYYY-MM [--to YYYY-MM], or --file <path>.")
        if args.end and args.end < args.start:
            fail("--to must not be earlier than --from.")
        for month in month_range(args.start, args.end or args.start):
            info(f"Downloading VRA {month:%Y-%m}")
            try:
                files.append((download_month(month.year, month.month, RAW_DIR, force=args.force), month))
            except DownloadError as exc:
                print(exc, file=sys.stderr)
                if not args.keep_going:
                    fail("Download failed (use --keep-going to skip missing months).")

    failures = 0
    summaries = []
    with connect("otp", cfg["OTP_PASSWORD"], int(cfg.get("ORACLE_PORT", "1521"))) as conn:
        for path, month in files:
            info(f"Loading {path.name}")
            try:
                summary = load_file(conn, path, month)
            except Exception as exc:  # report and continue with the next month
                failures += 1
                print(f"   FAILED: {exc}", file=sys.stderr)
                continue
            print(f"   {summary}")
            if summary.status != "SUCCESS":
                failures += 1
            else:
                summaries.append(summary)
        loaded = [summary.ref_month for summary in summaries]
        if loaded:
            sync_names(conn)  # give names to codes these months may have added
            for month in loaded:
                _, facts = refresh_mart(conn, month)
                print(f"   star schema {month:%Y-%m}: {facts:,} facts")
    if failures:
        fail(f"{failures} file(s) failed. See CORE_LOAD_RUN.ERROR_MESSAGE for details.")


def cmd_load_ref(args: argparse.Namespace) -> None:
    from loader.db import connect, load_reference, refresh_mart_dimensions
    from loader.download import DownloadError, download_file
    from loader.reference import ANAC_STATS_URL, OURAIRPORTS_URL

    cfg = env()
    require_docker()
    require_running()

    try:
        if args.anac_file:
            anac = Path(args.anac_file)
        else:
            info("Downloading ANAC statistics (about 360 MB, only the first time)")
            anac = download_file(ANAC_STATS_URL, REF_DIR / "Dados_Estatisticos.csv", force=args.force)
        if args.airports_file:
            airports = Path(args.airports_file)
        else:
            info("Downloading OurAirports airports.csv (about 13 MB)")
            airports = download_file(OURAIRPORTS_URL, REF_DIR / "airports.csv", force=args.force)
    except DownloadError as exc:
        fail(str(exc))
    for path in (anac, airports):
        if not path.exists():
            fail(f"File not found: {path}")

    info(f"Loading reference data from {anac.name} and {airports.name}")
    with connect("otp", cfg["OTP_PASSWORD"], int(cfg.get("ORACLE_PORT", "1521"))) as conn:
        summary = load_reference(conn, anac, airports)
        if summary.status == "SUCCESS":
            refresh_mart_dimensions(conn)  # new names reach the star schema at once
    print(f"   {summary}")
    if summary.status != "SUCCESS":
        fail("Reference load failed. See CORE_LOAD_RUN.ERROR_MESSAGE for details.")


def cmd_mart(args: argparse.Namespace) -> None:
    from loader.db import connect, refresh_mart

    cfg = env()
    require_running()
    info("Rebuilding the star schema for every month")
    with connect("otp", cfg["OTP_PASSWORD"], int(cfg.get("ORACLE_PORT", "1521"))) as conn:
        months, facts = refresh_mart(conn)
    print(f"   {months} month(s), {facts:,} facts")


def cmd_status(args: argparse.Namespace) -> None:
    from loader.db import connect, names_coverage

    cfg = env()
    require_running()
    with connect("otp", cfg["OTP_PASSWORD"], int(cfg.get("ORACLE_PORT", "1521"))) as conn:
        cur = conn.cursor()
        info("Latest load runs")
        cur.execute(
            "select run_id, src_file, to_char(ref_month, 'YYYY-MM'), status, rows_loaded, rows_rejected, "
            "to_char(started_at, 'YYYY-MM-DD HH24:MI') from core_load_run order by run_id desc "
            "fetch first 10 rows only"
        )
        print(f"   {'run':>5}  {'file':<34} {'month':<8} {'status':<8} {'loaded':>9} {'rejected':>9}  started")
        for run_id, src, month, status, loaded, rejected, started in cur:
            print(f"   {run_id:>5}  {src[:34]:<34} {month or '':<8} {status:<8} "
                  f"{loaded or 0:>9,} {rejected or 0:>9,}  {started}")
        info("Flights per month")
        cur.execute(
            "select to_char(ref_month, 'YYYY-MM'), count(*), sum(is_cancelled), "
            "round(100 * avg(on_time_15), 1) from core_flight group by ref_month order by ref_month"
        )
        print(f"   {'month':<8} {'flights':>9} {'cancelled':>10} {'on-time %':>10}")
        for month, flights, cancelled, otp in cur:
            print(f"   {month:<8} {flights:>9,} {cancelled:>10,} {f'{otp:.1f}' if otp is not None else '-':>10}")
        airlines_named, airports_named = names_coverage(cur)
        info("Names (load them with: python tasks.py load-ref)")
        print(f"   airlines with a name: {airlines_named}    airports with a name: {airports_named}")
        cur.execute("select (select count(*) from fact_flight), (select count(*) from core_flight) from dual")
        facts, flights = cur.fetchone()
        info("Star schema (rebuild with: python tasks.py mart)")
        print(f"   facts: {facts:,} of {flights:,} flights")


def cmd_sql(args: argparse.Namespace) -> None:
    cfg = env()
    require_running()
    sys.exit(compose("exec", SERVICE, "sqlplus", "-L", otp_logon(cfg)).returncode)


# --------------------------------------------------------------------------- CLI
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("up", help="start the database")
    p.add_argument("--timeout", type=int, default=900, help="seconds to wait for the database (default 900)")
    p.set_defaults(func=cmd_up)

    sub.add_parser("down", help="stop the database (keeps data)").set_defaults(func=cmd_down)

    p = sub.add_parser("reset", help="delete the database volume")
    p.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    p.set_defaults(func=cmd_reset)

    sub.add_parser("install", help="install utPLSQL and the schema").set_defaults(func=cmd_install)
    sub.add_parser("test", help="run the utPLSQL tests").set_defaults(func=cmd_test)

    p = sub.add_parser("load", help="download and load VRA files")
    p.add_argument("--from", dest="start", type=parse_month, help="first month, YYYY-MM")
    p.add_argument("--to", dest="end", type=parse_month, help="last month, YYYY-MM (default: same as --from)")
    p.add_argument("--file", nargs="+", help="load local file(s) instead of downloading")
    p.add_argument("--month", type=parse_month, help="reference month for --file when the name has none")
    p.add_argument("--force", action="store_true", help="download again even if the file exists")
    p.add_argument("--keep-going", action="store_true", help="skip months that cannot be downloaded")
    p.set_defaults(func=cmd_load)

    p = sub.add_parser("load-ref", help="download and load airline and airport names")
    p.add_argument("--anac-file", help="local copy of ANAC Dados_Estatisticos.csv instead of downloading")
    p.add_argument("--airports-file", help="local copy of OurAirports airports.csv instead of downloading")
    p.add_argument("--force", action="store_true", help="download again even if the files exist")
    p.set_defaults(func=cmd_load_ref)

    sub.add_parser("mart", help="rebuild the star schema for every month").set_defaults(func=cmd_mart)
    sub.add_parser("status", help="show load runs and monthly counts").set_defaults(func=cmd_status)
    sub.add_parser("sql", help="interactive SQL*Plus as OTP").set_defaults(func=cmd_sql)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
