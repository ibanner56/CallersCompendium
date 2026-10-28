import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/editor_snapshot.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/editor/editor_undo_stack.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';
import 'support/new_dance_draft.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  String title = 'My Dance',
  List<Figure> figures = const [],
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps the home → editor push flow used by most tests.
Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? danceId,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-editor'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<String>(
                builder: (_) => DanceEditorScreen(danceId: danceId),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
  // Fire any post-frame callbacks (e.g. the draft-restore dialog trigger)
  // and settle the dialog entrance animation if one was scheduled.
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Expands the collapsible "More details" (Tier 2) section so its fields
/// (including custom fields) become visible and hittable. Idempotent: if the
/// section is already expanded, it does nothing.
Future<void> _expandMoreDetails(WidgetTester tester) async {
  if (find.byKey(const ValueKey('related-dance-add')).evaluate().isNotEmpty) {
    return;
  }
  final tile = find.byKey(const ValueKey('more-details-tile'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// Returns the current text of the title TextFormField via its EditableText.
String _titleText(WidgetTester tester) {
  final et = tester.firstWidget<EditableText>(
    find.descendant(
      of: find.byKey(const ValueKey('title-field')),
      matching: find.byType(EditableText),
    ),
  );
  return et.controller.text;
}

/// Reads the value a dropdown's own [FormFieldState] is holding — what the
/// closed field displays, and deliberately independent of how it is keyed.
T? _dropdownValue<T>(WidgetTester tester) => tester
    .state<FormFieldState<T>>(find.byType(DropdownButtonFormField<T>))
    .value;

/// Opens a dropdown and picks the item carrying [value], matching on the item's
/// value rather than its localized label.
Future<void> _pickFromDropdown<T>(WidgetTester tester, T value) async {
  final field = find.byType(DropdownButtonFormField<T>);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .byWidgetPredicate((w) => w is DropdownMenuItem<T> && w.value == value)
        .last,
  );
  await tester.pumpAndSettle();
}

/// Minimal [EditorSnapshot] for unit-test construction.
EditorSnapshot _snap({
  String title = '',
  List<FigureDraftSnapshot> figureDrafts = const [],
}) => EditorSnapshot(
  title: title,
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
  figureDrafts: figureDrafts,
);

// ---------------------------------------------------------------------------
// EditorUndoStack — pure-Dart unit tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditorUndoStack', () {
    test('initially empty: canUndo and canRedo both false', () {
      final stack = EditorUndoStack();
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
      expect(stack.current, isNull);
    });

    test('push first item: canUndo false (at floor), canRedo false', () {
      final stack = EditorUndoStack();
      stack.push(_snap(title: 'S0'));
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
      expect(stack.current!.title, 'S0');
    });

    test('push two items: canUndo true, canRedo false', () {
      final stack = EditorUndoStack();
      stack.push(_snap(title: 'S0'));
      stack.push(_snap(title: 'S1'));
      expect(stack.canUndo, isTrue);
      expect(stack.canRedo, isFalse);
      expect(stack.current!.title, 'S1');
    });

    test('undo/redo cursor navigation', () {
      final stack = EditorUndoStack();
      stack.push(_snap(title: 'S0'));
      stack.push(_snap(title: 'S1'));
      stack.push(_snap(title: 'S2'));

      final s1 = stack.undo();
      expect(s1.title, 'S1');
      expect(stack.canUndo, isTrue);
      expect(stack.canRedo, isTrue);

      final s0 = stack.undo();
      expect(s0.title, 'S0');
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isTrue);

      expect(stack.redo().title, 'S1');
      expect(stack.redo().title, 'S2');
      expect(stack.canRedo, isFalse);
    });

    test('push after undo clears redo tail', () {
      final stack = EditorUndoStack();
      stack.push(_snap(title: 'S0'));
      stack.push(_snap(title: 'S1'));
      stack.push(_snap(title: 'S2'));
      stack.undo(); // cursor → S1
      stack.push(_snap(title: 'S3'));
      expect(stack.current!.title, 'S3');
      expect(stack.canRedo, isFalse);
      expect(stack.length, 3); // S0, S1, S3
    });

    test('stack evicts oldest entry when bounded limit is reached', () {
      final stack = EditorUndoStack();
      for (var i = 0; i <= kUndoStackMax; i++) {
        stack.push(_snap(title: 'S$i'));
      }
      expect(stack.length, kUndoStackMax);
      // Most-recent entry is preserved after eviction.
      expect(stack.current!.title, 'S$kUndoStackMax');
    });

    test('undo throws StateError when canUndo is false', () {
      final stack = EditorUndoStack();
      stack.push(_snap());
      expect(() => stack.undo(), throwsStateError);
    });

    test('redo throws StateError when canRedo is false', () {
      final stack = EditorUndoStack();
      stack.push(_snap());
      expect(() => stack.redo(), throwsStateError);
    });
  });

  // =========================================================================
  // EditorDraftCodec — pure-Dart round-trip tests
  // =========================================================================
  group('EditorDraftCodec', () {
    test('round-trips a minimal snapshot', () {
      final s = _snap(title: 'Test Dance');
      final decoded = decodeDraft(encodeDraft(s));
      expect(decoded.title, 'Test Dance');
      expect(decoded.form, DanceForm.contra);
      expect(decoded.figureDrafts, isEmpty);
    });

    test(
      'round-trips full snapshot including partial/null-move figure draft',
      () {
        final s = EditorSnapshot(
          title: 'Full',
          hook: 'A hook',
          notes: 'Notes',
          phrase: '2*32',
          formationDetail: 'detail',
          form: DanceForm.contra,
          formationShape: FormationShape.becketCw,
          progression: Progression.double,
          status: DanceStatus.deprecated,
          authorIds: const ['a1'],
          tagIds: const ['t1'],
          tunes: const ['Tune A'],
          links: const [
            LinkSnapshot(
              id: 'l1',
              kind: LinkKind.source,
              url: 'http://x.y',
              label: 'X',
            ),
            LinkSnapshot(
              id: 'pl1',
              kind: LinkKind.relatedDance,
              url: '',
              label: 'Related',
              targetDanceId: 'other',
            ),
          ],
          sourceCitations: const [],
          customValues: const {'f1': 'hello', 'f2': true},
          figureDrafts: [
            FigureDraftSnapshot(
              id: 'fd1',
              move: 'swing',
              params: const {'who': 'partners', 'beats': 16},
              note: 'scoop',
              progression: true,
              schemaVersion: figureSchemaVersion,
            ),
            // Incomplete draft: null move.
            FigureDraftSnapshot(
              id: 'fd2',
              move: null,
              params: const {},
              note: '',
              progression: false,
              schemaVersion: figureSchemaVersion,
            ),
          ],
        );

        final d = decodeDraft(encodeDraft(s));
        expect(d.title, 'Full');
        expect(d.hook, 'A hook');
        expect(d.formationShape, FormationShape.becketCw);
        expect(d.progression, Progression.double);
        expect(
          d.links.firstWhere((l) => l.kind == LinkKind.source).url,
          'http://x.y',
        );
        final related = d.links.firstWhere(
          (l) => l.kind == LinkKind.relatedDance,
        );
        expect(related.targetDanceId, 'other');
        expect(d.customValues['f1'], 'hello');
        expect(d.customValues['f2'], true);
        expect(d.figureDrafts[0].move, 'swing');
        expect(d.figureDrafts[0].params['beats'], 16);
        expect(d.figureDrafts[0].note, 'scoop');
        expect(d.figureDrafts[0].progression, isTrue);
        // Null-move draft round-trips intact.
        expect(d.figureDrafts[1].move, isNull);
        expect(d.figureDrafts[1].progression, isFalse);
      },
    );

    test('decodeDraft rejects an unknown schema version', () {
      expect(
        () => decodeDraft({'v': 99, 'title': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodeDraft tolerates missing optional arrays (empty defaults)', () {
      final minimal = {
        'v': 2,
        'title': 'T',
        'hook': '',
        'notes': '',
        'phrase': '',
        'formationDetail': '',
        'form': 'contra',
        'formationShape': 'dupleImproper',
        'progression': 'single',
        'status': 'active',
      };
      final decoded = decodeDraft(minimal);
      expect(decoded.title, 'T');
      expect(decoded.authorIds, isEmpty);
      expect(decoded.figureDrafts, isEmpty);
    });

    test('decodeDraft accepts a pre-encoded JSON string', () {
      // SettingsRepository returns the raw JSON string from .get(); decodeDraft
      // must handle a String in addition to a Map.
      final inner = {
        'v': 2,
        'title': 'Stringified',
        'hook': '',
        'notes': '',
        'phrase': '',
        'formationDetail': '',
        'form': 'contra',
        'formationShape': 'dupleImproper',
        'progression': 'single',
        'status': 'active',
      };
      final decoded = decodeDraft(jsonEncode(inner));
      expect(decoded.title, 'Stringified');
    });

    test(
      'FigureDraftSnapshot.toDraft preserves all fields including null move',
      () {
        const snap = FigureDraftSnapshot(
          id: 'x',
          move: null,
          params: {'beats': 8},
          note: 'test',
          progression: true,
          schemaVersion: 1,
        );
        final draft = snap.toDraft();
        expect(draft.id, 'x');
        expect(draft.move, isNull);
        expect(draft.params['beats'], 8);
        expect(draft.note, 'test');
        expect(draft.progression, isTrue);
      },
    );

    test('FigureDraftSnapshot round-trips a meanwhile group losslessly '
        '(#590/#593)', () {
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
          FigureDraft(move: 'allemande', params: {'who': 'neighbors'}),
        ],
      );
      draft.params['beats'] = 16;
      draft.beatsTouched = true;

      final snap = FigureDraftSnapshot.fromDraft(draft);
      expect(snap.meanwhileSides, hasLength(2));

      final restored = snap.toDraft();
      expect(restored.id, draft.id);
      expect(restored.isMeanwhileGroup, isTrue);
      expect(restored.beats, 16);
      expect(restored.meanwhileSides![0].id, draft.meanwhileSides![0].id);
      expect(restored.meanwhileSides![0].move, 'swing');
      expect(restored.meanwhileSides![1].move, 'allemande');
      expect(restored.toFigure(), draft.toFigure());
      // A typed group count stays protected after an undo (AUTH-5).
      expect(restored.beatsTouched, isTrue);
      expect(restored.meanwhileSides![0].beatsTouched, isFalse);
    });

    test('a draft round-trips beatsTouched, its save time and baseline, and '
        'the role terms its text is in (AUTH-5, AUTH-10, AUTH-17)', () {
      final savedAt = DateTime.utc(2026, 10, 28, 15, 4, 5);
      final base = DateTime.utc(2026, 10, 27, 9);
      final snapshot = _snap(title: 'T').copyWith(
        figureDrafts: const [
          FigureDraftSnapshot(
            id: 'typed',
            move: 'swing',
            params: {'beats': 12},
            note: 'Larks go',
            progression: false,
            schemaVersion: 1,
            beatsTouched: true,
          ),
          FigureDraftSnapshot(
            id: 'derived',
            move: 'swing',
            params: {'beats': 8},
            note: '',
            progression: false,
            schemaVersion: 1,
          ),
        ],
        textDialect: Dialect.larksRobins,
        savedAt: savedAt,
        baseUpdatedAt: base,
      );
      final decoded = decodeDraft(encodeDraft(snapshot));
      expect(
        [for (final d in decoded.figureDrafts) d.beatsTouched],
        [true, false],
      );
      expect(decoded.savedAt, savedAt);
      expect(decoded.baseUpdatedAt, base);
      expect(decoded.textDialect?.roles, Dialect.larksRobins.roles);
      // The text is kept as typed; only a restore under other roles converts.
      expect(decoded.figureDrafts.first.note, 'Larks go');
    });

    test('new-dance drafts are keyed under the editor draft prefix, which '
        'backup excludes and the registry classifies', () {
      expect(danceEditorDraftKey(kLegacyNewDanceDraftId), 'editor_draft:new');
      expect(danceEditorDraftKey(kNewDanceDraftIdPrefix), 'editor_draft:new:');
      expect(
        classifySettingsKey('editor_draft:new:x')?.egress,
        EgressClass.deviceScoped,
      );
      expect(isNewDanceEditorDraftKey('editor_draft:new'), isTrue);
      expect(isNewDanceEditorDraftKey('editor_draft:new:x'), isTrue);
      expect(isNewDanceEditorDraftKey('editor_draft:newer'), isFalse);
      expect(isNewDanceEditorDraftKey('editor_draft:d1'), isFalse);
      expect(isNewDanceEditorDraftKey('program_editor_draft:new'), isFalse);
    });

    test('unreadable text roles read as unknown, not as no roles', () {
      final decoded = decodeDraft({
        'v': 13,
        'form': 'contra',
        'formationShape': 'dupleImproper',
        'progression': 'single',
        'status': 'active',
        'textRoles': {'role1': 'lark'},
      });
      expect(decoded.textDialect, isNull);
    });

    test('a draft written before F2 still decodes, with a stored count read '
        'as typed and no save time, baseline or dialect', () {
      final decoded = decodeDraft({
        'v': 13,
        'title': 'Old',
        'form': 'contra',
        'formationShape': 'dupleImproper',
        'progression': 'single',
        'status': 'active',
        'figureDrafts': [
          {
            'id': 'a',
            'move': 'swing',
            'params': {'beats': 12},
            'note': 'larks go',
            'progression': false,
            'sv': 1,
          },
          {
            'id': 'b',
            'move': null,
            'params': <String, Object?>{},
            'note': '',
            'progression': false,
            'sv': 1,
          },
        ],
      });
      expect(decoded.title, 'Old');
      expect(
        [for (final d in decoded.figureDrafts) d.beatsTouched],
        [true, false],
      );
      expect(decoded.savedAt, isNull);
      expect(decoded.baseUpdatedAt, isNull);
      expect(decoded.textDialect, isNull);
    });
  });

  // =========================================================================
  // Undo / redo widget tests
  // =========================================================================
  group('Undo / redo in editor', () {
    testWidgets('undo button disabled on initial load', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('undo-button')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('redo-button')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('undo enabled after debounced text edit', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Hello',
      );
      // Before debounce: still disabled.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('undo-button')))
            .onPressed,
        isNull,
      );

      // Advance debounce timer.
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('undo-button')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('undo reverts title; redo re-applies it', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'After',
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Undo → title should be empty.
      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(_titleText(tester), '');

      // Redo → title back to 'After'.
      await tester.tap(find.byKey(const ValueKey('redo-button')));
      await tester.pumpAndSettle();
      expect(_titleText(tester), 'After');
    });

    testWidgets('undo resyncs text controllers after title change', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'First',
      );
      await tester.pump(const Duration(milliseconds: 600));

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Second',
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Undo once → should revert to 'First'.
      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(_titleText(tester), 'First');
    });

    // Issue #775. Four dropdowns carried a value-based key justified by the
    // claim that `DropdownButtonFormField` never re-reads `initialValue`, so
    // undo/redo needed a fresh subtree to resync. The claim is false —
    // `_DropdownButtonFormFieldState.didUpdateWidget` calls `setValue` — but
    // until now nothing tested the scenario it named: every test in this group
    // drove text fields or figures, never a dropdown. These pin it through a
    // real undo, so the resync is checkable rather than asserted in a comment.
    //
    // They read `FormFieldState.value`, which is what the closed field
    // displays, deliberately independent of how the field is keyed.

    testWidgets('undo reverts the formation dropdown; redo re-applies it', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      final before = _dropdownValue<FormationShape>(tester);
      expect(before, isNot(FormationShape.circleMixer));

      await _pickFromDropdown(tester, FormationShape.circleMixer);
      expect(
        _dropdownValue<FormationShape>(tester),
        FormationShape.circleMixer,
      );

      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(_dropdownValue<FormationShape>(tester), before);

      await tester.tap(find.byKey(const ValueKey('redo-button')));
      await tester.pumpAndSettle();
      expect(
        _dropdownValue<FormationShape>(tester),
        FormationShape.circleMixer,
      );
    });

    testWidgets('undo reverts the type dropdown; redo re-applies it '
        '(issue #1418)', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      expect(_dropdownValue<DanceForm>(tester), DanceForm.contra);

      await _pickFromDropdown(tester, DanceForm.square);
      expect(_dropdownValue<DanceForm>(tester), DanceForm.square);

      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(_dropdownValue<DanceForm>(tester), DanceForm.contra);

      await tester.tap(find.byKey(const ValueKey('redo-button')));
      await tester.pumpAndSettle();
      expect(_dropdownValue<DanceForm>(tester), DanceForm.square);
    });

    testWidgets('undo reverts the level dropdown all the way back to null', (
      tester,
    ) async {
      // The nullable transition is the one worth pinning separately: the
      // selection drops rather than being replaced.
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1'));
      await _pumpEditor(tester, repos, danceId: 'd1');
      await _expandMoreDetails(tester);

      expect(_dropdownValue<DanceLevel?>(tester), isNull);

      await _pickFromDropdown<DanceLevel?>(tester, DanceLevel.advanced);
      expect(_dropdownValue<DanceLevel?>(tester), DanceLevel.advanced);

      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(_dropdownValue<DanceLevel?>(tester), isNull);
    });

    testWidgets('undo reverts a choice custom field dropdown', (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'adj',
          key: 'adjectives',
          label: 'Adjectives',
          type: CustomFieldType.choice,
          choices: const ['driving', 'lyrical'],
        ),
      );
      await repos.dances.create(_dance(id: 'd1'));
      await _pumpEditor(tester, repos, danceId: 'd1');
      await _expandMoreDetails(tester);

      expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
      expect(_dropdownValue<String?>(tester), isNull);

      await _pickFromDropdown<String?>(tester, 'lyrical');
      expect(_dropdownValue<String?>(tester), 'lyrical');

      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(_dropdownValue<String?>(tester), isNull);
    });

    testWidgets('undo after figure add removes the added figure', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // Start from a blank figure list (this test predates the DD.2 default
      // stand_still × 8 template).
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([]),
      );
      await _pumpEditor(tester, repos);

      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-add-figure')));
      await tester.pumpAndSettle();
      expect(find.text('No figures yet.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(find.text('No figures yet.'), findsOneWidget);
    });

    testWidgets('undo after figure delete restores the figure', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(
          id: 'd1',
          figures: [
            Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
          ],
        ),
      );
      await _pumpEditor(tester, repos, danceId: 'd1');

      // Delete the figure (via the ⋮ overflow menu).
      await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
      await tester.pumpAndSettle();
      expect(find.text('No figures yet.'), findsOneWidget);

      // Undo restores it.
      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(find.text('No figures yet.'), findsNothing);
    });

    testWidgets('redo disabled after second undo from top of stack', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(find.byKey(const ValueKey('title-field')), 'X');
      await tester.pump(const Duration(milliseconds: 600));

      // Undo back to initial → redo should be available.
      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('redo-button')))
            .onPressed,
        isNotNull,
      );

      // Redo re-applies → redo disabled again.
      await tester.tap(find.byKey(const ValueKey('redo-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('redo-button')))
            .onPressed,
        isNull,
      );
    });

    for (final (platform, undo, redo) in [
      (TargetPlatform.android, 'Undo (Ctrl+Z)', 'Redo (Ctrl+Shift+Z)'),
      (TargetPlatform.macOS, 'Undo (\u2318Z)', 'Redo (\u21e7\u2318Z)'),
    ]) {
      testWidgets('undo and redo tooltips name the $platform shortcut', (
        tester,
      ) async {
        final repos = openTestRepositories();
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _pumpEditor(tester, repos);

          String tooltipOf(String key) =>
              tester.widget<IconButton>(find.byKey(ValueKey(key))).tooltip!;
          expect(tooltipOf('undo-button'), undo);
          expect(tooltipOf('redo-button'), redo);
        } finally {
          // Must be cleared before the test body returns: the binding checks
          // foundation debug variables before any addTearDown callback runs.
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('keyboard shortcut Ctrl+Z triggers undo', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Typed',
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Fire Ctrl+Z on the Focus widget that wraps the whole editor.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(_titleText(tester), '');
    });

    testWidgets('push new edit after undo clears redo tail', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(find.byKey(const ValueKey('title-field')), 'A');
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-add-figure')));
      await tester.pumpAndSettle();

      // Undo the figure add.
      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('redo-button')))
            .onPressed,
        isNotNull,
      );

      // Now make a new edit — redo tail should be cleared.
      await tester.enterText(find.byKey(const ValueKey('title-field')), 'B');
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('redo-button')))
            .onPressed,
        isNull,
      );
    });
  });

  // =========================================================================
  // Autosave draft widget tests
  // =========================================================================
  group('Autosave drafts', () {
    testWidgets('draft saved after title edit (debounced)', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Draft Title',
      );
      // Before debounce fires, no draft yet.
      expect(await hasNewDanceDraft(repos), isFalse);

      // Advance debounce.
      await tester.pump(const Duration(milliseconds: 600));
      expect(await hasNewDanceDraft(repos), isTrue);

      final raw = await newDanceDraft(repos);
      final decoded = decodeDraft(raw);
      expect(decoded.title, 'Draft Title');
    });

    testWidgets(
      'draft saved immediately after structural change (add figure)',
      (tester) async {
        final repos = openTestRepositories();
        await _pumpEditor(tester, repos);

        await tester.tap(find.byKey(const ValueKey('figure-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('figure-add-figure')));
        await tester.pumpAndSettle();

        // Structural changes schedule autosave (debounced 500ms).
        await tester.pump(const Duration(milliseconds: 600));
        expect(await hasNewDanceDraft(repos), isTrue);
      },
    );

    testWidgets('draft cleared on explicit save', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'To Save',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(await hasNewDanceDraft(repos), isTrue);

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      expect(await hasNewDanceDraft(repos), isFalse);
    });

    testWidgets('back navigation on a dirty editor prompts before discarding', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Will Discard',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(await hasNewDanceDraft(repos), isTrue);

      // Backing out no longer silently discards: it shows the same
      // 'Discard changes?' confirmation the program editor uses.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      // Still on the editor, and the draft is preserved until the user
      // explicitly confirms the discard — no silent data loss.
      expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
      expect(await hasNewDanceDraft(repos), isTrue);
    });

    testWidgets(
      "'Keep editing' cancels the back navigation and preserves the draft",
      (tester) async {
        final repos = openTestRepositories();
        await _pumpEditor(tester, repos);

        await tester.enterText(
          find.byKey(const ValueKey('title-field')),
          'Keep Me',
        );
        await tester.pump(const Duration(milliseconds: 600));

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('discard-cancel')));
        await tester.pumpAndSettle();

        // Dialog dismissed, still editing, draft intact.
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
        expect(await hasNewDanceDraft(repos), isTrue);
      },
    );

    testWidgets("'Discard' clears the draft and leaves the editor", (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Will Discard',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(await hasNewDanceDraft(repos), isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();

      // Editor popped back to the launcher and the draft was cleared.
      expect(find.byKey(const ValueKey('title-field')), findsNothing);
      expect(find.byKey(const ValueKey('open-editor')), findsOneWidget);
      expect(await hasNewDanceDraft(repos), isFalse);
    });

    testWidgets('restore dialog shown when draft exists for new dance', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        'editor_draft:new',
        encodeDraft(_snap(title: 'Pre-saved')),
      );

      await _pumpEditor(tester, repos);

      expect(find.text('Unsaved draft'), findsOneWidget);
    });

    testWidgets('restore path: editor shows draft content', (tester) async {
      final repos = openTestRepositories();
      final draft = _snap(title: 'Restored Title');
      await repos.settings.set('editor_draft:new', encodeDraft(draft));

      await _pumpEditor(tester, repos);
      await tester.tap(find.byKey(const ValueKey('draft-restore')));
      await tester.pumpAndSettle();

      expect(_titleText(tester), 'Restored Title');
    });

    testWidgets('discard path: draft removed, editor starts clean', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        'editor_draft:new',
        encodeDraft(_snap(title: 'Should Not Show')),
      );

      await _pumpEditor(tester, repos);
      await tester.tap(find.byKey(const ValueKey('draft-discard')));
      await tester.pumpAndSettle();

      expect(_titleText(tester), '');
      expect(await hasNewDanceDraft(repos), isFalse);
    });

    testWidgets('the restore prompt gives the draft\'s age, and warns when the '
        'dance has changed since (AUTH-10)', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd5', title: 'D5'));
      final stored = (await repos.dances.getById('d5'))!;
      await repos.settings.set(
        'editor_draft:d5',
        encodeDraft(
          _snap(title: 'Pending').copyWith(
            savedAt: DateTime.utc(2026, 10, 28, 15, 4),
            baseUpdatedAt: stored.updatedAt.subtract(const Duration(hours: 1)),
          ),
        ),
      );

      await _pumpEditor(tester, repos, danceId: 'd5');

      expect(
        find.text(
          'You have an unsaved draft for this dance. Would you like '
          'to restore it?',
        ),
        findsOneWidget,
      );
      // Shown in local time, so the expected text is built the same way.
      final shown = DateFormat.yMMMd(
        'en',
      ).add_jm().format(DateTime.utc(2026, 10, 28, 15, 4).toLocal());
      expect(find.text('Draft saved $shown.'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-changed-since')), findsOneWidget);
    });

    testWidgets('the restore prompt does not warn when the dance is as the '
        'draft left it (AUTH-10)', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd6', title: 'D6'));
      final stored = (await repos.dances.getById('d6'))!;
      await repos.settings.set(
        'editor_draft:d6',
        encodeDraft(
          _snap(title: 'Pending').copyWith(
            savedAt: DateTime.utc(2026, 10, 28, 15, 4),
            baseUpdatedAt: stored.updatedAt,
          ),
        ),
      );

      await _pumpEditor(tester, repos, danceId: 'd6');

      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-changed-since')), findsNothing);
    });

    testWidgets('a new dance is offered an abandoned new dance\'s draft by '
        'name, not as "this dance" (AUTH-10)', (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        danceEditorDraftKey(kLegacyNewDanceDraftId),
        encodeDraft(_snap(title: 'Abandoned')),
      );

      await _pumpEditor(tester, repos);

      expect(
        find.text(
          'You have an unsaved draft of another new dance, '
          '“Abandoned”. Would you like to restore it instead of starting a '
          'new one?',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('for this dance'), findsNothing);
    });

    testWidgets('draft keyed by danceId for an existing dance', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'dance123'));
      await _pumpEditor(tester, repos, danceId: 'dance123');

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Renamed',
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(await repos.settings.contains('editor_draft:dance123'), isTrue);
      // 'new' key is NOT written.
      expect(await hasNewDanceDraft(repos), isFalse);
    });

    testWidgets('partial/incomplete figure draft (null move) round-trips', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // Start from a blank figure list (this test predates the DD.2 default
      // stand_still × 8 template).
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([]),
      );
      await _pumpEditor(tester, repos);

      // Add a figure row without selecting a move.
      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-add-figure')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));

      final raw = await newDanceDraft(repos);
      final decoded = decodeDraft(raw);
      expect(decoded.figureDrafts, hasLength(1));
      expect(decoded.figureDrafts.single.move, isNull);
    });

    testWidgets('restore dialog shows for existing dance with saved draft', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd99', title: 'D99'));
      await repos.settings.set(
        'editor_draft:d99',
        encodeDraft(_snap(title: 'Pending Draft')),
      );

      await _pumpEditor(tester, repos, danceId: 'd99');
      expect(find.text('Unsaved draft'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('draft-restore')));
      await tester.pumpAndSettle();
      expect(_titleText(tester), 'Pending Draft');
    });

    testWidgets('corrupt draft is silently discarded — no dialog', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // Store non-JSON garbage.
      await repos.settings.set('editor_draft:new', 'NOT_VALID_JSON');

      await _pumpEditor(tester, repos);

      // No restore dialog should appear.
      expect(find.text('Unsaved draft'), findsNothing);
      // Key is cleaned up.
      expect(await hasNewDanceDraft(repos), isFalse);
    });

    // Regression: fix #3 (updated) — v1 drafts are now forward-compatible
    test('decodeDraft: v1 draft with URL-only links decodes successfully', () {
      // v1→v2 only added optional targetDanceId to links. A v1 autosave draft
      // must survive an app upgrade so the user does not lose in-progress work.
      // The preservedLinks bucket (v1 only) is ignored by the v2 parser.
      final v1Map = {
        'v': 1,
        'title': 'T',
        'hook': '',
        'notes': '',
        'phrase': '',
        'formationDetail': '',
        'form': 'contra',
        'formationShape': 'dupleImproper',
        'progression': 'single',
        'status': 'active',
        'links': [
          {'id': 'l1', 'kind': 'source', 'url': 'https://example.com'},
        ],
        'preservedLinks': [
          {
            'id': 'pl1',
            'kind': 'relatedDance',
            'targetDanceId': 42, // malformed — will be ignored (unknown key)
          },
        ],
      };
      // v1 is accepted; URL links are preserved; preservedLinks key is ignored.
      final decoded = decodeDraft(v1Map);
      expect(decoded.title, 'T');
      expect(decoded.links, hasLength(1));
      expect(decoded.links.single.url, 'https://example.com');
    });

    // Regression: fix #4 — custom text/number captured from controllers
    testWidgets('autosave captures custom text field typed by user', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'cf1',
          key: 'notes2',
          label: 'Extra Notes',
          type: CustomFieldType.text,
        ),
      );
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Custom Test',
      );
      await _expandMoreDetails(tester);
      await tester.enterText(
        find.byKey(const ValueKey('custom-cf1')),
        'my typed value',
      );
      await tester.pump(const Duration(milliseconds: 600));

      final raw = await newDanceDraft(repos);
      final decoded = decodeDraft(raw);
      expect(decoded.customValues['cf1'], 'my typed value');
    });

    // Regression: fix #4 — undo restores custom text field value
    testWidgets('undo restores custom text field to previous value', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'cf2',
          key: 'extra',
          label: 'Extra',
          type: CustomFieldType.text,
        ),
      );
      await _pumpEditor(tester, repos);

      await _expandMoreDetails(tester);
      await tester.enterText(
        find.byKey(const ValueKey('custom-cf2')),
        'first value',
      );
      await tester.pump(const Duration(milliseconds: 600));

      await tester.enterText(
        find.byKey(const ValueKey('custom-cf2')),
        'second value',
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Undo → custom field should show 'first value'.
      await tester.tap(find.byKey(const ValueKey('undo-button')));
      await tester.pumpAndSettle();

      final et = tester.firstWidget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('custom-cf2')),
          matching: find.byType(EditableText),
        ),
      );
      expect(et.controller.text, 'first value');
    });
  });

  // =========================================================================
  // Regression: fix #1 — undo stack reset after draft restore
  // =========================================================================
  group('Undo stack after draft restore', () {
    testWidgets('undo disabled immediately after restoring a draft', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        'editor_draft:new',
        encodeDraft(_snap(title: 'Restored')),
      );

      await _pumpEditor(tester, repos);

      // Restore the draft.
      await tester.tap(find.byKey(const ValueKey('draft-restore')));
      await tester.pumpAndSettle();

      // After restore, undo should be disabled (restored state IS the floor).
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('undo-button')))
            .onPressed,
        isNull,
      );
    });
  });
}
