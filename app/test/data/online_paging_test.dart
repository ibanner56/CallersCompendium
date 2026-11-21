import 'package:compendium_app/src/data/online_paging.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rows with ids [from] to [to], inclusive.
List<OnlineSearchResultRow> _rows(
  int from,
  int to, {
  int? total,
  bool full = false,
}) => [
  for (var id = from; id <= to; id++)
    OnlineSearchResultRow(
      source: OnlineSource.contraDb,
      id: '$id',
      name: 'Dance $id',
      author: '',
      formation: '',
      totalMatching: total,
      mayHaveMore: full,
    ),
];

void main() {
  group('onlineHasMore', () {
    test('with a total: more while fewer rows than that are shown', () {
      final shown = _rows(1, 20, total: 45);
      expect(onlineHasMore(shown, shown), isTrue);
      expect(
        onlineHasMore(_rows(1, 45, total: 45), _rows(41, 45, total: 45)),
        isFalse,
      );
    });

    test('without a total: more only when the page just fetched was full', () {
      final page = _rows(21, 40, full: true);
      expect(onlineHasMore([..._rows(1, 20), ...page], page), isTrue);
      final last = _rows(41, 45);
      expect(onlineHasMore([..._rows(1, 40), ...last], last), isFalse);
    });

    test('nothing shown, or a page of nothing: no more', () {
      expect(onlineHasMore(const [], const []), isFalse);
      expect(onlineHasMore(_rows(1, 3, total: 99), const []), isFalse);
    });
  });

  group('appendOnlinePage', () {
    test('adds the rows not already shown, in order', () {
      final merged = appendOnlinePage(_rows(1, 3), _rows(3, 5));
      expect([for (final row in merged) row.id], ['1', '2', '3', '4', '5']);
    });

    test('a page of repeats adds nothing', () {
      expect(appendOnlinePage(_rows(1, 3), _rows(1, 3)), hasLength(3));
    });
  });
}
