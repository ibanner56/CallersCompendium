#!/usr/bin/env python3
"""Guard: every shipped iOS target declares the required-reason APIs it uses.

Apple requires each bundle that contains an executable to carry a privacy
manifest (``PrivacyInfo.xcprivacy``) listing every *required-reason API*
category the executable's own code touches, with an approved reason for each.
App Store Connect rejects an upload that uses one without declaring it
(ITMS-91053). TestFlight builds only get an email, so a missing declaration can
sit unnoticed until App Review (post-audit finding platform-6).

For each target in ``app/ios/Runner.xcodeproj`` whose product ships to users
(an application or an app extension), this checks that:

1. the target's *Resources* build phase copies a ``PrivacyInfo.xcprivacy``. A
   manifest that exists on disk but is not in the phase never reaches the
   bundle;
2. the manifest parses, sets ``NSPrivacyTracking`` to false with no tracking
   domains, and gives every declared category at least one reason that Apple
   allows for that category and for an app (not a third-party SDK);
3. every required-reason category whose symbols appear in the Swift and
   Objective-C files of the target's *Sources* build phase is declared; and
4. no category is declared that those sources do not use, so the manifest
   cannot keep claiming a reason for code that has gone.

Which files belong to a target is read from the project file, not from the
directory layout, so a source added to a target from another folder is still
scanned. Plugins are not scanned: each ships in its own bundle and is
responsible for its own manifest.

The symbol and reason lists come from Apple's "Describing use of required
reason API" and ``NSPrivacyAccessedAPIType`` reference (fetched 2026-10-06).
Apple revises that list; when it does, update ``CATEGORIES`` here.

Usage: ``check_ios_privacy_manifest.py`` (no arguments). Exit 0 when every
target passes, 1 otherwise.
"""

from __future__ import annotations

import plistlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
IOS_DIR = Path("app/ios")
PBXPROJ = IOS_DIR / "Runner.xcodeproj" / "project.pbxproj"
MANIFEST_NAME = "PrivacyInfo.xcprivacy"

# Product types that end up in what the user installs. Test bundles do not.
SHIPPED_PRODUCT_TYPES = {
    "com.apple.product-type.application",
    "com.apple.product-type.app-extension",
}

SCANNED_SUFFIXES = (".swift", ".m", ".mm", ".c", ".cc", ".cpp")

# Written by `flutter build` and git-ignored, so absent from a fresh checkout.
# It only calls each plugin's `register`; the plugins' own API use is theirs to
# declare. Any other source the project lists but the tree lacks is a failure.
GENERATED_SOURCES = {"GeneratedPluginRegistrant.m"}


@dataclass(frozen=True)
class Category:
    key: str
    # Regexes matched against source with comments removed.
    symbols: tuple[str, ...]
    # Reasons an app may declare. Reasons reserved for third-party SDKs
    # (0A2A.1, C56D.1) are deliberately absent: this project's targets are apps.
    app_reasons: frozenset[str]


def _words(*names: str) -> tuple[str, ...]:
    return tuple(rf"\b{re.escape(n)}\b" for n in names)


def _calls(*names: str) -> tuple[str, ...]:
    return tuple(rf"\b{re.escape(n)}\s*\(" for n in names)


_GETATTRLIST = _calls("getattrlist", "getattrlistbulk", "fgetattrlist", "getattrlistat")

