#!/usr/bin/env python3
"""Unit tests for ``gen_release_notes.py``.

Pure-stdlib, assert-based (no pytest / no third-party deps), matching the
free/offline tooling constraint. Run directly::

    python3 tools/release/test_gen_release_notes.py

Exits non-zero on the first failed assertion (prints a traceback), or prints an
"OK" summary when every case passes.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_release_notes as g  # noqa: E402

# A representative CHANGELOG mirroring app/CHANGELOG.md's shape.
CHANGELOG = """\
# Changelog

All notable changes to Caller's Compendium (the app) are documented here.

## [Unreleased]

### Added

- Something not yet released.

## [0.2.0] - 2026-08-01

### Added

- A shiny new feature.

### Fixed

- A pesky bug.

## [0.1.0] - 2026-07-15

### Added

- Initial app scaffold.
"""

# A CHANGELOG whose newest entry has no trailing " - <date>" on the heading.
CHANGELOG_NO_DATE = """\
# Changelog

## [0.1.0]

### Added

- Initial app scaffold.
"""


def _cases() -> None:
    # 1. Exact-version extraction pulls the right section body only.
    body, found = g.build_notes(
        version="0.1.0", tag="v0.1.0", channel="stable",
        changelog_text=CHANGELOG,
    )
    assert found is True
    assert "Initial app scaffold." in body
    # Must NOT bleed into the 0.2.0 section above it.
    assert "shiny new feature" not in body
    assert "A pesky bug" not in body
    # Must NOT include the Unreleased section.
    assert "not yet released" not in body

    # 2. The sole beta grammar matches the same core section.
    body, found = g.build_notes(
        version="0.1.0-beta", tag="v0.1.0-beta", channel="beta",
        changelog_text=CHANGELOG,
    )
    assert found is True
    assert "Initial app scaffold." in body

    # 3. Beta channel prepends a clear pre-release banner naming the tag.
    assert "Beta / pre-release" in body
    assert "`v0.1.0-beta`" in body

    # 4. Stable channel has NO beta banner.
    body, found = g.build_notes(
        version="0.2.0", tag="v0.2.0", channel="stable",
        changelog_text=CHANGELOG,
    )
    assert found is True
    assert "Beta / pre-release" not in body
    assert "A shiny new feature." in body

    # 5. Footer is always present (both stable and beta). With macOS signed and
    #    Windows unsigned (default), the footer names Windows+Linux unsigned and
    #    macOS Developer ID-signed, and does NOT claim Azure Trusted Signing.
    for ch, ver, tag in (("stable", "0.2.0", "v0.2.0"),
                         ("beta", "0.1.0-beta", "v0.1.0-beta")):
        body, _ = g.build_notes(
            version=ver, tag=tag, channel=ch, changelog_text=CHANGELOG,
            macos_signed=True,
        )
        assert "**unsigned**" in body
        assert "**Developer ID-signed & notarized**" in body
        assert "Windows and Linux desktop builds are **unsigned**" in body
        assert "Azure Trusted Signing" in body  # named as the pending Windows leg
        assert "signed via Azure Trusted Signing" not in body  # but not claimed
        assert "`SHA256SUMS`" in body
        assert "maintainer publishes this draft after review" in body

    # 5b. Honest footer when NEITHER Windows nor macOS was signed (default):
    #     all three desktops reported unsigned, and NO false signed claim.
    for kwargs in ({}, {"macos_signed": False, "windows_signed": False}):
        body, _ = g.build_notes(
            version="0.2.0", tag="v0.2.0", channel="stable",
            changelog_text=CHANGELOG, **kwargs,
        )
        assert "Windows, Linux, and macOS desktop builds are **unsigned**" in body
        assert "Developer ID-signed & notarized" not in body
        assert "signed via Azure Trusted Signing" not in body
        assert "`SHA256SUMS`" in body
        assert "maintainer publishes this draft after review" in body

    # 5c. Windows signed via Azure Trusted Signing (macOS unsigned): the footer
    #     claims Windows signing and does NOT list Windows among the unsigned.
    body, _ = g.build_notes(
        version="0.2.0", tag="v0.2.0", channel="stable",
        changelog_text=CHANGELOG, windows_signed=True,
    )
    assert "Windows is **signed via Azure Trusted Signing**" in body
    assert "Linux and macOS desktop builds are **unsigned**" in body
    assert "Developer ID-signed & notarized" not in body

    # 5d. Both Windows and macOS signed: only Linux is unsigned, and both signed
    #     claims appear.
    body, _ = g.build_notes(
        version="0.2.0", tag="v0.2.0", channel="stable",
        changelog_text=CHANGELOG, windows_signed=True, macos_signed=True,
    )
    assert "Linux desktop builds are **unsigned**" in body
    assert "Windows is **signed via Azure Trusted Signing**" in body
    assert "macOS is **Developer ID-signed & notarized**" in body
    assert "this release" not in body  # nothing pending to activate

    # 6. Every selected release requires its shared core section.
    for version, tag, channel in (
        ("9.9.9", "v9.9.9", "stable"),
        ("9.9.9-beta", "v9.9.9-beta", "beta"),
    ):
        ok, message = g.check_section(
            version=version, tag=tag, channel=channel, changelog_text=CHANGELOG,
        )
        assert ok is False
        assert "9.9.9" in message

    # 8. Heading without a trailing date is matched too.
    section = g.extract_section(CHANGELOG_NO_DATE, "0.1.0")
    assert section is not None
    assert "Initial app scaffold." in section

    # 7. _core_version strips the selected beta suffix.
    assert g._core_version("0.1.0-beta") == "0.1.0"
    assert g._core_version("1.2.3") == "1.2.3"

    # 10. A version that is a prefix of another must not partial-match.
    #     Looking up 0.1 must NOT match the [0.1.0] heading.
    assert g.extract_section(CHANGELOG, "0.1") is None

    # --- check_section (the meta job's channel-conditional fail-fast guard) ---

    # 9. Stable release WITH a matching section -> ok.
    ok, msg = g.check_section(
        version="0.2.0", tag="v0.2.0", channel="stable", changelog_text=CHANGELOG,
    )
    assert ok is True, msg

    # 10. Stable release with NO matching section -> NOT ok.
    ok, msg = g.check_section(
        version="9.9.9", tag="v9.9.9", channel="stable", changelog_text=CHANGELOG,
    )
    assert ok is False
    assert "9.9.9" in msg and "Unreleased" in msg

    # 11. Beta release with NO matching section is also rejected.
    ok, msg = g.check_section(
        version="9.9.9-beta", tag="v9.9.9-beta", channel="beta",
        changelog_text=CHANGELOG,
    )
    assert ok is False

    # 12. Bare beta whose core has a section -> ok.
    ok, msg = g.check_section(
        version="0.1.0-beta", tag="v0.1.0-beta", channel="beta",
        changelog_text=CHANGELOG,
    )
    assert ok is True, msg

    # 13. The tool's --check CLI exits non-zero for either selected channel when
    #     the required shared section is absent.
    import io
    import contextlib
    from pathlib import Path
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        cl = Path(td) / "CHANGELOG.md"
        cl.write_text(CHANGELOG, encoding="utf-8")
        argv_common = ["--tag", "v9.9.9", "--changelog", str(cl), "--check"]
        with contextlib.redirect_stderr(io.StringIO()) as err:
            rc_stable = g.main(
                ["--version", "9.9.9", "--channel", "stable", *argv_common]
            )
        assert rc_stable == 1
        assert "::error::" in err.getvalue()
        rc_beta = g.main(
            ["--version", "9.9.9-beta", "--channel", "beta",
             "--tag", "v9.9.9-beta", "--changelog", str(cl), "--check"]
        )
        assert rc_beta == 1

        # 14. --macos-signing toggles the footer's macOS claim end-to-end via the
        #     CLI (default = unsigned; 'configured' = Developer ID-signed).
        out_default = Path(td) / "notes-default.md"
        rc = g.main(
            ["--version", "0.2.0", "--channel", "stable", "--tag", "v0.2.0",
             "--changelog", str(cl), "--output", str(out_default)]
        )
        assert rc == 0
        default_body = out_default.read_text(encoding="utf-8")
        assert "Developer ID-signed & notarized" not in default_body
        assert "**unsigned**" in default_body

        out_signed = Path(td) / "notes-signed.md"
        rc = g.main(
            ["--version", "0.2.0", "--channel", "stable", "--tag", "v0.2.0",
             "--macos-signing", "configured",
             "--changelog", str(cl), "--output", str(out_signed)]
        )
        assert rc == 0
        signed_body = out_signed.read_text(encoding="utf-8")
        assert "**Developer ID-signed & notarized**" in signed_body

        # 14b. --windows-signing toggles the footer's Windows claim end-to-end.
        #      Default = unsigned (no Azure claim); 'configured' = Azure-signed.
        assert "signed via Azure Trusted Signing" not in default_body
        out_win = Path(td) / "notes-win.md"
        rc = g.main(
            ["--version", "0.2.0", "--channel", "stable", "--tag", "v0.2.0",
             "--windows-signing", "configured",
             "--changelog", str(cl), "--output", str(out_win)]
        )
        assert rc == 0
        win_body = out_win.read_text(encoding="utf-8")
        assert "Windows is **signed via Azure Trusted Signing**" in win_body

    # 15. Reject a beta counter, rc, malformed tags, mismatched channel, and
    # leading-zero core values rather than treating every hyphen as a beta.
    for version, tag, channel in (
        ("0.1.0-beta.1", "v0.1.0-beta.1", "beta"),
        ("0.1.0-rc.1", "v0.1.0-rc.1", "beta"),
        ("01.1.0", "v01.1.0", "stable"),
        ("0.1.0", "v0.1.0-beta", "stable"),
        ("0.1.0-beta", "v0.1.0-beta", "stable"),
    ):
        try:
            g.validate_release(version=version, tag=tag, channel=channel)
            raise AssertionError(f"accepted invalid release identity: {tag}")
        except ValueError:
            pass


def main() -> int:
    _cases()
    print("OK: all gen_release_notes tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
