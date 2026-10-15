import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/editor_snapshot.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';

/// A dance-editor row that is one of the user's own compound figures, until
/// the dance is saved (#709).
void main() {
  /// The maintainer's worked example: four pull-bys alternating hands.
  CompoundDefinition grandRightAndLeft() {
    Figure pullBy({String? note}) => Figure(
      move: 'pull_by',
      params: const {'who': 'neighbors', 'hand': 'right', 'beats': 2},
      note: note,
    );
    return CompoundDefinition(
      params: const [
        CompoundParam(key: 'who', kind: ParamKind.dancerSet),
        CompoundParam(key: 'hand', kind: ParamKind.handedness),
      ],
      figures: [
        pullBy(note: 'look at them'),
        pullBy(),
        pullBy(),
        pullBy(),
      ],
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
  }

  CompoundDefinition? resolve(String id) =>
      id == 'grl' ? grandRightAndLeft() : null;

  FigureDraft placeholder({
    Map<String, Object?> args = const {'who': 'partners', 'hand': 'left'},
    String note = '',
    bool progression = false,
    String name = 'grand right and left',
  }) => FigureDraft(
    note: note,
    progression: progression,
    compound: CompoundPlaceholder(
      id: 'grl',
      name: name,
      args: {...args},
      beats: 8,
    ),
  );

  group('toFigures', () {
    test('expands a placeholder with its arguments', () {
      final figures = placeholder().toFigures(resolveCompound: resolve);
      expect([for (final f in figures) f.move], List.filled(4, 'pull_by'));
      expect([
        for (final f in figures) f.params['who'],
      ], List.filled(4, 'partners'));
      expect(
        [for (final f in figures) f.params['hand']],
        ['left', 'right', 'left', 'right'],
      );
    });

    test('puts the note on the first figure, after its own, and the '
        'progression mark on the last', () {
      final figures = placeholder(
        note: '  Larks lead  ',
        progression: true,
      ).toFigures(resolveCompound: resolve, canonicalizeNote: (n) => n.trim());
      expect(figures.first.note, 'look at them; Larks lead');
      expect(
        [for (final f in figures) f.progression],
        [false, false, false, true],
      );
    });

    test('a compound that is gone becomes one custom figure with its stored '
        'name, which the note canonicalizer never touches', () {
      // A stand-in canonicalizer that would visibly change any text it saw.
      String shout(String text) => text.trim().toUpperCase();
      final figures = placeholder(
        name: 'the role2 follows',
        note: 'note',
      ).toFigures(resolveCompound: (_) => null, canonicalizeNote: shout);
      expect(figures, hasLength(1));
      final fallback = figures.single;
      expect(fallback.move, customMove);
      expect(fallback.params['text'], 'the role2 follows');
      expect(fallback.params['beats'], 8, reason: 'the last expansion\'s');
      expect(fallback.note, 'NOTE');
    });

    test('arguments the compound no longer accepts fall back, too', () {
      final figures = placeholder(
        args: const {'who': 'partners', 'hand': 'sideways'},
      ).toFigures(resolveCompound: resolve);
      expect(figures.single.move, customMove);
    });

    test('toFigure builds the fallback, so nothing that reads one figure per '
        'row sees a placeholder', () {
      expect(placeholder().toFigure()!.move, customMove);
    });

    test('an ordinary row builds its one figure', () {
      final draft = FigureDraft(move: 'swing', params: {'who': 'partners'});
      expect(
        draft.toFigures(resolveCompound: resolve).single.move,
        draft.toFigure()!.move,
      );
      expect(FigureDraft().toFigures(resolveCompound: resolve), isEmpty);
    });
  });

  test('a placeholder never nests in a container, in either kind', () {
    final draft = placeholder();
    expect(draft.canNestInContainer(modifierParent: false), isFalse);
    expect(draft.canNestInContainer(modifierParent: true), isFalse);
  });

  test('a clone has its own copy of the arguments', () {
    final source = placeholder();
    final clone = source.clone();
    clone.compound!.args['hand'] = 'right';
    expect(clone.compound!.id, 'grl');
    expect(clone.compound!.beats, 8);
    expect(source.compound!.args['hand'], 'left');
  });

  test('a snapshot round-trips the placeholder and does not share it', () {
    final source = placeholder();
    final snapshot = FigureDraftSnapshot.fromDraft(source);
    source.compound!.args['hand'] = 'right';
    final restored = snapshot.toDraft();
    expect(restored.compound!.args, {'who': 'partners', 'hand': 'left'});
    expect(restored.compound!.name, 'grand right and left');
  });

  group('autosave draft', () {
    EditorSnapshot snapshotOf(List<FigureDraft> drafts) => EditorSnapshot(
      title: 'Test',
      hook: '',
      notes: '',
      phrase: '',
      formationDetail: '',
      form: DanceForm.contra,
      formationShape: FormationShape.dupleImproper,
      progression: Progression.single,
      status: DanceStatus.active,
      authorIds: const [],
      tagIds: const [],
      tunes: const [],
      links: const [],
      sourceCitations: const [],
      customValues: const {},
      figureDrafts: [for (final d in drafts) FigureDraftSnapshot.fromDraft(d)],
      stagedTags: const [],
    );

    test('a placeholder round-trips, and the draft is stamped v14', () {
      final encoded = encodeDraft(
        snapshotOf([placeholder(note: 'n', progression: true)]),
      );
      expect((jsonDecode(encoded) as Map)['v'], 14);
      final restored = decodeDraft(encoded).figureDrafts.single.toDraft();
      expect(restored.move, isNull);
      expect(restored.note, 'n');
      expect(restored.progression, isTrue);
      expect(restored.compound!.id, 'grl');
      expect(restored.compound!.name, 'grand right and left');
      expect(restored.compound!.args, {'who': 'partners', 'hand': 'left'});
      expect(restored.compound!.beats, 8);
    });

    test('a draft with no placeholder stays v13, which older builds read', () {
      final encoded = encodeDraft(
        snapshotOf([
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
        ]),
      );
      expect((jsonDecode(encoded) as Map)['v'], 13);
      expect(decodeDraft(encoded).figureDrafts.single.compound, isNull);
    });

    Map<String, Object?> withRow(Map<String, Object?> row) =>
        (jsonDecode(encodeDraft(snapshotOf(const []))) as Map)
            .cast<String, Object?>()
          ..['v'] = 14
          ..['figureDrafts'] = [row];

    Map<String, Object?> row(Object? compound, {String? move}) => {
      'id': 'r1',
      'move': move,
      'params': const <String, Object?>{},
      'note': '',
      'progression': false,
      'sv': figureSchemaVersion,
      'compound': compound,
    };

    test('a malformed placeholder is refused', () {
      for (final bad in <Object?>[
        'grl',
        {'name': 'x', 'args': <String, Object?>{}},
        {'id': '', 'name': 'x', 'args': <String, Object?>{}},
        {'id': 'grl', 'args': <String, Object?>{}},
        {'id': 'grl', 'name': 'x', 'args': 'hand=left'},
        {'id': 'grl', 'name': 'x', 'args': <String, Object?>{}, 'beats': -1},
      ]) {
        expect(
          () => decodeDraft(withRow(row(bad))),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('a placeholder with a move, or inside a container, is refused', () {
      const compound = {'id': 'grl', 'name': 'x', 'args': <String, Object?>{}};
      expect(
        () => decodeDraft(withRow(row(compound, move: 'swing'))),
        throwsFormatException,
      );
      expect(
        () => decodeDraft(
          withRow({
            ...row(null),
            'containerKind': meanwhileMove,
            'children': [
              {...row(compound), 'id': 'a'},
              {...row(null, move: 'swing'), 'id': 'b'},
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  });
}
