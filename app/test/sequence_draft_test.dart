import 'dart:convert';

import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/editor_snapshot.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The editor's `sequence` draft: its derived count, how it builds, which
/// groupings and conversions it allows, and the autosave round-trip.
void main() {
  FigureDraft step(String move, int beats, {String? who}) => FigureDraft(
    move: move,
    params: {'beats': beats, 'who': ?who},
    beatsTouched: true,
  );

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

  group('FigureDraft sequence', () {
    test('counts the sum of its steps, ignoring a stale shared count', () {
      final draft = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      )..params['beats'] = 99;
      expect(draft.isSequenceGroup, isTrue);
      expect(draft.containerKind, sequenceMove);
      expect(draft.beats, 16);
    });

    test('builds a sequence whose count is its built steps', () {
      final figure = FigureDraft(
        sequenceFigures: [step('balance', 4), FigureDraft(), step('swing', 12)],
      ).toFigure()!;
      expect(figure.isSequence, isTrue);
      expect(figure.beats, 16);
      expect(figure.subFigures.map((f) => f.move), ['balance', 'swing']);
      expect(figure.subFigures.map((f) => f.beats), [4, 12]);
    });

    test('round-trips through fromFigure', () {
      final figure = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      ).toFigure()!;
      expect(FigureDraft.fromFigure(figure).toFigure(), figure);
    });

    test('clones its steps independently', () {
      final draft = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      );
      final copy = draft.clone();
      copy.sequenceFigures!.first.params['beats'] = 8;
      expect(draft.beats, 16);
      expect(copy.beats, 20);
    });

    test('nests only inside another kind', () {
      final sequence = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      );
      expect(sequence.canNestInContainer(meanwhileMove), isTrue);
      expect(sequence.canNestInContainer(modifierMove), isTrue);
      expect(sequence.canNestInContainer(sequenceMove), isFalse);
    });
  });

  group('grouping and conversion', () {
    test('groups two rows as a sequence while they fit one phrase', () {
      final fits = [step('balance', 4), step('swing', 12)];
      expect(
        FigureDraft.canGroup(
          sequenceMove,
          fits[0],
          fits[1],
          sequenceBeatLimit: 16,
        ),
        isTrue,
      );
      final group = FigureDraft.group(sequenceMove, fits[0], fits[1]);
      expect(group.sequenceFigures, fits);
      expect(group.beats, 16);
      expect(
        FigureDraft.canGroup(
          sequenceMove,
          step('swing', 12),
          step('swing', 8),
          sequenceBeatLimit: 16,
        ),
        isFalse,
      );
      // The phrase limit is the sequence's alone.
      expect(
        FigureDraft.canGroup(
          meanwhileMove,
          step('swing', 12),
          step('swing', 8),
          sequenceBeatLimit: 16,
        ),
        isTrue,
      );
    });

    test('converts to a sequence only within its caps', () {
      final meanwhile = FigureDraft(
        meanwhileSides: [step('allemande', 8), step('orbit', 8)],
      )..params['beats'] = 8;
      expect(
        meanwhile.canConvertContainerTo(sequenceMove, sequenceBeatLimit: 16),
        isTrue,
      );
      expect(
        meanwhile.canConvertContainerTo(sequenceMove, sequenceBeatLimit: 12),
        isFalse,
      );
      final five = FigureDraft(
        meanwhileSides: [for (var i = 0; i < 5; i++) step('balance', 2)],
      );
      expect(
        five.canConvertContainerTo(sequenceMove, sequenceBeatLimit: 16),
        isFalse,
      );
    });

    test('a nested container of the target kind blocks conversion', () {
      final nestedSequence = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 4)],
      );
      final meanwhile = FigureDraft(
        meanwhileSides: [nestedSequence, step('orbit', 8)],
      )..params['beats'] = 8;
      expect(
        meanwhile.canConvertContainerTo(sequenceMove, sequenceBeatLimit: 16),
        isFalse,
      );
      expect(
        meanwhile.canConvertContainerTo(modifierMove, sequenceBeatLimit: 16),
        isTrue,
      );
    });

    test('leaving a sequence keeps its total as the shared count', () {
      final draft = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      );
      draft.convertContainerTo(meanwhileMove);
      expect(draft.isMeanwhileGroup, isTrue);
      expect(draft.isSequenceGroup, isFalse);
      expect(draft.beats, 16);
      expect(draft.beatsTouched, isTrue);
    });
  });

  group('autosave codec', () {
    test('round-trips a sequence nested in a meanwhile', () {
      final sequence = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      );
      final meanwhile = FigureDraft(
        meanwhileSides: [sequence, step('orbit', 16)],
      )..params['beats'] = 16;
      final decoded = decodeDraft(encodeDraft(snapshotOf([meanwhile])));
      final restored = decoded.figureDrafts.single.toDraft();
      expect(restored.toFigure(), meanwhile.toFigure());
      expect(restored.meanwhileSides!.first.isSequenceGroup, isTrue);
    });

    test('rejects a sequence with more than four steps', () {
      final raw =
          jsonDecode(
                encodeDraft(
                  snapshotOf([
                    FigureDraft(
                      sequenceFigures: [step('balance', 2), step('swing', 2)],
                    ),
                  ]),
                ),
              )
              as Map<String, Object?>;
      final children =
          ((raw['figureDrafts']! as List).single as Map)['children'] as List;
      for (var i = 0; i < 3; i++) {
        children.add({...children.first as Map, 'id': 'extra-$i'});
      }
      expect(() => decodeDraft(raw), throwsA(isA<FormatException>()));
    });

    test('rejects a sequence directly inside a sequence', () {
      final raw =
          jsonDecode(
                encodeDraft(
                  snapshotOf([
                    FigureDraft(
                      sequenceFigures: [step('balance', 2), step('swing', 2)],
                    ),
                  ]),
                ),
              )
              as Map<String, Object?>;
      final outer = (raw['figureDrafts']! as List).single as Map;
      (outer['children'] as List)[0] = {
        ...outer,
        'id': 'inner',
        'children': [
          for (final c in outer['children'] as List)
            {...c as Map, 'id': 'inner-${c['id']}'},
        ],
      };
      expect(() => decodeDraft(raw), throwsA(isA<FormatException>()));
    });
  });
}
