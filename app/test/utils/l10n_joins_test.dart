import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/utils/l10n_joins.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lists and sentences shown on screen are joined the way the UI language
/// joins them, not with ASCII ", " and " " (pre-release audit L10N-06).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ja = lookupAppLocalizations(const Locale('ja'));

  test('sentences join with a space in English and nothing in Japanese', () {
    expect(joinSentences(en, ['One.', 'Two.']), 'One. Two.');
    expect(joinSentences(ja, ['一。', '二。']), '一。二。');
    expect(joinSentences(ja, ['一。']), '一。');
    expect(joinSentences(ja, const []), '');
  });

  test('author names join with the language list separator', () {
    expect(authorsWithYearLabel(en, ['A', 'B'], null), 'A, B');
    final names = authorsWithYearLabel(ja, ['A', 'B'], null)!;
    expect(names, 'A、B');
  });

  test('interpreter names join with the language list separator', () {
    expect(interpretersWithYearLabel(ja, ['A', 'B'], null), contains('A、B'));
  });
}
