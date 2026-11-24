import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/dialect/ecd_display.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// ADR-006 §7's movements, without the `ecd_` prefix, table by table.
const _adrMovements = {
  // §7.1
  'set', 'honor', 'clap', 'set_and_link',
  // §7.2 (swat the flea is an alias of box the gnat)
  'turn_single', 'turn_alone', 'hand_turn', 'two_hand_turn', 'arm_turn',
  'shoulder_round', 'swing', 'box_the_gnat', 'gate', 'orbit', 'mad_robin',
  // §7.3
  'balance', 'balance_ring', 'circle', 'star', 'form_short_wave',
  'form_long_wave',
  // §7.4
  'circular_hey', 'rights_and_lefts', 'chain', 'figure_eight', 'dolphin_hey',
  'hey_for_three', 'hey_for_four', 'tandem_reel', 'mirror_hey',
  'grand_chain',
  // §7.5
  'cross', 'right_left_through', 'fall_back', 'forward_and_back',
  'back_to_back', 'siding', 'pass_through', 'promenade', 'poussette', 'arch',
  'rollaway', 'change_places', 'lead', 'cast', 'galop', 'chevron',
  'bend_line',
  // §9.3, from the check against one caller's notes
  'pull_by', 'hey_for_six', 'petronella', 'contra_corners',
};

/// Movements in which dancers don't travel, so take no `destination`
/// (§6.4), and `forward_and_back`, whose `goBack` replaces it.
const _noDestination = {
  'set',
  'honor',
  'clap',
  'set_and_link',
  'balance',
  'balance_ring',
  'arch',
  'form_short_wave',
  'form_long_wave',
  'forward_and_back',
  'bend_line',
};

final _renderer = FigureRenderer(shippedTaxonomies.anyForm);

String _show(Figure figure) => _renderer.render(figure, Dialect.canonical);

