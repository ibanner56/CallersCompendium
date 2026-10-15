import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Uses of figures of your own in a dance (#1023): the soft reference inside a
/// free-text figure's params, and how the renderer shows it.
void main() {
  final created = DateTime.utc(2026, 10, 15);

  UserGlossaryEntry entry({
    String id = 'zoom-id',
    String kind = 'customFigure',
    String name = 'zoom',
    Object? payload,
  }) => UserGlossaryEntry(
    id: id,
    kindName: kind,
    name: name,
    definition: 'A zoom.',
    description: 'Fast.',
    payload:
        payload ??
        {
          'form': 'contra',
          'template': '{who} {move} [{hand} hand,] then {otherHand} {style}',
          'defaultBeats': 6,
          'params': [
            {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
            {'key': 'hand', 'kind': 'handedness'},
            {
              'key': 'style',
              'kind': 'choice',
              'choices': [
                {'id': 'f', 'label': 'fast'},
                {'id': 's', 'label': 'slow'},
              ],
            },
          ],
        },
    createdAt: created,
  );

  final catalog = UserFigureCatalog.fromEntries([entry()]);
  final renderer = FigureRenderer(contraTaxonomy, userFigures: catalog);
  final bare = FigureRenderer(contraTaxonomy);

  Figure use(Map<String, Object?> args, {String text = 'stored line'}) =>
      userFigureUseFigure(id: 'zoom-id', args: args, text: text);

  group('the reference', () {
    test('rides inside params, so builds before it keep it whole', () {
      final figure = use(const {'hand': 'right'});
      expect(figure.move, customMove);
      expect(figure.customOrigin, CustomOrigin.userEntered);
      final json = figureToJson(figure);
      expect(unsupportedFigurePath([json]), isNull);
      expect(figureFromJson(json), figure);
      expect(userFigureUseOf(figureFromJson(json))!.args, {'hand': 'right'});
    });

    test('is attached while its stored line is the one written with it, and '
        'detached once something else edits the line', () {
      final figure = use(const {});
      expect(userFigureUseOf(figure)!.attached, isTrue);
      final edited = figure.copyWith(
        params: {...figure.params, 'text': 'typed on an older device'},
      );
      expect(userFigureUseOf(edited)!.attached, isFalse);
    });

    test('its check is taken over the text as the repository stores it', () {
      expect(
        userFigureTextCheck('café zoom'),
        userFigureTextCheck('café zoom'),
        reason: 'NFC-equivalent text has one check',
      );
      expect(
        userFigureTextCheck('zoom​'),
        userFigureTextCheck('zoom'),
        reason: 'what normalisation strips does not count',
      );
    });

    test('a reference of the wrong shape reads as none', () {
      // invalid-fixture: deliberately malformed references, one per case.
      Figure withParams(Map<String, Object?> extra) => Figure(
        move: customMove,
        params: {
          'text': 'x',
          userFigureRefKey: 'zoom-id',
          userFigureArgsKey: const <String, Object?>{},
          userFigureCheckKey: userFigureTextCheck('x'),
          ...extra,
        },
      );
      expect(userFigureUseOf(withParams(const {})), isNotNull);
      for (final bad in <Map<String, Object?>>[
        {userFigureRefKey: 7},
        {userFigureRefKey: '../etc'},
        {userFigureRefKey: 'x' * 65},
        {userFigureArgsKey: 'nope'},
        {
          userFigureArgsKey: {
            'a': [1],
          },
        },
        {
          userFigureArgsKey: {'a': 'x' * 1001},
        },
        {
          userFigureArgsKey: {for (var i = 0; i < 17; i++) 'k$i': i},
        },
        {userFigureCheckKey: 'XYZ'},
      ]) {
        expect(userFigureUseOf(withParams(bad)), isNull, reason: '$bad');
      }
      expect(
        userFigureUseOf(Figure(move: 'swing', params: const {})),
        isNull,
        reason: 'only a free-text figure holds one',
      );
    });

    test('detaching keeps the line and drops only the reference', () {
      final figure = userFigureUseFigure(
        id: 'zoom-id',
        args: const {'hand': 'left'},
        text: 'neighbors zoom',
        beats: 6,
        note: 'smile',
        progression: true,
      );
      final frozen = detachUserFigureUse(figure);
      expect(frozen.params, {'text': 'neighbors zoom', 'beats': 6});
      expect(frozen.note, 'smile');
      expect(frozen.progression, isTrue);
      expect(hasUserFigureReferenceKeys(frozen), isFalse);
    });

    test('a figure transform reaches leaves inside containers, and returns '
        'the same list when nothing changed', () {
      final inner = use(const {});
      final meanwhile = Figure.meanwhile(
        figures: [
          inner,
          Figure(move: 'swing', params: const {}),
        ],
        beats: 8,
      );
      final figures = [meanwhile];
      expect(identical(mapFigureLeaves(figures, (f) => f), figures), isTrue);
      final frozen = mapFigureLeaves(figures, detachUserFigureUse);
      expect(hasUserFigureReferenceKeys(frozen.single.subFigures.first), false);
      expect(userFigureIdsUsedBy(figures), {'zoom-id'});
      expect(userFigureIdsUsedBy(frozen), isEmpty);
    });
  });

  group('validation', () {
    test('a well-formed use is a valid custom figure', () {
      expect(
        contraTaxonomy.validateFigure(use(const {'hand': 'right'})),
        isEmpty,
      );
    });

    test('any other key on a custom figure is still an error', () {
      final figure = use(const {});
      final extra = figure.copyWith(params: {...figure.params, 'surprise': 1});
      expect(
        contraTaxonomy.validateFigure(extra).map((i) => i.code),
        contains('unknown_param'),
      );
    });

    test('a malformed or partial reference is an error', () {
      final figure = use(const {});
      final partial = figure.copyWith(
        params: {
          for (final e in figure.params.entries)
            if (e.key != userFigureCheckKey) e.key: e.value,
        },
      );
      expect(
        contraTaxonomy.validateFigure(partial).map((i) => i.code),
        contains('invalid_param_value'),
      );
    });
  });

  group('rendering', () {
    test('renders live from the definition, in the dialect, on every path', () {
      final figure = use(const {
        'who': 'role1s',
        'hand': 'right',
        'style': 's',
      });
      expect(
        renderer.render(figure, Dialect.larksRobins),
        'larks zoom right hand, then left slow',
      );
      expect(
        renderer.renderSummary(figure, Dialect.larksRobins),
        'larks zoom right hand, then left slow',
      );
      expect(
        renderer.renderVerbose(figure, Dialect.larksRobins),
        'larks zoom right hand, then left slow',
      );
      expect(
        renderer.renderCanonical(figure),
        'role1s zoom right hand, then left slow',
      );
    });

    test('an unset argument takes the default, or renders nothing, and an '
        'emptied optional group goes', () {
      expect(renderer.renderCanonical(use(const {})), 'neighbors zoom then');
    });

    test('a renderer without the figure shows the stored line', () {
      final figure = use(const {'hand': 'right'}, text: 'neighbors zoom');
      expect(bare.render(figure, Dialect.larksRobins), 'neighbors zoom');
      expect(bare.renderCanonical(figure), 'neighbors zoom');
    });

    test(
      'a detached use shows its stored line, even with the figure known',
      () {
        final figure = use(const {'hand': 'right'});
        final edited = figure.copyWith(
          params: {...figure.params, 'text': 'typed elsewhere'},
        );
        expect(renderer.renderCanonical(edited), 'typed elsewhere');
      },
    );

    test('an argument outside its values, such as a removed choice, shows the '
        'stored line', () {
      expect(
        renderer.renderCanonical(use(const {'style': 'gone'})),
        'stored line',
      );
      expect(
        renderer.renderCanonical(use(const {'hand': 'sideways'})),
        'stored line',
      );
    });

    test('a definition that no longer decodes shows the stored line', () {
      final broken = FigureRenderer(
        contraTaxonomy,
        userFigures: UserFigureCatalog.fromEntries([
          entry(payload: const {'template': 3}),
        ]),
      );
      expect(broken.renderCanonical(use(const {})), 'stored line');
    });

    test('only figures of your own enter the catalog', () {
      final mixed = UserFigureCatalog.fromEntries([
        entry(id: 'c', kind: 'compound'),
        entry(id: 't', kind: 'term'),
        entry(),
      ]);
      expect(mixed.figures.map((f) => f.id), ['zoom-id']);
    });

    test(
      'an argument is inserted literally: it can never fill another slot',
      () {
        final textual = FigureRenderer(
          contraTaxonomy,
          userFigures: UserFigureCatalog.fromEntries([
            entry(
              payload: const {
                'template': '{move} to {where}',
                'defaultBeats': 8,
                'params': [
                  {'key': 'where', 'kind': 'text'},
                ],
              },
            ),
          ]),
        );
        expect(
          textual.renderCanonical(use(const {'where': '{move} {beats}‮'})),
          'zoom to {move} {beats}',
        );
      },
    );

    test('the beats slot reads the use\'s beats, else the default', () {
      final beaty = FigureRenderer(
        contraTaxonomy,
        userFigures: UserFigureCatalog.fromEntries([
          entry(
            payload: const {
              'template': '{move} ({beats})',
              'defaultBeats': 6,
              'params': <Object?>[],
            },
          ),
        ]),
      );
      expect(beaty.renderCanonical(use(const {})), 'zoom (6)');
      expect(
        beaty.renderCanonical(
          userFigureUseFigure(
            id: 'zoom-id',
            args: const {},
            text: 'x',
            beats: 4,
          ),
        ),
        'zoom (4)',
      );
    });

    test('a flag renders its label when set, and nothing otherwise', () {
      final flagged = FigureRenderer(
        contraTaxonomy,
        userFigures: UserFigureCatalog.fromEntries([
          entry(
            payload: const {
              'template': '{move} [{prefix}]',
              'defaultBeats': 8,
              'params': [
                {'key': 'prefix', 'kind': 'flag', 'label': 'with a flourish'},
              ],
            },
          ),
        ]),
      );
      expect(
        flagged.renderCanonical(use(const {'prefix': true})),
        'zoom with a flourish',
      );
      expect(flagged.renderCanonical(use(const {'prefix': false})), 'zoom');
    });

    test('the canonical line is what a stored line is refreshed to', () {
      final figure = use(const {'who': 'role1s', 'hand': 'left', 'style': 'f'});
      expect(
        renderer.renderUserFigureCanonical(figure),
        renderer.renderCanonical(figure),
      );
      expect(bare.renderUserFigureCanonical(figure), isNull);
    });
  });

  group('the dance diff key', () {
    test('keys an attached use by its figure and arguments, not its line', () {
      final a = use(const {'hand': 'right'}, text: 'old wording');
      final b = use(const {'hand': 'right'}, text: 'new wording');
      final c = use(const {'hand': 'left'}, text: 'new wording');
      expect(
        figureCanonicalKey(a, contraTaxonomy),
        figureCanonicalKey(b, contraTaxonomy),
      );
      expect(
        figureCanonicalKey(a, contraTaxonomy),
        isNot(figureCanonicalKey(c, contraTaxonomy)),
      );
    });

    test('keys a detached use by its line, as any free-text figure', () {
      final frozen = detachUserFigureUse(use(const {}, text: 'a line'));
      expect(
        figureCanonicalKey(frozen, contraTaxonomy),
        figureCanonicalKey(customFigure('a line'), contraTaxonomy),
      );
    });
  });

  group('elsewhere', () {
    test('#417\'s re-parse never replaces a use, whatever its origin says', () {
      final figure = testFigure(
        move: customMove,
        params: use(const {}, text: 'neighbors swing').params,
        customOrigin: CustomOrigin.importGap,
      );
      final result = reparseImportGapFigures([
        figure,
      ], taxonomy: contraTaxonomy);
      expect(result.figures.single, figure);
      expect(result.upgradedCount, 0);
    });

    test('a figure shorthand never holds a use: builds before it would drop '
        'the mapping', () {
      final mappings = ShorthandMappings.decode([
        {
          'token': 'zz',
          'figures': [figureToJson(use(const {}))],
        },
        {
          'token': 'sw',
          'figures': [figureToJson(Figure(move: 'swing', params: const {}))],
        },
      ], taxonomy: contraTaxonomy);
      expect([for (final m in mappings.mappings) m.token], ['sw']);
    });
  });
}
