// What Fill makes of a placeholder's slot once a dance is picked (#2338).
import 'package:compendium_app/src/widgets/placeholder_fill.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final performed = DateTime.utc(2026, 3, 1);
  final placeholder = ProgramSlot(
    id: 's1',
    position: 2,
    text: 'Easy family opener',
    placeholderSearchId: 'search-1',
    isAlt: true,
    guestCaller: 'Robin',
    walkthroughMinutes: 3,
    danceMinutes: 9,
    performedAt: performed,
  );

  test('an unfilled placeholder becomes a dance slot that keeps the rest', () {
    final filled = filledPlaceholderSlot(placeholder, 'd2')!;
    expect(filled.danceId, 'd2');
    expect(filled.text, isNull);
    expect(filled.placeholderSearchId, isNull);
    expect(
      (
        filled.id,
        filled.position,
        filled.isAlt,
        filled.guestCaller,
        filled.walkthroughMinutes,
        filled.danceMinutes,
        filled.performedAt,
      ),
      ('s1', 2, true, 'Robin', 3, 9, performed),
    );
  });

  test(
    'a slot that became a dance while the picker was open is left alone',
    () {
      expect(
        filledPlaceholderSlot(placeholder.copyWith(danceId: 'd1'), 'd2'),
        isNull,
      );
    },
  );

  test('a slot that became a plain note (a break, or its search cleared) '
      'while the picker was open is left alone', () {
    expect(
      filledPlaceholderSlot(placeholder.copyWith(text: 'Break'), 'd2'),
      isNull,
    );
    expect(
      filledPlaceholderSlot(
        placeholder.copyWith(clearPlaceholderSearchId: true),
        'd2',
      ),
      isNull,
    );
  });
}
