#!/usr/bin/env python3
"""Offline tests for ``check_version_bump_policy.py`` -- the vNext bump gate.

Pure-stdlib, assert-based, run directly::

    python3 tools/ci/test_check_version_bump_policy.py

Two layers. ``judge`` is a pure function holding the whole policy table, so it
is exercised exhaustively without git. The rest build a throwaway repository
with a release tag, a base and a head, and drive the real script, because the
part most likely to break -- reading the constants from three refs, and
choosing the newest tag -- only exists in that integration.

The case that matters most is the second bump: ``base`` already ahead of the
tag, ``head`` ahead again. It is the mistake this gate was written for; if it
ever goes green the gate has stopped doing its job.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_version_bump_policy.py"
sys.path.insert(0, str(HERE))

import check_version_bump_policy as gate  # noqa: E402

FAILURES: list[str] = []
SCHEMA, TAXONOMY, WIRE, ECD = gate.CONSTANTS[:4]
# Spelled out rather than unpacked, so that dropping it from CONSTANTS turns the
# square scenarios red instead of crashing the import.
SQUARE = gate.Constant("squareTaxonomyVersion", f"{gate.CORE_LIB}/taxonomy/square_taxonomy.dart")


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def declaration(constant: gate.Constant, value: int) -> str:
    return f"const int {constant.name} = {value};\n"


class Repo:
    """A throwaway git repository the real script can be pointed at."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.clock = 1_700_000_000
        self._git("init", "-q", ".")
        self._git("config", "user.email", "t@example.invalid")
        self._git("config", "user.name", "test")

    def _git(self, *args: str, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, **env},
        )

    def set_versions(
        self, schema: int, taxonomy: int, wire: int, ecd: int | None = 1, square: int | None = 1
    ) -> None:
        """``ecd=None`` or ``square=None`` leaves that constant undeclared, as at a release that predates it."""
        pairs = [(SCHEMA, schema), (TAXONOMY, taxonomy), (WIRE, wire)]
        if ecd is not None:
            pairs.append((ECD, ecd))
        if square is not None:
            pairs.append((SQUARE, square))
        for constant, value in pairs:
            target = self.root / constant.source
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(declaration(constant, value), encoding="utf-8")

    def commit(self, message: str) -> None:
        self.clock += 86_400
        stamp = f"{self.clock} +0000"
        self._git("add", "-A")
        self._git(
            "commit", "-q", "--allow-empty", "-m", message, GIT_AUTHOR_DATE=stamp, GIT_COMMITTER_DATE=stamp
        )

    def tag(self, name: str) -> None:
        """An annotated tag at HEAD, dated by the repo clock so ordering is real."""
        self.clock += 86_400
        self._git(
            "tag", "-a", name, "-m", name, GIT_COMMITTER_DATE=f"{self.clock} +0000"
        )

    def run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )


def scenario(name: str, tag: tuple[int, int, int], base: tuple[int, int, int], head: tuple[int, int, int]):
    """Run one tag/base/head triple in its own repository; returns (repo, result)."""
    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.set_versions(*tag)
        repo.commit("release")
        repo.tag("v1.0.0")
        repo.set_versions(*base)
        repo.commit("base")
        repo.set_versions(*head)
        repo.commit("head")
        print(f"{name}:")
        return repo.run("HEAD~1", "HEAD")


def judge_table() -> None:
    labels = ("tag", "base", "head")
    rows = [
        # (tag, base, head, expected code, why)
        (5, 5, 5, 0, "no bump at the tag"),
        (5, 7, 7, 0, "no bump while vNext is banked"),
        (5, 5, 6, 0, "first bump after release"),
        (5, 6, 7, 1, "second bump while base is already vNext"),
        (5, 7, 9, 1, "base several ahead, head bumps again"),
        (5, 6, 5, 1, "head below base"),
        (5, 5, 4, 1, "head below base, base at tag"),
        (5, 4, 4, 2, "base behind the tag"),
        (5, 4, 6, 2, "base behind the tag even though head is ahead"),
        (None, 1, 1, 0, "constant absent at the tag, unchanged: all of it is vNext"),
        (None, 1, 2, 1, "constant absent at the tag, bumped again: stack on vNext"),
        (None, None, 1, 2, "constant absent at base too"),
        (5, None, 5, 2, "base unreadable"),
        (5, 5, None, 2, "head unreadable"),
    ]
    print("judge table:")
    for tag, base, head, expected, why in rows:
        code, message = gate.judge("c", tag, base, head, labels)
        check(f"{why} -> {expected}", code == expected, f"got {code}: {message}")
    _, message = gate.judge("c", 5, 6, 7, labels)
    check("failure names constant and values", "c 6 -> 7" in message and "amend" in message.lower(), message)


