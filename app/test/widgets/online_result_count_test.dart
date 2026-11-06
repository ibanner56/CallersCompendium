import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/widgets/online_result_count.dart';

OnlineSearchResultRow _row(
  int id, {
  bool mayHaveMore = false,
  int? total,
  bool partly = false,
}) => OnlineSearchResultRow(
  source: OnlineSource.contraDb,
  id: '$id',
  name: 'Dance $id',
  author: '',
  formation: '',
  mayHaveMore: mayHaveMore,
  totalMatching: total,
  advancedPartlyApplied: partly,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  String label(List<OnlineSearchResultRow> rows, {bool? hasMore}) =>
      onlineResultCountLabel(
        l10n,
        rows,
        hasMore: hasMore ?? rows.any((row) => row.mayHaveMore),
      );

  test('a total larger than what is shown says "of"', () {
    expect(
      label([_row(1, total: 143), _row(2, total: 143)]),
      'Showing 2 of 143 online results. Narrow your search to see the rest.',
    );
  });

  test('a total that equals what is shown is the plain count, even on a '
      'full page', () {
    expect(label([_row(1, total: 1, mayHaveMore: true)]), '1 online result');
    expect(
      label([
        for (var i = 1; i <= 20; i++) _row(i, total: 20, mayHaveMore: true),
      ]),
      '20 online results',
    );
  });

  test('no total and a full page: the "may be more" form', () {
    expect(
      label([_row(1, mayHaveMore: true), _row(2, mayHaveMore: true)]),
      'Showing 2 online results. There may be more: narrow your search to see '
      'the rest.',
    );
  });

  test('no total and the last page loaded: the plain count', () {
    expect(
      label([_row(1, mayHaveMore: true), _row(2)], hasMore: false),
      '2 online results',
      reason: 'an earlier full page must not keep the "may be more" form',
    );
  });

  test('nothing shown: the plain count, whatever an earlier search left', () {
    expect(label(const [], hasMore: true), '0 online results');
  });

  test('no total and no full page: the plain count', () {
    expect(label([_row(1), _row(2)]), '2 online results');
    expect(label(const []), '0 online results');
  });

  test('the left-out note follows whichever count form applies', () {
    const note =
        "Some Advanced conditions don't exist on ContraDB and were "
        'left out.';
    expect(label([_row(1, partly: true)]), '1 online result · $note');
    expect(
      label([_row(1, total: 5, partly: true)]),
      'Showing 1 of 5 online results. Narrow your search to see the rest. '
      '· $note',
    );
  });
}
