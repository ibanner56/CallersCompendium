#!/usr/bin/env python3
"""CI ratchet: a live preference's settings handler persists exactly what the
preference's own descriptor would encode (post-audit finding prefs-1).

Why
---
Each settings-backed live preference is a ``PreferenceNotifier`` descriptor
(``app/lib/main.dart``, plus ``DateFormatPreferenceNotifier`` in
``app/lib/src/data/persisted_preference.dart``). The descriptor owns the key,
the default, ``decode`` and ``encode``. But the handlers that write a changed
value do not call ``descriptor.persist()``: the scopes hand them a plain
``ValueNotifier``, so each handler does

    XScope.notifierOf(context).value = v;
    await persistSetting(settings, kXKey, <its own encoding of v>);

and the encoding exists twice. Startup and restore read the value back through
the descriptor's ``decode``, so a handler whose hand encoding drifts from
``encode`` writes a value the app cannot read back as it was. The maintainer
chose this guard over narrowing every scope to ``PreferenceNotifier`` (the
refactor CS-30c deferred).

The contract this checks
------------------------
For every write of a descriptor's key -- ``persistSetting(_, kXKey, VALUE)`` or
``<anything>.set(kXKey, VALUE)`` -- anywhere in ``app/lib`` or
``packages/*/lib``:

1. the enclosing function first assigns the live notifier,
   ``<...>.value = V;`` (the "flip the live value, then persist" order every
   handler documents), and
2. VALUE is the descriptor's ``encode`` applied to V, textually: for
   ``encode: (v) => v.name`` and ``.value = selection``, VALUE must be
   ``selection.name``; for a tear-off ``encode: localeToTag``, VALUE must be
   ``localeToTag(value)``. Whitespace and trailing commas are ignored.

So a handler cannot persist its own encoding: changing a descriptor's
``encode`` makes every handler of that key fail here until it is changed to
match, and a handler that encodes differently (``selection.index`` for an
``encode`` of ``v.name``) fails on its own.

Textual, so it is conservative: an equivalent but differently spelled encoding
fails and must be rewritten to the descriptor's spelling. That is intended --
the point is one spelling.

Fail closed
-----------
- A ``PreferenceNotifier`` construction (or a ``super(...)`` in a class that
  extends it) whose ``key:`` is not a ``k...Key`` identifier, or that has no
  ``encode:``, is an error: the checker cannot know its contract.
- A write of a descriptor key with no preceding ``.value =`` in its enclosing
  function is a violation.

Limits
------
Writes through a non-identifier key (``settings.set(key, ...)`` with a
variable, as ``PreferenceNotifier.persist`` and the backup restore do) are not
seen. ``PreferenceNotifier.persist`` is ``encode(value)`` by construction; the
restore writes the backup's stored JSON verbatim, which is not a handler.

Exit codes: 0 = compliant, 1 = violation, 2 = the descriptors could not be read.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_kdf_override_unassigned import mask_source  # noqa: E402
from check_l10n_unused import strip_comments  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]

# Files that declare PreferenceNotifier descriptors.
DESCRIPTOR_FILES = (
    "app/lib/main.dart",
    "app/lib/src/data/persisted_preference.dart",
)

_KEY_IDENT = re.compile(r"k\w*Key")
_CTOR = re.compile(r"\b(?:PreferenceNotifier\s*(?:<[\w<>?,\s]*>)?|super)\s*\(")
_LAMBDA = re.compile(
    r"^\(\s*(?:[\w<>?,\s]+\s+)?(?P<param>\w+)\s*\)\s*=>\s*(?P<body>.+)$", re.S
)
_TEAR_OFF = re.compile(r"^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*$")
_IDENT = re.compile(r"^[A-Za-z_$][\w$]*$")


class DescriptorError(Exception):
    pass


def _segments(expr: str) -> list[tuple[bool, str]]:
    """[expr] split into (is_string_literal, text) runs.

    Handles '...', "...", triple quotes and raw strings. A `${...}`
    interpolation stays inside its literal, so it is compared verbatim (an
    equivalent interpolation spelled differently fails, which is safe).
    """
    out: list[tuple[bool, str]] = []
    i, n, start = 0, len(expr), 0
    while i < n:
        c = expr[i]
        if c not in "'\"":
            i += 1
            continue
        raw = i > 0 and expr[i - 1] in "rR" and (i < 2 or not (expr[i - 2].isalnum() or expr[i - 2] == "_"))
        lit_start = i - 1 if raw else i
        quote = expr[i : i + 3] if expr.startswith(("\'\'\'", '"""'), i) else c
        j = i + len(quote)
        while j < n and not expr.startswith(quote, j):
            j += 2 if (expr[j] == "\\" and not raw) else 1
        j = min(j + len(quote), n)
        if lit_start > start:
            out.append((False, expr[start:lit_start]))
        out.append((True, expr[lit_start:j]))
        start = i = j
    if start < n:
        out.append((False, expr[start:]))
    return out


