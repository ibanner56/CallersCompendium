import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The picker's search field shares one row with the "Search in" menu, leaving
/// it about 150 logical pixels for its label at a 390-point phone. A label
/// longer than this is cut short with an ellipsis ("Find a dance to a…").
const _maxLabelLength = 17;

void main() {
  test(
    'the picker search label is short enough for a phone-width field',
    () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(
          l10n.collectionPickerSearchLabel.length,
          lessThanOrEqualTo(_maxLabelLength),
          reason: '$locale: "${l10n.collectionPickerSearchLabel}"',
        );
      }
    },
  );
}
