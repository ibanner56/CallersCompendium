import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// `shift` (taxonomy v40): one named group sidesteps ("Men shift left", "Twos
/// shift up"). Its neighbour `slide_along_set` is everyone sliding as couples,
/// which The Caller's Box writes as a bare "Shift left", and that reading must
/// not change.
///
/// Lines are verbatim from The Caller's Box unless marked otherwise.
void main() {
  final tax = contraTaxonomy;

  List<Figure> parse(String line) =>
      parseFigureLines(line, beats: 4, frontEnd: tcbFigureFrontEnd);

  group('the move', () {
    test('names who, and which way', () {
      final def = tax.moves['shift']!;
      expect(def.displayName, 'shift');
      expect(
        {
          for (final MapEntry(:key, :value) in def.params.entries)
            key: (value.kind, value.defaultValue),
        },
        {
          'who': (ParamKind.dancerSet, 'role1s'),
          'direction': (ParamKind.choice, 'left'),
          'beats': (ParamKind.beats, 4),
        },
      );
      expect(def.params['direction']!.choices, ['left', 'right', 'up', 'down']);
      expect(def.goodBeats, [2, 4, 6, 8]);
    });

    // invalid-fixture: probes who's domain, so everyone is invalid on purpose
    test('offers every dancer set but everyone, which is the slide', () {
      bool valid(String who) => !tax
          .validateFigure(Figure(move: 'shift', params: {'who': who}))
          .any((i) => i.severity == ValidationSeverity.error);
      expect(valid('everyone'), isFalse);
      for (final who in ParamVocab.dancerSets) {
        if (who == 'everyone') continue;
        expect(valid(who), isTrue, reason: who);
      }
    });

    test('is in the glossary, with a definition', () {
      expect(contraFigureDefinitions['shift'], isNotNull);
      expect(figureGlossaryEntries(tax).map((e) => e.id), contains('shift'));
    });

    test('renders who, the move and the way', () {
      final renderer = FigureRenderer(tax);
      final figure = testFigure(
        move: 'shift',
        params: {'who': 'twos', 'direction': 'up'},
      );
      expect(renderer.renderCanonical(figure), 'twos shift up');
    });
  });

  group('The Caller\'s Box', () {
    for (final (line, who, direction) in const [
      ('Men shift left', 'role1s', 'left'),
      ('Women shift right', 'role2s', 'right'),
      ('Twos shift up', 'twos', 'up'),
      ('Ones shift down', 'ones', 'down'),
    ]) {
      test('"$line" is a shift', () {
        final figure = parse(line).single;
        expect(figure.move, 'shift');
        expect(figure.params, {'who': who, 'direction': direction, 'beats': 4});
        expect(figure.note, isNull);
      });
    }

    test('a bare "Shift left/right" stays a slide along the set', () {
      // Mutation caught: reading the shift without requiring a named group
      // turns every bare shift (710 lines) into this move.
      for (final side in const ['left', 'right']) {
        final figure = parse('Shift $side').single;
        expect(figure.move, 'slide_along_set', reason: side);
        expect(figure.params['slide'], side);
      }
    });

    test('a count of places is kept as the note', () {
      // Verbatim: dance 15257. "two places" is not from a shift line (the
      // only stated counts there are "one place"); it checks the plural.
      for (final (line, note) in const [
        ('Men shift left one place', 'one place'),
        ('Men shift left two places', 'two places'),
      ]) {
        final figure = parse(line).single;
        expect(figure.move, 'shift', reason: line);
        expect(figure.params['direction'], 'left');
        expect(figure.note, note);
      }
    });

    test('an annotation is kept as the note', () {
      final figure = parse('Women shift left (past W)').single;
      expect(figure.move, 'shift');
      expect(figure.note, 'past W');
    });

    for (final line in const [
      // Not a shift's shape, so kept whole.
      "Men shift left to next man's position",
      'Women shift right one step',
      'Men shift right behind neighbor',
      // "Others" depends on the line before; no dancer set holds it.
      'Others shift up',
      // A slide, not a shift; and "everyone" is the slide (invented line).
      'Women slide left',
      'Everyone shift left',
    ]) {
      test('"$line" stays custom', () {
        expect(parse(line).single.isCustom, isTrue);
      });
    }

    test('a re-check reads a shift imported before the move existed', () {
      // The text an import stored for these lines before v40 read them: the
      // reader writes the roles as tokens.
      Figure gap(String text) => testFigure(
        move: customMove,
        params: {'text': text},
        customOrigin: CustomOrigin.importGap,
      );
      final reparsed = reparseImportGapFigures([
        gap('role2s shift right'),
        Figure.meanwhile(
          figures: [
            testFigure(
              move: 'allemande',
              params: {'who': 'role2s', 'hand': 'right', 'travel': 0.75},
            ),
            gap('role1s shift left'),
          ],
          beats: 4,
        ),
      ]);
      expect(reparsed.upgradedCount, 2);
      final [alone, together] = reparsed.figures;
      expect(alone.move, 'shift');
      expect(alone.params['who'], 'role2s');
      expect(together.subFigures.last.move, 'shift');
      expect(together.subFigures.last.params['direction'], 'left');
    });

    test(
      'Mary Cay\'s Reel (dance 10579): the men shift as the women turn',
      () async {
        final payload = jsonEncode({
          'ID': '10579',
          'Name': "Mary Cay's Reel",
          'Permission': 'full',
          'phrases': [
            {
              'name': 'B1',
              'figures': [
                '(8) In long lines, go forward and back',
                '(4) Women allemande right 3/4 || Men shift left',
                '(4) N2 women allemande left 3/4',
              ],
            },
          ],
        });
        final adapter = CallersBoxAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: payload),
        );
        final raw = await adapter.fetch(discovered.single);
        final figures = figuresOf(adapter.parse(raw).dance);
        final together = figures[1];
        expect(together.isContainer, isTrue);
        expect(together.beats, 4);
        final [turn, shift] = together.subFigures;
        expect(turn.move, 'allemande');
        expect(shift.move, 'shift');
        expect(shift.params, {'who': 'role1s', 'direction': 'left'});
      },
    );
  });
}
