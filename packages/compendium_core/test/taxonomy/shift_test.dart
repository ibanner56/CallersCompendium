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
      // turns every bare shift into this move (710 bare "Shift left/right"
      // lines in the 2026-11-24 census).
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

    test('a destination is kept as the note', () {
      // The maintainer's ruling (2026-11-24): a group shift that says where
      // it goes, or how far, still reads as the shift, with those words as
      // the note. Verbatim lines.
      for (final (line, who, direction, note) in const [
        (
          "Men shift right to next man's position",
          'role1s',
          'right',
          "to next role1's position",
        ),
        ('Women shift right one step', 'role2s', 'right', 'one step'),
        (
          'Men shift right behind neighbor',
          'role1s',
          'right',
          'behind neighbor',
        ),
        (
          'Women shift left a step until across from N3 women',
          'role2s',
          'left',
          'a step until across from N3 role2s',
        ),
        ('Men shift left to N2', 'role1s', 'left', 'to N2'),
      ]) {
        final figure = parse(line).single;
        expect(figure.move, 'shift', reason: line);
        expect(figure.params, {
          'who': who,
          'direction': direction,
          'beats': 4,
        }, reason: line);
        expect(figure.note, note, reason: line);
      }
    });

    test('a bare shift that says where everyone goes stays the slide', () {
      // The maintainer's ruling (2026-11-24): the destination is the note.
      // Verbatim lines.
      for (final (line, side, note) in const [
        ('Shift left to N2', 'left', 'to N2'),
        ('Shift right to N1', 'right', 'to N1'),
        ('Shift right to shadow', 'right', 'to shadow'),
        ('Shift left with neighbor', 'left', 'with neighbor'),
        ('Shift left with neighbor N2', 'left', 'with neighbor N2'),
      ]) {
        final figure = parse(line).single;
        expect(figure.move, 'slide_along_set', reason: line);
        expect(figure.params, {'slide': side, 'beats': 4}, reason: line);
        expect(figure.note, note, reason: line);
      }
    });

    for (final line in const [
      // A tail that is not a destination is another figure, so the line is
      // kept whole (invented lines).
      'Men shift left and swing',
      // A tail that runs on into another figure or a facing (invented lines).
      'Men shift left to new neighbor, swing',
      'Men shift right to swing',
      'Men shift left behind and allemande left',
      'Men shift left to the right',
      'Women shift left a step to face N3',
      'Shift left to ones',
      'Shift left to the end of the line',
      'Shift left with partner',
      'Shift left two places to N2',
      // A count that disagrees with its noun (invented lines).
      'Men shift left one places',
      'Men shift left two place',
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

    test('a re-check reads a destination line imported before', () {
      // The text an import stored for these lines before the destination
      // ruling: roles as tokens, the line otherwise as written.
      Figure gap(String text) => testFigure(
        move: customMove,
        params: {'text': text},
        customOrigin: CustomOrigin.importGap,
      );
      final reparsed = reparseImportGapFigures([
        gap('role2s shift right one step'),
        gap('Shift left to N2'),
      ]);
      expect(reparsed.upgradedCount, 2);
      final [shift, slide] = reparsed.figures;
      expect(shift.move, 'shift');
      expect(shift.note, 'one step');
      expect(slide.move, 'slide_along_set');
      expect(slide.note, 'to N2');
    });

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
