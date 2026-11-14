import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// `starburst` (taxonomy v39): the maintainer's figure of their own of that
/// name, shipped as a move, with `travel` a plain number rather than places.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final canonical = Dialect.canonical;
  final leadsFollows = Dialect.presets.singleWhere(
    (d) => d.name == 'Leads/Follows',
  );

  Figure starburst([Map<String, Object?> params = const {}]) =>
      testFigure(move: 'starburst', params: params);

  /// The figure of the maintainer's own export the move was added from.
  const example = {
    'direction': 'clockwise',
    'travel': 2,
    'who': 'role2s',
    'whom': 'partners',
  };

  group('the move', () {
    test('carries the figure of your own\'s params, travel a number', () {
      final def = tax.moves['starburst']!;
      expect(def.displayName, 'starburst');
      expect(
        {
          for (final MapEntry(:key, :value) in def.params.entries)
            key: (value.kind, value.defaultValue),
        },
        {
          'direction': (ParamKind.spinDirection, 'counterclockwise'),
          'travel': (ParamKind.number, 1),
          'who': (ParamKind.dancerSet, 'role1s'),
          'whom': (ParamKind.dancerPair, 'partners'),
          'beats': (ParamKind.beats, 8),
        },
      );
      expect(def.params.keys, ['direction', 'travel', 'who', 'whom', 'beats']);
      expect(def.goodBeats, [8]);
      expect(def.paramBeats, isNull);
      expect(def.searchKeywords, ['dolphin loop']);
      expect(tax.effectiveParams(Figure(move: 'starburst'))['beats'], 8);
    });

    // invalid-fixture: probes travel's range, so 100, -1 and 1.5 are invalid on purpose
    test('travel takes any whole number 0 to 99', () {
      bool valid(Object? travel) => !tax
          .validateFigure(Figure(move: 'starburst', params: {'travel': travel}))
          .any((i) => i.severity == ValidationSeverity.error);
      expect(valid(0), isTrue);
      expect(valid(12), isTrue);
      expect(valid(99), isTrue);
      expect(valid(100), isFalse);
      expect(valid(-1), isFalse);
      expect(valid(1.5), isFalse);
    });

    test('is in the glossary, with a definition', () {
      expect(contraFigureDefinitions['starburst'], isNotNull);
      expect(
        figureGlossaryEntries(tax).map((e) => e.id),
        contains('starburst'),
      );
    });

    test('a figure of your own of its name can switch travel to it only '
        'from a number', () {
      // The export it was added from declared travel as places; a switch maps
      // a parameter only onto one of the same kind.
      expect(shippedFigureNamed('Starburst', tax), 'starburst');
      List<String> targets(ParamKind kind) => userFigureSwitchTargets(
        UserFigureParam(key: 'travel', kind: kind),
        'starburst',
        tax,
      );
      expect(targets(ParamKind.number), ['travel']);
      expect(targets(ParamKind.places), isEmpty);
    });

    test('a combination can bind a number parameter to travel', () {
      // The first built-in slot of `ParamKind.number`, so the combination
      // editor offers that kind.
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'n', kind: ParamKind.number)],
        figures: [
          Figure(move: 'starburst', params: const {'beats': 8}),
        ],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'travel', paramKey: 'n'),
        ],
      );
      expect(validateCompound(definition, tax), isEmpty);
      expect(
        expandCompound(definition, {'n': 3}, tax)!.single.params['travel'],
        3,
      );
    });

    test('a search for dolphin loop finds it by name', () {
      expect(canonicalizeMoveSearchText('dolphin loop', tax), 'starburst');
    });
  });

  group('wording', () {
    test('the canonical line is the figure of your own\'s template', () {
      expect(
        renderer.renderCanonical(starburst(example)),
        'starburst clockwise around 2, role2s lead partners out of the set',
      );
      expect(
        renderer.renderCanonical(starburst()),
        'starburst counterclockwise around 1, role1s lead partners out of the '
        'set',
      );
    });

    test('travel reads as its digits alone, never as places', () {
      // Mutation caught: `travel` declared as `ParamKind.places`, which words
      // it "2 places".
      final line = renderer.renderSummary(starburst(example), canonical);
      expect(
        line,
        'starburst clockwise around 2, role2s lead partner out of the set',
      );
      expect(line, isNot(contains('place')));
    });

    test('renders as the figure of your own did, given travel as a number', () {
      // The template the maintainer's figure of their own declares, with
      // `travel` a number as the move has it: the move's line is that
      // figure's line, in both renders and in a dialect.
      final mine = UserFigureDefinition(
        template:
            'starburst {direction} around {travel}, {who} lead {whom} out '
            'of the set',
        defaultBeats: 8,
        params: [
          UserFigureParam(
            key: 'direction',
            kind: ParamKind.spinDirection,
            defaultValue: 'counterclockwise',
          ),
          UserFigureParam(
            key: 'travel',
            kind: ParamKind.number,
            defaultValue: 1,
          ),
          UserFigureParam(
            key: 'who',
            kind: ParamKind.dancerSet,
            defaultValue: 'role1s',
          ),
          UserFigureParam(
            key: 'whom',
            kind: ParamKind.dancerPair,
            defaultValue: 'partners',
          ),
        ],
      );
      final mineRenderer = FigureRenderer(
        tax,
        userFigures: UserFigureCatalog.fromEntries([
          UserGlossaryEntry(
            id: 'mine',
            kindName: UserGlossaryEntryKind.customFigure.name,
            name: 'starburst',
            definition: 'Mine.',
            description: 'Mine.',
            payload: mine.toJson(),
            createdAt: DateTime.utc(2026),
          ),
        ]),
      );
      final use = userFigureUseFigure(
        id: 'mine',
        args: example,
        text: 'placeholder',
      );
      expect(
        renderer.renderCanonical(starburst(example)),
        mineRenderer.renderUserFigureCanonical(use),
      );
      for (final dialect in [canonical, leadsFollows]) {
        expect(
          renderer.renderSummary(starburst(example), dialect),
          mineRenderer.renderSummary(use, dialect),
          reason: dialect.name,
        );
      }
    });

    test('a dialect\'s role words and name for it apply', () {
      expect(
        renderer.renderSummary(starburst(example), leadsFollows),
        'starburst clockwise around 2, follows lead partner out of the set',
      );
      final named = Dialect(name: 'Named', moves: {'starburst': 'sunburst'});
      expect(
        renderer.renderSummary(starburst(example), named),
        startsWith('sunburst clockwise around 2'),
      );
    });

    test('as a modifier side it reads as doing a starburst', () {
      final figure = Figure.modifier(
        figures: [
          Figure(move: 'swing'),
          starburst(example),
        ],
        beats: 8,
      );
      expect(
        renderer.renderSummary(figure, canonical),
        contains('doing a starburst clockwise around 2'),
      );
    });
  });

  group('free-text entry reads its display back', () {
    Figure? read(String line, [Dialect? dialect]) {
      final read = parseFreeTextFigureEntry(line, dialect: dialect);
      return read.length == 1 && read.single.move == 'starburst'
          ? read.single
          : null;
    }

    test('every slot, travel included', () {
      expect(
        read(
          'starburst clockwise around 12, role2s lead partner out of the set',
        )?.params,
        {...example, 'travel': 12},
      );
      expect(
        read(
          '(8) starburst counterclockwise around 0, neighbors lead shadows '
          'out of the set.',
        )?.params,
        {
          'direction': 'counterclockwise',
          'travel': 0,
          'who': 'neighbors',
          'whom': 'shadows',
          'beats': 8,
        },
      );
    });

    test('around a verb lead that Leads/Follows also has as a role', () {
      // Mutation caught: dropping the per-side canonicalization, after which
      // "lead" before any dancer the role reader does not take as an object
      // ("third neighbor", "centers", "first lead") is read as a role.
      for (final (line, who, whom) in [
        (
          'starburst clockwise around 2, leads lead third neighbor out of the '
              'set',
          'role1s',
          'thirdNeighbors',
        ),
        (
          'starburst clockwise around 2, follows lead centers out of the set',
          'role2s',
          'centers',
        ),
        (
          'starburst clockwise around 2, first lead lead first follow out of '
              'the set',
          'onesRole1',
          'onesRole2',
        ),
      ]) {
        expect(read(line, leadsFollows)?.params, {
          'direction': 'clockwise',
          'travel': 2,
          'who': who,
          'whom': whom,
        }, reason: line);
      }
    });

    test('only the whole display line, every slot stated', () {
      // A bare `starburst` reads as the move by its name, as every move's
      // name does; a line that goes on must be the whole display.
      expect(read('starburst')?.params, isEmpty);
      for (final line in [
        'starburst clockwise',
        'starburst clockwise around 2',
        'starburst around 2, role2s lead partner out of the set',
        'starburst clockwise around two, role2s lead partner out of the set',
        'starburst clockwise around 2, role2s lead partner',
        'starburst clockwise around 2, lead partner out of the set',
        'starburst clockwise around 2, role2s lead partner out of the set '
            'and back',
        // Beyond the number's range.
        'starburst clockwise around 100, role2s lead partner out of the set',
      ]) {
        expect(read(line), isNull, reason: line);
      }
    });

    test('an import does not read it', () {
      // Only free-text entry reads the display; no source writes the figure.
      const line =
          'starburst clockwise around 2, role2s lead partners out of the set';
      expect(read(line), isNotNull);
      for (final frontEnd in [
        canonicalFigureFrontEnd,
        tcbFigureFrontEnd,
        contraDbHtmlFigureFrontEnd,
      ]) {
        expect(
          parseFigureLines(
            line,
            beats: 8,
            frontEnd: frontEnd,
          ).map((f) => f.move),
          isNot(contains('starburst')),
        );
      }
    });
  });
}