CATEGORIES: tuple[Category, ...] = (
    Category(
        "NSPrivacyAccessedAPICategoryFileTimestamp",
        _words(
            "creationDate",
            "modificationDate",
            "fileModificationDate",
            "contentModificationDateKey",
            "creationDateKey",
            "NSFileCreationDate",
            "NSFileModificationDate",
            "NSURLCreationDateKey",
            "NSURLContentModificationDateKey",
        )
        + _GETATTRLIST
        + _calls("stat", "fstat", "fstatat", "lstat"),
        frozenset({"DDA9.1", "C617.1", "3B52.1"}),
    ),
    Category(
        "NSPrivacyAccessedAPICategorySystemBootTime",
        _words("systemUptime") + _calls("mach_absolute_time"),
        frozenset({"35F9.1", "8FFB.1", "3D61.1"}),
    ),
    Category(
        "NSPrivacyAccessedAPICategoryDiskSpace",
        _words(
            "volumeAvailableCapacityKey",
            "volumeAvailableCapacityForImportantUsageKey",
            "volumeAvailableCapacityForOpportunisticUsageKey",
            "volumeTotalCapacityKey",
            "systemFreeSize",
            "systemSize",
            "NSFileSystemFreeSize",
            "NSFileSystemSize",
            "NSURLVolumeAvailableCapacityKey",
            "NSURLVolumeTotalCapacityKey",
        )
        + _calls("statfs", "statvfs", "fstatfs", "fstatvfs")
        + _GETATTRLIST,
        frozenset({"85F4.1", "E174.1", "7D9E.1", "B728.1"}),
    ),
    Category(
        "NSPrivacyAccessedAPICategoryActiveKeyboards",
        _words("activeInputModes"),
        frozenset({"3EC4.1", "54BD.1"}),
    ),
    Category(
        "NSPrivacyAccessedAPICategoryUserDefaults",
        _words("UserDefaults", "NSUserDefaults"),
        frozenset({"CA92.1", "1C8F.1", "AC6B.1"}),
    ),
)

CATEGORY_BY_KEY = {c.key: c for c in CATEGORIES}


# --------------------------------------------------------------------------
# A minimal reader for the old-style (OpenStep) property list that
# project.pbxproj is written in. Python's plistlib reads only XML and binary.
# --------------------------------------------------------------------------


class PbxParseError(ValueError):
    pass


_BARE = re.compile(r"[A-Za-z0-9_$+/:.\-]+")


def parse_pbxproj(text: str) -> dict:
    pos = 0
    n = len(text)

    def skip() -> None:
        nonlocal pos
        while pos < n:
            if text[pos].isspace():
                pos += 1
            elif text.startswith("//", pos):
                end = text.find("\n", pos)
                pos = n if end < 0 else end + 1
            elif text.startswith("/*", pos):
                end = text.find("*/", pos + 2)
                if end < 0:
                    raise PbxParseError("unterminated comment")
                pos = end + 2
            else:
                return

    def expect(ch: str) -> None:
        nonlocal pos
        skip()
        if pos >= n or text[pos] != ch:
            raise PbxParseError(f"expected {ch!r} at offset {pos}")
        pos += 1

    def value():
        nonlocal pos
        skip()
        if pos >= n:
            raise PbxParseError("unexpected end of input")
        ch = text[pos]
        if ch == "{":
            pos += 1
            out: dict = {}
            while True:
                skip()
                if pos < n and text[pos] == "}":
                    pos += 1
                    return out
                key = value()
                if not isinstance(key, str):
                    raise PbxParseError(f"non-string key at offset {pos}")
                expect("=")
                out[key] = value()
                expect(";")
        if ch == "(":
            pos += 1
            items: list = []
            while True:
                skip()
                if pos < n and text[pos] == ")":
                    pos += 1
                    return items
                items.append(value())
                skip()
                if pos < n and text[pos] == ",":
                    pos += 1
        if ch == '"':
            pos += 1
            buf: list[str] = []
            while pos < n and text[pos] != '"':
                if text[pos] == "\\" and pos + 1 < n:
                    buf.append(text[pos + 1])
                    pos += 2
                else:
                    buf.append(text[pos])
                    pos += 1
            if pos >= n:
                raise PbxParseError("unterminated string")
            pos += 1
            return "".join(buf)
        m = _BARE.match(text, pos)
        if not m:
            raise PbxParseError(f"unexpected {ch!r} at offset {pos}")
        pos = m.end()
        return m.group(0)

    root = value()
    if not isinstance(root, dict) or "objects" not in root:
        raise PbxParseError("no objects dictionary")
    return root


# --------------------------------------------------------------------------
# Project model
# --------------------------------------------------------------------------


@dataclass
class Target:
    name: str
    product_type: str
    sources: list[Path]  # relative to the iOS project directory
    resources: list[Path]


