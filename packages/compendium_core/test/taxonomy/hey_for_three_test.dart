import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// `hey_for_three` (taxonomy v39): the dolphin hey's params, beats and
/// wording, except that `who` is a single dancer, from the list `whom` takes.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final canonical = Dialect.canonical;
  final leadsFollows = Dialect.presets.singleWhere(
    (d) => d.name == 'Leads/Follows',
  );

  Figure heyForThree([Map<String, Object?> params = const {}]) =>
      testFigure(move: 'hey_for_three', params: params);

  group('the move', () {
    test('carries the dolphin hey\'s params, who a single dancer', () {
      final def = tax.moves['hey_for_three']!;
      final dolphin = tax.moves['dolphin_hey']!;
      expect(def.displayName, 'hey for three');
      expect(def.params.keys, dolphin.params.keys);
      expect(def.renderTemplate, dolphin.renderTemplate);
      expect(def.goodBeats, dolphin.goodBeats);
      expect(def.searchKeywords, dolphin.searchKeywords);
      expect(def.paramBeats, dolphin.paramBeats);
      for (final key in ['whom', 'shoulder', 'beats']) {
        final mine = def.params[key]!;
        final theirs = dolphin.params[key]!;
        expect(
          (mine.kind, mine.defaultValue, mine.choices),
          (theirs.kind, theirs.defaultValue, theirs.choices),
          reason: key,
        );
      }
      // Mutation caught: `who` copied from the dolphin hey whole, which offers
      // every dancer set and defaults to the ones.
      final who = def.params['who']!;
      expect(who.kind, ParamKind.dancerSet);
      expect(who.choices, ParamVocab.singleDancers);
      expect(who.choices, dolphin.params['whom']!.choices);
      expect(who.defaultValue, 'twosRole2');
      expect(tax.effectiveParams(Figure(move: 'hey_for_three'))['beats'], 16);
    });

    // invalid-fixture: probes who's domain, so `ones` and `neighbors` are invalid on purpose
    test('who takes a single dancer and nothing else', () {
      bool valid(Object? who) => !tax
          .validateFigure(Figure(move: 'hey_for_three', params: {'who': who}))
          .any((i) => i.severity == ValidationSeverity.error);
      for (final dancer in ParamVocab.singleDancers) {
        expect(valid(dancer), isTrue, reason: dancer);
      }
      expect(valid('ones'), isFalse);
      expect(valid('neighbors'), isFalse);
      // The dolphin hey's `who` still takes any dancers.
      expect(
        tax
            .validateFigure(
              Figure(move: 'dolphin_hey', params: {'who': 'ones'}),
            )
            .where((i) => i.severity == ValidationSeverity.error),
        isEmpty,
      );
    });

    test('a figure of your own of its name now shares a shipped name', () {
      expect(shippedFigureNamed('Hey for three', tax), 'hey_for_three');
    });

    test('is in the glossary, with a definition', () {
      expect(contraFigureDefinitions['hey_for_three'], isNotNull);
      expect(
        figureGlossaryEntries(tax).map((e) => e.id),
        contains('hey_for_three'),
      );
    });
  });

  group('wording', () {
    test('the canonical line follows the dolphin hey\'s template', () {
      expect(
        renderer.renderCanonical(heyForThree()),
        'twos role2 hey for three right',
      );
    });

    test('the display is the dolphin hey\'s, under its own name', () {
      // The dolphin hey renders a single dancer in `who` as this move does, so
      // the comparison below also holds for a builder that copied it whole;
      // the two lines pinned here catch a changed template or dancer word.
      expect(
        renderer.renderSummary(heyForThree(), canonical),
        'hey for three - start with second role2 passing first role1 by '
        'right shoulders',
      );
      expect(
        renderer.renderSummary(
          heyForThree({
            'who': 'threesRole1',
            'whom': 'foursRole2',
            'shoulder': 'left',
          }),
          leadsFollows,
        ),
        'hey for three - start with third lead passing fourth follow by left '
        'shoulders',
      );
      for (final dialect in [canonical, leadsFollows]) {
        for (final who in ParamVocab.singleDancers) {
          for (final shoulder in ['left', 'right']) {
            final params = {
              'who': who,
              'whom': 'onesRole1',
              'shoulder': shoulder,
            };
            expect(
              renderer.renderSummary(heyForThree(params), dialect),
              renderer
                  .renderSummary(
                    testFigure(move: 'dolphin_hey', params: params),
                    dialect,
                  )
                  .replaceFirst('dolphin hey', 'hey for three'),
              reason: '${dialect.name} $who $shoulder',
            );
          }
        }
      }
    });

    test('a dialect\'s name for it applies', () {
      final named = Dialect(name: 'Named', moves: {'hey_for_three': 'hey3'});
      expect(
        renderer.renderSummary(heyForThree(), named),
        startsWith('hey3 - start with'),
      );
    });

    test('as a modifier side it reads as doing a hey for three', () {
      final figure = Figure.modifier(
        figures: [
          Figure(move: 'swing'),
          heyForThree(),
        ],
        beats: 16,
      );
      expect(
        renderer.renderSummary(figure, canonical),
        contains('doing a hey for three - start with second role2'),
      );
    });
  });

  group('free-text entry reads its display back', () {
    Figure? read(String line, [Dialect? dialect]) {
      final read = parseFreeTextFigureEntry(line, dialect: dialect);
      return read.length == 1 && read.single.move == 'hey_for_three'
          ? read.single
          : null;
    }

    test('every displayed figure, in each dialect', () {
      // Mutation caught: a reader that drops the shoulder, or one that is not
      // tried on the dialect's role words read back (`second follow`).
      for (final dialect in [canonical, leadsFollows]) {
        for (final who in ParamVocab.singleDancers) {
          for (final whom in ['onesRole1', 'foursRole2']) {
            for (final shoulder in ['left', 'right']) {
              final params = {'who': who, 'whom': whom, 'shoulder': shoulder};
              final line = renderer.renderSummary(heyForThree(params), dialect);
              expect(
                read(line, dialect)?.params,
                params,
                reason: '${dialect.name}: $line',
              );
            }
          }
        }
      }
    });

    test('with a count, and the bare name', () {
      expect(
        read(
          '(16) hey for three - start with second role2 passing first role1 '
          'by right shoulders.',
        )?.params,
        {
          'who': 'twosRole2',
          'whom': 'onesRole1',
          'shoulder': 'right',
          'beats': 16,
        },
      );
      expect(read('Hey for three')?.params, isEmpty);
    });

    test('under a dialect\'s name for it', () {
      final named = Dialect(name: 'Named', moves: {'hey_for_three': 'Hey 3'});
      final line = renderer.renderSummary(heyForThree(), named);
      expect(line, startsWith('Hey 3 - '));
      expect(read(line, named)?.params, {
        'who': 'twosRole2',
        'whom': 'onesRole1',
        'shoulder': 'right',
      });
    });

    test('a line that is not its whole display is not read', () {
      for (final line in [
        // A couple is not a single dancer.
        'hey for three - start with ones passing first role1 by right '
            'shoulders',
        // Every slot is required.
        'hey for three - start with second role2 passing first role1',
        'hey for three - start with second role2 passing first role1 by '
            'right shoulders then swing',
      ]) {
        expect(read(line), isNull, reason: line);
      }
    });

    test('no import reads it', () {
      final line =
          'hey for three - start with second role2 passing first role1 by '
          'right shoulders';
      expect(parseFigureLinesFanOut(line).single.isCustom, isTrue);
      expect(parseFigureLinesFanOut('hey for three').single.isCustom, isTrue);
    });
  });
}
