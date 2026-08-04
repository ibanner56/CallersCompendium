#!/usr/bin/env python3
"""Offline tests for ``check_pages_signature_files.py`` — the gh-pages
signature-file presence checker.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest
of ``tools/release/test_*.py``) and fully OFFLINE: it constructs throwaway
temporary directories that simulate ``gh-pages`` root states and drives the
real checker against them. Run directly::

    python3 tools/release/test_check_pages_signature_files.py

Each case proves a distinct behavioural facet; case 2 is the **primary red
run** — the checker is shown failing on the exact mutation the invariant is
meant to catch (a ``.json`` with no sibling ``.sig`` file), then passing once
the ``.sig`` is added. Case 6 is an additional red run proving ``is_file()``
semantics: a directory named ``*.json.sig`` must not satisfy the check. A check
that has never been seen to fail is not a check.
"""

from __future__ import annotations

import io
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_pages_signature_files  # noqa: E402  (after sys.path fixup)


def _run_main(args: list[str]) -> tuple[int, str, str]:
    """Invoke ``main()`` with all output captured; return ``(rc, stdout, stderr)``.

    Suppresses stdout and stderr so that workflow commands emitted by failing
    paths (``::error::FAIL: ...``, ``::error::directory not found: ...``) are
    not written into the Actions log of this test run. Without this, every
    green test run would fire the same ``::error::`` annotations that the gate
    uses to signal a real missing signature — training readers to ignore exactly
    the alarm this gate exists to raise.

    Callers that need only the exit code unpack as ``rc, _, _ = _run_main(...)``.
    Callers that also assert message text unpack ``out`` or ``err`` directly.
    """
    buf_out, buf_err = io.StringIO(), io.StringIO()
    with redirect_stdout(buf_out), redirect_stderr(buf_err):
        rc = check_pages_signature_files.main(args)
    return rc, buf_out.getvalue(), buf_err.getvalue()


