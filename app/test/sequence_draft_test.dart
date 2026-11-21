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

  group('a sequence that states its own span (ADR-006 §5.5)', () {
    FigureDraft untimed(String move) =>
        FigureDraft(move: move, beatsTouched: true);

    test('counts its span, and builds it with its untimed steps', () {
      final draft = FigureDraft(
        sequenceFigures: [step('ecd_lead', 4), untimed('ecd_set')],
      )..setSequenceSpan(12);
      expect(draft.sequenceSpanStated, isTrue);
      expect(draft.beats, 12);
      final built = draft.toFigure()!;
      expect(built.beats, 12);
      expect(stepStatesTiming(built.subFigures[0]), isTrue);
      expect(stepStatesTiming(built.subFigures[1]), isFalse);
    });

    test('without a span counts its steps, as before', () {
      final draft = FigureDraft(
        sequenceFigures: [step('ecd_lead', 4), step('ecd_set', 2)],
      );
      expect(draft.sequenceSpanStated, isFalse);
      expect(draft.beats, 6);
      draft
        ..setSequenceSpan(12)
        ..setSequenceSpan(null);
      expect(draft.beats, 6);
    });

    test('a stored span is read back where the steps do not make it up', () {
      final spanned = Figure.sequence(
        figures: [
          Figure(move: 'ecd_lead', params: const {'beats': 4}),
          Figure(move: 'ecd_set', params: const {}),
        ],
        beats: 12,
      );
      final draft = FigureDraft.fromFigure(spanned);
      expect(draft.sequenceSpanStated, isTrue);
      expect(draft.beats, 12);
      // The untimed step is the caller's: nothing fills in its count.
      expect(draft.sequenceFigures![1].untimed, isTrue);
      expect(draft.sequenceFigures![1].beatsTouched, isTrue);

      // A sequence the editor saved as its steps' sum keeps counting them.
      final summed = Figure.sequence(
        figures: [
          Figure(move: 'balance', params: const {'beats': 4}),
          Figure(move: 'swing', params: const {'beats': 12}),
        ],
        beats: 16,
      );
      expect(FigureDraft.fromFigure(summed).sequenceSpanStated, isFalse);
    });

    test('survives the autosave round-trip', () {
      final draft = FigureDraft(
        sequenceFigures: [step('ecd_lead', 4), untimed('ecd_set')],
      )..setSequenceSpan(12);
      final restored = decodeDraft(
        jsonDecode(encodeDraft(snapshotOf([draft]))),
      ).figureDrafts.single.toDraft();
      expect(restored.sequenceSpanStated, isTrue);
      expect(restored.beats, 12);
      expect(restored.sequenceFigures![1].untimed, isTrue);
    });

    test('a draft from before spans counts its steps, not its stale count', () {
      // A build before spans marked every sequence it loaded as touched, over
      // the count it was loaded with, and never kept that count up to date.
      final draft = FigureDraft(
        sequenceFigures: [step('ecd_lead', 4), step('ecd_set', 4)],
      );
      final json =
          jsonDecode(encodeDraft(snapshotOf([draft]))) as Map<String, dynamic>;
      final figure =
          (json['figureDrafts'] as List).single as Map<String, dynamic>;
      figure['beatsTouched'] = true;
      (figure['params'] as Map<String, dynamic>)['beats'] = 16;
      final restored = decodeDraft(json).figureDrafts.single.toDraft();
      expect(restored.sequenceSpanStated, isFalse);
      expect(restored.beats, 8);
    });

    test('clearing the span times its untimed steps by their defaults', () {
      final draft = FigureDraft(
        sequenceFigures: [step('ecd_lead', 4), untimed('ecd_set')],
      )..setSequenceSpan(12);
      draft.setSequenceSpan(null);
      expect(draft.sequenceFigures![1].untimed, isFalse);
      expect(draft.beats, 8);
      expect(draft.toFigure()!.beats, 8);
      // Reopened, the saved sequence counts its steps.
      expect(
        FigureDraft.fromFigure(draft.toFigure()!).sequenceSpanStated,
        isFalse,
      );
    });

    test('becoming another kind of group times its untimed steps', () {
      final draft = FigureDraft(
        sequenceFigures: [step('ecd_lead', 4), untimed('ecd_set')],
      )..setSequenceSpan(8);
      draft.convertContainerTo(meanwhileMove);
      expect(draft.meanwhileSides![1].untimed, isFalse);
      expect(draft.meanwhileSides![1].beats, 4);
    });

    test('a group with a typed count becomes a sequence that counts its '
        'steps, in any form', () {
      final draft = FigureDraft(
        meanwhileSides: [step('swing', 8), step('balance', 8)],
        params: {'beats': 4},
        beatsTouched: true,
      );
      draft.convertContainerTo(sequenceMove);
      expect(draft.sequenceSpanStated, isFalse);
      expect(draft.beats, 16);
      expect(draft.toFigure()!.beats, 16);
    });
  });

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

    test('leaving a sequence, the shared count follows the children', () {
      final draft = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      );
      draft.convertContainerTo(meanwhileMove);
      expect(draft.isMeanwhileGroup, isTrue);
      expect(draft.isSequenceGroup, isFalse);
      // The longer side's, as for any meanwhile nobody typed a count for.
      expect(draft.beats, 12);
      expect(draft.beatsTouched, isFalse);
      draft.convertContainerTo(modifierMove);
      // A modifier's core's.
      expect(draft.beats, 4);
    });

    test('a meanwhile follows a sequence side\'s total', () {
      final sequence = FigureDraft(
        sequenceFigures: [step('balance', 4), step('swing', 12)],
      );
      final group = FigureDraft.group(
        meanwhileMove,
        sequence,
        step('orbit', 8),
      );
      expect(group.beats, 16);
      expect(group.beatsTouched, isFalse);
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
