import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// [peelUnnamedOthers] and the Caller's Companion mapping's "and others" note
/// (#1976 item 2).
void main() {
  group('peelUnnamedOthers', () {
    test('drops a field that is only an unnamed-others credit', () {
      for (final credit in [
        'And Others',
        '& others',
        'et al.',
        'Et Al',
        'Others',
        '  and   OTHERS ',
      ]) {
        final peeled = peelUnnamedOthers(['Rick Mohr', credit]);
        expect(peeled.fields, ['Rick Mohr'], reason: credit);
        expect(peeled.hadOthers, isTrue, reason: credit);
      }
    });

    test('keeps the names before a trailing credit', () {
      expect(peelUnnamedOthers(['Rick Mohr and others']).fields, ['Rick Mohr']);
      expect(peelUnnamedOthers(['Rick Mohr, et al.']).fields, ['Rick Mohr']);
      expect(peelUnnamedOthers(['Rick Mohr & Others']).fields, ['Rick Mohr']);
    });

    test('leaves other credits alone', () {
      final peeled = peelUnnamedOthers([
        'Bob Others',
        'Alice and Bob',
        'Sandra Othersen',
        null,
      ]);
      expect(peeled.fields, [
        'Bob Others',
        'Alice and Bob',
        'Sandra Othersen',
        null,
      ]);
      expect(peeled.hadOthers, isFalse);
    });

    test('a long run of commas before the credit is cheap', () {
      final field = '${',' * 100000}and others';
      final watch = Stopwatch()..start();
      expect(peelUnnamedOthers([field]).fields, ['']);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('mapCallersCompanionDance', () {
    test('"And Others" is a note, not a choreographer', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'Sharks in the Pond',
          authors: const ['Rick Mohr', 'And Others'],
          fromUsrColumns: true,
        ),
      );
      expect(mapping.authorNames, ['Rick Mohr']);
      expect(
        mapping.dance.callingNotes,
        contains('Choreography: Rick Mohr and others'),
      );
    });

    test('names every credited author in the note', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'D',
          authors: const ['Alice Smith and Bob Jones', 'and others'],
        ),
      );
      expect(mapping.authorNames, ['Alice Smith', 'Bob Jones']);
      expect(
        mapping.dance.callingNotes,
        contains('Choreography: Alice Smith, Bob Jones and others'),
      );
    });

    test('with nobody named, the note says so and no author is made', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(name: 'D', authors: const ['And Others']),
      );
      expect(mapping.authorNames, isEmpty);
      expect(
        mapping.dance.callingNotes,
        contains('Choreography: others, not named'),
      );
    });

    test('a dance without the credit gets no note', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(name: 'D', authors: const ['Rick Mohr']),
      );
      expect(mapping.dance.callingNotes ?? '', isNot(contains('Choreography')));
    });
  });
}
