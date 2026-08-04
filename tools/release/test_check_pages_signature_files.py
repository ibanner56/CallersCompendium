#!/usr/bin/env python3
"""Offline tests for ``check_pages_signature_files.py`` — the gh-pages
signature-file presence checker.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest
of ``tools/release/test_*.py``) and fully OFFLINE: it constructs throwaway
temporary directories that simulate ``gh-pages`` root states and drives the
real checker against them. Run directly::

    python3 tools/release/test_check_pages_signature_files.py

Each case proves a distinct behavioural facet; case 2 is the **red run** —
the checker is shown failing on the exact mutation the invariant is meant to
catch (a ``.json`` with no sibling ``.sig`` file), and then passing once the
``.sig`` file is added. A check that has never been seen to fail is not a check.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_pages_signature_files  # noqa: E402  (after sys.path fixup)


def _cases() -> None:
    # ------------------------------------------------------------------
    # Case 1: all *.sig files present → exit 0
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n')
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n")
        (root / "beta.json").write_text('{"channel":"beta"}\n')
        (root / "beta.json.sig").write_text("c2lnbmF0dXJl\n")
        # A non-JSON file should be ignored.
        (root / "index.html").write_text("<html></html>\n")
        result = check_pages_signature_files.check(root)
        assert result == [], f"case 1 expected no missing sigs, got: {result}"
        rc = check_pages_signature_files.main([str(root)])
        assert rc == 0, f"case 1 expected exit 0, got: {rc}"

    # ------------------------------------------------------------------
    # Case 2 (RED RUN): one .sig file missing → exit 1, message names the file
    #
    # This is the invariant mutation: beta.json exists, beta.json.sig does
    # not. This is the exact state that caused the #714 incident.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n')
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n")
        (root / "beta.json").write_text('{"channel":"beta"}\n')
        # beta.json.sig intentionally absent

        missing = check_pages_signature_files.check(root)
        assert missing == ["beta.json"], (
            f"case 2 expected ['beta.json'] to be missing, got: {missing}"
        )
        rc = check_pages_signature_files.main([str(root)])
        assert rc == 1, (
            f"case 2 (red run): expected exit 1 on missing beta.json.sig, got: {rc}"
        )

        # Now add the missing .sig file — check must pass.
        (root / "beta.json.sig").write_text("c2lnbmF0dXJl\n")
        missing_after = check_pages_signature_files.check(root)
        assert missing_after == [], (
            f"case 2 expected no missing sigs after fix, got: {missing_after}"
        )
        rc_after = check_pages_signature_files.main([str(root)])
        assert rc_after == 0, (
            f"case 2 (green run): expected exit 0 after adding beta.json.sig, got: {rc_after}"
        )

    # ------------------------------------------------------------------
    # Case 3: all *.sig files missing → exit 1, message names ALL files
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n')
        (root / "beta.json").write_text('{"channel":"beta"}\n')

        missing = check_pages_signature_files.check(root)
        assert sorted(missing) == ["beta.json", "stable.json"], (
            f"case 3 expected both json files missing, got: {missing}"
        )
        rc = check_pages_signature_files.main([str(root)])
        assert rc == 1, f"case 3 expected exit 1, got: {rc}"

    # ------------------------------------------------------------------
    # Case 4: no *.json files at all → exit 0 (vacuously valid)
    #
    # A fresh gh-pages branch before any release has no manifests yet. The
    # check must not spuriously fail on an empty root.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / ".nojekyll").write_text("")
        (root / "index.html").write_text("<html></html>\n")

        missing = check_pages_signature_files.check(root)
        assert missing == [], f"case 4 expected no missing sigs, got: {missing}"
        rc = check_pages_signature_files.main([str(root)])
        assert rc == 0, f"case 4 expected exit 0 on empty root, got: {rc}"

    # ------------------------------------------------------------------
    # Case 5: orphaned *.json.sig with no corresponding *.json → exit 0
    #
    # Deliberate scope: we assert every .json has a .sig — not the reverse.
    # The converse (every .sig has a .json) is a different invariant and is
    # deliberately out of scope. An orphaned .sig is harmless to the update
    # client: the client fetches the manifest (.json) first and only requests
    # the .sig if the manifest exists. If the .json is absent the client
    # silently no-ops before even trying the .sig.
    #
    # The failure mode this gate is aimed at is the opposite direction:
    # a .json WITHOUT a .sig. That is what publish_pages_manifest.sh produces
    # when signing is skipped (its `if [ -n "$sig_abs" ]` gate stages the .sig
    # only when a signature file was provided — a .json is always written), and
    # it is the condition that caused #714. Do not conflate the two directions.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n")
        # stable.json intentionally absent — only the .sig exists

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 5 expected no missing sigs for orphaned-sig state, got: {missing}"
        )
        rc = check_pages_signature_files.main([str(root)])
        assert rc == 0, f"case 5 expected exit 0 on orphaned sig, got: {rc}"

    # ------------------------------------------------------------------
    # Case 6: argument errors → exit 2
    # ------------------------------------------------------------------
    rc_no_args = check_pages_signature_files.main([])
    assert rc_no_args == 2, f"case 6a expected exit 2 on no args, got: {rc_no_args}"

    rc_two_args = check_pages_signature_files.main(["a", "b"])
    assert rc_two_args == 2, f"case 6b expected exit 2 on two args, got: {rc_two_args}"

    with tempfile.TemporaryDirectory() as td:
        nonexistent = Path(td) / "does_not_exist"
        rc_missing_dir = check_pages_signature_files.main([str(nonexistent)])
        assert rc_missing_dir == 2, (
            f"case 6c expected exit 2 on missing dir, got: {rc_missing_dir}"
        )

    # ------------------------------------------------------------------
    # Case 7: *.json in a subdirectory is NOT checked
    #
    # The guide/ subtree under gh-pages has .html files; if JSON ever
    # appeared in a subdirectory it must not be subject to the sig
    # invariant (only root-level channel manifests need sigs).
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n')
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n")
        subdir = root / "guide"
        subdir.mkdir()
        # A hypothetical JSON in a subdirectory — must not trigger the check.
        (subdir / "something.json").write_text('{"nested":true}\n')

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 7 expected no missing sigs (subdirectory JSON ignored), got: {missing}"
        )
        rc = check_pages_signature_files.main([str(root)])
        assert rc == 0, f"case 7 expected exit 0 on subdirectory JSON, got: {rc}"


def main() -> int:
    _cases()
    print("OK: all check_pages_signature_files tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
