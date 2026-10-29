import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: Caller's Companion's "Neighbor Roll Away" is a roll away with your
/// neighbor, and a box circulate's beats say whether it carries a balance (8
/// beats: a balance; 4: none).
void main() {
  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 4),
    'free-text entry': (String line) => parseFreeTextFigureEntry(line),
    // ContraDB's dialect claims "Larks roll away" first on both paths above;
    // the Caller's Box front end reaches the shared recognizer.
    'Caller\'s Box': (String line) => [
      parseFigureLine(line, beats: 4, frontEnd: tcbFigureFrontEnd)!,
    ],
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      Figure single(String line) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        return figures.single;
      }

      group('roll away', () {
        test('a relationship before it is whom the roll away is with', () {
          for (final (line, whom) in [
            ('Neighbor Roll Away with half sashay', 'neighbors'),
            ('Partner roll away', 'partners'),
            ('Neighbors roll away', 'neighbors'),
            ('Partners roll away', 'partners'),
            ('Shadow roll away', 'shadows'),
            ('roll away neighbors', 'neighbors'),
          ]) {
            final f = single(line);
            expect(f.move, 'roll_away', reason: line);
            expect(f.params['whom'], whom, reason: line);
            expect(f.params.containsKey('who'), isFalse, reason: line);
            expect(f.assumedSubject, isTrue, reason: line);
          }
        });

        test('"rollaway" and "w/ half sashay" read', () {
          final f = single('Neighbor rollaway w/ half sashay');
          expect(f.move, 'roll_away');
          expect(f.params['whom'], 'neighbors');
          expect(f.params['halfSashay'], isTrue);
        });

        test('a role or couple before it is still who rolls', () {
          final larks = single('Larks roll away');
          expect(larks.params['who'], 'role1s');
          expect(larks.params.containsKey('whom'), isFalse);

          final ones = single('Ones roll away neighbors');
          expect(ones.params['who'], 'ones');
          expect(ones.params['whom'], 'neighbors');
        });

        test('a note naming the role that steps states the roller', () {
          // Caller's Companion's wording of the Caller's Box "W roll R, M
          // side-step L" note (maintainer decision, #1975): the role that
          // does not roll rolls the other away.
          for (final (line, who) in [
            ('Neighbor roll away (Robins roll R, Larks step L)', 'role1s'),
            (
              'Neighbor roll away (Larks roll Right, Robins step Left)',
              'role2s',
            ),
            ('Neighbor roll away (Robins Roll R, Larks Step L)', 'role1s'),
          ]) {
            final f = single(line);
            expect(f.params['who'], who, reason: line);
            expect(f.params['whom'], 'neighbors', reason: line);
            expect(f.assumedSubject, isFalse, reason: line);
          }
        });

        test('a Caller\'s Box note names the roller with any relationship', () {
          final f = single('Shadow roll away (W roll R, M side-step L)');
          expect(f.params['who'], 'role1s');
          expect(f.params['whom'], 'shadows');
          expect(f.assumedSubject, isFalse);
        });

        test('any other note leaves the roller assumed', () {
          for (final line in [
            'Neighbor roll away (Robins roll R, Larks roll L)',
            'Neighbor roll away (Robins roll R, Robins step L)',
            'Neighbor roll away (Robins roll L-to-R)',
          ]) {
            final f = single(line);
            expect(f.params.containsKey('who'), isFalse, reason: line);
            expect(f.assumedSubject, isTrue, reason: line);
          }
        });

        test('a relationship with a dancer after it keeps both slots', () {
          final f = single('Neighbors roll away partners');
          expect(f.params['who'], 'neighbors');
          expect(f.params['whom'], 'partners');
        });
      });
    });
  }

  group('a leading Caller\'s Box bracket', () {
    Figure tcb(String line) =>
        parseFigureLine(line, beats: 4, frontEnd: tcbFigureFrontEnd)!;

    test('names the roller, which is then not assumed', () {
      final f = tcb('[Larks] Neighbor roll away');
      expect(f.params['who'], 'role1s');
      expect(f.params['whom'], 'neighbors');
      expect(f.assumedSubject, isFalse);
    });

    test('states the subject of any move it fills', () {
      final f = tcb('[Ones] Box circulate');
      expect(f.params['who'], 'ones');
      expect(f.assumedSubject, isFalse);
    });

    test('does not overrule the roller a note names', () {
      final f = tcb('[Women] Neighbor roll away (W roll R, M side-step L)');
      expect(f.params['who'], 'role1s');
      expect(f.params['whom'], 'neighbors');
      expect(f.assumedSubject, isFalse);
      // The bracket stays as the note it was before #1975.
      expect(f.note, 'role2s; role2s roll right, role1s side-step left');
    });

    test('naming no dancer set is a note when a note names the roller', () {
      final f = tcb('[All four] Neighbor roll away (W roll R, M side-step L)');
      expect(f.move, 'roll_away');
      expect(f.params['who'], 'role1s');
      expect(f.note, contains('All four'));
    });

    test('naming no dancer set leaves the line custom', () {
      // The roller would be assumed beside a subject the line states.
      expect(tcb('[All four] Neighbor roll away').isCustom, isTrue);
    });
  });

  // Only an importer reads the balance from beats, once a line's beats are
  // settled and the box circulate is the whole line. Free-text entry has no
  // beats.
  group('box circulate', () {
    final importers = {
      "Caller's Companion": _ccFigures,
      "Caller's Box": _tcbFigures,
      're-parse': (String line) async => reparseImportGapFigures([
        customFigure(
          _lineText(line),
          beats: _lineBeats(line),
          origin: CustomOrigin.importGap,
        ),
      ]).figures,
    };
    for (final MapEntry(key: path, value: read) in importers.entries) {
      test('$path: 8 beats is a balance and circulate', () async {
        final f = (await read('(8) Box circulate')).single;
        expect(f.move, 'box_circulate');
        expect(f.params['balance'], isTrue);
      });

      test('$path: 4 beats is no balance', () async {
        // Explicitly false: the renderer shows a box circulate's balance when
        // the flag is absent.
        final f = (await read('(4) Box circulate')).single;
        expect(f.move, 'box_circulate');
        expect(f.params['balance'], isFalse);
      });

      test('$path: any other count says nothing', () async {
        for (final line in ['(6) Box circulate', '(16) Box circulate']) {
          final f = (await read(line)).single;
          expect(f.move, 'box_circulate', reason: line);
          expect(f.params.containsKey('balance'), isFalse, reason: line);
        }
      });

      test('$path: another move in 8 beats gets no balance', () async {
        final f = (await read('(8) Box the gnat')).single;
        expect(f.move, 'box_the_gnat');
        expect(f.params.containsKey('balance'), isFalse);
      });
    }

    test('a split line\'s beats are not the box circulate\'s own', () async {
      for (final figures in [
        await _ccFigures('(8) Box circulate; Neighbor swing'),
        await _ccFigures('(4,4) Box circulate; Neighbor swing'),
        await _tcbFigures('(8) Box circulate; Neighbor swing'),
      ]) {
        expect(figures.map((f) => f.move), ['box_circulate', 'swing']);
        expect(figures.first.params.containsKey('balance'), isFalse);
      }
    });

    test('a ContraDB box circulate keeps its own reading of the balance', () {
      final f = parseFigureLine(
        'box circulate - larks cross while robins loop right',
        beats: 8,
        frontEnd: contraDbHtmlFigureFrontEnd,
      )!;
      expect(f.move, 'box_circulate');
      expect(f.params.containsKey('balance'), isFalse);
    });
  });
}

final RegExp _beatsPrefix = RegExp(r'^\((\d+)\)\s*');

int _lineBeats(String line) =>
    int.parse(_beatsPrefix.firstMatch(line)!.group(1)!);

String _lineText(String line) => line.replaceFirst(_beatsPrefix, '');

/// The figures a Caller's Companion text export imports for one body line.
Future<List<Figure>> _ccFigures(String line) async {
  final adapter = CallersCompanionTextAdapter();
  final discovered = await adapter.discover(
    ImportRequest(payload: 'Test Dance\nType: Contra\n\nA1   $line\n'),
  );
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return _figures(draft.dance);
}

/// The figures a Caller's Box record imports for one phrase line.
Future<List<Figure>> _tcbFigures(String line) async {
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(
    ImportRequest(
      payload: jsonEncode({
        'ID': '42',
        'Name': 'Test Dance',
        'Permission': 'full',
        'phrases': [
          {
            'name': 'A1',
            'figures': [line],
          },
        ],
      }),
    ),
  );
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return _figures(draft.dance);
}

List<Figure> _figures(Dance dance) => switch (dance.figuresSource) {
  DecodedFigures(:final figures) => figures,
  UnreadableFigures() => throw StateError('figures did not decode'),
};
