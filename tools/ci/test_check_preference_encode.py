#!/usr/bin/env python3
"""Offline tests for ``check_preference_encode.py``.

Pure-stdlib, assert-based, like the other ``tools/ci/test_*.py``. Run::

    python3 tools/ci/test_check_preference_encode.py
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_preference_encode import (  # noqa: E402
    DescriptorError,
    descriptors_in,
    scan,
    violations_in,
)

FAILURES: list[str] = []

DESCRIPTORS_SRC = """
class _AppState {
  final _theme = PreferenceNotifier<AppThemeSelection>(
    key: kAppThemeKey,
    defaultValue: AppThemeSelection.system,
    // encode: (v) => v.index,   <- a comment, not the contract
    decode: (Object? v) => AppThemeSelection.forName(v is String ? v : null),
    encode: (v) => v.name,
  );
  final _flag = PreferenceNotifier<bool>(
    key: kFlagKey,
    defaultValue: false,
    decode: (Object? v) => v is bool ? v : false,
    encode: (v) => v,
  );
  final _tiles = PreferenceNotifier<Set<Field>>(
    key: kTilesKey,
    defaultValue: Field.all,
    decode: Scope.decodeStored,
    encode: (v) => v.map((f) => f.toJson()).toList(),
  );
  final _locale = PreferenceNotifier<Locale?>(
    key: kLocaleKey,
    defaultValue: null,
    decode: (Object? v) => null,
    encode: localeToTag,
  );
  late final List<PreferenceNotifier<Object?>> _preferences = [_theme, _flag];
  void _reset() { for (final p in _preferences) p.reset(); }
}

