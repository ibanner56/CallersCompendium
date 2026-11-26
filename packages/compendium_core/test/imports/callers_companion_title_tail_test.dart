import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/imports/callers_companion_title_tail.dart';
import 'package:test/test.dart';

/// A date a Caller's Companion library pads onto the end of a dance's Name
/// ("Jack's Maggot   1702"). The shapes below are the ones a real English
/// library uses: a plain year, two years, a doubtful or approximate year, and
/// a year followed by the tune's key and meter.
void main() {
  group('splitCcNameTail', () {
    test('takes a year padded after two or more spaces off the title', () {
      expect(splitCcNameTail('Jack’s Maggot   1702'), (
        title: 'Jack’s Maggot',
        tail: '1702',
      ));
      expect(splitCcNameTail('Hole in the Wall  1701'), (
        title: 'Hole in the Wall',
        tail: '1701',
      ));
      expect(splitCcNameTail('Foo\t1702'), (title: 'Foo', tail: '1702'));
    });

    test('keeps everything after the year in the tail', () {
      expect(splitCcNameTail('Gypsy Round, The      1979    Am 3/4     '), (
        title: 'Gypsy Round, The',
        tail: '1979    Am 3/4',
      ));
      expect(splitCcNameTail('Bloomsbury Market     1703/2009'), (
        title: 'Bloomsbury Market',
        tail: '1703/2009',
      ));
      expect(splitCcNameTail('Physical Snob, The   Circa 1800'), (
        title: 'Physical Snob, The',
        tail: 'Circa 1800',
      ));
    });

    test('leaves a title whose number follows one space, or no year', () {
      for (final name in [
        'Trip to the Manors 2000',
        'Dublin Bay (We’ll Wed and We’ll Bed) 1710',
        'Domino 5',
        'Belle of Amherst, The        ',
        'Two  Words',
        'Fourteen  12345',
      ]) {
        expect(splitCcNameTail(name), (title: name.trim(), tail: null));
      }
    });

    test('never leaves an empty title', () {
      expect(splitCcNameTail('   1702'), (title: '1702', tail: null));
    });
  });

  test('ccNameTailPlainYear reads only a tail that is one plain year', () {
    expect(ccNameTailPlainYear('1702'), 1702);
    for (final tail in [
      '1703/2009',
      '2024?',
      'Circa 1800',
      '1750ish',
      '1979    Am 3/4',
    ]) {
      expect(ccNameTailPlainYear(tail), isNull, reason: tail);
    }
  });

  test('ccNameTailAfterDate gives what follows the date', () {
    expect(ccNameTailAfterDate('1979    Am 3/4'), 'Am 3/4');
    expect(ccNameTailAfterDate('1971/86?'), '');
    expect(ccNameTailAfterDate('Circa 1800'), '');
    expect(
      ccNameTailAfterDate('2015             e modal   6/8'),
      'e modal   6/8',
    );
  });

  test('ccDanceTitleOf fronts the article of the title without its tail', () {
    expect(ccDanceTitleOf('Fandango, The              1774'), 'The Fandango');
  });

  group('mapCallersCompanionDance', () {
    test('a plain year becomes the composed date and leaves the title', () {
      final dance = mapCallersCompanionDance(
        CcDanceRecord(name: 'Fandango, The              1774'),
      ).dance;
      expect(dance.title, 'The Fandango');
      expect(dance.composedOn, PartialDate(1774));
      expect(dance.callingNotes, isNot(contains('1774')));
    });

    test('a tail that says more is kept in the notes, with no date', () {
      for (final (name, tail) in [
        ('Bloomsbury Market     1703/2009', '1703/2009'),
        ('A Night to Remember  2024?     ', '2024?'),
        ('Physical Snob, The   Circa 1800', 'Circa 1800'),
        ('Tom Jones     1750ish', '1750ish'),
      ]) {
        final dance = mapCallersCompanionDance(CcDanceRecord(name: name)).dance;
        expect(dance.title, isNot(contains(tail)), reason: name);
        expect(dance.composedOn, isNull, reason: name);
        expect(
          dance.callingNotes,
          contains('From the title: $tail'),
          reason: name,
        );
      }
    });

    test('DateComposed wins; a title year that differs stays in the notes', () {
      final same = mapCallersCompanionDance(
        CcDanceRecord(name: 'Well Hall    1679', composed: '1679'),
      ).dance;
      expect(same.composedOn, PartialDate(1679));
      expect(same.callingNotes, isNot(contains('From the title')));

      final differs = mapCallersCompanionDance(
        CcDanceRecord(name: 'Well Hall    1679', composed: '1680'),
      ).dance;
      expect(differs.title, 'Well Hall');
      expect(differs.composedOn, PartialDate(1680));
      expect(differs.callingNotes, contains('From the title: 1679'));
    });

    test('an English dance takes the key and meter its Music does not '
        'state from the tail', () {
      final dance = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'Gypsy Round, The      1979    Am 3/4',
          type: 'Contra',
        ),
        englishDances: true,
      ).dance;
      expect(dance.title, 'The Gypsy Round');
      expect(dance.meter, '3/4');
      expect(dance.musicalKey, 'Am');
      expect(dance.composedOn, isNull);
      expect(dance.callingNotes, contains('From the title: 1979    Am 3/4'));

      final fromMusic = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'Gypsy Round, The      1979    Am 3/4',
          type: 'Contra',
          music: 'Key: G, Meter: 6/8',
        ),
        englishDances: true,
      ).dance;
      expect(fromMusic.meter, '6/8');
      expect(fromMusic.musicalKey, 'G');
    });

    test('a contra dance does not take a meter from the tail', () {
      final dance = mapCallersCompanionDance(
        CcDanceRecord(name: 'Reel Time    1999    G 2/2', type: 'Contra'),
      ).dance;
      expect(dance.meter, '');
      expect(dance.title, 'Reel Time');
    });
  });

  test('a text-export discovery label agrees with the drafted title', () async {
    final text = CallersCompanionTextAdapter();
    final records = await text.discover(
      const ImportRequest(payload: 'Fandango, The     1774\nType: Contra\n'),
    );
    expect(records.single.label, 'The Fandango');
    final draft = text.parse(await text.fetch(records.single));
    expect(draft.dance.title, records.single.label);
  });
}
