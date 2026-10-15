import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// User compound figures' core semantics (#709).
void main() {
  final taxonomy = contraTaxonomy;
  const u = ParamVocab.unspecified;

  Figure pullBy({String hand = 'right'}) => Figure(
    move: 'pull_by',
    params: {'who': 'neighbors', 'hand': hand, 'beats': 2},
  );

  /// The maintainer's worked example: grand right and left, four pull-bys
  /// alternating hands, taking a `who` and a starting `hand`.
  CompoundDefinition grandRightAndLeft() => CompoundDefinition(
    params: const [
      CompoundParam(key: 'who', kind: ParamKind.dancerSet),
      CompoundParam(key: 'hand', kind: ParamKind.handedness),
    ],
    figures: [pullBy(), pullBy(), pullBy(), pullBy()],
    bindings: [
      for (var i = 0; i < 4; i++) ...[
        CompoundSlotBinding(figureIndex: i, slotKey: 'who', paramKey: 'who'),
        CompoundSlotBinding(
          figureIndex: i,
          slotKey: 'hand',
          paramKey: 'hand',
          source: i.isEven
              ? CompoundBindingSource.declared
              : CompoundBindingSource.opposite,
        ),
      ],
    ],
  );

  List<ValidationIssue> errors(CompoundDefinition d) => [
    for (final issue in validateCompound(d, taxonomy))
      if (issue.severity == ValidationSeverity.error) issue,
  ];

  group('expansion', () {
    test('grand right and left writes the raw opposite on alternate parts', () {
      final expanded = expandCompound(grandRightAndLeft(), {
        'who': 'neighbors',
        'hand': 'right',
      }, taxonomy)!;
      expect([for (final f in expanded) f.move], List.filled(4, 'pull_by'));
      expect(
        [for (final f in expanded) f.params['hand']],
        ['right', 'left', 'right', 'left'],
      );
      expect([
        for (final f in expanded) f.params['who'],
      ], List.filled(4, 'neighbors'));
      expect(CompoundDefinition.beatsOf(expanded, taxonomy), 8);
    });

    test('a bound balance carries the editor\'s 4 beats', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'bal', kind: ParamKind.flag)],
        figures: [pullBy()],
        bindings: const [
          CompoundSlotBinding(
            figureIndex: 0,
            slotKey: 'balance',
            paramKey: 'bal',
          ),
        ],
      );
      final on = expandCompound(definition, {'bal': true}, taxonomy)!;
      expect(on.single.params['balance'], isTrue);
      expect(on.single.params['beats'], 6);
      final off = expandCompound(definition, {'bal': false}, taxonomy)!;
      expect(off.single.params['beats'], 2);
    });

    test('a bound chain role carries its role-implied hand', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'who', kind: ParamKind.dancerSet)],
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'hand': 'right'}),
        ],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'who'),
        ],
      );
      final expanded = expandCompound(definition, {'who': 'role1s'}, taxonomy)!;
      expect(expanded.single.params['hand'], 'left');
    });

    test('slots are set in the order the move declares them, whatever order '
        'the bindings were saved in', () {
      // chain's `who` re-seeds `hand`: set after it, a bound hand wins.
      const who = CompoundSlotBinding(
        figureIndex: 0,
        slotKey: 'who',
        paramKey: 'who',
      );
      const hand = CompoundSlotBinding(
        figureIndex: 0,
        slotKey: 'hand',
        paramKey: 'hand',
      );
      for (final bindings in [
        [who, hand],
        [hand, who],
      ]) {
        final definition = CompoundDefinition(
          params: const [
            CompoundParam(key: 'who', kind: ParamKind.dancerSet),
            CompoundParam(key: 'hand', kind: ParamKind.handedness),
          ],
          figures: [
            Figure(move: 'chain', params: {'who': 'role2s', 'hand': 'right'}),
          ],
          bindings: bindings,
        );
        final expanded = expandCompound(definition, {
          'who': 'role1s',
          'hand': 'right',
        }, taxonomy)!;
        expect(
          expanded.single.params,
          containsPair('hand', 'right'),
          reason: '${bindings.map((b) => b.slotKey)}',
        );
        expect(expanded.single.params, containsPair('who', 'role1s'));
      }
    });

    test('a template that states its beats keeps them when a bound value '
        'moves the canonical default; one that does not snaps to it', () {
      CompoundDefinition swing({required bool statedBeats}) =>
          CompoundDefinition(
            params: const [CompoundParam(key: 'pre', kind: ParamKind.choice)],
            figures: [
              Figure(
                move: 'swing',
                params: {'who': 'partners', if (statedBeats) 'beats': 8},
              ),
            ],
            bindings: const [
              CompoundSlotBinding(
                figureIndex: 0,
                slotKey: 'prefix',
                paramKey: 'pre',
              ),
            ],
          );
      final stated = expandCompound(swing(statedBeats: true), {
        'pre': 'balance',
      }, taxonomy)!;
      expect(stated.single.params['beats'], 8);
      final unstated = expandCompound(swing(statedBeats: false), {
        'pre': 'balance',
      }, taxonomy)!;
      expect(unstated.single.params['beats'], 16);
    });

    test('an inverse pair reroutes on a bound value', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 's', kind: ParamKind.shoulder)],
        figures: [
          Figure(move: 'do_si_do', params: {'who': 'partners'}),
        ],
        bindings: const [
          CompoundSlotBinding(
            figureIndex: 0,
            slotKey: 'shoulder',
            paramKey: 's',
          ),
        ],
      );
      expect(
        expandCompound(definition, {'s': 'left'}, taxonomy)!.single.move,
        'see_saw',
      );
    });

    test('is deterministic', () {
      final args = {'who': 'role1s', 'hand': 'left'};
      expect(
        [
          for (final f in expandCompound(grandRightAndLeft(), args, taxonomy)!)
            figureToJson(f),
        ],
        [
          for (final f in expandCompound(grandRightAndLeft(), args, taxonomy)!)
            figureToJson(f),
        ],
      );
    });

    test('declines rather than fabricate', () {
      final d = grandRightAndLeft();
      expect(expandCompound(d, {'who': 'neighbors'}, taxonomy), isNull);
      expect(
        expandCompound(d, {'who': 'neighbors', 'hand': 'sideways'}, taxonomy),
        isNull,
      );
      expect(
        expandCompound(d, {'who': 'nobody', 'hand': 'right'}, taxonomy),
        isNull,
      );
    });
  });

  group('allowed values', () {
    test('an unbound parameter takes its kind\'s vocabulary; free text is '
        'null; an undeclared key is empty', () {
      final definition = CompoundDefinition(
        params: const [
          CompoundParam(key: 'hand', kind: ParamKind.handedness),
          CompoundParam(key: 'slide', kind: ParamKind.choice),
          CompoundParam(key: 'words', kind: ParamKind.text),
        ],
        figures: [pullBy()],
        bindings: const [],
      );
      expect(allowedValues(definition, 'hand', taxonomy), {
        ...ParamVocab.sides,
        u,
      });
      expect(allowedValues(definition, 'slide', taxonomy), isEmpty);
      expect(allowedValues(definition, 'words', taxonomy), isNull);
      expect(allowedValues(definition, 'nope', taxonomy), isEmpty);
    });

    test('are the overlap of every slot a parameter fills', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'who', kind: ParamKind.dancerSet)],
        figures: [
          pullBy(),
          Figure(move: 'chain'),
        ],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(figureIndex: 1, slotKey: 'who', paramKey: 'who'),
        ],
      );
      expect(allowedValues(definition, 'who', taxonomy), {'role1s', 'role2s'});
    });

    test('using a partial opposite keeps only values that have one', () {
      expect(allowedValues(grandRightAndLeft(), 'who', taxonomy), {
        'everyone',
        ...ParamVocab.dancerSets,
        u,
      });
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'who', kind: ParamKind.dancerSet)],
        figures: [pullBy(), pullBy()],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(
            figureIndex: 1,
            slotKey: 'who',
            paramKey: 'who',
            source: CompoundBindingSource.opposite,
          ),
        ],
      );
      expect(allowedValues(definition, 'who', taxonomy), {
        'role1s',
        'role2s',
        'ones',
        'twos',
        'firstCorners',
        'secondCorners',
        u,
      });
      expect(
        expandCompound(definition, {'who': 'partners'}, taxonomy),
        isNull,
        reason: 'partners has no other pair',
      );
      expect(
        expandCompound(definition, {
          'who': 'ones',
        }, taxonomy)!.map((f) => f.params['who']),
        ['ones', 'twos'],
      );
    });
  });

  group('validation', () {
    test('the worked example is valid with no warnings', () {
      expect(validateCompound(grandRightAndLeft(), taxonomy), isEmpty);
    });

    test('an unused declared parameter warns; an unused opposite does not', () {
      final definition = CompoundDefinition(
        params: const [
          CompoundParam(key: 'who', kind: ParamKind.dancerSet),
          CompoundParam(key: 'hand', kind: ParamKind.handedness),
        ],
        figures: [pullBy()],
        bindings: const [
          CompoundSlotBinding(
            figureIndex: 0,
            slotKey: 'hand',
            paramKey: 'hand',
          ),
        ],
      );
      final issues = validateCompound(definition, taxonomy);
      expect(issues.map((i) => (i.severity, i.code)), [
        (ValidationSeverity.warning, CompoundIssueCodes.unusedParam),
      ]);
      expect(issues.single.data['param'], 'who');
    });

    test('a slot of another kind is a type mismatch', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'hand', kind: ParamKind.handedness)],
        figures: [pullBy()],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'hand'),
        ],
      );
      expect(errors(definition).map((i) => i.code), [
        CompoundIssueCodes.typeMismatch,
      ]);
    });

    test('a choice-kind left/right has no opposite', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'd', kind: ParamKind.choice)],
        figures: [Figure(move: 'circle')],
        bindings: const [
          CompoundSlotBinding(
            figureIndex: 0,
            slotKey: 'direction',
            paramKey: 'd',
            source: CompoundBindingSource.opposite,
          ),
        ],
      );
      expect(
        errors(definition).map((i) => i.code),
        contains(CompoundIssueCodes.noOpposite),
      );
    });

    test('no value fitting every slot is an error', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'who', kind: ParamKind.dancerSet)],
        figures: [
          Figure(move: 'chain'),
          Figure(move: 'figure_8'),
        ],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(figureIndex: 1, slotKey: 'lead', paramKey: 'who'),
        ],
      );
      expect(errors(definition).map((i) => i.code), [
        CompoundIssueCodes.emptyDomain,
      ]);
    });

    test('custom, container and nested-compound templates are refused', () {
      for (final figure in [
        Figure(move: customMove, params: {'text': 'x', 'beats': 8}),
        Figure.meanwhile(
          figures: [
            Figure(move: 'allemande'),
            Figure(move: 'orbit'),
          ],
          beats: 8,
        ),
        Figure.modifier(
          figures: [
            Figure(move: 'balance'),
            Figure(move: 'swing'),
          ],
          beats: 16,
        ),
        Figure(move: 'some_user_compound'),
      ]) {
        final definition = CompoundDefinition(
          params: const [],
          figures: [figure],
          bindings: const [],
        );
        expect(
          errors(definition).map((i) => i.code),
          contains(CompoundIssueCodes.badTemplate),
          reason: figure.move,
        );
      }
    });

    test('bound beats, a double binding and a dangling one are errors', () {
      final definition = CompoundDefinition(
        params: const [
          CompoundParam(key: 'b', kind: ParamKind.beats),
          CompoundParam(key: 'who', kind: ParamKind.dancerSet),
        ],
        figures: [pullBy()],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'beats', paramKey: 'b'),
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(figureIndex: 3, slotKey: 'who', paramKey: 'who'),
        ],
      );
      expect(errors(definition).map((i) => i.code).toSet(), {
        CompoundIssueCodes.beatsBinding,
        CompoundIssueCodes.doubleBinding,
        CompoundIssueCodes.danglingBinding,
      });
    });
  });

  group('codec', () {
    test('round-trips', () {
      final json = grandRightAndLeft().toJson();
      final decoded = decodeCompoundDefinition(json, taxonomy)!;
      expect(decoded.toJson(), json);
    });

    test('brings legacy template ids up to date as it reads them', () {
      final json = grandRightAndLeft().toJson();
      final figures = [
        for (final f in json['figures']! as List)
          {...(f as Map<String, Object?>), 'move': 'pull_by_dancers'},
      ];
      final decoded = decodeCompoundDefinition({
        ...json,
        'figures': figures,
      }, taxonomy)!;
      expect(decoded.figures.map((f) => f.move), List.filled(4, 'pull_by'));
    });

    test('anything it cannot use is null, never a throw', () {
      final good = grandRightAndLeft().toJson();
      final bad = <Object?>[
        null,
        'text',
        42,
        <String, Object?>{},
        {...good, 'params': 'x'},
        {
          ...good,
          'params': [
            {'key': 'who', 'kind': 'notAKind'},
          ],
        },
        {
          ...good,
          'figures': [
            {'move': 'not_a_move'},
          ],
        },
        {
          ...good,
          'bindings': [
            {'figure': 'zero', 'slot': 'who', 'param': 'who', 'source': 'x'},
          ],
        },
        {
          ...good,
          'figures': List.filled(
            maxCompoundFigures + 1,
            figureToJson(pullBy()),
          ),
        },
        {
          ...good,
          'bindings': [
            {'figure': -1, 'slot': 'who', 'param': 'who', 'source': 'declared'},
          ],
        },
      ];
      for (final raw in bad) {
        expect(
          () => decodeCompoundDefinition(raw, taxonomy),
          returnsNormally,
          reason: '$raw',
        );
        expect(decodeCompoundDefinition(raw, taxonomy), isNull, reason: '$raw');
      }
    });

    test('a definition with only warnings still decodes', () {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'who', kind: ParamKind.dancerSet)],
        figures: [pullBy()],
        bindings: const [],
      );
      expect(
        decodeCompoundDefinition(definition.toJson(), taxonomy),
        isNotNull,
      );
    });
  });
}
