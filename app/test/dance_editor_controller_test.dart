import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/screens/dance_editor/dance_editor_controller.dart';

import 'support/test_repositories.dart';

/// Pure-Dart unit tests for [DanceEditorController]: they construct the
/// controller directly (no widget tree) and drive its mutation methods to
/// assert undo/redo, debounced autosave, and save-assembly behaviour. This
/// complements the widget-level `editor_autosave_undo_test.dart` by exercising
/// the extracted controller in isolation.
///
/// The controller's debounce timers are real 500 ms [Timer]s, so tests wait a
/// little past that window (`settleDebounce`) to let them fire.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  Dance sampleDance({String id = 'd1', String title = 'My Dance'}) => Dance(
    id: id,
    title: title,
    figures: const [],
    createdAt: now,
    updatedAt: now,
  );

  /// Builds a loaded controller for a new (danceId == null) dance.
  Future<DanceEditorController> newDanceController(
    CompendiumRepositories repos,
  ) async {
    final controller = DanceEditorController(
      repositories: repos,
      danceId: null,
      dialect: Dialect.larksRobins,
    );
    await controller.load(dance: null, fieldDefs: const []);
    return controller;
  }

  /// Waits past the 500 ms undo/autosave debounce window, then lets the async
  /// draft write settle.
  Future<void> settleDebounce() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }

  /// Polls until the autosave draft exists (or times out), tolerating the async
  /// db write kicked off by the debounce timer.
  Future<bool> draftPersisted(CompendiumRepositories repos, String key) async {
    for (var i = 0; i < 40; i++) {
      if (await repos.settings.contains(key)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return false;
  }

  test('load seeds a new dance with a single initial undo entry', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    expect(controller.loaded, isTrue);
    expect(controller.isExistingDance, isFalse);
    // Only the initial snapshot is on the stack: nothing to undo or redo.
    expect(controller.canUndo, isFalse);
    expect(controller.canRedo, isFalse);
    expect(controller.dirty, isFalse);
  });

  test(
    'an enum mutation pushes undo immediately and can be undone/redone',
    () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await newDanceController(repos);
      addTearDown(controller.dispose);

      expect(controller.status, DanceStatus.active);

      controller.setStatus(DanceStatus.deprecated);
      expect(controller.status, DanceStatus.deprecated);
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);
      expect(controller.dirty, isTrue);

      controller.undo();
      expect(controller.status, DanceStatus.active);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.status, DanceStatus.deprecated);
      expect(controller.canRedo, isFalse);
    },
  );

  test('a text edit is debounced into a single undo entry', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    // Simulate rapid typing: several edits within one debounce window.
    controller.titleController.text = 'A';
    controller.onTextEdited();
    controller.titleController.text = 'Ab';
    controller.onTextEdited();
    controller.titleController.text = 'Abc';
    controller.onTextEdited();

    // Not yet flushed to the undo stack.
    expect(controller.canUndo, isFalse);

    await settleDebounce();

    // Exactly one undo entry captured for the whole burst.
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.titleController.text, isEmpty);
  });

  test(
    'editing schedules a debounced autosave draft that clearDraft removes',
    () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await newDanceController(repos);
      addTearDown(controller.dispose);

      expect(await repos.settings.contains('editor_draft:new'), isFalse);

      controller.titleController.text = 'Autosaved Title';
      controller.onTextEdited();

      expect(
        await draftPersisted(repos, 'editor_draft:new'),
        isTrue,
        reason: 'the debounced autosave should persist a draft',
      );

      final raw = await repos.settings.get('editor_draft:new');
      final decoded = decodeDraft(raw);
      expect(decoded.title, 'Autosaved Title');

      await controller.clearDraft();
      expect(await repos.settings.contains('editor_draft:new'), isFalse);
    },
  );

  test('buildDance assembles a new Dance from the trimmed draft', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    controller.titleController.text = '  Petronella  ';
    controller.onTextEdited();
    controller.setProgression(Progression.single);

    final dance = controller.buildDance();
    expect(dance.title, 'Petronella');
    expect(dance.id, isNotEmpty);
    // A brand-new dance gets fresh timestamps rather than reusing an original.
    expect(dance.createdAt, isNotNull);
  });

  test('buildDance for an existing dance preserves id via copyWith', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final controller = DanceEditorController(
      repositories: repos,
      danceId: 'd1',
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);

    await controller.load(
      dance: sampleDance(id: 'd1'),
      fieldDefs: const [],
    );
    expect(controller.isExistingDance, isTrue);

    controller.titleController.text = 'Renamed Dance';
    controller.onTextEdited();

    final dance = controller.buildDance();
    expect(dance.id, 'd1');
    expect(dance.title, 'Renamed Dance');
    expect(dance.createdAt, now);
  });

  test('markSaved clears the dirty flag', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    controller.setStatus(DanceStatus.deprecated);
    expect(controller.dirty, isTrue);

    controller.markSaved();
    expect(controller.dirty, isFalse);
  });

  test('duplicateFigure preserves the assumed-subject marker on the copy '
      '(#460)', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final controller = DanceEditorController(
      repositories: repos,
      danceId: 'd1',
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);

    // An imported figure whose subject the parser DEFAULTED carries the
    // non-authoritative provenance marker.
    final assumed = Figure(
      move: 'allemande',
      params: const {'who': 'neighbors', 'hand': 'left', 'beats': 8},
      assumedSubject: true,
    );
    await controller.load(
      dance: Dance(
        id: 'd1',
        title: 'My Dance',
        figures: [assumed],
        createdAt: now,
        updatedAt: now,
      ),
      fieldDefs: const [],
    );
    expect(controller.figureDrafts, hasLength(1));
    expect(controller.figureDrafts.single.assumedSubject, isTrue);

    controller.duplicateFigure(controller.figureDrafts.single);

    // The clone lands right after the source; BOTH keep the marker (the #460
    // regression dropped it on the copy), and the copy has a distinct id.
    expect(controller.figureDrafts, hasLength(2));
    expect(controller.figureDrafts[0].assumedSubject, isTrue);
    expect(controller.figureDrafts[1].assumedSubject, isTrue);
    expect(controller.figureDrafts[1].id, isNot(controller.figureDrafts[0].id));

    // And it survives assembly back into the immutable dance.
    final dance = controller.buildDance();
    expect(dance.figures, hasLength(2));
    expect(dance.figures.every((f) => f.assumedSubject), isTrue);
  });
}
