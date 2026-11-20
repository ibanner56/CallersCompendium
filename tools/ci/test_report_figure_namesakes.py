#!/usr/bin/env python3
"""Offline tests for ``report_figure_namesakes.py``.

Run directly: ``python3 tools/ci/test_report_figure_namesakes.py``.

The scanner (``mask``, ``blocks``, ``prefixes``) is exercised directly. The
report is exercised end to end in a throwaway git repository holding a miniature
taxonomy directory, because reading a block at the merge base and at the head is
what "a changed block, not a changed file" means. The last group runs the scanner
over this repository's real taxonomy files as a positive control: a scanner that
found no blocks would also report nothing.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "report_figure_namesakes.py"
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import report_figure_namesakes as gate  # noqa: E402

FAILURES: list[str] = []
D = gate.TAXONOMY_DIR


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(name)
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


REGISTRY = "const Map<DanceForm, String> danceFormMovePrefixes = {DanceForm.ecd: 'ecd_'};\n"

CONTRA = """const contraTaxonomy = Taxonomy(
  moves: [
    const MoveDef(
      id: 'box_the_gnat',
      displayName: 'box the gnat',
      params: {'beats': ParamSpec(ParamKind.beats, defaultValue: 4)},
    ),
    const MoveDef(
      id: 'do_si_do',
      displayName: 'do si do',
      // A comment with a ) and an apostrophe: don't break the scanner.
      params: {'beats': ParamSpec(ParamKind.beats, defaultValue: 8)},
      renderTemplate: '{who} {move} (see below',
    ),
    const MoveDef(
      id: 'pass_thru',
      displayName: 'pass through',
      params: {},
    ),
    const MoveDef(
      id: 'allemande',
      displayName: 'allemande',
      params: {},
    ),
  ],
  aliases: [
    const MoveAlias(
      id: 'swat_the_flea',
      displayName: 'swat the flea',
      targetMove: 'box_the_gnat',
    ),
  ],
);
"""

ECD = """const String _p = 'ecd_';
const ecdTaxonomy = Taxonomy(
  moves: [
    MoveDef(
      id: '${_p}box_the_gnat',
      displayName: 'box the gnat',
      params: {'beats': ParamSpec(ParamKind.beats, defaultValue: 4)},
    ),
    MoveDef(
      id: '${_p}pass_through',
      displayName: 'pass through',
      params: {},
    ),
    MoveDef(
      id: '${_p}allemande',
      displayName: 'a different name',
      params: {},
    ),
    MoveDef(
      id: '${_p}swing',
      displayName: 'swing',
      params: {},
    ),
  ],
);
"""

DEFS = """const Map<String, FigureDefinition> contraFigureDefinitions = {
  // A note (with parens) above the entry.
  'box_the_gnat': FigureDefinition(
    definition: 'Two dancers trade places.',
    description: 'Takes 4 beats (or 8).',
  ),
  'do_si_do': FigureDefinition(
    definition: 'Pass right shoulders.',
    description: 'Once around.',
  ),
};
"""


def git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, check=False)


def write(root: Path, name: str, text: str) -> None:
    target = root / D / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def commit(root: Path, message: str) -> None:
    git(root, "add", "-A")
    git(root, "commit", "-q", "--allow-empty", "-m", message)


def make_repo(root: Path, registry: str = REGISTRY, extra: dict[str, str] | None = None) -> None:
    git(root, "init", "-q", ".")
    git(root, "config", "user.email", "t@example.invalid")
    git(root, "config", "user.name", "test")
    write(root, "taxonomy_registry.dart", registry)
    write(root, "contra_taxonomy.dart", CONTRA)
    write(root, "ecd_taxonomy.dart", ECD)
    write(root, "contra_figure_definitions.dart", DEFS)
    for name, text in (extra or {}).items():
        write(root, name, text)
    commit(root, "base")
    git(root, "branch", "-M", "main")
    git(root, "checkout", "-q", "-b", "pr")


def run(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), *(args or ("main", "HEAD"))], cwd=root, capture_output=True, text=True)


def edit(root: Path, name: str, old: str, new: str) -> None:
    path = root / D / name
    text = path.read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    path.write_text(text.replace(old, new), encoding="utf-8")
    commit(root, f"edit {name}")


def fresh(**kwargs):
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    make_repo(root, **kwargs)
    return tmp, root


def main() -> int:
    # ---- the scanner
    masked = gate.mask("a('x)(', // y)(\n b) /* ( /* nested ( */ ) */ r'(' \"\"\"(\n)\"\"\" '${(}'")
    check("mask: parens in strings and comments are blanked", masked.count("(") == 1 and masked.count(")") == 1, repr(masked))
    check("mask: length and newlines are kept", len("a('x)(', // y)(\n b)") == len(gate.mask("a('x)(', // y)(\n b)")) and gate.mask("a\n// b\nc").count("\n") == 2)
    for bad in ("'unterminated", "/* open", "'a\nb'"):
        try:
            gate.mask(bad)
            check(f"mask: {bad!r} is unavailable", False)
        except gate.Unavailable:
            check(f"mask: {bad!r} is unavailable", True)

    found = gate.blocks(ECD, "ecd_taxonomy.dart")
    check("blocks: `${_p}` ids resolve through the file's const", [b.id for b in found] == ["ecd_box_the_gnat", "ecd_pass_through", "ecd_allemande", "ecd_swing"], repr([b.id for b in found]))
    check("blocks: display names are read", found[0].display_name == "box the gnat")
    contra = gate.blocks(CONTRA, "contra_taxonomy.dart")
    check("blocks: MoveDef and MoveAlias both count", [b.id for b in contra] == ["box_the_gnat", "do_si_do", "pass_thru", "allemande", "swat_the_flea"], repr([b.id for b in contra]))
    check("blocks: a ) in a string or comment does not end the block early", "(see below" in contra[1].text and contra[2].id == "pass_thru")
    defs = gate.blocks(DEFS, "contra_figure_definitions.dart")
    check("blocks: FigureDefinition entries are read, a commented one is not", [(b.kind, b.id) for b in defs] == [("definition", "box_the_gnat"), ("definition", "do_si_do")], repr(defs))
    commented = gate.blocks("/*\n  'x': FigureDefinition(a: 1),\n*/\n  'y': FigureDefinition(a: 1),\n", "f.dart")
    check("blocks: an entry inside a block comment is not a block", [b.id for b in commented] == ["y"], repr(commented))
    try:
        gate.blocks("MoveDef(id: '${nope}x', displayName: 'x')", "f.dart")
        check("blocks: an unresolvable interpolation is unavailable, never a silently dropped form", False)
    except gate.Unavailable as error:
        check("blocks: an unresolvable interpolation is unavailable, never a silently dropped form", "nope" in str(error), str(error))
    for decl in ("const String _p = 'ecd_';", "const _p = 'ecd_';", 'const String _p = "ecd_";', "final String _p = 'ecd_';", "  static const String _p = 'ecd_';"):
        got = [b.id for b in gate.blocks(decl + "\nMoveDef(id: '${_p}x', displayName: 'x')", "f.dart")]
        check(f"blocks: the prefix constant may be written {decl!r}", got == ["ecd_x"], repr(got))
    check("blocks: an id that is not a string literal is skipped (documented)", gate.blocks("MoveDef(id: customMoveId, displayName: 'x')", "f.dart") == [])
    check("blocks: a constant in a comment is not read", gate.blocks("// const String _p = 'zz_';\nconst String _p = 'ecd_';\nMoveDef(id: '${_p}x')", "f.dart")[0].id == "ecd_x")
    lead = gate.blocks("// TCB \"Swing\"\n// second line\n'x': FigureDefinition(a: 1),\n\n// detached\n\n'y': FigureDefinition(a: 1),\n", "f.dart")
    check("blocks: the // lines directly above a block are part of it, a detached comment is not", "TCB" in lead[0].text and "second line" in lead[0].text and "detached" not in lead[1].text, repr([b.text for b in lead]))
    try:
        gate.blocks("const MoveDef(id: 'a', displayName: 'a'", "f.dart")
        check("blocks: an unclosed block is unavailable", False)
    except gate.Unavailable:
        check("blocks: an unclosed block is unavailable", True)

    check("prefixes: read from the registry", gate.prefixes(REGISTRY) == {"ecd": "ecd_"})
    check("prefixes: a third form is picked up with no code change", gate.prefixes("const Map<DanceForm, String> danceFormMovePrefixes = {DanceForm.ecd: 'ecd_', DanceForm.squares: 'sq_'};") == {"ecd": "ecd_", "squares": "sq_"})
    check("prefixes: an entry in a comment is not read", gate.prefixes("// {DanceForm.x: 'x_'}\nconst Map<DanceForm, String> danceFormMovePrefixes = {DanceForm.ecd: 'ecd_'};") == {"ecd": "ecd_"})
    check("prefixes: an entry in a comment inside the map is not read", gate.prefixes("const Map<DanceForm, String> danceFormMovePrefixes = {\n  DanceForm.ecd: 'ecd_',\n  // DanceForm.squares: 'sq_', (not yet)\n};") == {"ecd": "ecd_"})
    check("prefixes: a double-quoted prefix is read", gate.prefixes('const Map<DanceForm, String> danceFormMovePrefixes = {DanceForm.ecd: "ecd_"};') == {"ecd": "ecd_"})
    try:
        gate.prefixes("const Map<DanceForm, String> danceFormMovePrefixes = {DanceForm.ecd: 'ecd_', DanceForm.squares: squaresPrefix};")
        check("prefixes: a prefix that is not a literal is unavailable, not dropped", False)
    except gate.Unavailable:
        check("prefixes: a prefix that is not a literal is unavailable, not dropped", True)
    for bad in ("nothing here", "const Map<DanceForm, String> danceFormMovePrefixes = {};"):
        try:
            gate.prefixes(bad)
            check(f"prefixes: {bad[:20]!r} is unavailable", False)
        except gate.Unavailable:
            check(f"prefixes: {bad[:20]!r} is unavailable", True)
    forms = {"ecd": "ecd_", "squares": "sq_"}
    check("form_and_stem: prefixed and unprefixed", gate.form_and_stem("ecd_swing", forms) == ("ecd", "swing") and gate.form_and_stem("swing", forms) == ("contra", "swing") and gate.form_and_stem("sq_swing", forms) == ("squares", "swing"))

    # ---- end to end
    tmp, root = fresh()
    with tmp:
        edit(root, "contra_taxonomy.dart", "defaultValue: 4)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'", "defaultValue: 8)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'")
        res = run(root)
        check("e2e: editing the contra box_the_gnat block lists ecd_box_the_gnat", res.returncode == 0 and "box_the_gnat (contra; changed in contra_taxonomy.dart)" in res.stdout and "-> ecd_box_the_gnat (ecd; ecd_taxonomy.dart; same display name and id stem)" in res.stdout, res.stdout)
        check("e2e: the report says plainly that namesakes may differ", "legitimately differ" in res.stdout and "not a claim of drift" in res.stdout and "never fails the build" in res.stdout)
        check("e2e: unchanged blocks are not listed", "do_si_do" not in res.stdout and "pass_thru" not in res.stdout, res.stdout)

    tmp, root = fresh()
    with tmp:
        edit(root, "contra_taxonomy.dart", "defaultValue: 8)},\n      renderTemplate", "defaultValue: 16)},\n      renderTemplate")
        res = run(root)
        check("e2e: editing an unrelated block in the same file lists nothing", res.returncode == 0 and res.stdout == "", res.stdout)

    tmp, root = fresh()
    with tmp:
        edit(root, "contra_taxonomy.dart", "      id: 'allemande',\n      displayName: 'allemande',", "      id: 'allemande',\n      displayName: 'allemande left',")
        res = run(root)
        check("e2e: an id-stem-only namesake (display names differ) is found and says so", "ecd_allemande" in res.stdout and "same id stem" in res.stdout and "display name" not in res.stdout.split("ecd_allemande")[1], res.stdout)

    tmp, root = fresh()
    with tmp:
        edit(root, "contra_taxonomy.dart", "      id: 'do_si_do',\n      displayName: 'do si do',", "      id: 'do_si_do',\n      displayName: 'do-si-do',")
        check("e2e: a figure with no namesake prints nothing", run(root).stdout == "")

    tmp, root = fresh()
    with tmp:
        edit(root, "contra_taxonomy.dart", "      id: 'pass_thru',\n      displayName: 'pass through',\n      params: {},", "      id: 'pass_thru',\n      displayName: 'pass through',\n      params: {'x': 1},")
        res = run(root)
        check("e2e: a display-name-only namesake is found (different ids)", "pass_thru (contra" in res.stdout and "-> ecd_pass_through (ecd; ecd_taxonomy.dart; same display name)" in res.stdout, res.stdout)

    tmp, root = fresh()
    with tmp:
        edit(root, "ecd_taxonomy.dart", "defaultValue: 4)},\n    ),\n    MoveDef(\n      id: '${_p}pass_through'", "defaultValue: 8)},\n    ),\n    MoveDef(\n      id: '${_p}pass_through'")
        res = run(root)
        check("e2e: it is symmetric: editing the ECD block lists contra's", "ecd_box_the_gnat (ecd; changed in ecd_taxonomy.dart)" in res.stdout and "-> box_the_gnat (contra" in res.stdout, res.stdout)
        check("e2e: the namesake's file is where its figure is defined, not its prose file", "-> box_the_gnat (contra; contra_taxonomy.dart;" in res.stdout, res.stdout)

    tmp, root = fresh()
    with tmp:
        edit(root, "contra_figure_definitions.dart", "Takes 4 beats (or 8).", "Takes 4 beats, or 8 with a balance.")
        res = run(root)
        check("e2e: a FigureDefinition entry's edit lists the namesake, matched by its figure's display name", "box_the_gnat (contra; changed in contra_figure_definitions.dart)" in res.stdout and "ecd_box_the_gnat" in res.stdout, res.stdout)

    tmp, root = fresh()
    with tmp:
        path = root / D / "contra_taxonomy.dart"
        path.write_text(path.read_text().replace("      id: 'box_the_gnat',\n      displayName: 'box the gnat',", "      id:   'box_the_gnat',\n\n      displayName:   'box the gnat',"), encoding="utf-8")
        commit(root, "reflow")
        check("e2e: a whitespace-only reflow of a block lists nothing", run(root).stdout == "")
        path.write_text(path.read_text().replace("const contraTaxonomy", "// a new comment above, outside any block\nconst contraTaxonomy"), encoding="utf-8")
        commit(root, "comment")
        check("e2e: a comment outside every block lists nothing", run(root).stdout == "")
        path.write_text(path.read_text().replace("      params: {'beats': ParamSpec(ParamKind.beats, defaultValue: 4)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'", "      // reviewed against the ECD form\n      params: {'beats': ParamSpec(ParamKind.beats, defaultValue: 4)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'"), encoding="utf-8")
        commit(root, "comment in block")
        check("e2e: a comment inside a block counts as a change to it", "box_the_gnat (contra" in run(root).stdout)

    tmp, root = fresh()
    with tmp:
        edit(root, "contra_taxonomy.dart", "    const MoveDef(\n      id: 'allemande',\n      displayName: 'allemande',\n      params: {},\n    ),\n", "")
        check("e2e: a deleted block lists nothing", run(root).stdout == "")
        edit(root, "ecd_taxonomy.dart", "    MoveDef(\n      id: '${_p}swing',", "    MoveDef(\n      id: '${_p}box_the_gnat_two',\n      displayName: 'box the gnat',\n      params: {},\n    ),\n    MoveDef(\n      id: '${_p}swing',")
        res = run(root)
        check("e2e: a new block is a changed block", "ecd_box_the_gnat_two (ecd; changed in ecd_taxonomy.dart)" in res.stdout and "-> box_the_gnat (contra" in res.stdout and "same display name" in res.stdout, res.stdout)

    # A block moved to another file, a renamed file and a split: not changes.
    tmp, root = fresh()
    with tmp:
        git(root, "mv", D + "ecd_taxonomy.dart", D + "ecd_moves.dart")
        commit(root, "rename")
        check("e2e: a renamed file lists nothing", run(root).stdout == "", run(root).stdout)
        text = (root / D / "contra_taxonomy.dart").read_text()
        start = text.index("    const MoveDef(\n      id: 'box_the_gnat'")
        end = text.index("    const MoveDef(\n      id: 'do_si_do'")
        block = text[start:end]
        (root / D / "contra_taxonomy.dart").write_text(text[:start] + text[end:], encoding="utf-8")
        write(root, "contra_extra.dart", "const extra = [\n" + block + "];\n")
        commit(root, "move a block to a new file")
        check("e2e: a block moved to another file lists nothing", run(root).stdout == "", run(root).stdout)
        edit(root, "contra_extra.dart", "defaultValue: 4)}", "defaultValue: 6)}")
        res = run(root)
        check("e2e: a block moved and then edited is reported once, from its new file", res.stdout.count("box_the_gnat (contra; changed in contra_extra.dart)") == 1, res.stdout)

    # A comment directly above a block is part of it; helpers a block only uses are not.
    tmp, root = fresh()
    with tmp:
        edit(root, "contra_figure_definitions.dart", "  // A note (with parens) above the entry.\n", "  // A note (with parens) above the entry, reviewed.\n")
        res = run(root)
        check("e2e: editing the comment directly above a FigureDefinition entry reports it", "box_the_gnat (contra; changed in contra_figure_definitions.dart)" in res.stdout, res.stdout)

    # A form that cannot be read must be said, not dropped without a word.
    tmp, root = fresh()
    with tmp:
        edit(root, "ecd_taxonomy.dart", "const String _p = 'ecd_';", "const String _p = 'ecd_' + 'x';")
        edit(root, "contra_taxonomy.dart", "defaultValue: 4)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'", "defaultValue: 8)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'")
        res = run(root)
        check("e2e: a prefix constant the scanner cannot read is unavailable, never an empty report", res.returncode == 0 and "unavailable" in res.stdout and "cannot resolve" in res.stdout, res.stdout)
    tmp, root = fresh()
    with tmp:
        edit(root, "ecd_taxonomy.dart", "const String _p = 'ecd_';", 'const _p = "ecd_";')
        edit(root, "contra_taxonomy.dart", "defaultValue: 4)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'", "defaultValue: 8)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'")
        check("e2e: a differently written prefix constant still finds the namesake", "ecd_box_the_gnat" in run(root).stdout)

    # A third form, registered by the registry edit alone.
    squares = "const String _p = 'sq_';\nconst squaresTaxonomy = Taxonomy(moves: [\n  MoveDef(\n    id: '${_p}box_the_gnat',\n    displayName: 'box the gnat',\n    params: {},\n  ),\n]);\n"
    tmp, root = fresh(registry="const Map<DanceForm, String> danceFormMovePrefixes = {DanceForm.ecd: 'ecd_', DanceForm.squares: 'sq_'};\n", extra={"squares_taxonomy.dart": squares})
    with tmp:
        edit(root, "contra_taxonomy.dart", "defaultValue: 4)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'", "defaultValue: 8)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'")
        res = run(root)
        check("e2e: a form added to the registry is listed with no code change", "-> sq_box_the_gnat (squares; squares_taxonomy.dart" in res.stdout and "-> ecd_box_the_gnat (ecd" in res.stdout, res.stdout)

    tmp, root = fresh()
    with tmp:
        edit(root, "ecd_taxonomy.dart", "defaultValue: 4)},\n    ),\n    MoveDef(\n      id: '${_p}pass_through'", "defaultValue: 8)},\n    ),\n    MoveDef(\n      id: '${_p}pass_through'")
        edit(root, "taxonomy_registry.dart", "{DanceForm.ecd: 'ecd_'}", "{DanceForm.ecd: 'xx_'}")
        res = run(root)
        check("e2e: forms are assigned from the registry at the head (with another prefix the ECD ids are no longer a separate form)", res.returncode == 0 and res.stdout == "", res.stdout)

    # ---- unavailable, always exit 0
    tmp, root = fresh()
    with tmp:
        res = run(root, "no-such-ref", "HEAD")
        check("unavailable: an unresolvable base", res.returncode == 0 and "unavailable" in res.stdout, res.stdout)
        res = run(root)
        check("unavailable: nothing changed is silent, exit 0", res.returncode == 0 and res.stdout == "")
        res = run(root, "main")
        check("head defaults to HEAD", res.returncode == 0 and res.stdout == "")
        res = run(root, "")
        check("unavailable: usage", res.returncode == 0 and "unavailable" in res.stdout and "usage" in res.stdout, res.stdout)
        edit(root, "contra_taxonomy.dart", "      id: 'allemande',\n      displayName: 'allemande',\n      params: {},\n    ),", "      id: 'allemande',\n      displayName: 'allemande',\n      params: {},\n")
        res = run(root)
        check("unavailable: a block that never closes", res.returncode == 0 and "unavailable" in res.stdout and "unbalanced" in res.stdout and "::notice" in res.stdout, res.stdout)

    tmp, root = fresh(registry="// the registry lost its prefixes map\n")
    with tmp:
        edit(root, "contra_taxonomy.dart", "defaultValue: 4)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'", "defaultValue: 8)},\n    ),\n    const MoveDef(\n      id: 'do_si_do'")
        res = run(root)
        check("unavailable: a registry it cannot read", res.returncode == 0 and "unavailable" in res.stdout and "danceFormMovePrefixes" in res.stdout, res.stdout)

    # ---- positive control on the real taxonomy
    real = []
    for path in sorted((REPO / D).glob("*.dart")):
        real.extend(gate.blocks(path.read_text(encoding="utf-8"), f"{D}{path.name}"))
    real_forms = gate.prefixes((REPO / gate.REGISTRY).read_text(encoding="utf-8"))
    check("control: the real registry has ECD's prefix", real_forms.get("ecd") == "ecd_", repr(real_forms))
    check("control: the real taxonomy yields many blocks (a scanner that finds none would pass too)", len(real) >= 150, str(len(real)))
    hits = gate.namesakes([b for b in real if b.id == "box_the_gnat"], real, real_forms)
    check("control: the real box_the_gnat has the namesake ecd_box_the_gnat", bool(hits) and any(o[0] == "ecd_box_the_gnat" for o in hits[0][2]), repr(hits))

    if FAILURES:
        print(f"\n{len(FAILURES)} check(s) failed")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
