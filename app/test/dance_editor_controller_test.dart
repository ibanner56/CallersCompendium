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

  test('clearDraft awaits an in-flight autosave so it cannot resurrect the '
      'draft afterwards (issue #616)', () async {
    final delayed = openTestRepositoriesWithDelayedSettings();
    addTearDown(delayed.repos.db.close);
    final controller = await newDanceController(delayed.repos);
    addTearDown(controller.dispose);

    controller.titleController.text = 'Racing Title';
    controller.onTextEdited();

    // Arm the gate so the debounced autosave's settings.set() suspends
    // right after starting, simulating a write already "in flight" when
    // cleanup runs.
    delayed.settings.holdNextWrite();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await delayed.settings.writeStarted;

    // Fire the cleanup while the autosave write is still suspended. If
    // clearDraft() didn't wait for it, the held write would complete after
    // the remove() below and resurrect the draft.
    final clearFuture = controller.clearDraft();
    delayed.settings.releaseWrite();
    await clearFuture;

    expect(
      await delayed.repos.settings.contains('editor_draft:new'),
      isFalse,
      reason:
          'the draft must stay removed even though an autosave write was '
          'in flight when clearDraft ran',
    );
  });

  test('a late autosave scheduled before clearDraft cannot resurrect the draft '
      'once cleanup has started (issue #616)', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    controller.titleController.text = 'Discarded Title';
    controller.onTextEdited();
    await controller.clearDraft();

    // Autosave was scheduled before the discard; clearDraft cancels the
    // timer, so waiting past the debounce window must not resurrect it.
    await settleDebounce();
    expect(await repos.settings.contains('editor_draft:new'), isFalse);
  });

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

  group('insertFreeTextFigures (#419)', () {
    /// A controller loaded from an EXISTING dance with no figures, so the
    /// figure list starts genuinely empty (a NEW dance would seed the default
    /// stand-still template).
    Future<DanceEditorController> emptyExistingController(
      CompendiumRepositories repos,
    ) async {
      final controller = DanceEditorController(
        repositories: repos,
        danceId: 'd1',
        dialect: Dialect.larksRobins,
      );
      await controller.load(
        dance: Dance(
          id: 'd1',
          title: 'My Dance',
          figures: const [],
          createdAt: now,
          updatedAt: now,
        ),
        fieldDefs: const [],
      );
      return controller;
    }

    test('a recognised line appends one structured figure', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await emptyExistingController(repos);
      addTearDown(controller.dispose);

      controller.insertFreeTextFigures(
        parseFreeTextFigureEntry('Neighbor swing'),
      );

      expect(controller.figureDrafts, hasLength(1));
      final built = controller.buildDance().figures.single;
      expect(built.move, 'swing');
      expect(built.params['who'], 'neighbors');
      expect(built.customOrigin, CustomOrigin.userEntered);
      // An insert is undoable.
      expect(controller.canUndo, isTrue);
    });

    test('a `;`-compound appends one row per clause', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await emptyExistingController(repos);
      addTearDown(controller.dispose);

      controller.insertFreeTextFigures(
        parseFreeTextFigureEntry('circle left 3/4; turn alone'),
      );

      expect(controller.figureDrafts, hasLength(2));
      final figures = controller.buildDance().figures;
      expect(figures[0].move, 'circle');
      expect(figures[1].move, 'turn_alone');
    });

    test('an unparsed line appends an importGap custom that survives '
        'assembly (reparse-eligible)', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await emptyExistingController(repos);
      addTearDown(controller.dispose);

      controller.insertFreeTextFigures(
        parseFreeTextFigureEntry('do a barrel roll into the sunset'),
      );

      expect(controller.figureDrafts, hasLength(1));
      final built = controller.buildDance().figures.single;
      expect(built.isCustom, isTrue);
      // The parser-gap origin is NOT laundered off by the editor round-trip,
      // so the saved custom keeps its #398 marker and stays reparse-eligible.
      expect(built.customOrigin, CustomOrigin.importGap);
    });

    test('an empty result is a no-op', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await emptyExistingController(repos);
      addTearDown(controller.dispose);

      controller.insertFreeTextFigures(const []);

      expect(controller.figureDrafts, isEmpty);
      expect(controller.canUndo, isFalse);
    });
  });

  group('addChoiceOption (inline choice-field option add, #373)', () {
    CustomFieldDef choiceDef({List<String> choices = const ['driving']}) =>
        CustomFieldDef(
          id: 'adj',
          key: 'adjectives',
          label: 'Adjectives',
          type: CustomFieldType.choice,
          choices: choices,
        );

    Future<DanceEditorController> controllerWith(
      CompendiumRepositories repos,
      CustomFieldDef def,
    ) async {
      await repos.customFieldDefs.upsert(def);
      final controller = DanceEditorController(
        repositories: repos,
        danceId: null,
        dialect: Dialect.larksRobins,
      );
      await controller.load(dance: null, fieldDefs: [def]);
      return controller;
    }

    test('appends, persists, and selects a new option', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await controllerWith(repos, choiceDef());
      addTearDown(controller.dispose);

      final result = await controller.addChoiceOption('adj', '  lyrical  ');

      expect(result, AddChoiceResult.added);
      // Trimmed, appended to the in-memory def, and selected for the dance.
      expect(controller.fieldDefs.single.choices, ['driving', 'lyrical']);
      expect(controller.customValues['adj'], 'lyrical');
      // Persisted to the repository so it round-trips like any other option.
      final stored = await repos.customFieldDefs.getById('adj');
      expect(stored!.choices, ['driving', 'lyrical']);
    });

    test('rejects a case-sensitive duplicate without persisting', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await controllerWith(repos, choiceDef());
      addTearDown(controller.dispose);

      final result = await controller.addChoiceOption('adj', 'driving');

      expect(result, AddChoiceResult.duplicate);
      expect(controller.fieldDefs.single.choices, ['driving']);
      expect(controller.customValues['adj'], isNull);
    });

    test('rejects an empty / whitespace-only option', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await controllerWith(repos, choiceDef());
      addTearDown(controller.dispose);

      expect(
        await controller.addChoiceOption('adj', '   '),
        AddChoiceResult.empty,
      );
      expect(controller.fieldDefs.single.choices, ['driving']);
    });

    test('soft-clamps an over-length option to the shared bound', () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final controller = await controllerWith(repos, choiceDef());
      addTearDown(controller.dispose);

      final long = 'x' * (kMaxCustomFieldChoiceLength + 50);
      final result = await controller.addChoiceOption('adj', long);

      expect(result, AddChoiceResult.added);
      final added = controller.fieldDefs.single.choices!.last;
      expect(added.length, kMaxCustomFieldChoiceLength);
    });
  });
}
