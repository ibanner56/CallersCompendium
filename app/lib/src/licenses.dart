import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A bundled license text (a font's, or a ported library's) that ships as a
/// repo asset and should appear in Flutter's `showLicensePage` (reached from
/// Settings ▸ About ▸ View licenses).
class _BundledLicense {
  const _BundledLicense({required this.packages, required this.assetPath});

  /// The "package" names this license is filed under on the license page. Using
  /// the font-family display name groups each font's text under its own entry.
  final List<String> packages;

  /// Path to the license text asset (declared under `flutter/assets` in
  /// `app/pubspec.yaml`) loaded verbatim via [rootBundle].
  final String assetPath;
}

/// The bundled fonts and their license texts.
///
/// All four are SIL Open Font License 1.1. Notably the bundled **Roboto**
/// (`Roboto-VariableFont.ttf`, v3.015 from googlefonts/roboto-classic) ships
/// under the OFL — its own `name` table reads "…licensed under the SIL Open
/// Font License, Version 1.1…" — *not* Apache-2.0, so there is no Apache NOTICE
/// to convey; `Roboto-OFL.txt` is the corresponding license.
///
/// `ProgramMatrixMarkers-Regular.ttf` is a hand-subsetted (`fonttools
/// subset`) instance of Google's **Noto Sans Symbols 2** (also OFL 1.1),
/// trimmed to only the three glyphs (★ U+2605, ▸ U+25B8, ✓ U+2713) the
/// bundled Roboto lacks — see `program_matrix_pdf.dart` (#633). It isn't a
/// reading/UI font (not listed in the About section's typography credits
/// alongside Fraunces/Roboto), but its license text is still bundled/
/// registered here since it ships as a font asset under the OFL.
const List<_BundledLicense> _bundledFontLicenses = [
  _BundledLicense(
    packages: ['Fraunces (OFL 1.1)'],
    assetPath: 'assets/fonts/Fraunces-OFL.txt',
  ),
  _BundledLicense(
    packages: ['Atkinson Hyperlegible (OFL 1.1)'],
    assetPath: 'assets/fonts/AtkinsonHyperlegible-OFL.txt',
  ),
  _BundledLicense(
    packages: ['Roboto (OFL 1.1)'],
    assetPath: 'assets/fonts/Roboto-OFL.txt',
  ),
  _BundledLicense(
    packages: ['Noto Sans Symbols 2 (OFL 1.1)'],
    assetPath: 'assets/fonts/NotoSansSymbols2-OFL.txt',
  ),
];

/// Code the app ports from other projects, whose license requires its notice to
/// travel with the port.
///
/// `fmptools` (MIT, © 2020 Evan Miller) is what `fmp_reader.dart` and `scsu.dart`
/// in `compendium_core` are ported from (#1392). `THIRD_PARTY_NOTICES.md` at the
/// repo root and the head of each of those two files carry the same text;
/// `test/licenses_notice_test.dart` keeps the copies identical.
const List<_BundledLicense> _bundledCodeLicenses = [
  _BundledLicense(
    packages: ['fmptools (MIT)'],
    assetPath: 'assets/licenses/fmptools-LICENSE.txt',
  ),
];

/// Guards [registerBundledLicenses] so the license stream is added to the
/// global [LicenseRegistry] at most once, even if called from both `main` and a
/// test in the same isolate.
bool _registered = false;

/// Registers the bundled font and ported-code license texts with
/// [LicenseRegistry] so they are listed by Flutter's `showLicensePage`. Call once during app bootstrap (and
/// in any test that exercises the license page). Idempotent.
///
/// The texts are loaded lazily from bundled assets when the license page first
/// enumerates licenses, keeping the assets as the single source of truth rather
/// than duplicating ~90 lines of license text into Dart source.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final license in [..._bundledFontLicenses, ..._bundledCodeLicenses]) {
      final text = await rootBundle.loadString(license.assetPath);
      yield LicenseEntryWithLineBreaks(license.packages, text);
    }
  });
}

/// Test-only reset of the once-guard so a test can re-register against a fresh
/// [LicenseRegistry] (which tests reset between cases).
@visibleForTesting
void resetBundledLicensesForTest() {
  _registered = false;
}