def _file_paths(objects: dict) -> dict[str, Path]:
    """Maps every PBXFileReference / PBXVariantGroup id to its path relative to
    the project directory, by walking the group tree from the main group."""
    root = next(o for o in objects.values() if o.get("isa") == "PBXProject")
    paths: dict[str, Path] = {}

    def walk(obj_id: str, parent: Path) -> None:
        obj = objects.get(obj_id)
        if obj is None:
            return
        tree = obj.get("sourceTree", "<group>")
        own = obj.get("path")
        if tree == "SOURCE_ROOT":
            base = Path(".")
        elif tree == "<group>":
            base = parent
        else:  # BUILT_PRODUCTS_DIR, SDKROOT, …: not a source file in the tree
            return
        here = base / own if own else base
        isa = obj.get("isa")
        if isa == "PBXGroup":
            for child in obj.get("children", []):
                walk(child, here)
        else:
            paths[obj_id] = here

    walk(root["mainGroup"], Path("."))
    return paths


def read_targets(pbxproj_text: str) -> list[Target]:
    objects = parse_pbxproj(pbxproj_text)["objects"]
    paths = _file_paths(objects)
    targets: list[Target] = []
    for obj in objects.values():
        if obj.get("isa") != "PBXNativeTarget":
            continue
        sources: list[Path] = []
        resources: list[Path] = []
        for phase_id in obj.get("buildPhases", []):
            phase = objects.get(phase_id, {})
            bucket = {
                "PBXSourcesBuildPhase": sources,
                "PBXResourcesBuildPhase": resources,
            }.get(phase.get("isa"))
            if bucket is None:
                continue
            for build_file_id in phase.get("files", []):
                ref = objects.get(build_file_id, {}).get("fileRef")
                if ref in paths:
                    bucket.append(paths[ref])
        targets.append(
            Target(
                name=obj.get("name", "?"),
                product_type=obj.get("productType", ""),
                sources=sources,
                resources=resources,
            )
        )
    return targets


# --------------------------------------------------------------------------
# Source scanning
# --------------------------------------------------------------------------

_STRIP = re.compile(
    r'"""[\s\S]*?"""'  # Swift multi-line string
    r'|"(?:\\.|[^"\\\n])*"'  # string literal
    r"|//[^\n]*"  # line comment
    r"|/\*[\s\S]*?\*/",  # block comment
)


def strip_comments(src: str) -> str:
    """Blanks comments, keeping line numbers. String literals are matched only
    so that a ``//`` inside one is not taken for a comment; they are kept,
    because a Swift string can interpolate a call (``"\\(x.creationDate)"``)
    and a missed use is worse than a declaration a string forced."""

    def repl(m: re.Match[str]) -> str:
        text = m.group(0)
        return text if text.startswith('"') else "\n" * text.count("\n")

    return _STRIP.sub(repl, src)


def used_categories(src: str) -> dict[str, list[tuple[int, str]]]:
    """Category key -> [(line, symbol)] for every required-reason symbol in
    ``src`` outside comments."""
    code = strip_comments(src)
    found: dict[str, list[tuple[int, str]]] = {}
    for category in CATEGORIES:
        for pattern in category.symbols:
            for m in re.finditer(pattern, code):
                line = code.count("\n", 0, m.start()) + 1
                symbol = m.group(0).rstrip("( \t")
                found.setdefault(category.key, []).append((line, symbol))
    for hits in found.values():
        hits.sort()
    return found


# --------------------------------------------------------------------------
# Manifest validation
# --------------------------------------------------------------------------


