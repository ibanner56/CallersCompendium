import 'dart:io';

import 'package:compendium_core/src/imports/contradb_program.dart';
import 'package:test/test.dart';

/// Parses a **real, verbatim** ContraDB program page captured from
/// `contradb.com/programs/33` (see `support/contradb/programs_33.html`). The
/// fixture is fetched HTML, not hand-built, so the parser is verified against
/// the true live DOM (fidelity rule). No network access at test time.
void main() {
  final fixture = File(
    'test/imports/support/contradb/programs_33.html',
  ).readAsStringSync();

  group('parseContraDbProgram (real /programs/33 fixture)', () {
    test('extracts the program title from the page h1', () {
      final program = parseContraDbProgram(fixture);
      expect(program.title, '01.12.18-Harrisburg, Pa');
    });

    test('preserves activity order: dances and notes interleaved', () {
      final program = parseContraDbProgram(fixture);

      // 9 linked dances + 2 standalone "Waltz" notes = 11 activities, in order.
      expect(program.activities.length, 11);

      final dances = program.activities.where((a) => a.isDance).toList();
      expect(dances.length, 9);
      final notes = program.activities.where((a) => !a.isDance).toList();
      expect(notes.length, 2);
      expect(notes.every((n) => n.text == 'Waltz'), isTrue);

      // The standalone Waltz notes are the 6th and 11th activities (index 5, 10).
      expect(program.activities[5].isDance, isFalse);
      expect(program.activities[5].text, 'Waltz');
      expect(program.activities[10].isDance, isFalse);
      expect(program.activities[10].text, 'Waltz');
    });

    test('first activity links the correct dance id + verbatim title', () {
      final program = parseContraDbProgram(fixture);
      final first = program.activities.first;
      expect(first.isDance, isTrue);
      expect(first.danceId, '185');
      expect(first.title, 'Courageous Soul');
      expect(first.text, isNull);
    });

    test('a linked dance carries its attached note verbatim', () {
      final program = parseContraDbProgram(fixture);
      // Activity 7 on the program (index 6) is a dance with an attached note.
      final withNote = program.activities.firstWhere(
        (a) => a.isDance && a.text != null,
      );
      expect(withNote.danceId, isNotEmpty);
      expect(withNote.title, isNotEmpty);
      expect(
        withNote.text,
        'Called as ladles:"pirates" - gentlespoons:"wenches"',
      );
    });

    test('every linked dance has a numeric id and non-empty title', () {
      final program = parseContraDbProgram(fixture);
      for (final dance in program.activities.where((a) => a.isDance)) {
        expect(int.tryParse(dance.danceId!), isNotNull);
        expect(dance.title, isNotEmpty);
      }
    });
  });

  group('parseContraDbProgram (robustness / parse-never-throws)', () {
    test('empty string → empty program, no throw', () {
      final program = parseContraDbProgram('');
      expect(program.title, isEmpty);
      expect(program.activities, isEmpty);
    });

    test('foreign HTML with no program markup → empty activities', () {
      final program = parseContraDbProgram(
        '<html><body><p>not a program</p></body></html>',
      );
      expect(program.activities, isEmpty);
    });

    test('dance heading without a /dances link → kept as a verbatim note', () {
      const html = '''
<div class="programs-show-content"><h1>Mini</h1></div>
<div class="activity-breakdown">
  <h2 class="activity-breakdown-dance-title">Orphan Title</h2>
</div>
''';
      final program = parseContraDbProgram(html);
      expect(program.activities, hasLength(1));
      expect(program.activities.single.isDance, isFalse);
      expect(program.activities.single.text, 'Orphan Title');
    });

    test('empty activity (~ ~ ~) is dropped', () {
      const html = '''
<div class="programs-show-content"><h1>Mini</h1></div>
<div class="activity-breakdown">
  <h2 class="activity-breakdown-empty-activity">~ ~ ~</h2>
</div>
<div class="activity-breakdown">
  <h2 class="activity-breakdown-dance-title"><a href="/dances/42">Keeper</a></h2>
</div>
''';
      final program = parseContraDbProgram(html);
      expect(program.activities, hasLength(1));
      expect(program.activities.single.danceId, '42');
    });

    test('parses an absolute /dances URL href', () {
      const html = '''
<div class="activity-breakdown">
  <h2 class="activity-breakdown-dance-title"><a href="https://contradb.com/dances/7">Abs</a></h2>
</div>
''';
      final program = parseContraDbProgram(html);
      expect(program.activities.single.danceId, '7');
    });
  });
}