void main() {
  _heyStartersEachShown();
  _ecdKeywordsNameOneMove();
  group('the registry', () {
    test('holds exactly ADR-006 §7\'s movements, each prefixed', () {
      expect(ecdTaxonomy.moves.keys.toSet(), {
        for (final id in _adrMovements) 'ecd_$id',
      });
      expect(ecdTaxonomy.aliases.keys, ['ecd_swat_the_flea', 'ecd_hand_cast']);
      expect(ecdTaxonomy.form, DanceForm.ecd);
    });

    test('a travelling movement takes a destination; the rest do not', () {
      for (final MapEntry(key: id, value: def) in ecdTaxonomy.moves.entries) {
        final bare = id.substring('ecd_'.length);
        expect(
          def.params.containsKey('destination'),
          !_noDestination.contains(bare),
          reason: id,
        );
      }
    });

    test('a value a source can leave out defaults to unspecified (R2)', () {
      // The maintainer's exceptions: a double when no distance is stated
      // (§9.1 point 3), the hand that names box the gnat, and the flags,
      // counts of beats and free text, which have no "not stated" value.
      const exceptions = {
        'ecd_forward_and_back.distance',
        'ecd_box_the_gnat.hand',
      };
      for (final MapEntry(key: id, value: def) in ecdTaxonomy.moves.entries) {
        for (final MapEntry(key: name, value: spec) in def.params.entries) {
          if (exceptions.contains('$id.$name')) continue;
          switch (spec.kind) {
            case ParamKind.flag:
              expect(spec.defaultValue, false, reason: '$id.$name');
            case ParamKind.beats || ParamKind.text:
              break;
            case ParamKind.dancerList:
              expect(spec.defaultValue, [ParamVocab.unspecified]);
            default:
              expect(
                spec.defaultValue,
                ParamVocab.unspecified,
                reason: '$id.$name',
              );
          }
        }
      }
      expect(
        ecdTaxonomy.effectiveParams(
          Figure(move: 'ecd_forward_and_back'),
        )['distance'],
        'double',
      );
    });

    test('every who is a list; the editor suggests everyone', () {
      for (final MapEntry(key: id, value: def) in ecdTaxonomy.moves.entries) {
        final who = def.params['who'];
        if (who == null) continue;
        expect(who.kind, ParamKind.dancerList, reason: id);
        expect(ecdTaxonomy.entryParams(id)['who'], ['everyone'], reason: id);
      }
      expect(ecdTaxonomy.effectiveParams(Figure(move: 'ecd_cast'))['who'], [
        'unspecified',
      ]);
    });

    test('the editor suggests a set to the right, a right turn single, a '
        'double forward', () {
      expect(ecdTaxonomy.entryParams('ecd_set')['direction'], 'right');
      expect(ecdTaxonomy.entryParams('ecd_turn_single')['shoulder'], 'right');
      expect(ecdTaxonomy.entryParams('ecd_forward_and_back'), {
        'who': ['everyone'],
        'where': 'forward',
        'formation': ParamVocab.unspecified,
        'distance': 'double',
        'goBack': false,
        'beats': 8,
      });
    });

    test('set and link takes no parameters but its timing (§9.1 point 4)', () {
      expect(ecdTaxonomy.moves['ecd_set_and_link']!.params.keys, ['beats']);
    });

    test('no gendered role term appears anywhere (§9.1 point 7)', () {
      final gendered = RegExp(
        r'\b(gents?|ladies|lady|men|man|women|woman|gentlespoons?|ladles?)\b',
        caseSensitive: false,
      );
      final words = [
        for (final def in ecdTaxonomy.moves.values) ...[
          def.displayName,
          def.renderTemplate,
          ...def.searchKeywords,
          for (final spec in def.params.values) ...?spec.choices,
        ],
        for (final alias in ecdTaxonomy.aliases.values) alias.displayName,
        ...ecdSelectors,
        ...ecdDestinations,
      ];
      expect(words.where(gendered.hasMatch), isEmpty);
    });

    test(
      '"gypsy" is recognised as shoulder round and flagged, never named',
      () {
        final def = ecdTaxonomy.moves['ecd_shoulder_round']!;
        expect(def.searchKeywords, contains('gypsy'));
        expect(def.displayName, isNot(contains('gypsy')));
        expect(Dialect.defaultDiscouragedTerms, contains('gypsy'));
      },
    );

    test('swat the flea is box the gnat by the left, an inverse pair', () {
      final gnat = Figure(move: 'ecd_box_the_gnat', params: {'hand': 'left'});
      expect(ecdTaxonomy.resolvedMoveId(gnat), 'ecd_swat_the_flea');
      final flea = Figure(move: 'ecd_swat_the_flea', params: {'hand': 'right'});
      expect(ecdTaxonomy.resolvedMoveId(flea), 'ecd_box_the_gnat');
    });
  });

  group('who as a list (§5.2)', () {
    final spec = ecdTaxonomy.moves['ecd_circle']!.params['who']!;

    test('accepts one selector or several, in order', () {
      expect(spec.validate(['ones']), isTrue);
      expect(spec.validate(['twos', 'threes']), isTrue);
      expect(spec.validate(['leftFile']), isTrue);
      expect(spec.validate(['everyone']), isTrue);
      expect(spec.validate(['unspecified']), isTrue);
    });

    test('refuses everyone or unspecified beside another selector (Q1b)', () {
      expect(spec.validate(['everyone', 'ones']), isFalse);
      expect(spec.validate(['ones', 'unspecified']), isFalse);
    });

    test(
      'refuses an empty list, a repeat, an unknown token, a bare string',
      () {
        expect(spec.validate(<String>[]), isFalse);
        expect(spec.validate(['ones', 'ones']), isFalse);
        expect(spec.validate(['ladies']), isFalse);
        expect(spec.validate('ones'), isFalse);
      },
    );

    test('validateFigure reports an invalid list', () {
      final figure = invalidTestFigure(
        move: 'ecd_circle',
        params: {
          'who': ['everyone', 'ones'],
        },
        reason: 'everyone cannot be combined with another selector (Q1b)',
      );
      expect(ecdTaxonomy.validateFigure(figure).map((i) => i.code), [
        'invalid_param_value',
      ]);
    });

    test('renders as an English list, and says nothing when unstated', () {
      expect(
        _show(
          Figure(
            move: 'ecd_circle',
            params: {
              'who': ['twos', 'threes'],
              'direction': 'left',
            },
          ),
        ),
        'twos and threes, circle left',
      );
      expect(
        _show(
          Figure(
            move: 'ecd_star',
            params: {
              'who': ['unspecified'],
              'hand': 'right',
            },
          ),
        ),
        'right hands across',
      );
    });
  });

  group('display (ADR-006 §8)', () {
    test('The Farmer\'s Joy, A1 and B2 (§8.1)', () {
      final a1 = Figure.sequence(
        figures: [
          Figure(
            move: 'ecd_set',
            params: {
              'who': ['firstCorners'],
              'where': 'forward',
            },
          ),
          Figure(
            move: 'ecd_turn_single',
            params: {
              'who': ['firstCorners'],
              'destination': 'place',
            },
          ),
        ],
        beats: 8,
      );
      expect(
        _show(a1),
        'first corners set forward and turn single back to place',
      );
      final b2 = Figure.sequence(
        figures: [
          Figure(
            move: 'ecd_star',
            params: {
              'who': ['unspecified'],
              'hand': 'right',
              'beats': 8,
            },
          ),
          Figure(
            move: 'ecd_star',
            params: {
              'who': ['unspecified'],
              'hand': 'left',
              'destination': 'place',
              'beats': 8,
            },
          ),
        ],
        beats: 16,
      );
      expect(_show(b2), 'right hands across and back by the left');
      // The search text keeps both stars whole.
      expect(
        _renderer.renderCanonical(b2),
        'right hands across sequence left hands across, back to place',
      );
    });

    test('The American Husband, A2 (§8.2)', () {
      expect(
        _show(
          Figure(
            move: 'ecd_rights_and_lefts',
            params: {
              'who': ['ones', 'twos'],
              'whom': 'neighbors',
              'changes': 2,
              'where': 'diagonally',
            },
          ),
        ),
        'ones and twos dance 2 changes of rights and lefts, '
        'starting with neighbor diagonally',
      );
    });

    test('Alexander\'s Birth Day, poussette (§8.3)', () {
      expect(
        _show(
          Figure(
            move: 'ecd_poussette',
            params: {
              'who': ['role2s'],
              'whom': 'neighbors',
              'fraction': 'half',
            },
          ),
        ),
        'with neighbor, half poussette, role2s push',
      );
    });

    test('Midwinter Maggot, B5-6 (§8.4)', () {
      expect(
        _show(
          Figure(
            move: 'ecd_circle',
            params: {
              'singleFile': true,
              'direction': 'counterclockwise',
              'places': 2,
              'destination': 'originalPlaces',
            },
          ),
        ),
        'single file circle counter-clockwise 2 places, to original places',
      );
      expect(
        _show(Figure(move: 'ecd_turn_single', params: {'shoulder': 'left'})),
        'turn single left',
      );
    });

    test('a forward and back always shows its distance (§7.5)', () {
      expect(
        _show(
          Figure(
            move: 'ecd_forward_and_back',
            params: {
              'formation': 'linesOfThree',
              'where': 'forward',
              'goBack': true,
            },
          ),
        ),
        'lines of three forward a double and back',
      );
    });

    test('a star is worded as a return only after a star of the same '
        'dancers, stating no extent', () {
      Figure star(Map<String, Object?> params) =>
          testFigure(move: 'ecd_star', params: params);
      final back = star({
        'who': ['ones', 'twos'],
        'hand': 'left',
        'destination': 'place',
      });
      final there = star({
        'who': ['ones', 'twos'],
        'hand': 'right',
      });
      expect(
        _show(Figure.sequence(figures: [there, back], beats: 16)),
        'ones and twos, right hands across and back by the left',
      );
      final circle = testFigure(
        move: 'ecd_circle',
        params: {
          'who': ['twos', 'threes'],
          'direction': 'left',
        },
      );
      expect(
        _show(Figure.sequence(figures: [circle, back], beats: 16)),
        'twos and threes, circle left and ones and twos, left hands across, '
        'back to place',
      );
      final otherDancers = star({
        'who': ['threes', 'fours'],
        'hand': 'right',
      });
      expect(
        _show(Figure.sequence(figures: [otherDancers, back], beats: 16)),
        contains('ones and twos, left hands across'),
      );
      final farther = star({
        'who': ['ones', 'twos'],
        'hand': 'left',
        'places': 2,
        'destination': 'place',
      });
      expect(
        _show(Figure.sequence(figures: [there, farther], beats: 16)),
        contains('left hands across 2 places'),
      );
    });

    test('a run of changes with no count, and a direction-less forward and '
        'back, still name the movement', () {
      expect(
        _show(testFigure(move: 'ecd_grand_chain', params: {'changes': 6})),
        '6 changes of a grand chain',
      );
      expect(
        _show(
          testFigure(
            move: 'ecd_grand_chain',
            params: {'changes': 6, 'hand': 'right'},
          ),
        ),
        '6 changes of a grand chain by the right',
      );
      expect(
        _show(
          testFigure(
            move: 'ecd_circular_hey',
            params: {
              'who': ['everyone'],
            },
          ),
        ),
        'everyone dance a circular hey',
      );
      expect(
        _show(testFigure(move: 'ecd_rights_and_lefts')),
        'rights and lefts',
      );
      expect(
        _show(
          testFigure(move: 'ecd_forward_and_back', params: {'goBack': true}),
        ),
        'forward and back, a double',
      );
      expect(
        _renderer.renderCanonical(testFigure(move: 'ecd_forward_and_back')),
        'forward and back, a double',
      );
    });

    test('cloverleaf turn single and draw poussette (§9.3)', () {
      expect(
        _show(
          testFigure(
            move: 'ecd_turn_single',
            params: {
              'who': ['everyone'],
              'shoulder': 'cloverleaf',
            },
          ),
        ),
        'everyone cloverleaf turn single',
      );
      Figure poussette(String style) => testFigure(
        move: 'ecd_poussette',
        params: {
          'who': ['role2s'],
          'fraction': 'half',
          'style': style,
        },
      );
      expect(_show(poussette('draw')), 'half poussette, role2s draw');
      expect(_show(poussette('push')), 'half poussette, role2s push');
      expect(
        _show(poussette(ParamVocab.unspecified)),
        'half poussette, role2s push',
      );
      // A stated style or switch is kept when no dancers are named.
      expect(
        _show(
          testFigure(
            move: 'ecd_poussette',
            params: {'fraction': 'half', 'style': 'draw'},
          ),
        ),
        'half poussette, draw',
      );
      expect(
        _show(
          testFigure(
            move: 'ecd_poussette',
            params: {'fraction': 'half', 'switchPush': true},
          ),
        ),
        'half poussette, push first',
      );
    });

    test('a set shows its side only when it is not right (§7.1)', () {
      Figure set(String direction) => testFigure(
        move: 'ecd_set',
        params: {
          'who': ['partners'],
          'direction': direction,
        },
      );
      expect(_show(set('right')), 'partner set');
      expect(_show(set('left')), 'partner set left');
      expect(_renderer.renderCanonical(set('right')), 'partners set right');
    });

    test('every movement renders at its suggested values', () {
      final taxonomy = shippedTaxonomies.forForm(DanceForm.ecd);
      for (final id in ecdTaxonomy.moves.keys) {
        final figure = testFigure(move: id, params: taxonomy.entryParams(id));
        expect(taxonomy.validateFigure(figure), isEmpty, reason: id);
        final line = _show(figure);
        expect(line, isNotEmpty, reason: id);
        expect(line, isNot(contains(RegExp(r'[\[\]{}]|unspecified'))));
        expect(line, isNot(matches(RegExp(r'^[,:]|[,:]$|\s[,:]'))));
      }
    });
  });

  group('the template notation (§6.3)', () {
    test('drops a group when a value inside it is empty', () {
      expect(
        expandEcdTemplate('{who} cast [around {whom}] [to {where}]', {
          'who': 'ones',
          'whom': '',
          'where': 'second place',
        }, const {}),
        'ones cast to second place',
      );
    });

    test('keeps a {?flag} group only while the flag is set', () {
      const template = '{move} [{?goBack}and back]';
      expect(
        expandEcdTemplate(template, {'move': 'up a double'}, {'goBack': true}),
        'up a double and back',
      );
      expect(
        expandEcdTemplate(template, {'move': 'up a double'}, {'goBack': false}),
        'up a double',
      );
    });

    test('leaves no stray comma or colon', () {
      expect(
        expandEcdTemplate('[{who},] {move} [, {where}]', {
          'who': '',
          'move': 'circle',
          'where': '',
        }, const {}),
        'circle',
      );
    });

    test('words each destination (§6.4)', () {
      expect(ecdDestinationPhrase('place'), 'back to place');
      expect(ecdDestinationPhrase('secondPlace'), 'to second place');
      expect(ecdDestinationPhrase('partnersPlace'), "to partner's place");
      expect(ecdDestinationPhrase('allImproper'), 'ending improper');
      expect(ecdDestinationPhrase(ParamVocab.unspecified), '');
      expect(ecdDestinationPhrase(null), '');
    });
  });

  group('cast (§7.5, §9.4)', () {
    String cast(Map<String, Object?> params) =>
        _show(testFigure(move: 'ecd_cast', params: params));

    test('takes contra cast\'s parameter shape', () {
      final def = ecdTaxonomy.moves['ecd_cast']!;
      expect(def.params.keys.toSet(), {
        'who',
        'direction',
        'places',
        'whom',
        'destination',
        'beats',
      });
      expect(def.params['direction']!.kind, ParamKind.choice);
      expect(def.params['direction']!.choices, [
        'left',
        'right',
        'up',
        'down',
        ParamVocab.unspecified,
      ]);
      expect(def.params['places']!.kind, ParamKind.places);
      expect(def.params['places']!.choices, [ParamVocab.unspecified]);
      expect(
        def.params['destination']!.choices,
        containsAll(['top', 'bottom', 'secondPlace', ParamVocab.unspecified]),
      );
      expect(def.params['destination']!.choices!.last, ParamVocab.unspecified);
      expect(def.params['beats']!.defaultValue, 4);
      // Only a cast ends at the top or bottom.
      expect(ecdDestinations, isNot(contains('top')));
      expect(ecdDestinations, isNot(contains('bottom')));
    });

    test('reads back when no direction is stated', () {
      expect(cast({}), 'cast back');
      expect(
        cast({
          'who': ['ones'],
        }),
        'ones cast back',
      );
    });

    test('a shoulder is always shown, whoever casts', () {
      // Never hidden as a role's usual shoulder, unlike a chain's hand.
      expect(
        cast({
          'who': ['role2s'],
          'direction': 'right',
        }),
        'role2s cast back right',
      );
      expect(
        cast({
          'who': ['role1s'],
          'direction': 'left',
        }),
        'role1s cast back left',
      );
    });

    test('a shoulder reads back left or back right', () {
      expect(
        cast({
          'who': ['ones'],
          'direction': 'left',
        }),
        'ones cast back left',
      );
      expect(cast({'direction': 'right'}), 'cast back right');
    });

    test('up and down read on their own, with any places', () {
      expect(
        cast({
          'who': ['ones'],
          'direction': 'down',
          'places': 1,
        }),
        'ones cast down 1 place',
      );
      expect(
        cast({
          'who': ['twos'],
          'direction': 'up',
          'places': 2,
        }),
        'twos cast up 2 places',
      );
    });

    test('around whom, and to a destination, including the bottom', () {
      expect(
        cast({
          'who': ['ones'],
          'whom': 'twos',
        }),
        'ones cast back around twos',
      );
      expect(
        cast({
          'who': ['ones'],
          'direction': 'down',
          'destination': 'bottom',
        }),
        'ones cast down to the bottom',
      );
      expect(
        cast({
          'who': ['ones'],
          'direction': 'down',
          'destination': 'secondPlace',
        }),
        'ones cast down to second place',
      );
    });

    test('a return to place never reads back twice', () {
      expect(
        cast({
          'who': ['ones'],
          'destination': 'place',
        }),
        'ones cast back to place',
      );
      expect(
        cast({'direction': 'left', 'destination': 'place'}),
        'cast back left to place',
      );
      expect(
        cast({'direction': 'down', 'destination': 'place'}),
        'cast down to place',
      );
    });

    test('canonical text words the direction as the display does', () {
      expect(
        _renderer.renderCanonical(
          testFigure(
            move: 'ecd_cast',
            params: {
              'who': ['ones'],
              'direction': 'down',
            },
          ),
        ),
        'ones cast down',
      );
    });

    test('a hand cast is a listed alias of gate that pins nothing', () {
      final alias = ecdTaxonomy.aliases['ecd_hand_cast']!;
      expect(alias.targetMove, 'ecd_gate');
      expect(alias.pinnedParams, isEmpty);
      expect(alias.listedAsMove, isTrue);
      expect(ecdTaxonomy.resolve('ecd_hand_cast')?.id, 'ecd_gate');
      expect(
        _show(
          testFigure(
            move: 'ecd_hand_cast',
            params: {
              'who': ['ones'],
            },
          ),
        ),
        'ones hand cast',
      );
      // Its wording starts from gate's slots, so a wording keeps the dancers.
      expect(
        _renderer.moveWordingSlots('ecd_hand_cast'),
        _renderer.moveWordingSlots('ecd_gate'),
      );
      expect(
        _renderer.moveWordingErrorMissingSlots('ecd_hand_cast', '{move}'),
        containsAll(['who', 'whom']),
      );
      expect(
        ecdTaxonomy.moves['ecd_cast']!.searchKeywords,
        contains('cast off'),
      );
    });
  });

  group('a sequence\'s span (§5.5)', () {
    Figure step({int? beats}) =>
        testFigure(move: 'ecd_set', params: {'beats': ?beats});

    Figure sequence(List<Figure> steps, int span) =>
        Figure.sequence(figures: steps, beats: span);

    test('untimed steps share the span', () {
      expect(
        sequenceSpanIssue(sequence([step(), step()], 8), DanceForm.ecd),
        isNull,
      );
    });

    test('timed steps must add up to the span', () {
      expect(
        sequenceSpanIssue(
          sequence([step(beats: 4), step(beats: 4)], 8),
          DanceForm.ecd,
        ),
        isNull,
      );
      final issue = sequenceSpanIssue(
        sequence([step(beats: 4), step(beats: 8)], 8),
        DanceForm.ecd,
      );
      expect(issue?.code, 'sequence_span_mismatch');
      expect(issue?.severity, ValidationSeverity.warning);
      expect(issue?.data, {'actual': 12, 'expected': 8, 'allTimed': true});
    });

    test('timed steps must leave time for the untimed', () {
      expect(
        sequenceSpanIssue(sequence([step(beats: 4), step()], 8), DanceForm.ecd),
        isNull,
      );
      expect(
        sequenceSpanIssue(
          sequence([step(beats: 8), step()], 8),
          DanceForm.ecd,
        )?.code,
        'sequence_span_mismatch',
      );
    });

    test('contra keeps its own contract', () {
      expect(
        sequenceSpanIssue(
          sequence([step(beats: 4), step(beats: 8)], 8),
          DanceForm.contra,
        ),
        isNull,
      );
    });

    test('a square has spans too (ADR-007 Q10); contra alone has none', () {
      expect(
        {for (final form in DanceForm.values) form: formHasSequenceSpan(form)},
        {DanceForm.contra: false, DanceForm.ecd: true, DanceForm.square: true},
      );
      expect(
        sequenceSpanIssue(
          sequence([step(beats: 4), step(beats: 8)], 8),
          DanceForm.square,
        )?.data,
        {'actual': 12, 'expected': 8, 'allTimed': true},
      );
      expect(
        sequenceSpanIssue(sequence([step(), step()], 8), DanceForm.square),
        isNull,
      );
    });
  });
}