class DateNotifier extends PreferenceNotifier<DateFormatSetting> {
  DateNotifier()
    : super(
        key: kDateFormatKey,
        defaultValue: DateFormatSetting.system,
        decode: (Object? s) => DateFormatSetting.system,
        encode: (setting) => setting.pref.token,
      );
}
"""


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def descriptors():
    return {d.key: d for d in descriptors_in(DESCRIPTORS_SRC, "main.dart")}


def bad(handler: str) -> list[str]:
    return [detail for _, detail in violations_in(handler, "h.dart", descriptors())]


def test_descriptors() -> None:
    print("descriptors:")
    ds = descriptors()
    check(
        "every construction and the super(...) form are read",
        set(ds) == {"kAppThemeKey", "kFlagKey", "kTilesKey", "kLocaleKey", "kDateFormatKey"},
        str(sorted(ds)),
    )
    check("a commented-out encode is not read", ds["kAppThemeKey"].encode == "(v) => v.name")
    check("lambda application", ds["kAppThemeKey"].apply("selection") == "selection.name")
    check(
        "an inner lambda's own parameter is left alone",
        ds["kTilesKey"].apply("updated") == "updated.map((f) => f.toJson()).toList()",
        ds["kTilesKey"].apply("updated"),
    )
    check("tear-off application", ds["kLocaleKey"].apply("value") == "localeToTag(value)")
    check(
        "a non-identifier value is parenthesised",
        ds["kAppThemeKey"].apply("a ?? b") == "(a ?? b).name",
    )
    for name, src in {
        "an inline string key": "final x = PreferenceNotifier<int>(key: 'k', encode: (v) => v);",
        "a missing encode": "final x = PreferenceNotifier<int>(key: kXKey, decode: f);",
    }.items():
        try:
            descriptors_in(src, "main.dart")
        except DescriptorError:
            check(f"fails closed on {name}", True)
        else:
            check(f"fails closed on {name}", False, "no DescriptorError")
    check(
        "the constructor's own declaration is not a descriptor",
        descriptors_in(
            "class PreferenceNotifier<T> extends ValueNotifier<T> {\n"
            "  PreferenceNotifier({required this.key, required this.encode});\n}\n",
            "p.dart",
        )
        == [],
    )


def test_compliant_handlers() -> None:
    print("compliant handlers:")
    check(
        "bool handler",
        not bad(
            "Future<void> f(bool value) async {\n"
            "  FlagScope.notifierOf(context).value = value;\n"
            "  await persistSetting(repos.settings, kFlagKey, value);\n}\n"
        ),
    )
    check(
        "enum handler with the assignment before an unrelated await",
        not bad(
            "Future<void> f(AppThemeSelection selection) async {\n"
            "  AppThemeScope.notifierOf(context).value = selection;\n"
            "  await customs.setActive(null);\n"
            "  await persistSetting(\n    repos.settings,\n    kAppThemeKey,\n"
            "    selection.name,\n  );\n}\n"
        ),
    )
    check(
        "closure handler, set comprehension, trailing comma",
        not bad(
            "Future<void> toggle(Field field, bool on) async {\n"
            "  final updated = Set.of(notifier.value);\n"
            "  notifier.value = updated;\n"
            "  await persistSetting(settings, kTilesKey, "
            "updated.map((f) => f.toJson()).toList(),);\n}\n"
        ),
    )
    check(
        "assignment inside an if block",
        not bad(
            "Future<void> f(bool value) async {\n"
            "  if (scoped != null) { Scope.notifierOf(context).value = value; }\n"
            "  await persistSetting(repos.settings, kFlagKey, value);\n}\n"
        ),
    )
    check(
        "tear-off encode and the super(...) descriptor",
        not bad(
            "Future<void> f(Locale? value) async {\n"
            "  LocaleScope.notifierOf(context).value = value;\n"
            "  await persistSetting(repos.settings, kLocaleKey, localeToTag(value));\n}\n"
            "Future<void> g(DateFormatSetting setting) async {\n"
            "  DateFormatScope.notifierOf(context).value = setting;\n"
            "  await persistSetting(repos.settings, kDateFormatKey, setting.pref.token);\n"
            "  await persistSetting(repos.settings, kDateFormatCustomPatternKey, '');\n}\n"
        ),
    )
    check(
        "keys with no descriptor and writes in comments/strings are ignored",
        not bad(
            "Future<void> f(int v) async {\n"
            "  await persistSetting(repos.settings, kOtherKey, v.toString());\n"
            "  // await persistSetting(repos.settings, kAppThemeKey, x.index);\n"
            "  final s = 'persistSetting(s, kAppThemeKey, x.index)';\n}\n"
        ),
    )


def test_violations() -> None:
    print("violations:")
    hand_encoded = bad(
        "Future<void> f(AppThemeSelection selection) async {\n"
        "  AppThemeScope.notifierOf(context).value = selection;\n"
        "  await persistSetting(repos.settings, kAppThemeKey, selection.index);\n}\n"
    )
    check(
        "a hand encoding that differs from encode",
        len(hand_encoded) == 1 and "selection.name" in hand_encoded[0],
        str(hand_encoded),
    )
    check(
        "encoding a different variable than the one assigned",
        len(
            bad(
                "Future<void> f(bool value) async {\n"
                "  FlagScope.notifierOf(context).value = value;\n"
                "  await persistSetting(repos.settings, kFlagKey, !value);\n}\n"
            )
        )
        == 1,
    )
    check(
        "a direct settings.set of a preference key",
        len(
            bad(
                "Future<void> f(Set<Field> updated) async {\n"
                "  notifier.value = updated;\n"
                "  await repos.settings.set(kTilesKey, "
                "updated.map((f) => f.name).toList());\n}\n"
            )
        )
        == 1,
    )
    no_assignment = bad(
        "Future<void> f(bool value) async {\n"
        "  await persistSetting(repos.settings, kFlagKey, value);\n}\n"
    )
    check(
        "a write with no live-notifier assignment",
        len(no_assignment) == 1 and "without first assigning" in no_assignment[0],
        str(no_assignment),
    )
    check(
        "an assignment in an earlier function does not count",
        len(
            bad(
                "void a(bool value) { FlagScope.notifierOf(context).value = value; }\n"
                "Future<void> f(bool value) async {\n"
                "  await persistSetting(repos.settings, kFlagKey, value);\n}\n"
            )
        )
        == 1,
    )


def test_repository() -> None:
    print("repository:")
    descriptors, checked, problems = scan()
    check("the live tree is compliant", not problems, "\n".join(problems))
    check(
        "every live preference descriptor is read",
        len(descriptors) >= 23,
        str(len(descriptors)),
    )
    check("handler writes were found (not vacuous)", checked >= len(descriptors), str(checked))


def main() -> int:
    test_descriptors()
    test_compliant_handlers()
    test_violations()
    test_repository()
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s)")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
