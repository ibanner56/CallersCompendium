#!/usr/bin/env python3
"""Offline tests for ``check_app_coverage.py`` -- the app line-coverage floor.

Pure-stdlib, assert-based, run directly::

    python3 tools/ci/test_check_app_coverage.py

Every case drives the real script on a hand-built lcov file, so the numbers are
exact and need no Flutter SDK. Three groups: the floor itself (at it, a line or a
hundredth of a point under it), the generated-source exclusion, and the
fail-closed paths -- a report that is missing, empty, malformed or truncated must
exit 2, because the core gate's "skip" behaviour is exactly what this gate must
not copy.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_app_coverage.py"
sys.path.insert(0, str(HERE))

import check_app_coverage as gate  # noqa: E402
import run_app_tests_with_coverage as runner  # noqa: E402

FAILURES: list[str] = []
TMP = tempfile.TemporaryDirectory()
ROOT = Path(TMP.name)


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def record(source: str, covered: int, uncovered: int, *, start: int = 1) -> str:
    """One lcov record with ``covered`` hit lines and ``uncovered`` unhit ones."""
    lines = [f"SF:{source}"]
    number = start
    for _ in range(covered):
        lines.append(f"DA:{number},{3}")
        number += 1
    for _ in range(uncovered):
        lines.append(f"DA:{number},0")
        number += 1
    lines += [f"LF:{covered + uncovered}", f"LH:{covered}", "end_of_record"]
    return "\n".join(lines) + "\n"


def run(name: str, text: str | None, floor: str = "80", *, label: str = "") -> subprocess.CompletedProcess:
    """Write ``text`` (or nothing, for None) and run the gate on it as a subprocess."""
    path = ROOT / f"{name}.info"
    if text is not None:
        path.write_bytes(text.encode("utf-8")) if isinstance(text, str) else path.write_bytes(text)
    elif path.exists():
        path.unlink()
    print(f"{label or name}:")
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--lcov", str(path), "--floor", floor],
        capture_output=True, text=True, check=False,
    )


def main() -> int:
    # ---- the floor ---------------------------------------------------------

    res = run("at_floor", record("lib/a.dart", 40, 10), label="40 of 50 lines covered, floor 80")
    check("exactly at the floor passes", res.returncode == 0, f"exit={res.returncode} {res.stdout}")
    check("prints the measurement", "80.00%" in res.stdout and "40/50" in res.stdout, res.stdout)

    res = run("one_under", record("lib/a.dart", 39, 11), label="39 of 50 lines covered, floor 80")
    check("one covered line under the floor fails with exit 1", res.returncode == 1, f"exit={res.returncode} {res.stdout}")
    check("names required and measured", "80.00% required, 78.00% measured" in res.stdout, res.stdout)
    check("names the shortfall in points and lines", "2.00 points" in res.stdout and "1 more covered line" in res.stdout, res.stdout)

    res = run("hundredth_under", record("lib/a.dart", 7999, 2001), label="79.99% against 80")
    check("0.01 below the floor fails", res.returncode == 1 and "79.99% measured" in res.stdout, f"exit={res.returncode} {res.stdout}")
    res = run("hundredth_at", record("lib/a.dart", 8000, 2000), label="80.00% of 10000 lines against 80")
    check("exactly 80.00% of 10000 passes", res.returncode == 0, f"exit={res.returncode} {res.stdout}")

    # A float computation rounds 0.7999999999999999 and 80.00000000000001 the wrong
    # way round for some fractions; the gate compares exact fractions.
    res = run("fractional_floor", record("lib/a.dart", 1, 2), floor="33.3", label="1 of 3 lines against 33.3")
    check("33.33% passes a 33.3 floor", res.returncode == 0, f"exit={res.returncode} {res.stdout}")
    res = run("fractional_floor_under", record("lib/a.dart", 1, 2), floor="33.4", label="1 of 3 lines against 33.4")
    check("33.33% fails a 33.4 floor", res.returncode == 1, f"exit={res.returncode} {res.stdout}")

    res = run("checksums", record("lib/a.dart", 40, 10).replace("DA:1,3", "DA:1,3,abc123=="), label="DA records with checksums")
    check("a checksum field is accepted", res.returncode == 0, f"exit={res.returncode} {res.stdout}")

    res = run("two_files", record("lib/a.dart", 20, 5) + record("lib/b.dart", 20, 5), label="two files, 40/50 together")
    check("totals are summed across files", res.returncode == 0 and "40/50" in res.stdout, res.stdout)

    # ---- generated sources are excluded ------------------------------------

    base = record("lib/a.dart", 40, 10)
    for label, source in (
        ("relative", "lib/l10n/app_localizations_en.dart"),
        ("absolute", "/work/CallersCompendium/app/lib/l10n/app_localizations.dart"),
        ("Windows separators", "lib\\l10n\\app_localizations_de.dart"),
    ):
        res = run("generated", base + record(source, 0, 1000), label=f"+1,000 uncovered generated lines ({label} path)")
        check("the percentage does not move", res.returncode == 0 and "80.00%" in res.stdout and "40/50" in res.stdout, f"exit={res.returncode} {res.stdout}")

    for label, source in (
        ("a similarly named file", "lib/src/l10n_helpers.dart"),
        ("a nested l10n folder", "lib/src/l10n/labels.dart"),
        ("another package's l10n", "../packages/x/lib/l10n_extra.dart"),
    ):
        res = run("not_generated", base + record(source, 0, 50), label=f"+50 uncovered lines in {label}")
        check("is NOT excluded: it moves the number", res.returncode == 1 and "40/100" in res.stdout, f"exit={res.returncode} {res.stdout}")

    res = run("generated_only", record("lib/l10n/app_localizations_en.dart", 5, 5), label="only generated sources")
    check("exits 2: nothing outside the exclusion was measured", res.returncode == 2, f"exit={res.returncode} {res.stdout}")

    # ---- it must not fail open ---------------------------------------------

    res = run("missing", None, label="no report at all")
    check("missing report exits 2, not a skip", res.returncode == 2, f"exit={res.returncode} {res.stdout}")
    check("says no report was measured", "no coverage report" in res.stdout and "not measured" in res.stdout, res.stdout)

    res = run("empty", "", label="an empty file")
    check("empty report exits 2, not 100%", res.returncode == 2, f"exit={res.returncode} {res.stdout}")

    res = run("no_da", "SF:lib/a.dart\nLF:0\nLH:0\nend_of_record\n", label="a record with no DA lines")
    check("no instrumented lines exits 2, not 100%", res.returncode == 2, f"exit={res.returncode} {res.stdout}")

    res = run("malformed_da", "SF:lib/a.dart\nDA:1,3\nDA:abc,1\nend_of_record\n", label="a malformed DA line")
    check("malformed report exits 2", res.returncode == 2, f"exit={res.returncode} {res.stdout}")
    check("names the line", "line 3" in res.stdout, res.stdout)

    res = run("negative", "SF:lib/a.dart\nDA:1,-1\nend_of_record\n", label="a negative hit count")
    check("negative hits exit 2", res.returncode == 2 and "line 2" in res.stdout, f"exit={res.returncode} {res.stdout}")

    res = run("truncated", "SF:lib/a.dart\nDA:1,3\nDA:2,0\n", label="a report cut off mid-record")
    check("truncated report exits 2, not a smaller denominator", res.returncode == 2 and "truncated" in res.stdout, f"exit={res.returncode} {res.stdout}")

    res = run("unclosed", "SF:lib/a.dart\nDA:1,3\nSF:lib/b.dart\nDA:1,3\nend_of_record\n", label="a record that never closes before the next one")
    check("exits 2 naming the line", res.returncode == 2 and "line 3" in res.stdout, f"exit={res.returncode} {res.stdout}")

    res = run("orphan", "DA:1,3\n", label="a DA line outside any record")
    check("exits 2 naming the line", res.returncode == 2 and "line 1" in res.stdout, f"exit={res.returncode} {res.stdout}")

    res = run("orphan_end", "end_of_record\n", label="end_of_record with no SF")
    check("exits 2", res.returncode == 2, f"exit={res.returncode} {res.stdout}")

    res = run("empty_sf", "SF:\nDA:1,3\nend_of_record\n", label="SF with no path")
    check("exits 2", res.returncode == 2, f"exit={res.returncode} {res.stdout}")

    res = run("binary", b"\xff\xfe\x00garbage\n".decode("latin-1").encode("latin-1"), label="not UTF-8")
    check("exits 2, not a crash", res.returncode == 2 and "Traceback" not in res.stderr, f"exit={res.returncode} {res.stdout}{res.stderr}")

    res = run("bad_floor", record("lib/a.dart", 40, 10), floor="eighty", label="a non-numeric floor")
    check("exits 2", res.returncode == 2, f"exit={res.returncode} {res.stdout}")

    # ---- the test wrapper deletes a stale report ----------------------------

    print("run_app_tests_with_coverage deletes a stale coverage/ before running:")
    with tempfile.TemporaryDirectory() as app:
        app_dir = Path(app)
        (app_dir / "coverage").mkdir()
        (app_dir / "coverage" / "lcov.info").write_text("stale\n", encoding="utf-8")
        seen: dict[str, object] = {}

        def fake(command, cwd, check):
            seen["stale_present"] = (cwd / "coverage" / "lcov.info").exists()
            seen["command"] = command
            seen["cwd"] = cwd
            return subprocess.CompletedProcess(command, 7)

        code = runner.run(app_dir, jobs=3, runner=fake)
        check("the stale report is gone before flutter runs", seen.get("stale_present") is False, str(seen))
        check("passes --coverage and the job count", "--coverage" in seen["command"] and "--concurrency=3" in seen["command"], str(seen))
        check("runs in the app directory", seen["cwd"] == app_dir, str(seen))
        check("returns flutter's status", code == 7, str(code))

    # ---- the repository's own floor ----------------------------------------

    print("the committed floor:")
    try:
        committed = Fraction(gate.FLOOR)
    except (ValueError, ZeroDivisionError):
        committed = None
    check("FLOOR is a number (not a placeholder)", committed is not None, repr(gate.FLOOR))
    check("FLOOR is a plausible percentage", committed is not None and 0 < committed <= 100, repr(gate.FLOOR))

    TMP.cleanup()
    if FAILURES:
        print(f"\n{len(FAILURES)} FAILED:")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
