import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/editor_snapshot.dart';
import 'package:compendium_app/src/editor/editor_undo_stack.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';

import 'support/test_repositories.dart';

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
      expect(await repos.settings.contains('editor_draft:new'), isFalse);

      // Advance debounce.
      await tester.pump(const Duration(milliseconds: 600));
      expect(await repos.settings.contains('editor_draft:new'), isTrue);

      final raw = await repos.settings.get('editor_draft:new');
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

        // Structural changes schedule autosave (debounced 500ms).
        await tester.pump(const Duration(milliseconds: 600));
        expect(await repos.settings.contains('editor_draft:new'), isTrue);
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
      expect(await repos.settings.contains('editor_draft:new'), isTrue);

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      expect(await repos.settings.contains('editor_draft:new'), isFalse);
    });

    testWidgets('draft cleared on back navigation', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Will Discard',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(await repos.settings.contains('editor_draft:new'), isTrue);

      // Use pageBack() (taps the AppBar BackButton → maybePop → PopScope handler
      // → _clearDraft() + programmatic Navigator.pop).
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(await repos.settings.contains('editor_draft:new'), isFalse);
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
      expect(await repos.settings.contains('editor_draft:new'), isFalse);
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
      expect(await repos.settings.contains('editor_draft:new'), isFalse);
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
      await tester.pump(const Duration(milliseconds: 600));

      final raw = await repos.settings.get('editor_draft:new');
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
      expect(await repos.settings.contains('editor_draft:new'), isFalse);
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

      final raw = await repos.settings.get('editor_draft:new');
      final decoded = decodeDraft(raw);
      expect(decoded.customValues['cf1'], 'my typed value');
    });

    // Regression: fix #4 — undo restores custom text field value
    testWidgets('undo restores custom text field to previous value', (
      tester,
    ) async {
      final repos = openTestRepositories();
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