void _ecdKeywordsNameOneMove() {
  test('no ECD search keyword names two movements', () {
    final names = <String, Set<String>>{};
    for (final m in ecdTaxonomy.moves.values) {
      for (final k in m.searchKeywords) {
        (names[k.toLowerCase()] ??= {}).add(m.displayName);
      }
    }
    for (final a in ecdTaxonomy.aliases.values) {
      for (final k in a.searchKeywords) {
        (names[k.toLowerCase()] ??= {}).add(a.displayName);
      }
    }
    expect({
      for (final e in names.entries)
        if (e.value.length > 1) e.key: e.value,
    }, isEmpty);
  });
}

void _heyStartersEachShown() {
  test('a hey shows a stated who or whom on its own', () {
    Figure hey(String move, Map<String, Object?> params) =>
        testFigure(move: move, params: params);
    expect(
      _show(
        hey('ecd_hey_for_three', {
          'who': ['ones'],
        }),
      ),
      'hey for three, ones',
    );
    expect(
      _show(hey('ecd_hey_for_four', {'whom': 'neighbors'})),
      'hey for four, pass neighbor',
    );
    expect(
      _show(
        hey('ecd_hey_for_six', {
          'who': ['ones'],
          'whom': 'neighbors',
        }),
      ),
      'hey for six, ones pass neighbor',
    );
    expect(
      _show(hey('ecd_dolphin_hey', {'whom': 'neighbors'})),
      'dolphin hey: pass neighbor',
    );
  });
}