def _cases() -> None:
    # ------------------------------------------------------------------
    # Case 1: all *.sig files present → exit 0
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n', encoding="utf-8")
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")
        (root / "beta.json").write_text('{"channel":"beta"}\n', encoding="utf-8")
        (root / "beta.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")
        # A non-JSON file should be ignored.
        (root / "index.html").write_text("<html></html>\n", encoding="utf-8")
        result = check_pages_signature_files.check(root)
        assert result == [], f"case 1 expected no missing sigs, got: {result}"
        rc, _, _ = _run_main([str(root)])
        assert rc == 0, f"case 1 expected exit 0, got: {rc}"

    # ------------------------------------------------------------------
    # Case 2 (RED RUN): one .sig file missing → exit 1, message names the file
    #
    # This is the invariant mutation: beta.json exists, beta.json.sig does
    # not. This is the exact state that caused the #714 incident.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n', encoding="utf-8")
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")
        (root / "beta.json").write_text('{"channel":"beta"}\n', encoding="utf-8")
        # beta.json.sig intentionally absent

        missing = check_pages_signature_files.check(root)
        assert missing == ["beta.json"], (
            f"case 2 expected ['beta.json'] to be missing, got: {missing}"
        )
        rc, out, _ = _run_main([str(root)])
        assert rc == 1, (
            f"case 2 (red run): expected exit 1 on missing beta.json.sig, got: {rc}"
        )
        assert "beta.json.sig" in out, (
            f"case 2: expected emitted message to name the missing file (beta.json.sig), got: {out!r}"
        )

        # Now add the missing .sig file — check must pass.
        (root / "beta.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")
        missing_after = check_pages_signature_files.check(root)
        assert missing_after == [], (
            f"case 2 expected no missing sigs after fix, got: {missing_after}"
        )
        rc_after, _, _ = _run_main([str(root)])
        assert rc_after == 0, (
            f"case 2 (green run): expected exit 0 after adding beta.json.sig, got: {rc_after}"
        )

    # ------------------------------------------------------------------
    # Case 3: all *.sig files missing → exit 1, message names ALL files
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n', encoding="utf-8")
        (root / "beta.json").write_text('{"channel":"beta"}\n', encoding="utf-8")

        missing = check_pages_signature_files.check(root)
        assert sorted(missing) == ["beta.json", "stable.json"], (
            f"case 3 expected both json files missing, got: {missing}"
        )
        rc, out, _ = _run_main([str(root)])
        assert rc == 1, f"case 3 expected exit 1, got: {rc}"
        assert "beta.json.sig" in out, (
            f"case 3: expected emitted message to name beta.json.sig, got: {out!r}"
        )
        assert "stable.json.sig" in out, (
            f"case 3: expected emitted message to name stable.json.sig, got: {out!r}"
        )

    # ------------------------------------------------------------------
    # Case 4: no *.json files at all → exit 0 (vacuously valid)
    #
    # A fresh gh-pages branch before any release has no manifests yet. The
    # check must not spuriously fail on an empty root.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / ".nojekyll").write_text("", encoding="utf-8")
        (root / "index.html").write_text("<html></html>\n", encoding="utf-8")

        missing = check_pages_signature_files.check(root)
        assert missing == [], f"case 4 expected no missing sigs, got: {missing}"
        rc, _, _ = _run_main([str(root)])
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
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")
        # stable.json intentionally absent — only the .sig exists

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 5 expected no missing sigs for orphaned-sig state, got: {missing}"
        )
        rc, _, _ = _run_main([str(root)])
        assert rc == 0, f"case 5 expected exit 0 on orphaned sig, got: {rc}"

    # ------------------------------------------------------------------
    # Case 6: *.json.sig exists as a directory, not a file → exit 1
    #
    # sig_file.exists() returns True for a directory, so a gate using
    # exists() passes on a directory-masquerading-as-sig. is_file() is the
    # correct predicate — the docstring says "sibling *.json.sig file".
    # This case proves the guard uses is_file(), not just exists().
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "beta.json").write_text('{"channel":"beta"}\n', encoding="utf-8")
        (root / "beta.json.sig").mkdir()  # directory masquerading as sig file

        missing = check_pages_signature_files.check(root)
        assert missing == ["beta.json"], (
            f"case 6 expected ['beta.json'] missing (directory is not a sig file), got: {missing}"
        )
        rc, _, _ = _run_main([str(root)])
        assert rc == 1, f"case 6 expected exit 1 (directory is not a sig file), got: {rc}"

    # ------------------------------------------------------------------
    # Case 7: *.json exists as a directory, not a file → not checked
    #
    # root.glob("*.json") returns directories too. A directory named
    # beta.json at the root is not a manifest file and must not be subject
    # to the sig invariant. is_file() on the iterator prevents a false
    # failure against an unlikely-but-possible directory name.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n', encoding="utf-8")
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")
        (root / "beta.json").mkdir()  # directory, not a manifest file; no sig needed

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 7 expected no missing sigs (directory *.json skipped), got: {missing}"
        )
        rc, _, _ = _run_main([str(root)])
        assert rc == 0, f"case 7 expected exit 0 (directory *.json skipped), got: {rc}"

    # ------------------------------------------------------------------
    # Case 8: argument errors → exit 2
    # ------------------------------------------------------------------
    rc_no_args, _, _ = _run_main([])
    assert rc_no_args == 2, f"case 8a expected exit 2 on no args, got: {rc_no_args}"

    rc_two_args, _, _ = _run_main(["a", "b"])
    assert rc_two_args == 2, f"case 8b expected exit 2 on two args, got: {rc_two_args}"

    with tempfile.TemporaryDirectory() as td:
        nonexistent = Path(td) / "does_not_exist"
        rc_missing_dir, _, _ = _run_main([str(nonexistent)])
        assert rc_missing_dir == 2, (
            f"case 8c expected exit 2 on missing dir, got: {rc_missing_dir}"
        )

    # ------------------------------------------------------------------
    # Case 9: *.json in a subdirectory is NOT checked
    #
    # The guide/ subtree under gh-pages has .html files; if JSON ever
    # appeared in a subdirectory it must not be subject to the sig
    # invariant (only root-level channel manifests need sigs).
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "stable.json").write_text('{"channel":"stable"}\n', encoding="utf-8")
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")
        subdir = root / "guide"
        subdir.mkdir()
        # A hypothetical JSON in a subdirectory — must not trigger the check.
        (subdir / "something.json").write_text('{"nested":true}\n', encoding="utf-8")

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 9 expected no missing sigs (subdirectory JSON ignored), got: {missing}"
        )
        rc, _, _ = _run_main([str(root)])
        assert rc == 0, f"case 9 expected exit 0 on subdirectory JSON, got: {rc}"


def main() -> int:
    _cases()
    print("OK: all check_pages_signature_files tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
