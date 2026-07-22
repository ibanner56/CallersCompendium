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

## Known limitation: system date pickers

Flutter's `showDatePicker` derives its **first day of week from the active
locale** and offers no per-call override, so the platform calendar picker — the
app's current date-entry surface — always follows the locale. The
first-day-of-week preference is therefore persisted and exposed app-wide (via
`FirstDayOfWeekScope`, with `FirstDayOfWeekPref.startWeekday` for consumers) so
that date surfaces the app draws itself can honor it as they are added; today
its visible effect is limited because date entry goes through the system picker.
Overriding `showDatePicker`'s first day of week is intentionally avoided rather
than hacked around. This is surfaced to users as a note in the Language & region
settings section and is intentional, not a bug.
