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
/// All five are SIL Open Font License 1.1. Notably the bundled **Roboto**
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
///
/// `NotoSansJP-Regular-Subset.ttf` is likewise a `fonttools subset` instance
/// (Hiragana, Katakana, CJK punctuation/fullwidth forms and the JIS X 0208
/// level 1 kanji) of Google's **Noto Sans JP** (OFL 1.1), bundled only as the
/// PDF export's CJK fallback font (`program_pdf.dart`).
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
  _BundledLicense(
    packages: ['Noto Sans JP (OFL 1.1)'],
    assetPath: 'assets/fonts/NotoSansJP-OFL.txt',
  ),
];

/// Code and data the app takes from other projects, whose license requires (or
/// whose author was promised) an attribution that travels with the copy.
///
/// `fmptools` (MIT, © 2020 Evan Miller) is what `fmp_reader.dart` and `scsu.dart`
/// in `compendium_core` are ported from (#1392). The EFF long wordlist (CC BY
/// 3.0 US) is compiled into `compendium_core`'s `eff_long_wordlist.dart` and
/// drives generated sync IDs. ContraDB (AGPL-3.0) is the source of the figure
/// sentence structure and modifier phrasing the dialect renderer follows.
/// `THIRD_PARTY_NOTICES.md` at the repo root carries the same texts (and the
/// ported/copied source files carry them in their heads);
/// `test/licenses_notice_test.dart` keeps the copies identical.
const List<_BundledLicense> _bundledCodeLicenses = [
  _BundledLicense(
    packages: ['fmptools (MIT)'],
    assetPath: 'assets/licenses/fmptools-LICENSE.txt',
  ),
  _BundledLicense(
    packages: ['EFF Long Wordlist (CC BY 3.0 US)'],
    assetPath: 'assets/licenses/eff-wordlist-NOTICE.txt',
  ),
  _BundledLicense(
    packages: ['ContraDB (AGPL-3.0)'],
    assetPath: 'assets/licenses/contradb-NOTICE.txt',
  ),
];

/// The pdfium the `printing` plugin bundles into the Linux and Windows builds:
/// a prebuilt binary from `bblanchon/pdfium-binaries`, pinned and
/// hash-checked by `packaging/pdfium/pdfium.cmake`. Not a Dart package, so
/// Flutter's own package licences never list it. The asset is the `LICENSE`
/// from that release's archive: PDFium's BSD-3-Clause and Apache-2.0 texts
/// followed by the notices of the libraries built into it (FreeType,
/// libjpeg-turbo, lcms, OpenJPEG, zlib, libpng, ICU and others).
/// `tools/release/test_pdfium_pin.py` checks the asset against the pinned
/// release.
///
/// Registered only where pdfium ships: on Android, iOS and macOS the plugin
/// prints through the platform's own PDF support, so listing pdfium there
/// would credit a component those builds do not contain.
const _BundledLicense _pdfiumLicense = _BundledLicense(
  packages: ['PDFium (BSD-3-Clause, with bundled third-party notices)'],
  assetPath: 'assets/licenses/pdfium-LICENSE.txt',
);

/// Whether the running build ships pdfium (see [_pdfiumLicense]).
bool get _shipsPdfium =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows;

/// Guards [registerBundledLicenses] so the license stream is added to the
/// global [LicenseRegistry] at most once, even if called from both `main` and a
/// test in the same isolate.
bool _registered = false;

/// Registers the bundled font, ported-code and native-library license texts
/// with [LicenseRegistry] so they are listed by Flutter's `showLicensePage`.
/// Call once during app bootstrap (and in any test that exercises the license
/// page). Idempotent.
///
/// The texts are loaded lazily from bundled assets when the license page first
/// enumerates licenses, keeping the assets as the single source of truth rather
/// than duplicating license text into Dart source.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final license in [
      ..._bundledFontLicenses,
      ..._bundledCodeLicenses,
      if (_shipsPdfium) _pdfiumLicense,
    ]) {
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
