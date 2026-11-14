import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// `trade_the_wave` (taxonomy v39), added from a figure of the user's own of
/// the same name. That figure's definition and one dance's use of it are
/// reproduced below as an export carried them.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final canonical = Dialect.canonical;

  Figure trade([Map<String, Object?> params = const {}]) =>
      testFigure(move: 'trade_the_wave', params: params);

  // The figure of the user's own, as exported (its `payload`).
  final mine = decodeUserFigureDefinition(const {
    'form': 'contra',
    'template':
        '{move} - all step forward and face {axis}, {otherSides} pass right '
        'shoulder and reform new short waves facing the other direction - '
        '{center} by the {centerHand} in the center, {sides} by the '
        '{otherCenterHand} on the sides {balance}',
    'defaultBeats': 8,
    'params': [
      {'key': 'sides', 'kind': 'dancerSet', 'default': 'neighbors'},
      {'key': 'center', 'kind': 'dancerSet', 'default': 'role1s'},
      {'key': 'centerHand', 'kind': 'handedness', 'default': 'right'},
      {'key': 'axis', 'kind': 'direction', 'default': 'across'},
      {
        'key': 'balance',
        'kind': 'flag',
        'default': true,
        'label': '- and balance',
      },
    ],
  })!;
  // A use of it, as the dance "All Along the Equinox" stores it.
  const useArgs = {
    'sides': 'partners',
    'center': 'role1s',
    'centerHand': 'left',
    'axis': 'across',
  };
  const useText =
      'trade the wave - all step forward and face across, neighbors pass '
      'right shoulder and reform new short waves facing the other direction - '
      'role1s by the left in the center, partners by the right on the sides - '
      'and balance';

  group('the move', () {
    test('has the params of the figure it was added from, key for key', () {
      final def = tax.moves['trade_the_wave']!;
      expect(def.displayName, 'trade the wave');
      expect(
        {
          for (final p in def.params.entries)
            if (p.key != 'beats') p.key: p.value.kind,
        },
        {for (final p in mine.params) p.key: p.kind},
      );
    });

    test('defaults to that figure\'s wave, its balance stored off and seeded '
        'on', () {
      expect(tax.effectiveParams(trade()), {
        'sides': 'neighbors',
        'center': 'role1s',
        'centerHand': 'right',
        'axis': 'across',
        'balance': false,
        'beats': 4,
      });
      expect(tax.entryParams('trade_the_wave'), {
        'sides': 'neighbors',
        'center': 'role1s',
        'centerHand': 'right',
        'axis': 'across',
        'balance': true,
        'beats': 8,
      });
    });

    test('takes 8 beats with the balance and 4 without', () {
      final beats = tax.moves['trade_the_wave']!.paramBeats!;
      expect(beats.param, 'balance');
      expect(beats.byValue, {true: 8, false: 4});
      expect(tax.validateFigure(trade({'balance': true, 'beats': 8})), isEmpty);
      expect(tax.validateFigure(trade({'beats': 4})), isEmpty);
    });

    test('is the shipped figure named like the user\'s own', () {
      expect(shippedFigureNamed('Trade the wave', tax), 'trade_the_wave');
    });

    test('has a glossary definition', () {
      expect(contraFigureDefinitions, contains('trade_the_wave'));
    });
  });

  group('wording', () {
    test('reads exactly as the figure of the user\'s own did', () {
      final figure = trade({...useArgs, 'balance': true, 'beats': 8});
      expect(renderer.renderSummary(figure, canonical), useText);
    });

    test('canonical text is the move name alone, as form short waves\'', () {
      expect(
        renderer.renderCanonical(trade({...useArgs, 'balance': true})),
        'trade the wave',
      );
    });

    test('the dancers who trade are the opposite of the sides pair', () {
      String traders(String sides) {
        final line = renderer.renderSummary(trade({'sides': sides}), canonical);
        return RegExp(r'face across, (.+) pass right').firstMatch(line)![1]!;
      }

      expect(traders('neighbors'), 'partners');
      expect(traders('partners'), 'neighbors');
      expect(traders('nextNeighbors'), 'partners');
      // A sides pair with no opposite names no traders it cannot know.
      expect(traders('shadows'), 'others');
    });

    test('the side hand is the other hand, and the axis is named', () {
      expect(
        renderer.renderSummary(
          trade({'centerHand': 'left', 'axis': 'rightDiagonal'}),
          canonical,
        ),
        'trade the wave - all step forward and face right diagonal, partners '
        'pass right shoulder and reform new short waves facing the other '
        'direction - role1s by the left in the center, neighbors by the right '
        'on the sides',
      );
    });

    test('names the dancers in the dialect\'s words', () {
      expect(
        renderer.renderSummary(trade(), Dialect.larksRobins),
        contains('larks by the right in the center'),
      );
    });
  });

  group('reading it back', () {
    List<Figure> read(String text) =>
        parseFreeTextFigureEntry(text, taxonomy: tax, dialect: canonical);

    test('its displayed line reads back as the same figure', () {
      final figures = read(useText);
      expect(figures, hasLength(1));
      expect(figures.single.move, 'trade_the_wave');
      expect(figures.single.params, containsPair('balance', true));
      expect(renderer.renderSummary(figures.single, canonical), useText);
    });

    test('a line whose traders are not the sides\' opposite is not read', () {
      final wrong = useText.replaceFirst('neighbors pass', 'shadows pass');
      expect(read(wrong).single.isCustom, isTrue);
    });

    test('a line whose two hands are the same is not read', () {
      final wrong = useText.replaceFirst(
        'partners by the right',
        'partners by the left',
      );
      expect(read(wrong).single.isCustom, isTrue);
    });

    test('a tail after the line is not read', () {
      expect(read('$useText, twice').single.isCustom, isTrue);
    });

    test('typing the bare name gives the move at its defaults', () {
      final figures = read('trade the wave');
      expect(figures.single.move, 'trade_the_wave');
    });

    test('the import grammar keeps a bare "Trade the wave" as text: it names '
        'no wave', () {
      expect(parseFigureLine('Trade the wave')!.isCustom, isTrue);
    });
  });

  group('switching the figure of the user\'s own to it', () {
    final mapping = UserFigureSwitch(
      target: 'trade_the_wave',
      params: {for (final p in mine.params) p.key: p.key},
    );
    final catalog = UserFigureCatalog.fromEntries([
      UserGlossaryEntry(
        id: 'mine',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'trade the wave',
        definition: 'Mine.',
        description: 'Mine.',
        payload: mine.toJson(),
        createdAt: DateTime.utc(2026),
      ),
    ]);

    test('maps every parameter onto the one of the same key', () {
      expect(userFigureSwitchProblems(mine, mapping, tax), isEmpty);
    });

    // The use's stored line is its canonical render, the dancers plural. The
    // figure's live display writes them singular ("neighbor pass"); the move
    // keeps the stored, plural wording, which the verb agrees with.
    test('shows each use as its stored line', () {
      final use = userFigureUseFigure(
        id: 'mine',
        args: useArgs,
        text: useText,
        beats: 8,
      );
      expect(
        FigureRenderer(
          tax,
          userFigures: catalog,
        ).renderUserFigureCanonical(use),
        useText,
      );
      final switched = switchUserFigureUsesIn(
        [use],
        'mine',
        mine,
        mapping,
        tax,
        FigureRenderer(tax, userFigures: catalog),
      ).single;
      expect(switched.move, 'trade_the_wave');
      expect(switched.params, {...useArgs, 'balance': true, 'beats': 8});
      expect(renderer.renderSummary(switched, canonical), useText);
    });
  });
}
