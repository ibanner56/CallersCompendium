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
        'And Others.',
        'and others...',
        '(and others)',
        'et. al.',
        'Others,',
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
      expect(peelUnnamedOthers(['Rick Mohr and others.']).fields, [
        'Rick Mohr',
      ]);
      expect(peelUnnamedOthers(['Rick Mohr (and others)']).fields, [
        'Rick Mohr',
      ]);
      expect(peelUnnamedOthers(['Rick Mohr, Others']).fields, ['Rick Mohr']);
      for (final sep in ['with', ';', '/', '+']) {
        expect(peelUnnamedOthers(['Rick Mohr $sep others']).fields, [
          'Rick Mohr',
        ], reason: sep);
      }
      expect(peelUnnamedOthers(['Bob Withothers']).hadOthers, isFalse);
    });

    test('leaves other credits alone', () {
      final names = [
        'Bob Others',
        'Alice and Bob',
        'Sandra Othersen',
        'Sandothers',
        'Sand others',
        'Janet al',
        'Smith-Others',
        '',
        '.',
        '(',
        ')',
        ',',
        null,
      ];
      final peeled = peelUnnamedOthers(names);
      expect(peeled.fields, names);
      expect(peeled.hadOthers, isFalse);
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

    test('the note comes after the other notes and before the source', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'D',
          authors: const ['Rick Mohr', 'And Others'],
          otherNotes: 'Taught at camp',
          from: 'A book',
          fromUsrColumns: true,
        ),
      );
      final notes = mapping.dance.callingNotes;
      final credit = notes.indexOf('Choreography: Rick Mohr and others');
      expect(credit, greaterThan(notes.indexOf('Other notes: Taught at camp')));
      expect(credit, lessThan(notes.indexOf('Source: A book')));
    });

    test('a pasted "by X and others" line credits X with the note', () async {
      final adapter = CallersCompanionTextAdapter();
      const request = ImportRequest(
        payload:
            'Sharks in the Pond\nby Rick Mohr and others\n\nA1\n(8) Circle left',
      );
      final discovered = (await adapter.discover(request)).single;
      final draft = adapter.parse(await adapter.fetch(discovered));
      expect(draft.authorNames, ['Rick Mohr']);
      expect(
        draft.dance.callingNotes,
        contains('Choreography: Rick Mohr and others'),
      );
    });

    test('a dance without the credit gets no note', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(name: 'D', authors: const ['Rick Mohr']),
      );
      expect(mapping.dance.callingNotes, isNot(contains('Choreography')));
    });
  });
}
