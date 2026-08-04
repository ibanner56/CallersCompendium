#!/usr/bin/env python3
"""Offline tests for ``check_pages_signature_files.py`` — the gh-pages
signature-file presence and validity checker.

Requires the ``cryptography`` package (``python3 -m pip install cryptography==50.0.0``)
for both the checker itself and this test suite (key-pair generation for
synthetic signatures).

Pure-stdlib + cryptography, assert-based (no pytest / no other third-party
deps, matching the rest of ``tools/release/test_*.py``) and fully OFFLINE: it
constructs throwaway temporary directories simulating ``gh-pages`` root states
and drives the real checker against them.  Run directly::

    python3 tools/release/test_check_pages_signature_files.py

Each case proves a distinct behavioural facet; the suite generates a synthetic
Ed25519 key pair once and uses it across all cases so signatures are always
real — the checker cannot pass on a fake-length or fake-format blob.

Case 2 is the **primary red run for the presence invariant**: a ``.json``
with no sibling ``.sig`` goes red, then green once the ``.sig`` is added.

Case 10 is the **primary red run for the validity invariant**: a manifest
with the previous release's signature (the stale-sig scenario from #810 and
issue #714) goes red where the old presence-only gate would have gone green.
This is the mutation the tightened gate exists to catch.

Case 12 is an additional red run proving that a structurally-valid 64-byte
signature signed by a *different* key fails — i.e. the checker does real
verification, not just length-checking.

A check that has never been seen to fail is not a check.
"""

from __future__ import annotations

import base64
import io
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
)

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_pages_signature_files  # noqa: E402  (after sys.path fixup)


def _run_main(args: list[str]) -> tuple[int, str, str]:
    """Invoke ``main()`` with all output captured; return ``(rc, stdout, stderr)``.

    Suppresses stdout and stderr so that workflow commands emitted by failing
    paths (``::error::FAIL: ...``, ``::error::directory not found: ...``) are
    not written into the Actions log of this test run. Without this, every
    green test run would fire the same ``::error::`` annotations that the gate
    uses to signal a real missing or invalid signature — training readers to
    ignore exactly the alarm this gate exists to raise.

    ``SystemExit`` is caught and converted to its integer exit code so callers
    always receive a plain ``(rc, out, err)`` tuple — ``parse_pinned_key``
    calls ``sys.exit(2)`` on failure, which would otherwise propagate past the
    context managers and terminate the test process.

    Callers that need only the exit code unpack as ``rc, _, _ = _run_main(...)``.
    Callers that also assert message text unpack ``out`` or ``err`` directly.
    """
    buf_out, buf_err = io.StringIO(), io.StringIO()
    with redirect_stdout(buf_out), redirect_stderr(buf_err):
        try:
            rc = check_pages_signature_files.main(args)
        except SystemExit as exc:
            if not isinstance(exc.code, int):
                raise AssertionError(
                    f"check_pages_signature_files exited with a non-int code "
                    f"({exc.code!r}); the checker's documented contract is "
                    f"exit 0 (all good), 1 (failures), or 2 (fatal error). "
                    f"A bare sys.exit() violates that contract."
                ) from exc
            rc = exc.code
    return rc, buf_out.getvalue(), buf_err.getvalue()


def _make_key_source(td: Path, pub_b64: str) -> Path:
    """Write a minimal synthetic update_config.dart containing *pub_b64*."""
    src = td / "update_config.dart"
    src.write_text(
        f"const String kUpdateManifestPublicKey =\n    '{pub_b64}';\n",
        encoding="utf-8",
    )
    return src