def _map_code(expr: str, fn) -> str:
    """[expr] with [fn] applied to its code runs only, never inside a string
    literal."""
    return "".join(text if is_str else fn(text) for is_str, text in _segments(expr))


@dataclass(frozen=True)
class Descriptor:
    key: str
    encode: str  # the `encode:` argument as written (comments stripped)
    path: str
    line: int
    field: str | None = None  # the main.dart field holding it, once resolved
    scope: str | None = None  # the scope its notifier is provided through
    owner_class: str | None = None  # for a `super(...)` descriptor

    def apply(self, value: str) -> str:
        """The source text of `encode(value)`."""
        expr = self.encode.strip()
        lam = _LAMBDA.match(expr)
        if lam:
            param = lam.group("param")
            arg = value if _IDENT.match(value) else f"({value})"
            pattern = re.compile(rf"(?<![\w$.]){re.escape(param)}(?![\w$])")
            return _map_code(lam.group("body"), lambda code: pattern.sub(arg, code))
        if _TEAR_OFF.match(expr):
            return f"{expr}({value})"
        raise DescriptorError(
            f"{self.path}:{self.line}: encode for {self.key} is neither a "
            f"one-parameter `=>` lambda nor a tear-off: {expr!r}"
        )


def normalize(expr: str) -> str:
    """[expr] without lexical whitespace or trailing commas. Whitespace inside
    a string literal is part of the value and is kept."""
    code = _map_code(expr.strip(), lambda c: re.sub(r"\s+", "", c))
    return _map_code(code, lambda c: re.sub(r",([)\]}])", r"\1", c)).rstrip(",")


