import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_failure_labels.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the typed download failure → localized sentence mapping (#1396).
void main() {
  Future<AppLocalizations> load(Locale locale) =>
      AppLocalizations.delegate.load(locale);

  test('every failure has its own non-empty message in every locale', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await load(locale);
      final messages = {
        for (final failure in UpdateDownloadFailure.values)
          failure: updateDownloadFailureMessage(l10n, failure),
      };
      for (final entry in messages.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '$locale ${entry.key} is empty',
        );
      }
      expect(
        messages.values.toSet(),
        hasLength(UpdateDownloadFailure.values.length),
        reason: '$locale maps two failures to the same sentence',
      );
    }
  });

  test('a message that tells the user to use "View release" quotes that '
      "locale's own button label", () async {
    // Every failure except the unusable-destination one points at the manual
    // download button. If a translation drifts from updateBannerViewRelease the
    // user is told to press a button that does not exist.
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await load(locale);
      for (final failure in UpdateDownloadFailure.values) {
        if (failure == UpdateDownloadFailure.destinationUnavailable) continue;
        expect(
          updateDownloadFailureMessage(l10n, failure),
          contains(l10n.updateBannerViewRelease),
          reason:
              '$locale ${failure.name} does not quote the View release '
              'button label',
        );
      }
    }
  });

  test('a non-English locale does not fall back to the English text', () async {
    final en = await load(const Locale('en'));
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == 'en') continue;
      final l10n = await load(locale);
      for (final failure in UpdateDownloadFailure.values) {
        expect(
          updateDownloadFailureMessage(l10n, failure),
          isNot(updateDownloadFailureMessage(en, failure)),
          reason: '$locale ${failure.name} is still English',
        );
      }
      expect(
        l10n.startupIntegrityCheckFailed,
        isNot(en.startupIntegrityCheckFailed),
        reason: '$locale startupIntegrityCheckFailed is still English',
      );
      expect(
        l10n.startupIntegrityCheckIncomplete,
        isNot(en.startupIntegrityCheckIncomplete),
        reason: '$locale startupIntegrityCheckIncomplete is still English',
      );
    }
  });
}
