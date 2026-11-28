import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a typed pass (taxonomy v40)', () {
    // Mutation caught: filling a typed pass from its effective params alone,
    // which takes a pass by's neighbors or a pass through's along as stated.
    test('starts who and where unstated unless the line states them', () {
      for (final (figure, who, where) in [
        (Figure(move: 'pass_by'), 'unspecified', 'unspecified'),
        (Figure(move: 'pass_through'), 'unspecified', 'unspecified'),
        (
          Figure(move: 'pass_through', params: const {'where': 'across'}),
          'unspecified',
          'across',
        ),
        (
          Figure(move: 'pass_by', params: const {'who': 'partners'}),
          'partners',
          'unspecified',
        ),
      ]) {
        final draft = FigureDraft.fromFreeTextFigure(
          figure,
          contraTaxonomy,
          requireStatedParams: true,
        );
        expect(draft.params['who'], who, reason: '${figure.params}');
        expect(draft.params['where'], where, reason: '${figure.params}');
      }
    });

    // Mutation caught: seeding unstated values where nothing enforces them
    // (Settings' figure lists), which stores a pass by naming no one in place
    // of the neighbors the line meant, and which a v39 build rejects.
    test('outside the dance editor the line keeps what it meant', () {
      final draft = FigureDraft.fromFreeTextFigure(
        Figure(move: 'pass_by'),
        contraTaxonomy,
      );
      expect(draft.params['who'], 'neighbors');
      expect(draft.toFigure()!.params, isNot(contains('where')));
    });

    test('a saved default states it', () {
      final draft = FigureDraft.fromFreeTextFigure(
        Figure(move: 'pass_through'),
        contraTaxonomy,
        moveParamDefaults: const {
          'pass_through': {'who': 'neighbors'},
        },
        requireStatedParams: true,
      );
      expect(draft.params['who'], 'neighbors');
      expect(draft.params['where'], 'unspecified');
    });
  });

  // A custom figure never renders a wording override (renderer.dart:
  // `figure.isCustom ? null : _renderWordingOverride`) and the editor offers no
  // field for it, so toFigure must not persist one (#1394).
  group('fromFreeTextFigure and a saved value kept only while stated', () {
    // A Move default saved by a build whose Settings still recorded it: an
    // unstated Rory O'More `twoPlaces` (taxonomy v40). An older peer rejects
    // the key, so the typed figure must not carry it, with a count typed or
    // without one.
    const defaults = {
      'rory_o_more': {'twoPlaces': 'unspecified', 'slide': 'left'},
    };
    for (final params in [
      <String, Object?>{'beats': 8},
      <String, Object?>{},
    ]) {
      test('typed params $params', () {
        final draft = FigureDraft.fromFreeTextFigure(
          testFigure(move: 'rory_o_more', params: params),
          contraTaxonomy,
          moveParamDefaults: defaults,
        );
        expect(draft.params['slide'], 'left');
        expect(draft.params.containsKey('twoPlaces'), isFalse);
      });
    }
  });

  group('childStartBeatsOfDraft (#2303)', () {
    FigureDraft step(int beats) =>
        FigureDraft(move: 'ecd_lead', params: {'beats': beats});

    test(
      'a sequence\'s steps follow one another, an untimed one adding none',
      () {
        final sequence = FigureDraft(
          sequenceFigures: [
            step(6),
            FigureDraft(move: 'ecd_set'),
            step(4),
          ],
        );
        expect(childStartBeatsOfDraft(sequence, 18), [18, 24, 24]);
      },
    );

    test(
      'a meanwhile\'s sides and a modifier\'s parts start with the group',
      () {
        expect(
          childStartBeatsOfDraft(
            FigureDraft(meanwhileSides: [step(6), step(6)]),
            18,
          ),
          [18, 18],
        );
        expect(
          childStartBeatsOfDraft(
            FigureDraft(modifierFigures: [step(6), step(2)]),
            18,
          ),
          [18, 18],
        );
      },
    );

    test('a figure that is no group has no children', () {
      expect(childStartBeatsOfDraft(step(6), 18), isEmpty);
    });
  });

  group('figureStartBeat (#2303)', () {
    test('counts only the rows Save writes as figures', () {
      final rows = [
        FigureDraft(move: 'ecd_lead', params: {'beats': 6}),
        FigureDraft()..params['beats'] = 8,
        FigureDraft(move: 'ecd_set', params: {'beats': 4}),
      ];
      expect(figureStartBeat(rows), 10);
      expect(figureStartBeat(rows.take(2)), 6);
      expect(figureStartBeat(const []), 0);
    });
  });

  group('FigureDraft.toFigure wordingOverride on a custom figure', () {
    test('a custom leaf draft drops a stale override', () {
      final draft = FigureDraft(move: customMove, params: {'text': 'my call'})
        ..wordingOverride = 'stale wording';
      expect(draft.toFigure()!.wordingOverride, isNull);
    });

    test('a custom child of a container drops a stale override', () {
      final container = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: customMove, params: {'text': 'my call'})
            ..wordingOverride = 'stale wording',
          FigureDraft(move: 'swing'),
        ],
      )..params['beats'] = 8;
      final sides = container.toFigure()!.subFigures;
      expect(sides.first.isCustom, isTrue);
      expect(sides.first.wordingOverride, isNull);
    });

    test('a move-less side materialised as a custom drops an override', () {
      final container = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing'),
          FigureDraft()..wordingOverride = 'stale wording',
        ],
      )..params['beats'] = 8;
      final sides = container.toFigure()!.subFigures;
      expect(sides.last.isCustom, isTrue);
      expect(sides.last.wordingOverride, isNull);
    });

    test('a structured figure and a container keep their override', () {
      final structured = FigureDraft(move: 'swing')
        ..wordingOverride = 'keep me';
      expect(structured.toFigure()!.wordingOverride, 'keep me');
      final container =
          FigureDraft(
              meanwhileSides: [
                FigureDraft(move: 'swing'),
                FigureDraft(move: 'roll_away'),
              ],
            )
            ..params['beats'] = 8
            ..wordingOverride = 'keep me too';
      expect(container.toFigure()!.wordingOverride, 'keep me too');
    });
  });

  group('FigureDraft.toFigure customOrigin', () {
    test('a manually created custom commits as userEntered', () {
      final draft = FigureDraft(move: customMove, params: {'text': 'my call'});
      expect(draft.toFigure()!.customOrigin, CustomOrigin.userEntered);
    });

    test('an importGap custom round-trips through the editor preserving its '
        'origin (stays reparse-eligible)', () {
      final gap = customFigure(
        'kept verbatim',
        beats: 8,
        origin: CustomOrigin.importGap,
      );
      expect(gap.customOrigin, CustomOrigin.importGap);

      // Merely loading a parser-gap custom into a draft and committing it back
      // (an open/save round-trip, or the #419 free-text insert path) must NOT
      // launder off the importGap marker — otherwise a locally-typed or
      // imported gap would silently lose its #398 badge and reparse
      // eligibility the moment the dance is saved. Ownership is only taken when
      // the user makes an explicit authoring choice in the structured editor
      // (picking a move or re-authoring the custom), which resets it to
      // userEntered (covered in figure_list_editor_test.dart).
      final draft = FigureDraft.fromFigure(gap);
      expect(draft.toFigure()!.customOrigin, CustomOrigin.importGap);
    });

    test('a structured figure is unaffected (userEntered)', () {
      final draft = FigureDraft.fromFigure(
        Figure(
          move: 'swing',
          params: const {'beats': 8},
          wordingOverride: 'Use the other hand.',
        ),
      );
      expect(draft.toFigure()!.customOrigin, CustomOrigin.userEntered);
      expect(draft.wordingOverride, 'Use the other hand.');
      expect(draft.toFigure()!.wordingOverride, 'Use the other hand.');
    });
  });

  group('FigureDraft.toFigure assumedSubject (#460)', () {
    test('defaults to false for a freshly built draft', () {
      final draft = FigureDraft(move: 'swing', params: {'who': 'partners'});
      expect(draft.assumedSubject, isFalse);
      expect(draft.toFigure()!.assumedSubject, isFalse);
    });

    test('fromFigure → toFigure preserves an assumed subject', () {
      // Merely opening and saving an imported dance must NOT launder off the
      // provenance marker — the same open/save-preserving contract now applies
      // to customOrigin too (see the importGap round-trip test above); both are
      // reset only on an explicit authoring choice.
      final imported = Figure(
        move: 'allemande',
        params: const {'who': 'neighbors', 'hand': 'left'},
        assumedSubject: true,
      );
      final draft = FigureDraft.fromFigure(imported);
      expect(draft.assumedSubject, isTrue);
      expect(draft.toFigure()!.assumedSubject, isTrue);
    });

    test('a stated subject round-trips as not assumed', () {
      final draft = FigureDraft.fromFigure(
        Figure(move: 'swing', params: const {'who': 'partners'}),
      );
      expect(draft.assumedSubject, isFalse);
      expect(draft.toFigure()!.assumedSubject, isFalse);
    });
  });

  group('FigureDraft.clone (#460)', () {
    test('preserves the assumed-subject marker and other fields', () {
      final source = FigureDraft(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'left', 'beats': 8},
        note: 'from CallersBox',
        progression: true,
        beatsTouched: true,
        assumedSubject: true,
      );
      final copy = source.clone();

      // Provenance + ownership flags survive the clone (the #460 bug lost these).
      expect(copy.assumedSubject, isTrue);
      expect(copy.beatsTouched, isTrue);
      expect(copy.move, 'allemande');
      expect(copy.note, 'from CallersBox');
      expect(copy.progression, isTrue);
      expect(copy.params, source.params);
      expect(copy.toFigure()!.assumedSubject, isTrue);
    });

    test('gives the copy a fresh id and an independent params map', () {
      final source = FigureDraft(
        move: 'swing',
        params: {'who': 'partners'},
        assumedSubject: true,
      );
      final copy = source.clone();
      expect(copy.id, isNot(source.id));
      // Deep copy: mutating the copy must not bleed into the source.
      copy.params['who'] = 'neighbors';
      expect(source.params['who'], 'partners');
    });

    test('a stated subject clones as not assumed', () {
      final copy = FigureDraft(
        move: 'swing',
        params: {'who': 'partners'},
      ).clone();
      expect(copy.assumedSubject, isFalse);
      expect(copy.toFigure()!.assumedSubject, isFalse);
    });
  });

  group('FigureDraft.toFigure canonicalises custom text (DIA-02)', () {
    String canon(String t) => canonicalizeText(t.trim(), Dialect.larksRobins);

    test('a custom leaf draft stores params[text] canonically', () {
      final draft = FigureDraft(
        move: customMove,
        params: {'text': 'Larks chain wide'},
      );
      expect(
        draft.toFigure(canonicalizeNote: canon)!.params['text'],
        'role1s chain wide',
      );
      // The draft keeps the dialect text being edited.
      expect(draft.params['text'], 'Larks chain wide');
    });

    test('re-saving already-canonical text is idempotent', () {
      final draft = FigureDraft(
        move: customMove,
        params: {'text': 'role1s chain wide'},
      );
      expect(
        draft.toFigure(canonicalizeNote: canon)!.params['text'],
        'role1s chain wide',
      );
    });

    test('a structured figure keeps its params untouched', () {
      final draft = FigureDraft(move: 'swing', params: {'who': 'Larks'});
      expect(draft.toFigure(canonicalizeNote: canon)!.params['who'], 'Larks');
    });

    test('a custom child inside a meanwhile is canonicalised', () {
      final container = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: customMove, params: {'text': 'Robins gypsy'}),
          FigureDraft(move: 'swing'),
        ],
      )..params['beats'] = 8;
      final sides = container.toFigure(canonicalizeNote: canon)!.subFigures;
      expect(sides.first.params['text'], 'role2s gypsy');
    });

    test('an incomplete side materialised as a custom is canonicalised', () {
      final container = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing'),
          FigureDraft()..params['text'] = 'Larks wait',
          FigureDraft(move: 'allemande'),
        ],
      )..params['beats'] = 8;
      final sides = container.toFigure(canonicalizeNote: canon)!.subFigures;
      expect(sides.map((f) => f.params['text']), contains('role1s wait'));
    });
  });

  group('FigureDraft meanwhile round-trip (#590/#593)', () {
    test(
      'fromFigure seeds meanwhileSides and shared beats from a container',
      () {
        final container = Figure.meanwhile(
          figures: [
            Figure(move: 'swing', params: const {'who': 'partners'}),
            Figure(move: 'allemande', params: const {'who': 'neighbors'}),
          ],
          beats: 16,
        );
        final draft = FigureDraft.fromFigure(container);
        expect(draft.isMeanwhileGroup, isTrue);
        expect(draft.meanwhileSides, hasLength(2));
        expect(draft.meanwhileSides![0].move, 'swing');
        expect(draft.meanwhileSides![1].move, 'allemande');
        expect(draft.beats, 16);
        // Sides are always flat — never themselves groups.
        expect(draft.meanwhileSides![0].isMeanwhileGroup, isFalse);
        expect(draft.meanwhileSides![1].isMeanwhileGroup, isFalse);
      },
    );

    test('toFigure rebuilds an equivalent Figure.meanwhile container', () {
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
          FigureDraft(move: 'allemande', params: {'who': 'neighbors'}),
        ],
      );
      draft.params['beats'] = 16;
      final figure = draft.toFigure()!;
      expect(figure.isMeanwhile, isTrue);
      expect(figure.beats, 16);
      expect(figure.subFigures, hasLength(2));
      expect(figure.subFigures[0].move, 'swing');
      expect(figure.subFigures[1].move, 'allemande');
    });

    test('a fully round-tripped meanwhile is unchanged', () {
      final original = Figure.meanwhile(
        figures: [
          Figure(move: 'swing', params: const {'who': 'partners', 'beats': 8}),
          Figure(
            move: 'allemande',
            params: const {'who': 'neighbors', 'hand': 'left'},
          ),
        ],
        beats: 16,
        note: 'watch your spacing',
      );
      final roundTripped = FigureDraft.fromFigure(original).toFigure();
      expect(roundTripped, original);
    });

    test('toFigure returns null while fewer than 2 sides are ready', () {
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing'),
          FigureDraft(),
        ],
      );
      draft.params['beats'] = 8;
      expect(draft.toFigure(), isNull);
    });

    test('preserves an in-progress side (no move, but a note) as a best-effort '
        'custom figure rather than silently dropping it (#679 review)', () {
      final inProgress = FigureDraft()..note = 'still deciding the move';
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
          FigureDraft(move: 'allemande', params: {'who': 'neighbors'}),
          inProgress,
        ],
      );
      draft.params['beats'] = 16;
      final figure = draft.toFigure()!;
      expect(figure.subFigures, hasLength(3));
      final third = figure.subFigures[2];
      expect(third.isCustom, isTrue);
      expect(third.note, 'still deciding the move');
    });

    test('still drops a genuinely untouched blank side once at least 2 sides '
        'are ready (#679 review)', () {
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing'),
          FigureDraft(move: 'allemande'),
          FigureDraft(), // freshly added placeholder — nothing entered.
        ],
      );
      draft.params['beats'] = 16;
      final figure = draft.toFigure()!;
      expect(figure.subFigures, hasLength(2));
    });

    test('clone deep-copies meanwhileSides with fresh ids', () {
      final source = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
          FigureDraft(move: 'allemande', params: {'who': 'neighbors'}),
        ],
      );
      source.params['beats'] = 16;
      final copy = source.clone();
      expect(copy.id, isNot(source.id));
      expect(copy.meanwhileSides![0].id, isNot(source.meanwhileSides![0].id));
      copy.meanwhileSides![0].params['who'] = 'someone else';
      expect(source.meanwhileSides![0].params['who'], 'partners');
    });

    test('defensively clamps an over-cap side list rather than throwing', () {
      final draft = FigureDraft(
        meanwhileSides: [
          for (var i = 0; i < 8; i++) FigureDraft(move: 'swing'),
        ],
      );
      draft.params['beats'] = 8;
      final figure = draft.toFigure()!;
      expect(figure.subFigures, hasLength(kMaxMeanwhileSides));
    });
  });

  group('FigureDraft modifier round-trip (#1198)', () {
    test('materializes ordered modifier children', () {
      final draft = FigureDraft(
        modifierFigures: [
          FigureDraft(move: 'swing'),
          FigureDraft(move: 'roll'),
        ],
      )..params['beats'] = 8;

      final figure = draft.toFigure();
      expect(figure, isNotNull);
      expect(figure!.isModifier, isTrue);
      expect(figure.subFigures.map((child) => child.move), ['swing', 'roll']);
    });

    test('a row with no move but a note saves as a custom figure holding the '
        'note (AUTH-2)', () {
      final draft = FigureDraft()..note = 'gents start on the left';
      // toFigure still reads "no move chosen yet"; the rows the dance saves
      // keep the note.
      expect(draft.toFigure(), isNull);
      final saved = draft.toFigures(resolveCompound: (_) => null);
      expect(saved, hasLength(1));
      expect(saved.single.move, customMove);
      expect(saved.single.note, 'gents start on the left');
    });

    test('a blank row with no move still saves nothing', () {
      expect(FigureDraft().toFigures(resolveCompound: (_) => null), isEmpty);
      expect(
        (FigureDraft()..note = '   ').toFigures(resolveCompound: (_) => null),
        isEmpty,
      );
    });

    test('does not materialize a partial modifier container', () {
      final draft = FigureDraft(modifierFigures: [FigureDraft(move: 'swing')])
        ..params['beats'] = 8;
      expect(draft.toFigure(), isNull);
    });

    test('does not promote a later modifier past a blank core', () {
      final draft = FigureDraft(
        modifierFigures: [
          FigureDraft(),
          FigureDraft(move: 'roll_away'),
          FigureDraft(move: 'swing'),
        ],
      )..params['beats'] = 8;

      expect(draft.toFigure(), isNull);
    });

    test('preserves alternating nested containers', () {
      final draft = FigureDraft(
        modifierFigures: [
          FigureDraft(
            meanwhileSides: [
              FigureDraft(move: 'swing'),
              FigureDraft(move: 'roll'),
            ],
          ),
          FigureDraft(move: 'allemande'),
        ],
      )..params['beats'] = 8;
      expect(draft.toFigure()!.subFigures.first.isMeanwhile, isTrue);
    });

    test('does not flatten an incomplete nested container', () {
      final draft = FigureDraft(
        modifierFigures: [
          FigureDraft(
            meanwhileSides: [
              FigureDraft(move: 'swing'),
              FigureDraft(),
            ],
          )..params['beats'] = 8,
          FigureDraft(move: 'roll'),
        ],
      )..params['beats'] = 8;
      expect(draft.toFigure(), isNull);
    });

    test('preserves unknown container parameters on open/save', () {
      final draft = FigureDraft(
        params: {'beats': 8, 'future': 'keep-me'},
        modifierFigures: [
          FigureDraft(move: 'swing'),
          FigureDraft(move: 'roll'),
        ],
      );

      expect(draft.toFigure()!.params['future'], 'keep-me');
    });

    test('preserves container metadata on open/save', () {
      final original =
          Figure.modifier(
            figures: [
              Figure(move: 'swing'),
              Figure(move: 'roll_away'),
            ],
            beats: 8,
          ).copyWith(
            schemaVersion: 7,
            customOrigin: CustomOrigin.importGap,
            assumedSubject: true,
            walkthroughOverride: 'walk this through',
            wordingOverride: 'use this wording',
          );

      expect(FigureDraft.fromFigure(original).toFigure(), original);
    });
  });

  group('FigureDraft container title', () {
    FigureDraft sequence() => FigureDraft(
      sequenceFigures: [
        FigureDraft(move: 'balance', params: {'who': 'partners', 'beats': 4}),
        FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 12}),
      ],
    );

    test('round-trips through fromFigure and toFigure, nested included', () {
      final inner = Figure.sequence(
        figures: [
          Figure(move: 'balance', params: const {'beats': 4}),
          Figure(move: 'swing', params: const {'beats': 4}),
        ],
        beats: 8,
        title: 'Balance and swing',
      );
      final figure = Figure.meanwhile(
        figures: [
          inner,
          Figure(move: 'swing'),
        ],
        beats: 8,
        title: 'Both at once',
      );
      final draft = FigureDraft.fromFigure(figure);
      expect(draft.containerTitle, 'Both at once');
      expect(
        draft.containerChildren!.first.containerTitle,
        'Balance and swing',
      );
      final rebuilt = draft.toFigure()!;
      expect(rebuilt.containerTitle, 'Both at once');
      expect(rebuilt.subFigures.first.containerTitle, 'Balance and swing');
    });

    test('a blank title removes it, and an untitled group stores no key', () {
      final draft = sequence()..containerTitle = 'Name';
      expect(draft.toFigure()!.containerTitle, 'Name');
      draft.containerTitle = '   ';
      expect(draft.params.containsKey(containerTitleKey), isFalse);
      expect(draft.toFigure()!.params.containsKey(containerTitleKey), isFalse);
    });

    test('saves the title through the note canonicalizer, then normalized', () {
      final draft = sequence()..containerTitle = '  larks\nbalance  ';
      final built = draft.toFigure(
        canonicalizeNote: (text) => text.trim().replaceAll('larks', 'role1s'),
      )!;
      expect(built.containerTitle, 'role1s balance');
    });

    test('survives a clone', () {
      final draft = sequence()..containerTitle = 'Name';
      expect(draft.clone().containerTitle, 'Name');
    });

    test('a non-string title from a damaged draft reads as none', () {
      final draft = sequence()..params[containerTitleKey] = 7;
      expect(draft.containerTitle, '');
      expect(draft.toFigure()!.containerTitle, isNull);
    });
  });

  // Pre-release audit finding A2-02: an English dance's Meter typed after its
  // figures keeps each figure's length in bars.
  group('rescaleFigureBars', () {
    FigureDraft row(int? beats, {bool touched = true}) => FigureDraft(
      move: 'ecd_set',
      params: {'beats': ?beats},
      beatsTouched: touched,
    );

    int? inOther(int beats, int from, int to) => beatsInOtherBars(
      beats,
      from: BarTiming.fixed(from),
      fromStart: 0,
      to: BarTiming.fixed(to),
      toStart: 0,
    );

    test('a count keeps its bars only where they are whole beats, whole or '
        'half bars, within 64 beats', () {
      // 4 bars and 1½ bars of two beats, in bars of three and of four.
      expect(inOther(8, 2, 3), 12);
      expect(inOther(8, 2, 4), 16);
      expect(inOther(3, 2, 4), 6);
      expect(inOther(3, 2, 3), isNull);
      // 1½ bars of four is 6 beats, and 3 in bars of two.
      expect(inOther(6, 4, 2), 3);
      // A quarter bar of four is no whole or half bar, though it would be 2
      // whole beats in bars of eight.
      expect(inOther(1, 4, 8), isNull);
      expect(inOther(0, 2, 3), 0);
      expect(inOther(32, 2, 4), 64);
      expect(inOther(64, 2, 3), isNull);
    });

    test('changes every count or none', () {
      final rows = [row(8), row(3)];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: BarTiming.fixed(3),
        ),
        FigureBarsRescale.notExact,
      );
      expect([for (final r in rows) r.beats], [8, 3]);
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: BarTiming.fixed(4),
        ),
        FigureBarsRescale.rescaled,
      );
      expect([for (final r in rows) r.beats], [16, 6]);
    });

    test('leaves rows with no count, or a count of 0, as they are', () {
      final rows = [row(null), row(0)];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: BarTiming.fixed(3),
        ),
        FigureBarsRescale.unchanged,
      );
      expect(rows.first.params.containsKey('beats'), isFalse);
      expect(
        rescaleFigureBars([], from: BarTiming.fixed(2), to: BarTiming.fixed(3)),
        FigureBarsRescale.unchanged,
      );
    });

    test('the same bar length changes nothing, whatever the counts', () {
      final rows = [row(1)];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(3),
          to: BarTiming.fixed(3),
        ),
        FigureBarsRescale.unchanged,
      );
      expect(rows.single.beats, 1);
    });

    test('keeps whether a count follows its move', () {
      final rows = [row(8, touched: false), row(8)];
      rescaleFigureBars(rows, from: BarTiming.fixed(2), to: BarTiming.fixed(3));
      expect([for (final r in rows) r.beatsTouched], [false, true]);
    });

    test("a compound figure's count is its expansion's: it blocks the "
        'change unless it is 0', () {
      FigureDraft compound(int beats) => FigureDraft(
        compound: CompoundPlaceholder(id: 'c1', name: 'Combo', beats: beats),
      );
      final rows = [row(8), compound(8)];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: BarTiming.fixed(3),
        ),
        FigureBarsRescale.notExact,
      );
      expect(rows.first.beats, 8);
      expect(rows.last.beats, 8);
      final empty = [row(8), compound(0)];
      expect(
        rescaleFigureBars(
          empty,
          from: BarTiming.fixed(2),
          to: BarTiming.fixed(3),
        ),
        FigureBarsRescale.rescaled,
      );
      expect(empty.first.beats, 12);
    });

    test("a sequence that counts its steps changes its steps', and an unread "
        'count of its own is left alone', () {
      final sequence = FigureDraft(sequenceFigures: [row(4), row(4)])
        ..params['beats'] = 5;
      expect(sequence.sequenceSpanStated, isFalse);
      expect(
        rescaleFigureBars(
          [sequence],
          from: BarTiming.fixed(2),
          to: BarTiming.fixed(3),
        ),
        FigureBarsRescale.rescaled,
      );
      expect(sequence.beats, 12);
      expect(sequence.params['beats'], 5);
    });

    test("a step's count inside a group blocks it as a row's does", () {
      final group = FigureDraft.group(meanwhileMove, row(8), row(3));
      expect(
        rescaleFigureBars(
          [group],
          from: BarTiming.fixed(2),
          to: BarTiming.fixed(3),
        ),
        FigureBarsRescale.notExact,
      );
      expect(
        [group.beats, for (final side in group.meanwhileSides!) side.beats],
        [8, 8, 3],
      );
    });
  });

  // Decision sheet question 48: where the phrases differ in beats to the bar,
  // each count keeps the bars of the phrase it falls in.
  group('rescaleFigureBars by phrase', () {
    FigureDraft row(int? beats) =>
        FigureDraft(move: 'ecd_set', params: {'beats': ?beats});
    BarTiming byPhrase(String raw) =>
        BarTiming.byPhrase(PhraseStructure.parse(raw));

    test('reads each count where it falls before and after', () {
      // Two 4-bar phrases of two beats; then A in three beats to the bar.
      final rows = [row(4), row(4), row(8)];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: byPhrase('A:1*4*3 + B:1*4*2'),
        ),
        FigureBarsRescale.rescaled,
      );
      // 2 bars and 2 bars of A, then 4 bars of B.
      expect([for (final r in rows) r.beats], [6, 6, 8]);
    });

    test('a count that runs across a change of meter keeps its bars', () {
      // 3 bars from bar 3 of a 4-bar A: one bar of A and two of B.
      final rows = [row(4), row(6)];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: byPhrase('A:1*3*3 + B:1*4*2'),
        ),
        FigureBarsRescale.rescaled,
      );
      expect([for (final r in rows) r.beats], [6, 7]);
    });

    test("a sequence's steps are read one after another, a meanwhile's sides "
        'from where it starts', () {
      final sequence = FigureDraft(sequenceFigures: [row(4), row(4)]);
      final meanwhile = FigureDraft.group(meanwhileMove, row(8), row(8));
      final rows = [sequence, meanwhile];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: byPhrase('A:1*2*3 + B:1*6*2'),
        ),
        FigureBarsRescale.rescaled,
      );
      // The sequence's two steps are A's two bars of three, then two bars
      // of B; the meanwhile starts in B.
      expect(
        [for (final step in sequence.sequenceFigures!) step.beats],
        [6, 4],
      );
      expect(
        [
          meanwhile.beats,
          for (final side in meanwhile.meanwhileSides!) side.beats,
        ],
        [8, 8, 8],
      );
    });

    test('a half bar that now falls in a bar of three changes no count', () {
      final rows = [row(3), row(8)];
      expect(
        rescaleFigureBars(
          rows,
          from: BarTiming.fixed(2),
          to: byPhrase('A:1*4*3 + B:1*4*2'),
        ),
        FigureBarsRescale.notExact,
      );
      expect([for (final r in rows) r.beats], [3, 8]);
    });
  });
}
