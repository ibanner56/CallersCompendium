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

Flutter build: `0.2.0+3`.

### Added

- A shiny new feature.

### Fixed

- A pesky bug.

## [0.1.0] - 2026-07-15

Flutter build: `0.1.0+1`.

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
    assert "Flutter build: `0.1.0+1`." in body
    # Must NOT bleed into the 0.2.0 section above it.
    assert "shiny new feature" not in body
    assert "A pesky bug" not in body
    # Must NOT include the Unreleased section.
    assert "not yet released" not in body

    # 2. Core-suffix stripping: a prerelease version matches the [x.y.z] core.
    body, found = g.build_notes(
        version="0.1.0-rc.3", tag="v0.1.0-rc.3", channel="beta",
        changelog_text=CHANGELOG,
    )
    assert found is True
    assert "Initial app scaffold." in body

    # 3. Beta channel prepends a clear pre-release banner naming the tag.
    assert "Beta / pre-release" in body
    assert "`v0.1.0-rc.3`" in body

    # 4. Stable channel has NO beta banner.
    body, found = g.build_notes(
        version="0.2.0", tag="v0.2.0", channel="stable",
        changelog_text=CHANGELOG,
    )
    assert found is True
    assert "Beta / pre-release" not in body
    assert "A shiny new feature." in body

    # 5. Footer is always present (both stable and beta).
    for ch, ver, tag in (("stable", "0.2.0", "v0.2.0"),
                         ("beta", "0.1.0-rc.3", "v0.1.0-rc.3")):
        body, _ = g.build_notes(
            version=ver, tag=tag, channel=ch, changelog_text=CHANGELOG,
        )
        assert "**UNSIGNED**" in body
        assert "`SHA256SUMS`" in body
        assert "maintainer publishes this draft after review" in body

    # 6. Graceful fallback when no matching section exists.
    body, found = g.build_notes(
        version="9.9.9", tag="v9.9.9", channel="stable",
        changelog_text=CHANGELOG,
    )
    assert found is False
    assert "No `## [9.9.9]` entry" in body
    # Footer still present so the safety wording never gets lost.
    assert "**UNSIGNED**" in body

    # 7. Fallback for a prerelease still shows the beta banner + warning.
    body, found = g.build_notes(
        version="9.9.9-beta.1", tag="v9.9.9-beta.1", channel="beta",
        changelog_text=CHANGELOG,
    )
    assert found is False
    assert "Beta / pre-release" in body
    assert "No `## [9.9.9]` entry" in body

    # 8. Heading without a trailing date is matched too.
    section = g.extract_section(CHANGELOG_NO_DATE, "0.1.0")
    assert section is not None
    assert "Initial app scaffold." in section

    # 9. _core_version strips prerelease and build metadata.
    assert g._core_version("0.1.0-rc.3") == "0.1.0"
    assert g._core_version("0.1.0+1") == "0.1.0"
    assert g._core_version("1.2.3") == "1.2.3"

    # 10. A version that is a prefix of another must not partial-match.
    #     Looking up 0.1 must NOT match the [0.1.0] heading.
    assert g.extract_section(CHANGELOG, "0.1") is None

    # --- check_section (the meta job's channel-conditional fail-fast guard) ---

    # 11. Stable release WITH a matching section -> ok.
    ok, msg = g.check_section(
        version="0.2.0", channel="stable", changelog_text=CHANGELOG,
    )
    assert ok is True, msg

    # 12. Stable release with NO matching section -> NOT ok (fail fast in meta).
    ok, msg = g.check_section(
        version="9.9.9", channel="stable", changelog_text=CHANGELOG,
    )
    assert ok is False
    assert "9.9.9" in msg and "Unreleased" in msg

    # 13. Beta/rc prerelease with NO matching section -> ok (graceful fallback);
    #     matched on the core, so the meta guard never blocks a prerelease.
    ok, msg = g.check_section(
        version="9.9.9-rc.1", channel="beta", changelog_text=CHANGELOG,
    )
    assert ok is True, msg

    # 14. Beta prerelease WHOSE core has a section -> ok.
    ok, msg = g.check_section(
        version="0.1.0-rc.3", channel="beta", changelog_text=CHANGELOG,
    )
    assert ok is True, msg

    # 15. The tool's --check CLI exits non-zero for a stable-missing section
    #     (proves the meta guard's actual invocation fails), and exits 0 for a
    #     beta-missing section.
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
            ["--version", "9.9.9-rc.1", "--channel", "beta",
             "--tag", "v9.9.9-rc.1", "--changelog", str(cl), "--check"]
        )
        assert rc_beta == 0


def main() -> int:
    _cases()
    print("OK: all gen_release_notes tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