def _line(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _close(masked: str, open_at: int) -> int:
    """Index of the delimiter closing the one at [open_at]."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack: list[str] = []
    for i in range(open_at, len(masked)):
        c = masked[i]
        if c in pairs:
            stack.append(pairs[c])
        elif c in ")]}":
            if not stack or stack.pop() != c:
                return -1
            if not stack:
                return i
    return -1


def _top_level_args(masked: str, open_at: int, close_at: int) -> list[tuple[int, int]]:
    """(start, end) spans of the top-level arguments of the call whose `(` is
    at [open_at] and `)` at [close_at]."""
    spans: list[tuple[int, int]] = []
    depth = 0
    start = open_at + 1
    for i in range(open_at + 1, close_at):
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            spans.append((start, i))
            start = i + 1
    if masked[start:close_at].strip():
        spans.append((start, close_at))
    return spans


def _enclosing_open_brace(masked: str, pos: int) -> int:
    depth = 0
    for i in range(pos - 1, -1, -1):
        c = masked[i]
        if c == "}":
            depth += 1
        elif c == "{":
            if depth == 0:
                return i
            depth -= 1
    return -1


def prepare(source: str) -> tuple[str, str]:
    """(comment-free text, the same text with string contents masked)."""
    text = strip_comments(source)
    return text, mask_source(text)


def descriptors_in(source: str, path: str) -> list[Descriptor]:
    text, masked = prepare(source)
    extends = re.search(r"\bextends\s+PreferenceNotifier\b", masked) is not None
    found: list[Descriptor] = []
    for match in _CTOR.finditer(masked):
        is_super = match.group(0).startswith("super")
        if is_super and not extends:
            continue
        open_at = match.end() - 1
        close_at = _close(masked, open_at)
        if close_at == -1:
            raise DescriptorError(f"{path}:{_line(text, open_at)}: unbalanced call")
        if masked[open_at + 1 : close_at].lstrip().startswith("{"):
            continue  # the constructor's own declaration, not a call
        named: dict[str, str] = {}
        for start, end in _top_level_args(masked, open_at, close_at):
            arg = text[start:end].strip()
            name = re.match(r"(\w+)\s*:", arg)
            if name:
                named[name.group(1)] = arg[name.end() :].strip()
        if is_super and "key" not in named:
            continue  # a super(...) call of some other shape
        line = _line(text, match.start())
        key = named.get("key")
        if key is None or not _KEY_IDENT.fullmatch(key):
            raise DescriptorError(
                f"{path}:{line}: PreferenceNotifier key must be a `k...Key` "
                f"identifier so its writes can be found; got {key!r}"
            )
        if "encode" not in named:
            raise DescriptorError(f"{path}:{line}: PreferenceNotifier {key} has no encode")
        field = owner = None
        if is_super:
            cls = None
            for cls in re.finditer(r"\bclass\s+(\w+)\s+extends\s+PreferenceNotifier\b", masked[: match.start()]):
                pass
            owner = cls.group(1) if cls else None
        else:
            decl = re.search(r"\b(_\w+)\s*=\s*$", masked[: match.start()])
            field = decl.group(1) if decl else None
        found.append(
            Descriptor(key, named["encode"], path, line, field=field, owner_class=owner)
        )
    return found


_SCOPE_WIRING = re.compile(r"\b(\w+Scope)\s*\(\s*notifier\s*:\s*(_\w+)\b")


def resolve_scopes(
    descriptors: dict[str, Descriptor], main_source: str, main_path: str
) -> dict[str, Descriptor]:
    """Attach to each descriptor the `XScope` that provides its notifier, from
    the `XScope(notifier: _field, ...)` wiring in main.dart, so a handler's
    `.value =` can be checked to target that notifier and no other."""
    _, masked = prepare(main_source)
    scope_of = {m.group(2): m.group(1) for m in _SCOPE_WIRING.finditer(masked)}
    out: dict[str, Descriptor] = {}
    for key, d in descriptors.items():
        field = d.field
        if field is None and d.owner_class:
            m = re.search(rf"\b(_\w+)\s*=\s*{re.escape(d.owner_class)}\s*\(", masked)
            field = m.group(1) if m else None
        scope = scope_of.get(field) if field else None
        if scope is None:
            raise DescriptorError(
                f"{d.path}:{d.line}: cannot find the scope that provides {key}'s "
                f"notifier (field {field!r}) in {main_path}"
            )
        out[key] = replace(d, field=field, scope=scope)
    return out


def load_descriptors(root: Path = REPO_ROOT) -> dict[str, Descriptor]:
    out: dict[str, Descriptor] = {}
    for rel in DESCRIPTOR_FILES:
        path = root / rel
        if not path.is_file():
            raise DescriptorError(f"descriptor file missing: {rel}")
        for d in descriptors_in(path.read_text(encoding="utf-8"), rel):
            if d.key in out:
                raise DescriptorError(f"{rel}:{d.line}: {d.key} has two descriptors")
            out[d.key] = d
    if not out:
        raise DescriptorError("no PreferenceNotifier descriptors found")
    main = DESCRIPTOR_FILES[0]
    return resolve_scopes(out, (root / main).read_text(encoding="utf-8"), main)


_WRITE = re.compile(r"(?<![\w$])persistSetting\s*\(|\.set\s*\(")
_ASSIGN = re.compile(r"\.value\s*=(?!=)")


def violations_in(
    source: str, path: str, descriptors: dict[str, Descriptor]
) -> list[tuple[int, str]]:
    return check_writes(source, path, descriptors)[1]


def check_writes(
    source: str, path: str, descriptors: dict[str, Descriptor]
) -> tuple[list[str], list[tuple[int, str]]]:
    """(keys of the descriptor-key writes found, violations among them)."""
    text, masked = prepare(source)
    seen: list[str] = []
    out: list[tuple[int, str]] = []
    for match in _WRITE.finditer(masked):
        open_at = match.end() - 1
        close_at = _close(masked, open_at)
        if close_at == -1:
            continue
        args = [
            (s, e)
            for s, e in _top_level_args(masked, open_at, close_at)
            if not re.match(r"\s*\w+\s*:", masked[s:e])
        ]
        key_index = 1 if match.group(0).startswith("persistSetting") else 0
        if len(args) <= key_index + 1:
            continue
        key = text[slice(*args[key_index])].strip()
        descriptor = descriptors.get(key)
        if descriptor is None:
            continue
        seen.append(key)
        written = text[slice(*args[key_index + 1])].strip()
        line = _line(text, match.start())
        body_at = _enclosing_open_brace(masked, match.start())
        body = masked[body_at + 1 : match.start()]
        assigned = None
        for a in _ASSIGN.finditer(masked, body_at + 1, match.start()):
            end = masked.find(";", a.end(), match.start())
            if end == -1:
                continue
            stmt_at = max(masked.rfind(c, body_at, a.start()) for c in ";{}") + 1
            target = text[stmt_at : a.start()].strip()
            if _targets_scope(target, descriptor.scope, body):
                assigned = text[a.end() : end].strip()
        if assigned is None:
            out.append(
                (
                    line,
                    f"writes {key} without first assigning its live notifier "
                    f"(`{descriptor.scope}.notifierOf(context).value = v;`, or a "
                    f"local holding that notifier), so the value cannot be "
                    f"checked against the descriptor's encode",
                )
            )
            continue
        expected = descriptor.apply(assigned)
        if normalize(written) != normalize(expected):
            out.append(
                (
                    line,
                    f"writes {key} as `{written}`, but its descriptor "
                    f"({descriptor.path}:{descriptor.line}) encodes the live value "
                    f"as `{expected}`",
                )
            )
    return seen, out


def _targets_scope(target: str, scope: str | None, body: str) -> bool:
    """Whether [target] (the left of `.value =`) is [scope]'s notifier: either
    `Scope.notifierOf(...)` itself or a local initialised from it in [body]."""
    if scope is None:
        return False
    notifier_of = rf"{re.escape(scope)}\s*\.\s*notifierOf\s*\("
    if re.fullmatch(notifier_of + r".*\)", target, re.S):
        return True
    return bool(
        _IDENT.match(target)
        and re.search(rf"\b{re.escape(target)}\s*=\s*{notifier_of}", body)
    )


def source_files(root: Path) -> list[Path]:
    roots = [root / "app" / "lib"]
    packages = root / "packages"
    if packages.is_dir():
        roots += [p / "lib" for p in sorted(packages.iterdir()) if (p / "lib").is_dir()]
    files: list[Path] = []
    for r in roots:
        if r.is_dir():
            files += sorted(
                p for p in r.rglob("*.dart") if "l10n" not in p.relative_to(r).parts[:1]
            )
    return files


def scan(root: Path = REPO_ROOT) -> tuple[dict[str, Descriptor], int, list[str]]:
    """(descriptors, number of handler writes checked, violations)."""
    descriptors = load_descriptors(root)
    checked = 0
    keys_seen: set[str] = set()
    problems: list[str] = []
    for path in source_files(root):
        rel = path.relative_to(root).as_posix()
        seen, bad = check_writes(path.read_text(encoding="utf-8"), rel, descriptors)
        checked += len(seen)
        keys_seen.update(seen)
        problems += [f"{rel}:{line}: {detail}" for line, detail in bad]
    if checked == 0:
        # Every descriptor has a settings handler today; finding none means the
        # write pattern changed and this checker went blind.
        raise DescriptorError("found no handler write of any preference key")
    problems += missing_handler_problems(descriptors, keys_seen)
    return descriptors, checked, problems


# Descriptor keys that deliberately have no settings handler, with why. Empty
# today: every live preference is changed from a settings control.
NO_HANDLER: dict[str, str] = {}


def missing_handler_problems(
    descriptors: dict[str, Descriptor], keys_seen: set[str]
) -> list[str]:
    """A descriptor key with no handler write is unguarded: either its handler
    moved to a shape this checker cannot see, or it writes another key."""
    return [
        f"{d.path}:{d.line}: no handler write of {key} was found, so nothing "
        f"checks that it persists the descriptor's encode (add the handler, or "
        f"list the key in NO_HANDLER with the reason)"
        for key, d in sorted(descriptors.items())
        if key not in keys_seen and key not in NO_HANDLER
    ]


def main() -> int:
    try:
        descriptors, checked, problems = scan()
    except DescriptorError as error:
        print(f"check_preference_encode: {error}", file=sys.stderr)
        return 2
    if problems:
        print(
            "Preference handlers must persist exactly the descriptor's "
            "encode(live value) (prefs-1):",
            file=sys.stderr,
        )
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1
    print(
        f"check_preference_encode: {checked} handler write(s) of "
        f"{len(descriptors)} preference key(s) match the descriptor's encode"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
