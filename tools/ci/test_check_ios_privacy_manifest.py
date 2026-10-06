#!/usr/bin/env python3
"""Offline tests for ``check_ios_privacy_manifest.py`` (post-audit platform-6).

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_ios_privacy_manifest.py

The guard has three ways to be quietly useless, and each has a case below:
reading target membership wrong (so a source or manifest is attributed to the
wrong bundle), missing a symbol (so a use goes undeclared), and accepting a
manifest that is on disk but not copied by the target's Resources phase.
"""

from __future__ import annotations

import plistlib
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_ios_privacy_manifest import (  # noqa: E402
    PBXPROJ,
    REPO_ROOT,
    check,
    manifest_problems,
    parse_pbxproj,
    read_targets,
    used_categories,
)

FAILURES: list[str] = []

FILE_TS = "NSPrivacyAccessedAPICategoryFileTimestamp"
DEFAULTS = "NSPrivacyAccessedAPICategoryUserDefaults"
BOOT = "NSPrivacyAccessedAPICategorySystemBootTime"
DISK = "NSPrivacyAccessedAPICategoryDiskSpace"
KEYBOARDS = "NSPrivacyAccessedAPICategoryActiveKeyboards"


def expect(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


# --------------------------------------------------------------------------
# Fixture project: an app target "App" (group App/, plus one source pulled in
# from Shared/) and an extension "Ext" (group Ext/, SOURCE_ROOT like the real
# ShareExtension group), and a test bundle that must be ignored.
# --------------------------------------------------------------------------


def pbxproj(app_resources: str = "", ext_resources: str = "") -> str:
    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	objects = {{
		B001 /* AppMain.swift in Sources */ = {{isa = PBXBuildFile; fileRef = F001 /* AppMain.swift */; }};
		B002 /* Helper.swift in Sources */ = {{isa = PBXBuildFile; fileRef = F002 /* Helper.swift */; }};
		B003 /* ExtMain.swift in Sources */ = {{isa = PBXBuildFile; fileRef = F003 /* ExtMain.swift */; }};
		B004 /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = F004 /* PrivacyInfo.xcprivacy */; }};
		B005 /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = F005 /* PrivacyInfo.xcprivacy */; }};
		B006 /* Tests.swift in Sources */ = {{isa = PBXBuildFile; fileRef = F006 /* Tests.swift */; }};
		F001 /* AppMain.swift */ = {{isa = PBXFileReference; path = AppMain.swift; sourceTree = "<group>"; }};
		F002 /* Helper.swift */ = {{isa = PBXFileReference; path = Helper.swift; sourceTree = "<group>"; }};
		F003 /* ExtMain.swift */ = {{isa = PBXFileReference; path = ExtMain.swift; sourceTree = "<group>"; }};
		F004 /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};
		F005 /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};
		F006 /* Tests.swift */ = {{isa = PBXFileReference; path = Tests.swift; sourceTree = "<group>"; }};
		P001 /* App.app */ = {{isa = PBXFileReference; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		G000 = {{isa = PBXGroup; children = (G001, G002, G003, G004, G005); sourceTree = "<group>"; }};
		G001 /* App */ = {{isa = PBXGroup; children = (F001, F004); path = App; sourceTree = "<group>"; }};
		G002 /* Shared */ = {{isa = PBXGroup; children = (F002); path = Shared; sourceTree = "<group>"; }};
		G003 /* Ext */ = {{isa = PBXGroup; children = (F003, F005); name = Ext; path = Ext; sourceTree = SOURCE_ROOT; }};
		G004 /* Tests */ = {{isa = PBXGroup; children = (F006); path = Tests; sourceTree = "<group>"; }};
		G005 /* Products */ = {{isa = PBXGroup; children = (P001); name = Products; sourceTree = "<group>"; }};
		S001 /* Sources */ = {{isa = PBXSourcesBuildPhase; files = (B001, B002, ); }};
		R001 /* Resources */ = {{isa = PBXResourcesBuildPhase; files = ({app_resources}); }};
		S002 /* Sources */ = {{isa = PBXSourcesBuildPhase; files = (B003, ); }};
		R002 /* Resources */ = {{isa = PBXResourcesBuildPhase; files = ({ext_resources}); }};
		S003 /* Sources */ = {{isa = PBXSourcesBuildPhase; files = (B006, ); }};
		T001 /* App */ = {{isa = PBXNativeTarget; buildPhases = (S001, R001, ); name = App; productType = "com.apple.product-type.application"; }};
		T002 /* Ext */ = {{isa = PBXNativeTarget; buildPhases = (S002, R002, ); name = Ext; productType = "com.apple.product-type.app-extension"; }};
		T003 /* Tests */ = {{isa = PBXNativeTarget; buildPhases = (S003, ); name = Tests; productType = "com.apple.product-type.bundle.unit-test"; }};
		X001 /* Project object */ = {{isa = PBXProject; mainGroup = G000; targets = (T001, T002, T003, ); }};
	}};
	rootObject = X001;
}}
"""


def manifest(categories: dict[str, list[str]], **overrides) -> bytes:
    body = {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": k, "NSPrivacyAccessedAPITypeReasons": v}
            for k, v in categories.items()
        ],
    }
    body.update(overrides)
    return plistlib.dumps(body)


APP_SRC = "let d = UserDefaults(suiteName: group)\n"
HELPER_SRC = "let k: URLResourceKey = .creationDateKey\n"
EXT_SRC = "// UserDefaults is not used here, only mentioned.\nlet x = 1\n"
GOOD_APP = {DEFAULTS: ["1C8F.1"], FILE_TS: ["C617.1"]}


def run(
    *,
    app_resources: str = "B004, ",
    ext_resources: str = "B005, ",
    app_manifest: bytes | None = None,
    ext_manifest: bytes | None = None,
    helper_src: str = HELPER_SRC,
) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, text in (
            ("App/AppMain.swift", APP_SRC),
            ("Shared/Helper.swift", helper_src),
            ("Ext/ExtMain.swift", EXT_SRC),
            ("Tests/Tests.swift", "let up = ProcessInfo.processInfo.systemUptime\n"),
        ):
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text, encoding="utf-8")
        (root / "App/PrivacyInfo.xcprivacy").write_bytes(
            app_manifest if app_manifest is not None else manifest(GOOD_APP)
        )
        (root / "Ext/PrivacyInfo.xcprivacy").write_bytes(
            ext_manifest if ext_manifest is not None else manifest({})
        )
        proj = root / "project.pbxproj"
        proj.write_text(pbxproj(app_resources, ext_resources), encoding="utf-8")
        return check(root, proj)


# --------------------------------------------------------------------------


def test_symbols() -> None:
    print("required-reason symbols are recognised:")
    cases = {
        "UserDefaults.standard": DEFAULTS,
        "[NSUserDefaults standardUserDefaults]": DEFAULTS,
        "url.resourceValues(forKeys: [.creationDateKey])": FILE_TS,
        "attrs[.modificationDate]": FILE_TS,
        "lstat(path, &st)": FILE_TS,
        "stat (path, &st)": FILE_TS,
        "ProcessInfo.processInfo.systemUptime": BOOT,
        "let t = mach_absolute_time()": BOOT,
        "[.volumeAvailableCapacityForImportantUsageKey]": DISK,
        "statvfs(path, &buf)": DISK,
        "UITextInputMode.activeInputModes": KEYBOARDS,
    }
    for src, key in cases.items():
        expect(f"{src!r} -> {key.removeprefix('NSPrivacyAccessedAPICategory')}",
               key in used_categories(src), str(used_categories(src)))
    found = used_categories("getattrlist(a, b, c, d, e)")
    expect("getattrlist counts as both FileTimestamp and DiskSpace",
           FILE_TS in found and DISK in found, str(found))

    print("non-uses are not flagged:")
    for src in (
        "// UserDefaults(suiteName: x)",
        "/* uses .creationDateKey\n and stat(x) */",
        "let status = statusCode",
        "func statistics() {}",
        "let myUserDefaultsWrapper = 1",
        "let stats = stat",  # no call
    ):
        expect(f"{src!r} -> nothing", used_categories(src) == {}, str(used_categories(src)))
    expect("a '//' inside a string does not hide the code after it",
           DEFAULTS in used_categories('let u = "http://x"; let d = UserDefaults.standard'))
    expect("an interpolated use inside a string literal still counts",
           FILE_TS in used_categories('print("\\(attrs.creationDate)")'))
    hits = used_categories("\n\nlet d = UserDefaults.standard\n")[DEFAULTS]
    expect("line numbers survive comment stripping", hits == [(3, "UserDefaults")], str(hits))


def test_manifest_validation() -> None:
    print("manifest contents are validated:")
    problems, declared = manifest_problems(manifest(GOOD_APP))
    expect("a well-formed manifest has no problems", problems == [], str(problems))
    expect("declared categories are returned", declared == GOOD_APP, str(declared))
    problems, _ = manifest_problems(manifest({}, NSPrivacyTracking=True))
    expect("NSPrivacyTracking true is rejected", any("NSPrivacyTracking" in p for p in problems))
    problems, _ = manifest_problems(manifest({}, NSPrivacyTrackingDomains=["t.example"]))
    expect("tracking domains are rejected", any("TrackingDomains" in p for p in problems))
    body = plistlib.loads(manifest({}))
    del body["NSPrivacyTracking"]
    problems, _ = manifest_problems(plistlib.dumps(body))
    expect("a missing NSPrivacyTracking is rejected", any("NSPrivacyTracking" in p for p in problems))
    problems, _ = manifest_problems(manifest({DEFAULTS: ["C56D.1"]}))
    expect("an SDK-only reason is rejected for an app", any("C56D.1" in p for p in problems))
    problems, _ = manifest_problems(manifest({DEFAULTS: ["C617.1"]}))
    expect("a reason from another category is rejected", any("C617.1" in p for p in problems))
    problems, _ = manifest_problems(manifest({DEFAULTS: []}))
    expect("a category with no reasons is rejected", any("no reasons" in p for p in problems))
    problems, _ = manifest_problems(b"not a plist")
    expect("an unparseable manifest is rejected", bool(problems))


def test_project_reading() -> None:
    print("target membership is read from the project file:")
    targets = {t.name: t for t in read_targets(pbxproj("B004, ", "B005, "))}
    expect("all three targets are found", set(targets) == {"App", "Ext", "Tests"}, str(set(targets)))
    expect("a source in another group belongs to its target",
           [p.as_posix() for p in targets["App"].sources] == ["App/AppMain.swift", "Shared/Helper.swift"],
           str(targets["App"].sources))
    expect("a SOURCE_ROOT group resolves from the project directory",
           [p.as_posix() for p in targets["Ext"].resources] == ["Ext/PrivacyInfo.xcprivacy"],
           str(targets["Ext"].resources))

    print("the real project parses:")
    real = {t.name: t for t in read_targets((REPO_ROOT / PBXPROJ).read_text(encoding="utf-8"))}
    expect("Runner and ShareExtension are targets", {"Runner", "ShareExtension"} <= set(real), str(set(real)))
    expect("IncomingFilesPlugin.swift is a Runner source",
           "Runner/IncomingFilesPlugin.swift" in [p.as_posix() for p in real["Runner"].sources])
    expect("ShareViewController.swift is a ShareExtension source",
           "ShareExtension/ShareViewController.swift"
           in [p.as_posix() for p in real["ShareExtension"].sources])
    parsed = parse_pbxproj('{ objects = { a = "x \\" y"; b = (1, 2,); }; }')
    expect("quoted strings and trailing commas parse",
           parsed["objects"] == {"a": 'x " y', "b": ["1", "2"]}, str(parsed))


def test_check() -> None:
    print("whole-project check:")
    failures = run()
    expect("a correct project passes", failures == [], str(failures))

    failures = run(app_resources="")
    expect("a manifest on disk but not in the Resources phase fails",
           any("target App" in f and "Resources build phase copies 0" in f for f in failures),
           str(failures))
    failures = run(ext_resources="")
    expect("the extension's manifest is required too",
           any("target Ext" in f and "copies 0" in f for f in failures), str(failures))
    failures = run(app_resources="B004, B005, ")
    expect("two manifests copied into one target fail",
           any("copies 2" in f for f in failures), str(failures))

    failures = run(app_manifest=manifest({DEFAULTS: ["1C8F.1"]}))
    expect("a use in a file from another group must be declared",
           any("uses " + FILE_TS in f and "Shared/Helper.swift:1" in f for f in failures),
           str(failures))
    failures = run(app_manifest=manifest({FILE_TS: ["C617.1"]}))
    expect("an undeclared UserDefaults use fails",
           any("uses " + DEFAULTS in f for f in failures), str(failures))

    failures = run(helper_src="let x = 1\n")
    expect("a declaration with no remaining use fails",
           any("declares " + FILE_TS in f and "no source" in f for f in failures), str(failures))
    failures = run(ext_manifest=manifest({DEFAULTS: ["1C8F.1"]}))
    expect("a use mentioned only in a comment does not justify a declaration",
           any("target Ext" in f and "declares " + DEFAULTS in f for f in failures), str(failures))

    expect("the unit-test target is not checked",
           not any("Tests" in f for f in run(app_resources="")), "")


def main() -> int:
    test_symbols()
    test_manifest_validation()
    test_project_reading()
    test_check()
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("\nall check_ios_privacy_manifest tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
