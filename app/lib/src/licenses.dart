import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A bundled font whose license text ships as a repo asset and should appear in
/// Flutter's `showLicensePage` (reached from Settings ▸ About ▸ View licenses).
class _BundledFontLicense {
  const _BundledFontLicense({required this.packages, required this.assetPath});

  /// The "package" names this license is filed under on the license page. Using
  /// the font-family display name groups each font's text under its own entry.
  final List<String> packages;

  /// Path to the license text asset (declared under `flutter/assets` in
  /// `app/pubspec.yaml`) loaded verbatim via [rootBundle].
  final String assetPath;
}

/// The bundled fonts and their license texts.
///
/// All three are SIL Open Font License 1.1. Notably the bundled **Roboto**
/// (`Roboto-VariableFont.ttf`, v3.015 from googlefonts/roboto-classic) ships
/// under the OFL — its own `name` table reads "…licensed under the SIL Open
/// Font License, Version 1.1…" — *not* Apache-2.0, so there is no Apache NOTICE
/// to convey; `Roboto-OFL.txt` is the corresponding license.
const List<_BundledFontLicense> _bundledFontLicenses = [
  _BundledFontLicense(
    packages: ['Fraunces (OFL 1.1)'],
    assetPath: 'assets/fonts/Fraunces-OFL.txt',
  ),
  _BundledFontLicense(
    packages: ['Atkinson Hyperlegible (OFL 1.1)'],
    assetPath: 'assets/fonts/AtkinsonHyperlegible-OFL.txt',
  ),
  _BundledFontLicense(
    packages: ['Roboto (OFL 1.1)'],
    assetPath: 'assets/fonts/Roboto-OFL.txt',
  ),
];

/// Guards [registerBundledFontLicenses] so the license stream is added to the
/// global [LicenseRegistry] at most once, even if called from both `main` and a
/// test in the same isolate.
bool _registered = false;

/// Registers the bundled font license texts with [LicenseRegistry] so they are
/// listed by Flutter's `showLicensePage`. Call once during app bootstrap (and
/// in any test that exercises the license page). Idempotent.
///
/// The texts are loaded lazily from bundled assets when the license page first
/// enumerates licenses, keeping the assets as the single source of truth rather
/// than duplicating ~90 lines of license text into Dart source.
void registerBundledFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final font in _bundledFontLicenses) {
      final text = await rootBundle.loadString(font.assetPath);
      yield LicenseEntryWithLineBreaks(font.packages, text);
    }
  });
}

/// Test-only reset of the once-guard so a test can re-register against a fresh
/// [LicenseRegistry] (which tests reset between cases).
@visibleForTesting
void resetBundledFontLicensesForTest() {
  _registered = false;
}
