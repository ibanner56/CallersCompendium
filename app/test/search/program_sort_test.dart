import 'package:compendium_app/src/search/program_sort.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProgramSort.defaultDirection', () {
    test(
      'title and eventDate default ascending; recentlyUpdated descending',
      () {
        expect(ProgramSort.title.defaultDirection, SortDirection.ascending);
        expect(ProgramSort.eventDate.defaultDirection, SortDirection.ascending);
        expect(
          ProgramSort.recentlyUpdated.defaultDirection,
          SortDirection.descending,
        );
      },
    );
  });

  group('programSortFromName', () {
    test('round-trips every member via .name', () {
      for (final sort in ProgramSort.values) {
        expect(programSortFromName(sort.name), sort);
      }
    });

    test('returns null for null, non-strings, and unknown names', () {
      expect(programSortFromName(null), isNull);
      expect(programSortFromName(3), isNull);
      expect(programSortFromName('not-a-sort'), isNull);
    });
  });
}
