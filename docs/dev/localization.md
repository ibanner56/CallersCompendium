# Localization (i18n)

Caller's Compendium is internationalized with Flutter's first-party stack:
[`flutter_localizations`](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization)
plus `flutter gen-l10n`. **English is the source locale** — every user-visible
string starts life in the English template and is referenced from code through a
generated, type-safe `AppLocalizations` API. Translations into other languages
are **community-driven** and require no code change to appear (see
[Contributing a translation](#contributing-a-translation)).

This document is the contract for the phased string-extraction work: the
framework and a first slice of strings have landed; the remaining UI strings are
extracted into the ARB incrementally. Follow the conventions here so those PRs
stay consistent.

**Extraction status (not yet complete).** Layers 1–5 have landed: the framework,
shared cross-cutting vocabulary (facet domain-value labels), the import-gap
badge, the `(copy)` title suffix, the small global/shared chrome, and most of
the **Settings surface** (the defaults, general-appearance, dialect, updates, and
about sections). The final layer (**L6**) localizes the remaining
feature-specific surfaces — the dance editor (`dance_editor/`), its detail
screen and editor dialogs, the figure editors, the Settings general
(data-management) section and the formation-colours screen, and a few secondary
screens (custom fields, dialect editor, theme editor, recently-deleted, ContraDB
import, user guide) — plus the large chrome widgets `collection_picker`,
`command_palette`, and `update_banner`. Those files are parked in the guard
allow-list (see [Guarding against hardcoded strings](#guarding-against-hardcoded-strings));
L6 removes each as it localizes it and flips this note to "complete".

## How it's wired

- **`app/pubspec.yaml`** declares `flutter_localizations` (SDK) and sets
  `generate: true` under `flutter:`, which turns on `gen-l10n`.
- **`app/l10n.yaml`** configures generation:
  - `arb-dir: lib/l10n` — where the ARB translation files live.
  - `template-arb-file: app_en.arb` — the English source of truth.
  - `output-localization-file: app_localizations.dart`, `output-class: AppLocalizations`.
  - `nullable-getter: false` — `AppLocalizations.of(context)` is **non-null**;
    the delegates are always wired (see below), so callers never null-check it.
- **`app/lib/l10n/app_en.arb`** is the English template and the source of every
  key. Editing it (and running `flutter pub get` / `flutter gen-l10n`) regenerates
  the Dart under `app/lib/l10n/`.
- **`app/lib/l10n/app_localizations*.dart`** are **generated** and **committed**.
  They are `dart format`-clean and analyzer-clean straight out of `gen-l10n` (the
  file carries `// ignore_for_file: type=lint`), so committing them keeps builds
  and tests independent of generation timing. CI regenerates them deterministically
  via `flutter pub get` before analyze/test/build, so the committed copy stays in
  sync. **After editing `app_en.arb`, always regenerate and commit the result.**
- **`app/lib/main.dart`** installs the delegates and the supported-locale list on
  the root `MaterialApp`:
  - `localizationsDelegates: AppLocalizations.localizationsDelegates`
  - `supportedLocales: AppLocalizations.supportedLocales`
  - `locale: _localeNotifier.value` — the chosen app locale (or `null` = follow
    the system), driven live by `LocaleScope`.
  - `onGenerateTitle: (context) => AppLocalizations.of(context).appTitle` — the
    window/task-switcher title comes from the ARB, not a hardcoded string.

### Locale & regional-format state

Three preferences are persisted via `SettingsRepository` and exposed to the tree
as `InheritedNotifier` scopes (mirroring `AppThemeScope`/`DateFormatScope`):

| Preference        | Scope                 | Key (const)            | Stored as            |
| ----------------- | --------------------- | ---------------------- | -------------------- |
| App language      | `LocaleScope`         | `kLocaleKey`           | BCP-47 tag (`en`)    |
| Date format       | `DateFormatScope`     | `kDateFormatKey`       | enum token           |
| First day of week | `FirstDayOfWeekScope` | `kFirstDayOfWeekKey`   | enum token           |

Read a scope with `Scope.of(context)` (registers a rebuild); change it with
`Scope.notifierOf(context)`. Changing `LocaleScope` updates `MaterialApp.locale`,
so the whole app re-renders in the selected language live. The Language & region
settings section (`app/lib/src/screens/settings/regional_section.dart`) is the
UI for all three.

### Security: validate every persisted value (OWASP)

Persisted settings are **untrusted input**. Everything read back on startup is
validated before use — a corrupted, unknown, or hostile value must never crash
startup or select an unsupported option:

- **Locale** — `localeFromStored(stored, supported)` never constructs an
  arbitrary `Locale` from the raw string. It only ever returns a locale that is
  actually in `AppLocalizations.supportedLocales`; a non-string, empty, over-long,
  or unrecognized tag resolves to `null` (follow system). Case/separator
  differences are tolerated and a full tag (`en-US`) falls back to a
  language-only match (`en`).
- **Enums** (`DateFormatPref`, `FirstDayOfWeekPref`) — resolved by token via
  `…PrefFromStored`, which falls back to the safe `system` default for `null`, a
  non-string, or an unknown token.

## Key-naming convention

Keys are **camelCase** and **area-prefixed** so the flat ARB namespace stays
navigable as it grows to ~900 strings. Every key gets an `@<key>` metadata block
with a `description`; use ICU placeholders/plurals where relevant.

| Prefix      | Area                                   | Examples                                      |
| ----------- | -------------------------------------- | --------------------------------------------- |
| `app*`      | app-wide identity                      | `appTitle`                                    |
| `nav*`      | top-level navigation labels            | `navCollection`, `navPrograms`, `navSettings` |
| `settings*` | Settings screens                       | `settingsTitle`, `settingsDateFormatTitle`    |
| `common*`   | shared across screens                  | `commonSystemDefault`, `commonCancel`         |

Guidelines:

- Prefer a `common*` key when a string is genuinely shared; don't force-share
  strings that merely happen to match today.
- Name by **meaning**, not by the English text (`commonSystemDefault`, not
  `commonSystemDefaultText`).
- Placeholders are named and typed in the `@key` metadata, e.g.
  `settingsDateFormatSubtitle` takes `{example}`.
- Language names in the selector are **endonyms** (native names) and live in a
  small in-code map (`nativeLanguageName` in `locale_scope.dart`), not the ARB —
  proper nouns read best in their own language and shouldn't be re-translated per
  UI locale.

## Adding a new UI string

1. Add the key and its `@key` metadata (with a `description`) to
   `app/lib/l10n/app_en.arb`, following the convention above.
2. Regenerate and format:
   ```sh
   fvm flutter gen-l10n     # (also runs as part of `flutter pub get`)
   fvm dart format .
   ```
3. Use it in a widget: `AppLocalizations.of(context).yourKey`. For a string with
   a placeholder, it's a method: `AppLocalizations.of(context).yourKey(value)`.
4. Commit the updated `app_en.arb` **and** the regenerated
   `app/lib/l10n/app_localizations*.dart`.

In tests, any `MaterialApp` that renders an l10n-dependent widget must wire the
delegates. Use the shared helper `app/test/support/l10n_harness.dart`:

```dart
MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: ...,
);
```

## Localizing enum labels defined in the Flutter-free core (ADR-001)

The `packages/compendium_core` package must **not** import Flutter or
`AppLocalizations` (ADR-001, CI-enforced). So an enum defined in core (e.g.
`DanceLevel`, `DanceStatus`, `Formation`, `Progression`, `DanceForm`,
`FormationShape`) can't carry its own localized display string. Instead, add an
**app-side helper** that maps the enum to a localized string:

```dart
// app/lib/src/search/facet_labels.dart
String danceLevelLabel(AppLocalizations l10n, DanceLevel level) =>
    switch (level) {
      DanceLevel.beginner => l10n.commonDanceLevelBeginner,
      DanceLevel.intermediate => l10n.commonDanceLevelIntermediate,
      DanceLevel.advanced => l10n.commonDanceLevelAdvanced,
    };
```

Call it from widgets: `Text(danceLevelLabel(l10n, dance.level))`. This is the
same pattern used by the earlier layers — `collection_query_labels.dart` (L2),
`program_status_labels.dart` (L3), `online_search_labels.dart` (L4).

**Exports stay English.** Exported documents (plain-text / PDF builders) are
deliberately *not* localized yet (a pending product decision — see the deferrals
below), so they must keep emitting English regardless of the UI locale. Feed the
export builders from a separate **English `.label` extension** on the core enum,
kept app-side so core stays Flutter-free:

```dart
// app/lib/src/models/dance_list_entry.dart
extension DanceLevelExportLabel on DanceLevel {
  String get label => switch (this) { /* fixed English strings */ };
}
```

So UI call sites route through the **localized** helper; export call sites route
through the **English `.label`** extension. Never call `AppLocalizations` from an
export builder, and never add either helper inside `compendium_core`.

## Guarding against hardcoded strings

A ratchet test — `app/test/l10n/no_hardcoded_ui_strings_test.dart` — runs inside
the ordinary `flutter test` gate (no extra CI step; it mirrors the `dart:io`
file-walking precedent of `test/data/migration_guard_test.dart`). It walks
`lib/src/**.dart` and fails if a **string literal** is passed to a user-facing
constructor/argument (`Text('…')`, `tooltip:`, `labelText:`, `hintText:`,
`helperText:`, `errorText:`, `semanticLabel:`, `message:`, `hint:`, `helpText:`).
Prose in a localized app must come from `l10n.*`, so any such literal is a leak.
Pure interpolations, numbers, and punctuation (`'$count'`, `'• '`, `'—'`) are
ignored.

- **Allow-list.** Files not yet localized live in
  `app/test/l10n/hardcoded_ui_strings_allowlist.dart`, split into **L6-deferred
  UI** (removed as L6 localizes them) and **permanent deferrals** (data/service
  curated messages awaiting a typed-error refactor, and the English export-body
  builders). The guard also fails if a listed file no longer exists or no longer
  has any flagged literal, so the manifest can't rot, and it asserts that no
  fully-localized L5 target file is on the list.
- **Escape hatch.** For a literal that is intentionally *not* translatable (a
  brand/proper noun, a single-glyph font specimen, a notation token), append
  `// i18n-ignore` to the literal's line. Keep the line ≤ 80 chars so
  `dart format` doesn't wrap the comment onto the next line.

## Contributing a translation

You do **not** need to write code to translate the app.

1. Copy the English template `app/lib/l10n/app_en.arb` to
   `app/lib/l10n/app_<locale>.arb`. The **filename** uses gen-l10n's underscore
   notation: a bare language code (`app_fr.arb`, `app_ja.arb`), a
   language+region (`app_pt_BR.arb`), or a language+script (`app_zh_Hant.arb` —
   `Hant`/`Hans` are *scripts*, not regions). The equivalent **BCP-47 tag** used
   everywhere else (the `@@locale` value, platform metadata, the in-app selector)
   is the same subtags joined with a hyphen: `pt-BR`, `zh-Hant`.
2. **Set the file's `"@@locale"`** to the copied locale (e.g. `"pt_BR"` or
   `"zh_Hant"`). The template still carries `"en"`; leaving it unchanged makes
   gen-l10n see conflicting locale metadata and can misfile your translations.
3. **Translate the string values only.** Leave the keys and the `@key` metadata
   blocks unchanged. Keep every ICU placeholder (e.g. `{example}`) and plural
   form intact — only the surrounding words change.
4. Regenerate the localizations. From the repository root:
   ```bash
   fvm flutter pub get               # workspace-wide
   (cd app && fvm flutter gen-l10n)  # l10n.yaml and the Flutter package live under app/
   fvm dart format .
   ```
   Commit your new ARB together with the regenerated `app_localizations*.dart`.
   Before committing, sanity-check the file with the validator CI also runs:
   ```bash
   python3 tools/ci/arb_translate.py validate --locale <locale>
   ```
   It flags missing/renamed placeholders, mismatched plural arguments, a wrong
   `@@locale`, and unsafe content before the change ever reaches a build.
5. **iOS only:** add your locale to `app/ios/Runner/Info.plist` under a
   `CFBundleLocalizations` array, using the **hyphenated BCP-47 tag** (e.g.
   `<string>fr</string>`, `<string>pt-BR</string>`, `<string>zh-Hant</string>`) —
   not the underscore filename form. iOS advertises the languages an app supports
   from this list, so without it a contributed language isn't offered by the
   system. Other platforms pick up the supported locales automatically, so no
   extra step is needed there.
6. That's it — your language automatically appears in **Settings ▸ Language &
   region ▸ App language**, shown by its native name, with no code change. If the
   endonym doesn't yet have an entry in `nativeLanguageName` it falls back to the
   locale tag; add your language there for a nicer label.

## Tooling: assisted translation & validation

Two `tools/ci` helpers speed up translating the app and keep contributed
translations safe. Both are pure-stdlib Python (no network, no third-party
dependencies) and treat a translated ARB as **untrusted input** — community
pull requests and the online import/sharing features — validating it in line
with OWASP guidance.

### `tools/ci/arb_translate.py`

A model-agnostic pipeline with three subcommands:

- `extract --locale <code>` — prints the keys still missing (or blank) in
  `app_<code>.arb` as a JSON batch. Each entry carries the English source, its
  `description`, its declared placeholders, and any matched **glossary** hints
  (`tools/ci/i18n_glossary.json`). This is the payload a translator — human or
  model — works from.
- `apply --locale <code> --input <map.json>` — merges a `{key: value}` map into
  `app_<code>.arb`, writing **values only** in template key order, refusing any
  key not in the template and any non-string value. It never invents keys or
  `@key` metadata.
- `validate --locale <code>` / `validate --all` — gates a translation against
  `app_en.arb`: keys must be a subset of the template; every message must keep
  the **same ICU arguments/placeholders** as the source (locale-specific plural
  categories such as `zero`/`few`/`many` are allowed, but a dropped, added, or
  renamed placeholder — or a plural→plain change — fails); `@@locale` must match
  the filename; any `@key` block that is present must equal the template's; and
  each value passes a content-safety scan (no C0/C1 control characters, no
  bidirectional-override characters — the Trojan-Source vectors — and no
  `javascript:`/`vbscript:`/`data:text/html` URIs). Non-fatal warnings cover
  HTML-looking tags, non-NFC text, and unusually long expansions.

CI runs `validate --all` (and the tool's own `test_arb_translate.py`) in
[`_checks.yml`](../../.github/workflows/_checks.yml) before the Flutter build,
so a malformed or unsafe translation fails the PR.

### The `arb-translate` Copilot extension

`.github/extensions/arb-translate/` wires the pipeline into the Copilot CLI so
the session model can do the actual translating — no third-party translation
API or extra key required. It exposes `arb_translate_plan` (→ `extract`),
`arb_translate_apply` (→ `apply`, then `validate`), and `arb_translate_validate`.
The model is instructed to preserve every placeholder, honor the glossary, and
emit plain text only. After a successful apply, regenerate and commit exactly as
in [Contributing a translation](#contributing-a-translation) (`fvm flutter
gen-l10n`, then `fvm dart format .`).

The glossary (`tools/ci/i18n_glossary.json`) pins the meaning of dance jargon
(`caller`, `set`, `figure`, `program`, `proper`/`improper`, …) and lists proper
nouns to copy verbatim (`Caller's Compendium`, `ContraDB`, license names).
Extend it as new domain terms enter the UI — it improves both assisted and
human translations.

## Known limitation: system date pickers

Flutter's `showDatePicker` derives its **first day of week from the active
locale** and offers no per-call override, so the platform calendar picker — the
app's current date-entry surface — always follows the locale. The app also draws
no week/month grid of its own, so the first-day-of-week preference has **no
consumer yet**. Its plumbing still ships — the value is persisted and exposed
app-wide (via `FirstDayOfWeekScope`, with `FirstDayOfWeekPref.startWeekday` for
consumers) and validated on load — so a future date surface can honor it without
re-plumbing. Until then, rather than surface a live control that changes nothing
observable, the Language & region settings section presents first-day-of-week as
a **disabled "Coming soon" row** (matching the app's convention for not-yet-wired
options). Overriding `showDatePicker`'s first day of week is intentionally avoided
rather than hacked around. When a real consumer lands, flip the row back to a live
control and re-add its option labels to `app_en.arb`.