def main() -> int:
    judge_table()

    # ---- the gate must FAIL ------------------------------------------------

    res = scenario("contra taxonomy bumped a second time", (5, 39, 1), (5, 40, 1), (5, 41, 1))
    check("exits 1", res.returncode == 1, f"exit={res.returncode} {res.stdout}")
    check("names the constant", "contraTaxonomyVersion 40 -> 41" in res.stdout, res.stdout)
    check("says to amend vNext", "unreleased vNext" in res.stdout, res.stdout)
    check("does not blame the others", "kCompendiumSchemaVersion" in res.stdout and "::error::kCompendiumSchemaVersion" not in res.stdout, res.stdout)

    res = scenario("sync wire version bumped a second time", (5, 39, 1), (5, 39, 2), (5, 39, 3))
    check("exits 1 naming the wire constant", res.returncode == 1 and "syncWireVersion 2 -> 3" in res.stdout, res.stdout)

    res = scenario("schema decreased", (5, 39, 1), (6, 39, 1), (5, 39, 1))
    check("exits 1", res.returncode == 1, f"exit={res.returncode} {res.stdout}")

    # One bump is legitimate and must not excuse another constant's second bump.
    res = scenario("one legitimate bump alongside a second bump", (5, 39, 1), (5, 40, 1), (6, 41, 1))
    check("exits 1", res.returncode == 1, f"exit={res.returncode} {res.stdout}")
    check("the legitimate bump is reported ok", "OK: kCompendiumSchemaVersion 5 -> 6" in res.stdout, res.stdout)
    check("the second bump is the failure", "::error::contraTaxonomyVersion 40 -> 41" in res.stdout, res.stdout)

    # A definite violation outranks an unreadable constant elsewhere.
    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.set_versions(5, 39, 1)
        repo.commit("release")
        repo.tag("v1.0.0")
        repo.set_versions(5, 40, 1)
        repo.commit("base")
        repo.set_versions(5, 41, 1)
        (repo.root / WIRE.source).write_text("// renamed\n", encoding="utf-8")
        repo.commit("head")
        print("a failure and an unreadable constant together:")
        res = repo.run("HEAD~1", "HEAD")
        check("exits 1, the actionable one", res.returncode == 1, f"exit={res.returncode} {res.stdout}")

    # ecdTaxonomyVersion is absent at v0.10.0-beta, so the release carries nothing of it.
    def ecd_scenario(base_ecd: int, head_ecd: int):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Repo(Path(tmp))
            repo.set_versions(5, 39, 1, ecd=None)
            repo.commit("release")
            repo.tag("v1.0.0")
            repo.set_versions(5, 39, 1, ecd=base_ecd)
            repo.commit("base")
            repo.set_versions(5, 39, 1, ecd=head_ecd)
            repo.commit("head")
            return repo.run("HEAD~1", "HEAD")

    print("ecdTaxonomyVersion introduced after the release:")
    res = ecd_scenario(1, 1)
    check("unchanged passes, not exit 2", res.returncode == 0, f"exit={res.returncode} {res.stdout}")
    res = ecd_scenario(1, 2)
    check("a bump over the banked v1 fails", res.returncode == 1 and "ecdTaxonomyVersion 1 -> 2" in res.stdout, f"exit={res.returncode} {res.stdout}")

    # squareTaxonomyVersion is absent at v0.10.0-beta too (pre-release audit finding H-06).
    def square_scenario(base_square: int, head_square: int):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Repo(Path(tmp))
            repo.set_versions(5, 39, 1, square=None)
            repo.commit("release")
            repo.tag("v1.0.0")
            repo.set_versions(5, 39, 1, square=base_square)
            repo.commit("base")
            repo.set_versions(5, 39, 1, square=head_square)
            repo.commit("head")
            return repo.run("HEAD~1", "HEAD")

    print("squareTaxonomyVersion introduced after the release:")
    check("the gate watches squareTaxonomyVersion", SQUARE in gate.CONSTANTS, repr(gate.CONSTANTS))
    res = square_scenario(1, 1)
    check("unchanged passes, not exit 2", res.returncode == 0, f"exit={res.returncode} {res.stdout}")
    res = square_scenario(1, 2)
    check("a bump over the banked v1 fails", res.returncode == 1 and "squareTaxonomyVersion 1 -> 2" in res.stdout, f"exit={res.returncode} {res.stdout}")

    # A constant absent at the tag AND unreadable at head: the message must name head.
    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.set_versions(5, 39, 1, ecd=None)
        repo.commit("release")
        repo.tag("v1.0.0")
        repo.set_versions(5, 39, 1, ecd=1)
        repo.commit("base")
        (repo.root / ECD.source).write_text("// renamed\n", encoding="utf-8")
        repo.commit("head")
        print("renamed at head while absent at the tag:")
        res = repo.run("HEAD~1", "HEAD")
        check("exits 2", res.returncode == 2, f"exit={res.returncode} {res.stdout}")
        check("blames head, not the tag", "at the head (HEAD)" in res.stdout and "at the tag" not in res.stdout, res.stdout)

    # ---- the gate must PASS ------------------------------------------------

    res = scenario("nothing moved", (5, 39, 1), (5, 39, 1), (5, 39, 1))
    check("exits 0", res.returncode == 0, f"exit={res.returncode} {res.stdout}")

    res = scenario("first bump after release", (5, 39, 1), (5, 39, 1), (5, 40, 1))
    check("exits 0", res.returncode == 0, f"exit={res.returncode} {res.stdout}")

    res = scenario("vNext banked, PR amends without moving", (5, 39, 1), (6, 40, 2), (6, 40, 2))
    check("exits 0 (an amend is invisible, by design)", res.returncode == 0, f"exit={res.returncode} {res.stdout}")

    # ---- the gate must refuse to answer ------------------------------------

    res = scenario("base behind the tag", (6, 39, 1), (5, 39, 1), (5, 39, 1))
    check("exits 2, not a pass", res.returncode == 2, f"exit={res.returncode} {res.stdout}")
    check("says base is behind", "behind the release" in res.stdout, res.stdout)

    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.set_versions(5, 39, 1)
        repo.commit("base")
        repo.set_versions(5, 40, 1)
        repo.commit("head")
        print("no release tag at all:")
        res = repo.run("HEAD~1", "HEAD")
        check("exits 2, not a pass", res.returncode == 2, f"exit={res.returncode} {res.stdout}")
        check("says to fetch tags", "no v* release tag" in res.stdout, res.stdout)

    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.set_versions(5, 39, 1)
        repo.commit("release")
        repo.tag("v1.0.0")
        (repo.root / SCHEMA.source).write_text("// the constant was renamed\n", encoding="utf-8")
        repo.commit("head")
        print("constant missing at head:")
        res = repo.run("HEAD~1", "HEAD")
        check("exits 2, not a pass", res.returncode == 2, f"exit={res.returncode} {res.stdout}")

    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.set_versions(5, 39, 1)
        repo.commit("release")
        repo.tag("v1.0.0")
        print("unresolvable refs and usage:")
        check("unknown base ref exits 2", repo.run("nope").returncode == 2)
        check("blank head ref exits 2", repo.run("HEAD", "").returncode == 2)
        check("no arguments exits 2", repo.run().returncode == 2)
        check("--tag without a value exits 2", repo.run("HEAD", "--tag").returncode == 2)

    # ---- tag selection -----------------------------------------------------

    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.set_versions(5, 39, 1)
        repo.commit("old release")
        repo.tag("v2.0.0")
        repo.set_versions(6, 39, 1)
        repo.commit("newer release")
        repo.tag("v1.9.0-beta")
        repo.commit("base")
        repo.set_versions(7, 39, 1)
        repo.commit("head")
        print("newest tag wins, whatever its name sorts to:")
        # The newer tag sorts LOWEST by name (v1.9.0 < v2.0.0), so a switch from date
        # order to name order picks v2.0.0 and flips the result below.
        # Schema: tag v1.9.0-beta has 6, v2.0.0 has 5. Base 6 -> head 7 is the first
        # bump after the newer tag (pass) but a second bump after the older one (fail),
        # so the exit code says which tag was chosen.
        res = repo.run("HEAD~1", "HEAD")
        check("selects the newest tag and passes", res.returncode == 0 and "v1.9.0-beta" in res.stdout, f"exit={res.returncode} {res.stdout}")
        res = repo.run("HEAD~1", "HEAD", "--tag", "v2.0.0")
        check("--tag overrides the selection", res.returncode == 1 and "v2.0.0" in res.stdout, f"exit={res.returncode} {res.stdout}")

    if FAILURES:
        print(f"\n{len(FAILURES)} FAILED:")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
