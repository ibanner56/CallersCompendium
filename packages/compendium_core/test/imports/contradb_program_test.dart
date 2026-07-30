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

    test('extracts the contributor verbatim from the user: line', () {
      final program = parseContraDbProgram(fixture);
      expect(program.contributor, 'Karl Senseman');
    });

    test('does not pick up the nav sign_up / sign_in user links', () {
      final program = parseContraDbProgram(fixture);
      expect(program.contributor, isNot(anyOf('sign up', 'sign in', 'login')));
    });
  });

  group('parseContraDbProgram (contributor extraction / hardening)', () {
    test('reads the numeric /users link inside the program content', () {
      const html = '''
<div class="programs-show-content">
  <h1>Night</h1>
  <p>user: <strong><a href="/users/67">Karl Senseman</a></strong></p>
</div>
''';
      expect(parseContraDbProgram(html).contributor, 'Karl Senseman');
    });

    test('ignores non-numeric /users links (sign_up / sign_in)', () {
      const html = '''
<ul><li><a href="/users/sign_up">sign up</a></li>
<li><a href="/users/sign_in">login</a></li></ul>
<div class="programs-show-content"><h1>Night</h1></div>
''';
      expect(parseContraDbProgram(html).contributor, isNull);
    });

    test('missing contributor → null (falls back to default caller)', () {
      const html = '<div class="programs-show-content"><h1>Night</h1></div>';
      expect(parseContraDbProgram(html).contributor, isNull);
    });

    test('blank/whitespace contributor → null', () {
      const html = '''
<div class="programs-show-content"><h1>Night</h1>
  <a href="/users/9">   </a></div>
''';
      expect(parseContraDbProgram(html).contributor, isNull);
    });

    test('collapses whitespace/newlines in the contributor name', () {
      const html = '''
<div class="programs-show-content"><h1>Night</h1>
  <a href="/users/9">  Karl\n\t  Senseman  </a></div>
''';
      expect(parseContraDbProgram(html).contributor, 'Karl Senseman');
    });

    test('over-long contributor is rejected as implausible → null', () {
      final huge = 'A' * 500;
      final html =
          '<div class="programs-show-content"><h1>Night</h1>'
          '<a href="/users/9">$huge</a></div>';
      expect(parseContraDbProgram(html).contributor, isNull);
    });

    test('a /users link outside the program content is ignored', () {
      const html = '''
<div class="sidebar"><a href="/users/5">Someone Else</a></div>
<div class="programs-show-content"><h1>Night</h1></div>
''';
      expect(parseContraDbProgram(html).contributor, isNull);
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

  group('parseContraDbProgram (#611 bidi/zero-width sanitization)', () {
    // U+202E RIGHT-TO-LEFT OVERRIDE and U+200B ZERO WIDTH SPACE — the same
    // spoofing characters #444 strips from the dance import paths.
    const rlo = '\u202E';
    const zwsp = '\u200B';

    test('strips bidi/zero-width characters from the program title', () {
      final html =
          '<div class="programs-show-content">'
          '<h1>${rlo}Evil${zwsp}Night</h1></div>';
      expect(parseContraDbProgram(html).title, 'EvilNight');
    });

    test('strips bidi/zero-width characters from a linked dance title', () {
      final html =
          '<div class="activity-breakdown">'
          '<h2 class="activity-breakdown-dance-title">'
          '<a href="/dances/9">${rlo}Spoofed${zwsp}Title</a></h2></div>';
      final activity = parseContraDbProgram(html).activities.single;
      expect(activity.danceId, '9');
      expect(activity.title, 'SpoofedTitle');
    });

    test(
      'strips bidi/zero-width characters from a standalone note activity',
      () {
        final html =
            '<div class="activity-breakdown">'
            '<h2 class="activity-breakdown-text">${rlo}Waltz${zwsp}Break</h2>'
            '</div>';
        final activity = parseContraDbProgram(html).activities.single;
        expect(activity.isDance, isFalse);
        expect(activity.text, 'WaltzBreak');
      },
    );

    test('strips bidi/zero-width characters from an attached note', () {
      final html =
          '<div class="activity-breakdown">'
          '<h2 class="activity-breakdown-dance-title">'
          '<a href="/dances/9">Clean Title</a></h2>'
          '<p class="activity-breakdown-text">${rlo}Called$zwsp weird</p>'
          '</div>';
      final activity = parseContraDbProgram(html).activities.single;
      expect(activity.text, 'Called weird');
    });

    test('a dance heading without a /dances link is sanitized as a note', () {
      final html =
          '<div class="activity-breakdown">'
          '<h2 class="activity-breakdown-dance-title">'
          '${rlo}Orphan${zwsp}Title</h2></div>';
      final activity = parseContraDbProgram(html).activities.single;
      expect(activity.isDance, isFalse);
      expect(activity.text, 'OrphanTitle');
    });

    test('strips bidi/zero-width characters from the contributor', () {
      final html =
          '<div class="programs-show-content"><h1>Night</h1>'
          '<a href="/users/9">${rlo}Karl${zwsp}Senseman</a></div>';
      expect(parseContraDbProgram(html).contributor, 'KarlSenseman');
    });

    test('a clean program is byte-stable (no spurious mangling)', () {
      final program = parseContraDbProgram(fixture);
      expect(program.title, '01.12.18-Harrisburg, Pa');
      expect(program.contributor, 'Karl Senseman');
      expect(program.activities.first.title, 'Courageous Soul');
    });
  });
}