def _cases() -> None:
    # ------------------------------------------------------------------
    # Synthetic key pair used across all cases.  One pair for the
    # "correct" key; a second pair for wrong-key tests.
    # ------------------------------------------------------------------
    priv_key = Ed25519PrivateKey.generate()
    pub_bytes = priv_key.public_key().public_bytes_raw()
    pub_b64 = base64.b64encode(pub_bytes).decode()

    wrong_priv = Ed25519PrivateKey.generate()

    def sign(content: bytes) -> str:
        """Return base64-encoded Ed25519 signature over *content*."""
        return base64.b64encode(priv_key.sign(content)).decode() + "\n"

    def sign_wrong(content: bytes) -> str:
        """Signature with the wrong (different) key — correct shape, won't verify."""
        return base64.b64encode(wrong_priv.sign(content)).decode() + "\n"

    # ------------------------------------------------------------------
    # Case 1: all *.sig files present and valid → exit 0
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        stable_bytes = b'{"channel":"stable"}\n'
        beta_bytes = b'{"channel":"beta"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        (root / "stable.json.sig").write_text(sign(stable_bytes), encoding="utf-8")
        (root / "beta.json").write_bytes(beta_bytes)
        (root / "beta.json.sig").write_text(sign(beta_bytes), encoding="utf-8")
        # A non-JSON file should be ignored.
        (root / "index.html").write_text("<html></html>\n", encoding="utf-8")
        result = check_pages_signature_files.check(root)
        assert result == [], f"case 1 expected no missing sigs, got: {result}"
        rc, _, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 0, f"case 1 expected exit 0, got: {rc}"

    # ------------------------------------------------------------------
    # Case 2 (RED RUN): one .sig file missing → exit 1, message names the file
    #
    # This is the presence-invariant mutation: beta.json exists,
    # beta.json.sig does not.  This is the exact state that caused the
    # #714 incident.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        stable_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        (root / "stable.json.sig").write_text(sign(stable_bytes), encoding="utf-8")
        (root / "beta.json").write_text('{"channel":"beta"}\n', encoding="utf-8")
        # beta.json.sig intentionally absent

        missing = check_pages_signature_files.check(root)
        assert missing == ["beta.json"], (
            f"case 2 expected ['beta.json'] to be missing, got: {missing}"
        )
        rc, out, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 1, (
            f"case 2 (red run): expected exit 1 on missing beta.json.sig, got: {rc}"
        )
        assert "beta.json.sig" in out, (
            f"case 2: expected emitted message to name the missing file (beta.json.sig), got: {out!r}"
        )

        # Now add the missing .sig file — check must pass.
        beta_bytes = (root / "beta.json").read_bytes()
        (root / "beta.json.sig").write_text(sign(beta_bytes), encoding="utf-8")
        missing_after = check_pages_signature_files.check(root)
        assert missing_after == [], (
            f"case 2 expected no missing sigs after fix, got: {missing_after}"
        )
        rc_after, _, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc_after == 0, (
            f"case 2 (green run): expected exit 0 after adding beta.json.sig, got: {rc_after}"
        )

    # ------------------------------------------------------------------
    # Case 3: all *.sig files missing → exit 1, message names ALL files
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        (root / "stable.json").write_text('{"channel":"stable"}\n', encoding="utf-8")
        (root / "beta.json").write_text('{"channel":"beta"}\n', encoding="utf-8")

        missing = check_pages_signature_files.check(root)
        assert sorted(missing) == ["beta.json", "stable.json"], (
            f"case 3 expected both json files missing, got: {missing}"
        )
        rc, out, _ = _run_main([str(root), "--key-source", str(key_src)])
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
        key_src = _make_key_source(root, pub_b64)
        (root / ".nojekyll").write_text("", encoding="utf-8")
        (root / "index.html").write_text("<html></html>\n", encoding="utf-8")

        missing = check_pages_signature_files.check(root)
        assert missing == [], f"case 4 expected no missing sigs, got: {missing}"
        rc, _, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 0, f"case 4 expected exit 0 on empty root, got: {rc}"

    # ------------------------------------------------------------------
    # Case 5: orphaned *.json.sig with no corresponding *.json → exit 0
    #
    # Deliberate scope: we assert every .json has a .sig — not the reverse.
    # An orphaned .sig is harmless to the update client.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        (root / "stable.json.sig").write_text("orphaned\n", encoding="utf-8")
        # stable.json intentionally absent — only the .sig exists

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 5 expected no missing sigs for orphaned-sig state, got: {missing}"
        )
        rc, _, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 0, f"case 5 expected exit 0 on orphaned sig, got: {rc}"

    # ------------------------------------------------------------------
    # Case 6: *.json.sig exists as a directory, not a file → exit 1
    #
    # sig_file.exists() returns True for a directory, so a gate using
    # exists() passes on a directory-masquerading-as-sig. is_file() is the
    # correct predicate — the check asserts a sibling *.json.sig *file*.
    # This case proves the guard uses is_file(), not just exists().
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        (root / "beta.json").write_text('{"channel":"beta"}\n', encoding="utf-8")
        (root / "beta.json.sig").mkdir()  # directory masquerading as sig file

        missing = check_pages_signature_files.check(root)
        assert missing == ["beta.json"], (
            f"case 6 expected ['beta.json'] missing (directory is not a sig file), got: {missing}"
        )
        rc, _, _ = _run_main([str(root), "--key-source", str(key_src)])
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
        key_src = _make_key_source(root, pub_b64)
        stable_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        (root / "stable.json.sig").write_text(sign(stable_bytes), encoding="utf-8")
        (root / "beta.json").mkdir()  # directory, not a manifest file; no sig needed

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 7 expected no missing sigs (directory *.json skipped), got: {missing}"
        )
        rc, _, _ = _run_main([str(root), "--key-source", str(key_src)])
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
        # The root-directory check fires first (main() line 213); the key
        # source is never opened, so no --key-source is needed here.
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
        key_src = _make_key_source(root, pub_b64)
        stable_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        (root / "stable.json.sig").write_text(sign(stable_bytes), encoding="utf-8")
        subdir = root / "guide"
        subdir.mkdir()
        # A hypothetical JSON in a subdirectory — must not trigger the check.
        (subdir / "something.json").write_text('{"nested":true}\n', encoding="utf-8")

        missing = check_pages_signature_files.check(root)
        assert missing == [], (
            f"case 9 expected no missing sigs (subdirectory JSON ignored), got: {missing}"
        )
        rc, _, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 0, f"case 9 expected exit 0 on subdirectory JSON, got: {rc}"

    # ------------------------------------------------------------------
    # Case 10 (RED RUN — validity): stale signature → exit 1
    #
    # The stale-sig scenario from #810: publish an updated manifest beside
    # the *previous* release's signature.  The signature is present (the
    # presence gate from #806 would pass), but it was computed over the old
    # manifest bytes — it cannot verify against the new manifest.
    #
    # This is the mutation the tightened gate exists to catch. The presence-
    # only gate went green; the validity gate must go red.
    #
    # After updating the signature to match the new manifest, the gate must
    # go green — a gate that fails always is not a gate.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        old_bytes = b'{"channel":"beta","version":"0.1.0-beta.5"}\n'
        new_bytes = b'{"channel":"beta","version":"0.1.0-beta.6"}\n'
        (root / "beta.json").write_bytes(new_bytes)
        # Sig is from the PREVIOUS release — presence check passes, validity must fail.
        (root / "beta.json.sig").write_text(sign(old_bytes), encoding="utf-8")

        rc, out, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 1, (
            f"case 10 (red run): expected exit 1 on stale sig (new manifest + old sig), got: {rc}"
        )
        assert "beta.json.sig" in out, (
            f"case 10: expected emitted message to name beta.json.sig, got: {out!r}"
        )

        # Update the sig to match the new manifest bytes — gate must pass.
        (root / "beta.json.sig").write_text(sign(new_bytes), encoding="utf-8")
        rc_after, _, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc_after == 0, (
            f"case 10 (green run): expected exit 0 after updating sig to new manifest, got: {rc_after}"
        )

    # ------------------------------------------------------------------
    # Case 11: key-source parse failure → exit 2
    #
    # If kUpdateManifestPublicKey cannot be parsed from the Dart source,
    # the gate must fail loudly (exit 2) rather than falling back to a
    # hardcoded constant. This tests the parse-fail path.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        # Write a key source that has no kUpdateManifestPublicKey declaration.
        bad_key_src = root / "no_key.dart"
        bad_key_src.write_text("// no key here\n", encoding="utf-8")
        stable_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        (root / "stable.json.sig").write_text(sign(stable_bytes), encoding="utf-8")

        rc, _, _ = _run_main([str(root), "--key-source", str(bad_key_src)])
        assert rc == 2, (
            f"case 11 expected exit 2 on missing kUpdateManifestPublicKey, got: {rc}"
        )

    # ------------------------------------------------------------------
    # Case 12 (RED RUN — validity): wrong-key signature → exit 1
    #
    # A structurally valid 64-byte signature signed by a different Ed25519
    # key — correct shape, correct length, valid base64 — must still fail
    # verification. This distinguishes real Ed25519 verification from a
    # length or format check.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        stable_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        # Signed by wrong_priv (different key) — structurally valid, won't verify.
        (root / "stable.json.sig").write_text(sign_wrong(stable_bytes), encoding="utf-8")

        rc, out, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 1, (
            f"case 12 (red run): expected exit 1 on wrong-key sig, got: {rc}"
        )
        assert "stable.json.sig" in out, (
            f"case 12: expected emitted message to name stable.json.sig, got: {out!r}"
        )

    # ------------------------------------------------------------------
    # Case 13: truncated / malformed sig body → exit 1
    #
    # A .sig file that is not valid base64, or that decodes to fewer than
    # 64 bytes, must fail with exit 1. This tests the format-error path
    # distinct from the cryptographic-failure path.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        (root / "stable.json").write_text('{"channel":"stable"}\n', encoding="utf-8")
        # A truncated base64 blob (decodes to fewer than 64 bytes).
        (root / "stable.json.sig").write_text("c2lnbmF0dXJl\n", encoding="utf-8")

        rc, out, _ = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 1, (
            f"case 13 expected exit 1 on truncated sig, got: {rc}"
        )
        assert "stable.json.sig" in out, (
            f"case 13: expected emitted message to name stable.json.sig, got: {out!r}"
        )

    # ------------------------------------------------------------------
    # Case 14: gate resolves the default key source from any working directory
    #
    # _DEFAULT_KEY_SOURCE is derived from Path(__file__).resolve().parents[2]
    # so it is always an absolute path. A relative default would resolve
    # against the process cwd, silently breaking the gate when invoked from
    # outside the repo root (e.g. in a future re-factoring of the workflow
    # steps). This case catches a reintroduction of that defect (issue #809
    # pattern, fixed here alongside #810).
    #
    # The fixture is signed with the *wrong* key (not the actual pinned key),
    # so rc=1 proves the default source was **found and parsed** (not rc=2)
    # while the signature correctly fails verification. rc=2 would mean the
    # default path was a relative path that broke under a different cwd.
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        manifest_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(manifest_bytes)
        # Sign with the WRONG key (not the real pinned key): valid shape, won't verify.
        (root / "stable.json.sig").write_text(sign_wrong(manifest_bytes), encoding="utf-8")

        import os
        original_cwd = os.getcwd()
        foreign_cwd = tempfile.gettempdir()
        try:
            os.chdir(foreign_cwd)
            # No --key-source: must find the real update_config.dart by absolute path.
            rc, out, err = _run_main([str(root)])
        finally:
            os.chdir(original_cwd)

        assert rc == 1, (
            f"case 14 expected exit 1 (validity error) from cwd={foreign_cwd!r}, got: {rc} "
            f"(rc=2 means the default key source resolved relatively, not absolutely)"
        )
        assert "does not verify" in out, (
            f"case 14: expected validity error (key found, sig wrong), got out={out!r} err={err!r}"
        )
        assert "cannot read key source" not in err, (
            f"case 14: got key-not-found error, meaning default path is still relative: {err!r}"
        )


    # ------------------------------------------------------------------
    # Case 15 (RED RUN — contract): non-UTF-8 .sig → exit 1, structured error
    #
    # A .sig file containing raw non-UTF-8 bytes raises UnicodeDecodeError
    # in an unguarded read_text() call. The guard added in the OSError/
    # UnicodeDecodeError fix must convert that into a structured failure
    # (exit 1, named file in the error message) rather than a traceback.
    #
    # This case is the guard's proof-of-reachability: write_bytes() is used
    # deliberately (not write_text) so the .sig contains bytes that are
    # not valid UTF-8. Without the UnicodeDecodeError guard, the exception
    # escapes verify_signatures() and produces a traceback — the 0/1/2
    # exit-code contract silently becomes "0/1/2/traceback".
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        key_src = _make_key_source(root, pub_b64)
        stable_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        # Raw non-UTF-8 bytes — not a valid signature, not valid UTF-8.
        (root / "stable.json.sig").write_bytes(b"\xff\xfe not utf-8")

        rc, out, err = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 1, (
            f"case 15 expected exit 1 on non-UTF-8 sig, got: {rc}"
        )
        assert "stable.json.sig" in out, (
            f"case 15: expected emitted message to name stable.json.sig, got: {out!r}"
        )
        assert "Traceback" not in err, (
            f"case 15: got a traceback instead of a structured error — "
            f"the UnicodeDecodeError guard is missing or bypassed: {err!r}"
        )

    # ------------------------------------------------------------------
    # Case 16 (RED RUN — contract): key with non-base64 chars → exit 2
    #
    # Python's lax base64.b64decode() silently discards non-alphabet
    # characters rather than raising. A corrupted kUpdateManifestPublicKey
    # that has junk chars injected (e.g. "!!!") decodes laxly to the same
    # 32-byte key (the junk is dropped), so the gate reports rc=0 —
    # green, as if the key string were intact.
    #
    # The validate=True fix causes the decode to raise binascii.Error on
    # non-base64 chars, converting this silent pass into exit 2.
    #
    # RED (without fix, lax decode): rc=0 — gate passes on corrupt key
    # GREEN (with fix, strict decode): rc=2 — loud rejection
    # ------------------------------------------------------------------
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        # Inject '!!!' into the middle of the key — non-base64, silently
        # dropped by lax b64decode, rejected by strict (validate=True).
        corrupted_key = pub_b64[:15] + '!!!' + pub_b64[15:]
        key_src = _make_key_source(root, corrupted_key)
        stable_bytes = b'{"channel":"stable"}\n'
        (root / "stable.json").write_bytes(stable_bytes)
        sig_b64 = base64.b64encode(priv_key.sign(stable_bytes)).decode()
        (root / "stable.json.sig").write_text(sig_b64, encoding="utf-8")

        rc, out, err = _run_main([str(root), "--key-source", str(key_src)])
        assert rc == 2, (
            f"case 16 expected exit 2 on corrupted key (non-base64 chars), "
            f"got rc={rc}; without validate=True the lax decoder would "
            f"silently drop the junk and report rc=0 (green on a corrupt key). "
            f"out={out!r} err={err!r}"
        )
        assert "not valid base64" in err, (
            f"case 16: expected 'not valid base64' in error output, got: {err!r}"
        )


def main() -> int:
    _cases()
    print("OK: all check_pages_signature_files tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
