#!/usr/bin/env python3
"""Unit tests for the Windows CompanyName guard."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_windows_company_name as check  # noqa: E402

_RC = '            VALUE "CompanyName", "{name}" "\\0"\n'


def _cases() -> None:
    assert check.company_names(_RC.format(name="x y")) == ["x y"]
    assert check.company_names('// VALUE "CompanyName", "x"\n') == []
    assert check.company_names("") == []


def _mutated_repo_rc() -> None:
    text = (check.REPO_ROOT / check.RUNNER_RC).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / check.RUNNER_RC
        dest.parent.mkdir(parents=True)
        # The value #1986 introduced is caught.
        dest.write_text(
            text.replace(
                f'"{check.PINNED}"', "\"Caller's Compendium contributors\"", 1
            ),
            encoding="utf-8",
        )
        assert len(check.check(Path(tmp))) == 1
        # A dropped CompanyName is an error, not a silent pass.
        dest.write_text("", encoding="utf-8")
        assert len(check.check(Path(tmp))) == 1
        # So is a missing file.
        dest.unlink()
        assert check.check(Path(tmp)) != []


def _repo() -> None:
    errors = check.check()
    assert errors == [], "\n".join(errors)


def main() -> int:
    _cases()
    _mutated_repo_rc()
    _repo()
    print("OK: all Windows CompanyName guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