def manifest_problems(data: bytes) -> tuple[list[str], dict[str, list[str]]]:
    """Returns (problems, declared category -> reasons)."""
    problems: list[str] = []
    try:
        plist = plistlib.loads(data)
    except Exception as exc:  # noqa: BLE001 - any parse failure is a finding
        return [f"does not parse as a property list ({exc})"], {}
    if not isinstance(plist, dict):
        return ["top level is not a dictionary"], {}
    if plist.get("NSPrivacyTracking") is not False:
        problems.append("NSPrivacyTracking must be present and false")
    if plist.get("NSPrivacyTrackingDomains", []):
        problems.append("NSPrivacyTrackingDomains must be empty")
    if not isinstance(plist.get("NSPrivacyCollectedDataTypes"), list):
        problems.append("NSPrivacyCollectedDataTypes must be present (an array)")
    declared: dict[str, list[str]] = {}
    entries = plist.get("NSPrivacyAccessedAPITypes")
    if not isinstance(entries, list):
        problems.append("NSPrivacyAccessedAPITypes must be present (an array)")
        entries = []
    for entry in entries:
        key = entry.get("NSPrivacyAccessedAPIType") if isinstance(entry, dict) else None
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons") if isinstance(entry, dict) else None
        category = CATEGORY_BY_KEY.get(key)
        if category is None:
            problems.append(f"unknown API category {key!r}")
            continue
        if key in declared:
            problems.append(f"{key} is declared twice")
        if not isinstance(reasons, list) or not reasons:
            problems.append(f"{key} has no reasons")
            reasons = []
        for reason in reasons:
            if reason not in category.app_reasons:
                problems.append(
                    f"{key}: {reason!r} is not a reason an app may declare for this "
                    f"category (allowed: {', '.join(sorted(category.app_reasons))})"
                )
        declared[key] = list(reasons)
    return problems, declared


def check(ios_dir: Path, pbxproj: Path) -> list[str]:
    failures: list[str] = []
    try:
        targets = read_targets(pbxproj.read_text(encoding="utf-8"))
    except (OSError, PbxParseError, StopIteration, KeyError) as exc:
        return [f"{pbxproj}: cannot read the project ({exc})"]
    shipped = [t for t in targets if t.product_type in SHIPPED_PRODUCT_TYPES]
    if not shipped:
        return [f"{pbxproj}: no application or app-extension target found"]
    for target in shipped:
        prefix = f"target {target.name}"
        manifests = [p for p in target.resources if p.name == MANIFEST_NAME]
        used: dict[str, list[str]] = {}
        for rel in target.sources:
            if rel.suffix not in SCANNED_SUFFIXES:
                continue
            path = ios_dir / rel
            if rel.name in GENERATED_SOURCES and not path.exists():
                continue
            try:
                src = path.read_text(encoding="utf-8")
            except OSError as exc:
                failures.append(f"{prefix}: cannot read source {rel} ({exc})")
                continue
            for key, hits in used_categories(src).items():
                used.setdefault(key, []).extend(f"{rel}:{line} {sym}" for line, sym in hits)
        if len(manifests) != 1:
            failures.append(
                f"{prefix}: its Resources build phase copies {len(manifests)} "
                f"{MANIFEST_NAME} files (expected exactly 1) — add the manifest to "
                f"the target in {PBXPROJ.as_posix()}, or it never reaches the bundle"
            )
            for key, where in sorted(used.items()):
                failures.append(f"{prefix}: uses {key} ({where[0]}) with no manifest to declare it")
            continue
        manifest_rel = manifests[0]
        try:
            data = (ios_dir / manifest_rel).read_bytes()
        except OSError as exc:
            failures.append(f"{prefix}: {manifest_rel} is in the project but unreadable ({exc})")
            continue
        problems, declared = manifest_problems(data)
        failures.extend(f"{prefix}: {manifest_rel}: {p}" for p in problems)
        for key, where in sorted(used.items()):
            if key not in declared:
                failures.append(
                    f"{prefix}: uses {key} but {manifest_rel} does not declare it; "
                    f"first use: {where[0]}"
                )
        for key in sorted(declared):
            if key not in used:
                failures.append(
                    f"{prefix}: {manifest_rel} declares {key} but no source in the "
                    f"target uses it — remove the entry or this check's symbol list "
                    f"is missing an API"
                )
    return failures


def main() -> int:
    failures = check(REPO_ROOT / IOS_DIR, REPO_ROOT / PBXPROJ)
    if failures:
        print("iOS privacy manifest check FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("iOS privacy manifests declare every required-reason API their targets use.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
