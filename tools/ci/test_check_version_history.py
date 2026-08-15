#!/usr/bin/env python3
"""Offline tests for ``check_version_history.py`` -- the version-ledger gate.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_version_history.py

The gate is only worth having if it fails when a version bump ships no entry in
the design doc that now holds the log, and stays quiet otherwise, so the cases
below are split into exactly those two groups. Each builds a throwaway git
repository and drives the real script end to end, because the part most likely
to break -- reading a constant out of two refs with ``git show`` -- only exists
in that integration.

The case that matters most is `bump logged against the wrong version`: it is the
one a naive "did the doc change?" gate passes and this one must fail. If that
case ever goes green, the gate has stopped doing the thing it was written for.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_version_history.py"

TAXONOMY_SOURCE = "packages/compendium_core/lib/src/taxonomy/contra_taxonomy.dart"
TAXONOMY_DOC = "docs/design/figure-taxonomy.md"
SCHEMA_SOURCE = "packages/compendium_core/lib/src/storage/database.dart"
SCHEMA_DOC = "docs/design/storage.md"

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def taxonomy_source(version: int) -> str:
    return f"const int contraTaxonomyVersion = {version};\n"


def schema_source(version: int) -> str:
    return f"const int kCompendiumSchemaVersion = {version};\n"


def taxonomy_doc(*entries: str) -> str:
    body = "\n".join(f"- {e}" for e in entries)
    return f"# Figure taxonomy\n\n## Taxonomy version history\n\n{body}\n\n## Next\n"


def schema_doc(retired: list[str], supported: list[str]) -> str:
    """A doc with the same two-subsection shape as the real storage.md."""
    r = "\n".join(f"- {e}" for e in retired)
    s = "\n".join(f"- {e}" for e in supported)
    return (
        "# Storage\n\n## Schema version history\n\n"
        f"### Retired (v1-v19): history only\n\n{r}\n\n"
        f"### Supported (v20 and later)\n\n{s}\n\n## The delete model\n"
    )


class Repo:
    """A throwaway git repository the real script can be pointed at."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self._git("init", "-q", ".")
        self._git("config", "user.email", "t@example.invalid")
        self._git("config", "user.name", "test")

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", *args], cwd=self.root, capture_output=True, text=True, check=False
        )

    def write(self, path: str, text: str) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def commit(self, message: str) -> None:
        self._git("add", "-A")
        self._git("commit", "-qm", message)

    def run(self, *args: str) -> subprocess.CompletedProcess:
        """Invoke the gate with exactly ``args``, so argument handling is testable."""
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )


def seed(repo: Repo) -> None:
    """A base commit at taxonomy v28 / schema v25, both properly logged."""
    repo.write(TAXONOMY_SOURCE, taxonomy_source(28))
    repo.write(SCHEMA_SOURCE, schema_source(25))
    repo.write(TAXONOMY_DOC, taxonomy_doc("v27 (#749): grip params.", "v28 (#976): chain hand."))
    repo.write(
        SCHEMA_DOC,
        schema_doc(["v1 (2026-07-10): initial schema."], ["v25 (#898): device sync."]),
    )
    repo.commit("base")


def case(name: str):
    """Run one scenario in its own temporary repository."""

    def decorate(fn):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Repo(Path(tmp))
            seed(repo)
            print(f"{name}:")
            fn(repo)
        return fn

    return decorate


def main() -> int:
    # ---- the gate must FAIL ------------------------------------------------

    @case("taxonomy bump with no doc entry")
    def _(repo: Repo) -> None:
        repo.write(TAXONOMY_SOURCE, taxonomy_source(29))
        repo.commit("bump")
        res = repo.run("HEAD~1")
        check("exits 1", res.returncode == 1, f"exit={res.returncode}")
        check("names the missing entry", "'- v29' entry" in res.stdout, res.stdout)

    @case("bump logged against the wrong version")
    def _(repo: Repo) -> None:
        # The realistic mistake, and the one a "did the doc change?" gate would
        # wave through: the doc IS edited in the same commit, but the entry that
        # changed is the previous version's.
        repo.write(TAXONOMY_SOURCE, taxonomy_source(29))
        repo.write(
            TAXONOMY_DOC,
            taxonomy_doc("v27 (#749): grip params.", "v28 (#976): chain hand, reworded."),
        )
        repo.commit("bump and edit the wrong entry")
        res = repo.run("HEAD~1")
        changed = subprocess.run(
            ["git", "diff", "--name-only", "HEAD~1", "HEAD"],
            cwd=repo.root, capture_output=True, text=True, check=False,
        ).stdout
        check("the naive premise holds (the doc did change)", TAXONOMY_DOC in changed)
        check("exits 1 anyway", res.returncode == 1, f"exit={res.returncode}")

    @case("schema bump with no doc entry")
    def _(repo: Repo) -> None:
        repo.write(SCHEMA_SOURCE, schema_source(26))
        repo.commit("bump")
        res = repo.run("HEAD~1")
        check("exits 1", res.returncode == 1, f"exit={res.returncode}")
        check("names the schema doc", SCHEMA_DOC in res.stdout, res.stdout)

    @case("bump with the history section deleted")
    def _(repo: Repo) -> None:
        repo.write(TAXONOMY_SOURCE, taxonomy_source(29))
        repo.write(TAXONOMY_DOC, "# Figure taxonomy\n\n## Next\n")
        repo.commit("bump, drop the section")
        res = repo.run("HEAD~1")
        check("exits 1", res.returncode == 1, f"exit={res.returncode}")
        check("says the section is missing", "no '## Taxonomy version history'" in res.stdout
              or "has no" in res.stdout, res.stdout)

    @case("unresolvable base ref")
    def _(repo: Repo) -> None:
        res = repo.run("no-such-ref", "HEAD")
        # 2, not 1: a gate that could not look must not report either verdict.
        check("exits 2", res.returncode == 2, f"exit={res.returncode}")

    @case("head ref supplied but empty")
    def _(repo: Repo) -> None:
        # An unset CI variable, not a request for the default. Silently reading
        # it as HEAD would check a different pair of commits than the caller
        # asked for, which is the same class of mistake as an unresolvable ref.
        res = repo.run("HEAD", "   ")
        check("exits 2", res.returncode == 2, f"exit={res.returncode}")

    # ---- the gate must stay QUIET -----------------------------------------

    @case("no bump at all")
    def _(repo: Repo) -> None:
        repo.write(TAXONOMY_DOC, taxonomy_doc("v27 (#749): grip params.", "v28 (#976): chain hand."))
        repo.write("README.md", "unrelated\n")
        repo.commit("unrelated change")
        res = repo.run("HEAD~1")
        check("exits 0", res.returncode == 0, res.stdout + res.stderr)

    @case("taxonomy bump with its entry appended")
    def _(repo: Repo) -> None:
        repo.write(TAXONOMY_SOURCE, taxonomy_source(29))
        repo.write(
            TAXONOMY_DOC,
            taxonomy_doc(
                "v27 (#749): grip params.",
                "v28 (#976): chain hand.",
                "v29 (#1000): adds a move.",
            ),
        )
        repo.commit("bump and log")
        res = repo.run("HEAD~1")
        check("exits 0", res.returncode == 0, res.stdout + res.stderr)

    @case("schema bump logged under the Supported subsection")
    def _(repo: Repo) -> None:
        # The entry sits under a `###` inside the section, which is how the real
        # storage.md is laid out; a section reader that stopped at the first
        # sub-heading would reject a correctly logged bump.
        repo.write(SCHEMA_SOURCE, schema_source(26))
        repo.write(
            SCHEMA_DOC,
            schema_doc(
                ["v1 (2026-07-10): initial schema."],
                ["v25 (#898): device sync.", "v26 (#1000): adds a column."],
            ),
        )
        repo.commit("bump and log")
        res = repo.run("HEAD~1")
        check("exits 0", res.returncode == 0, res.stdout + res.stderr)

    @case("head omitted defaults to HEAD")
    def _(repo: Repo) -> None:
        repo.write(TAXONOMY_SOURCE, taxonomy_source(29))
        repo.write(
            TAXONOMY_DOC,
            taxonomy_doc("v28 (#976): chain hand.", "v29 (#1000): adds a move."),
        )
        repo.commit("bump and log")
        res = repo.run("HEAD~1")
        check("exits 0", res.returncode == 0, res.stdout + res.stderr)

    @case("v2-style entry does not satisfy a v20 bump")
    def _(repo: Repo) -> None:
        # Prefix trap: `- v2:` must not be read as the entry for v20.
        repo.write(SCHEMA_SOURCE, schema_source(20))
        repo.write(
            SCHEMA_DOC, schema_doc(["v1 (x): initial.", "v2 (x): search."], ["v25 (#898): sync."])
        )
        repo.commit("bump to 20 with only a v2 entry")
        res = repo.run("HEAD~1")
        check("exits 1", res.returncode == 1, f"exit={res.returncode}")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) failed:")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("all version-history gate checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
