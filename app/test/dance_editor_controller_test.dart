import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/screens/dance_editor/dance_editor_controller.dart';

import 'support/test_repositories.dart';
import 'figures_support.dart';

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

  Dance sampleDance({
    String id = 'd1',
    String title = 'My Dance',
    List<String> tunes = const [],
  }) => Dance(
    id: id,
    title: title,
    figures: const [],
    tunes: tunes,
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

  group('an undecodable transcription survives editing (#1347)', () {
    /// Loads a dance whose [column] holds text the decoder cannot read.
    /// Parameterised because the figures and tunes preservation rules are two
    /// separate pieces of code (`_preserveStoredFigures`, `_preserveStoredTunes`)
    /// with the same hazard: corrupting only `figures_json` leaves the tune
    /// half of the contract untested.
    Future<DanceEditorController> loadUnreadable(
      CompendiumRepositories repos, {
      String column = 'figures_json',
      String raw = '[{"kind":',
    }) async {
      await repos.dances.create(
        sampleDance(id: 'd1', title: 'Corrupt', tunes: const ['Placeholder']),
      );
      await repos.ensureMigrated();
      await repos.db.customStatement(
        'UPDATE dances SET $column = ? WHERE id = ?',
        [raw, 'd1'],
      );
      final loaded = await repos.dances.getById('d1');
      final controller = DanceEditorController(
        repositories: repos,
        danceId: 'd1',
        dialect: Dialect.larksRobins,
      );
      await controller.load(dance: loaded, fieldDefs: const []);
      return controller;
    }

    test('a title edit does not replace the stored transcription', () async {
      final repos = openTestRepositories();
      final controller = await loadUnreadable(repos);
      addTearDown(controller.dispose);

      controller.titleController.text = 'Renamed';
      final built = controller.buildDance();

      expect(built.figuresSource, isA<UnreadableFigures>());
    });

    test('undo after adding a figure restores the preservation', () async {
      // `EditorSnapshot` captures `figureDrafts` and `tunes` as plain lists and
      // restores them with `..addAll(...)` — the exact shape that would have
      // destroyed the stored text on the Collection Undo path. It is safe here
      // only because `_preserveStoredFigures` is computed from LIVE content
      // rather than from a captured flag, so restoring an empty list turns
      // preservation back on. This pins that property rather than the current
      // implementation of it: a refactor to a snapshot-captured flag would fail
      // here.
      final repos = openTestRepositories();
      final controller = await loadUnreadable(repos);
      addTearDown(controller.dispose);

      controller.addFigure();
      controller.undo();
      controller.titleController.text = 'Renamed';

      expect(controller.buildDance().figuresSource, isA<UnreadableFigures>());
    });

    test('pressing Add figure does not replace it either', () async {
      // The placeholder trap: `addFigure()` makes `figureDrafts` non-empty
      // while the draft still yields no figure, so a guard keyed on the draft
      // list stops protecting the bytes the moment the button is pressed.
      final repos = openTestRepositories();
      final controller = await loadUnreadable(repos);
      addTearDown(controller.dispose);

      controller.addFigure();
      controller.titleController.text = 'Renamed';
      final built = controller.buildDance();

      expect(
        built.figuresSource,
        isA<UnreadableFigures>(),
        reason: 'an empty placeholder is not an authored transcription',
      );
    });

    test('undo after adding a tune restores the preservation', () async {
      // The tune half of the undo hazard above, and a separate piece of code:
      // `_preserveStoredTunes` reads `tunes.isEmpty`, and `EditorSnapshot`
      // restores `tunes` with `..addAll(...)` from a plain `List<String>` that
      // never held the stored bytes. Preservation therefore has to come back on
      // by itself when the list empties again. A refactor that captured the
      // unreadable state into the snapshot instead would pass the figures tests
      // and silently overwrite the stored tune text here.
      final repos = openTestRepositories();
      final controller = await loadUnreadable(
        repos,
        column: 'tunes_json',
        raw: '[1,2,3]',
      );
      addTearDown(controller.dispose);

      expect(
        controller.buildDance().tunesSource,
        isA<UnreadableTunes>(),
        reason: 'precondition: the editor opened on an unreadable tune list',
      );

      controller.tuneController.text = 'Whiskey Before Breakfast';
      controller.addTune();
      controller.undo();
      controller.titleController.text = 'Renamed';

      expect(controller.buildDance().tunesSource, isA<UnreadableTunes>());
    });
  });

  test('load seeds a new dance with a single initial undo entry', () async {
    final repos = openTestRepositories();
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

  group('initialTitle seed (issue #881 program-slot "create a dance")', () {
    test('seeds a new dance\'s title field', () async {
      final repos = openTestRepositories();
      final controller = DanceEditorController(
        repositories: repos,
        danceId: null,
        dialect: Dialect.larksRobins,
        initialTitle: 'Petronella',
      );
      addTearDown(controller.dispose);
      await controller.load(dance: null, fieldDefs: const []);

      expect(controller.titleController.text, 'Petronella');
    });

    test('an empty seed leaves the title field empty', () async {
      final repos = openTestRepositories();
      final controller = DanceEditorController(
        repositories: repos,
        danceId: null,
        dialect: Dialect.larksRobins,
        initialTitle: '',
      );
      addTearDown(controller.dispose);
      await controller.load(dance: null, fieldDefs: const []);

      expect(controller.titleController.text, isEmpty);
    });

    test('is ignored when editing an EXISTING dance', () async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.dances.create(sampleDance(id: 'd1', title: 'Real Title'));
      final controller = DanceEditorController(
        repositories: repos,
        danceId: 'd1',
        dialect: Dialect.larksRobins,
        initialTitle: 'Should Not Apply',
      );
      addTearDown(controller.dispose);
      await controller.load(
        dance: await repos.dances.getById('d1'),
        fieldDefs: const [],
      );

      expect(controller.titleController.text, 'Real Title');
    });

    test(
      'a restored autosave draft overrides the seed (draft precedence)',
      () async {
        final repos = openTestRepositories();

        // Stage a pending draft under the shared new-dance draft key, exactly
        // as a prior abandoned new-dance session would have left it.
        final seeded = DanceEditorController(
          repositories: repos,
          danceId: null,
          dialect: Dialect.larksRobins,
        );
        await seeded.load(dance: null, fieldDefs: const []);
        seeded.titleController.text = 'Old Draft Title';
        seeded.onTextEdited();
        await draftPersisted(repos, 'editor_draft:new');
        seeded.dispose();

        final controller = DanceEditorController(
          repositories: repos,
          danceId: null,
          dialect: Dialect.larksRobins,
          initialTitle: 'New Seed Title',
        );
        addTearDown(controller.dispose);
        await controller.load(dance: null, fieldDefs: const []);

        // Before the restore prompt resolves, the seed is what's showing —
        // this is the pre-existing shared-key hazard the plan calls out,
        // not something this change fixes.
        expect(controller.titleController.text, 'New Seed Title');
        expect(controller.pendingDraft, isNotNull);

        final draft = controller.pendingDraft!;
        controller.clearPendingDraft();
        controller.applyRestoredDraft(draft);

        expect(controller.titleController.text, 'Old Draft Title');
      },
    );
  });

  test(
    'editing schedules a debounced autosave draft that clearDraft removes',
    () async {
      final repos = openTestRepositories();
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

  test(
    'shutdown flush writes the newest edit before the debounce fires',
    () async {
      final delayed = openTestRepositoriesWithDelayedSettings();
      final controller = await newDanceController(delayed.repos);

      controller.titleController.text = 'Final title';
      controller.onTextEdited();
      delayed.settings.holdNextWrite();

      final flush = controller.prepareShutdownFlush()();
      var completed = false;
      final observed = flush.whenComplete(() => completed = true);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        delayed.settings.writesStarted,
        1,
        reason:
            'shutdown must enqueue the pending snapshot immediately instead '
            'of waiting for the autosave timer',
      );
      expect(completed, isFalse);

      controller.dispose();
      delayed.settings.releaseWrite();
      await observed;

      final draft = decodeDraft(
        await delayed.repos.settings.get('editor_draft:new'),
      );
      expect(draft.title, 'Final title');
    },
  );

  test('clearDraft awaits an in-flight autosave so it cannot resurrect the '
      'draft afterwards (issue #616)', () async {
    final delayed = openTestRepositoriesWithDelayedSettings();
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

  test('autosave preserves staged tags for restored drafts', () async {
    final repos = openTestRepositories();
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    controller.stageTag(
      Tag(id: 'provisional', name: 'New tag', color: 0xFFFF0000),
    );
    controller.addTag('provisional');

    expect(
      await draftPersisted(repos, 'editor_draft:new'),
      isTrue,
      reason: 'the staged tag draft should be persisted',
    );

    final restored = DanceEditorController(
      repositories: repos,
      danceId: null,
      dialect: Dialect.larksRobins,
    );
    addTearDown(restored.dispose);
    await restored.load(dance: null, fieldDefs: const []);

    final draft = restored.pendingDraft;
    expect(draft, isNotNull);
    restored.clearPendingDraft();
    restored.applyRestoredDraft(draft!);

    expect(restored.tagIds, ['provisional']);
    expect(restored.stagedTags, {
      'provisional': Tag(id: 'provisional', name: 'New tag', color: 0xFFFF0000),
    });
  });

  test('clearDraft awaits every queued autosave, not just the most recently '
      'scheduled one, when writes overlap (issue #616)', () async {
    final delayed = openTestRepositoriesWithDelayedSettings();
    final controller = await newDanceController(delayed.repos);
    addTearDown(controller.dispose);

    // First autosave: fire the debounce and hold its write open.
    controller.titleController.text = 'First Edit';
    controller.onTextEdited();
    delayed.settings.holdNextWrite();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await delayed.settings.writeStarted;

    // While the first write is still suspended, make a second edit. Its
    // debounced autosave is scheduled (and later fires) while the first
    // write is still in flight — an overlapping-writes scenario. Tracking
    // only "the most recent" in-flight future would let clearDraft miss
    // this still-earlier write.
    controller.titleController.text = 'Second Edit';
    controller.onTextEdited();
    delayed.settings.holdNextWrite();
    await Future<void>.delayed(const Duration(milliseconds: 650));

    // The second write is queued behind the still-suspended first write,
    // so it hasn't started yet.
    expect(delayed.settings.secondWriteStarted, isFalse);

    // Fire cleanup while both writes are outstanding (one in flight, one
    // queued behind it), then release the first write so the queue can
    // drain.
    final clearFuture = controller.clearDraft();
    delayed.settings.releaseWrite();
    await clearFuture;

    expect(
      await delayed.repos.settings.contains('editor_draft:new'),
      isFalse,
      reason:
          'the draft must stay removed even though an earlier autosave '
          'was still queued behind an in-flight write when clearDraft ran',
    );
  });

  test('buildDance assembles a new Dance from the trimmed draft', () async {
    final repos = openTestRepositories();
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

  test('collectCustomFields ignores non-finite number input', () async {
    final repos = openTestRepositories();
    final def = CustomFieldDef(
      id: 'f-num',
      key: 'number',
      label: 'Number',
      type: CustomFieldType.number,
    );
    final controller = DanceEditorController(
      repositories: repos,
      danceId: null,
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);
    await controller.load(dance: null, fieldDefs: [def]);

    for (final raw in ['1e400', '-1e400', 'Infinity', 'NaN']) {
      controller.customTextControllers['f-num']!.text = raw;
      expect(controller.hasInvalidCustomFieldNumber, isTrue, reason: raw);
      expect(controller.collectCustomFields(), isEmpty, reason: raw);
    }
  });

  test('buildDance stores typed prose VERBATIM, never canonicalized '
      '(issue #613)', () async {
    final repos = openTestRepositories();
    final controller = DanceEditorController(
      repositories: repos,
      danceId: null,
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);
    await controller.load(dance: null, fieldDefs: const []);

    // A caller types their own role terms into the prose fields. Canonicalizing
    // these was reverted: the substitution's always-on synonym set includes
    // ordinary English and proper nouns, so it corrupted dance titles, tune
    // names and people's names in long-form prose.
    controller.titleController.text = 'Larks in the Larch';
    controller.hookController.text = 'Larks and Robins balance the ring.';
    controller.notesController.text = 'Robins chain across to the Larks.';
    controller.walkthroughController.text =
        'A1: Larks allemande left. Balance the ring.';
    controller.onTextEdited();

    final dance = controller.buildDance();
    expect(dance.hook, 'Larks and Robins balance the ring.');
    expect(dance.callingNotes, 'Robins chain across to the Larks.');
    expect(dance.walkthrough, 'A1: Larks allemande left. Balance the ring.');
    expect(dance.title, 'Larks in the Larch');
    // No canonical token was written into anything the caller typed.
    for (final field in [dance.hook, dance.callingNotes, dance.walkthrough]) {
      expect(field, isNot(contains('role1')));
      expect(field, isNot(contains('role2')));
    }
  });

  test('buildDance preserves proper nouns and ordinary English in prose '
      '(issue #613 regression)', () async {
    final repos = openTestRepositories();
    final controller = DanceEditorController(
      repositories: repos,
      danceId: null,
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);
    await controller.load(dance: null, fieldDefs: const []);

    // Every one of these was corrupted while prose canonicalization was active.
    controller.titleController.text = 'Lady of the Lake';
    controller.hookController.text = 'Taught to me by Robin Hayden at NEFFA.';
    controller.notesController.text = 'The ladies room is past the stage.';
    controller.walkthroughController.text =
        'We opened with Larks in the Morning. One man short.';
    controller.onTextEdited();

    final dance = controller.buildDance();
    expect(dance.title, 'Lady of the Lake');
    expect(dance.hook, 'Taught to me by Robin Hayden at NEFFA.');
    expect(dance.callingNotes, 'The ladies room is past the stage.');
    expect(
      dance.walkthrough,
      'We opened with Larks in the Morning. One man short.',
    );
  });

  test(
    'buildDance leaves non-role prose byte-for-byte as typed (#613)',
    () async {
      final repos = openTestRepositories();
      final controller = await newDanceController(repos);
      addTearDown(controller.dispose);

      controller.titleController.text = 'Plain Sailing';
      controller.hookController.text = 'Balance and swing, then promenade.';
      controller.walkthroughController.text =
          'A1: Long lines forward and back. Star right.';
      controller.onTextEdited();

      final dance = controller.buildDance();
      expect(dance.hook, 'Balance and swing, then promenade.');
      expect(dance.walkthrough, 'A1: Long lines forward and back. Star right.');
    },
  );

  test('load shows stored prose exactly as stored, with no dialect rewrite '
      '(#613)', () async {
    final repos = openTestRepositories();
    final controller = DanceEditorController(
      repositories: repos,
      danceId: 'd1',
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);

    final stored = sampleDance(id: 'd1').copyWith(
      hook: 'Larks and Robins balance the ring.',
      callingNotes: 'Robins chain across to the Larks.',
    );
    await controller.load(dance: stored, fieldDefs: const []);

    expect(controller.hookController.text, stored.hook);
    expect(controller.notesController.text, stored.callingNotes);

    // Saving without edits is a true no-op on the prose fields.
    final rebuilt = controller.buildDance();
    expect(rebuilt.hook, stored.hook);
    expect(rebuilt.callingNotes, stored.callingNotes);
  });

  test('markSaved clears the dirty flag', () async {
    final repos = openTestRepositories();
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    controller.setStatus(DanceStatus.deprecated);
    expect(controller.dirty, isTrue);

    controller.markSaved();
    expect(controller.dirty, isFalse);
  });

  test('load renders a canonical figure note into the active dialect, and '
      'buildDance canonicalizes it back (#715)', () async {
    final repos = openTestRepositories();
    final controller = DanceEditorController(
      repositories: repos,
      danceId: 'd1',
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);

    // Storage is canonical (as written by imports / a previous save).
    final stored = sampleDance(id: 'd1').copyWith(
      figures: [
        Figure(
          move: 'allemande',
          params: const {'beats': 8},
          note: 'Open role2s chain to neighbor',
        ),
      ],
    );
    await controller.load(dance: stored, fieldDefs: const []);

    // The editor shows the caller's own dialect terms, not the canonical
    // token — mirroring how hook/callingNotes/walkthrough already render.
    expect(
      controller.figureDrafts.single.note,
      'Open robins chain to neighbor',
    );

    // Saving without edits round-trips back to the same canonical storage.
    final rebuilt = controller.buildDance();
    expect(figuresOf(rebuilt).single.note, 'Open role2s chain to neighbor');
  });

  test('buildDance canonicalizes a typed figure note before persistence '
      '(#715)', () async {
    final repos = openTestRepositories();
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    controller.addFigure();
    final draft = controller.figureDrafts.last;
    draft.move = 'allemande';
    draft.note = 'Open Robins chain to neighbor';
    controller.titleController.text = 'Some Dance';
    controller.onTextEdited();

    final dance = controller.buildDance();
    expect(figuresOf(dance).last.note, 'Open role2s chain to neighbor');
  });

  test('a figure note typed as a legacy synonym canonicalizes to the correct '
      'role regardless of the active dialect (#715)', () async {
    final repos = openTestRepositories();
    // Active dialect is Leads/Follows (NOT Larks/Robins) while the user
    // types the legacy synonym "Robins" — canonicalizeText's built-in
    // legacy synonym map resolves it to role2s independent of which
    // dialect is currently active.
    final controller = DanceEditorController(
      repositories: repos,
      danceId: null,
      dialect: Dialect.leadsFollows,
    );
    addTearDown(controller.dispose);
    await controller.load(dance: null, fieldDefs: const []);

    controller.addFigure();
    final draft = controller.figureDrafts.last;
    draft.move = 'allemande';
    draft.note = 'Robins chain to neighbor';
    controller.titleController.text = 'Some Dance';
    controller.onTextEdited();

    final dance = controller.buildDance();
    expect(figuresOf(dance).last.note, 'role2s chain to neighbor');
  });

  test('a figure note round-trips canonical -> render -> canonicalize '
      'idempotently (#715)', () async {
    final repos = openTestRepositories();
    final controller = DanceEditorController(
      repositories: repos,
      danceId: 'd1',
      dialect: Dialect.larksRobins,
    );
    addTearDown(controller.dispose);

    const canonicalNote = 'role1s allemande, then role2s orbit';
    final stored = sampleDance(id: 'd1').copyWith(
      figures: [
        Figure(
          move: 'allemande',
          params: const {'beats': 8},
          note: canonicalNote,
        ),
      ],
    );
    await controller.load(dance: stored, fieldDefs: const []);
    final rebuilt = controller.buildDance();
    expect(figuresOf(rebuilt).single.note, canonicalNote);
  });

  test(
    'non-role figure note prose survives load/save byte-identical (#715)',
    () async {
      final repos = openTestRepositories();
      final controller = DanceEditorController(
        repositories: repos,
        danceId: 'd1',
        dialect: Dialect.larksRobins,
      );
      addTearDown(controller.dispose);

      const plainNote = 'end facing across, smooth swing';
      final stored = sampleDance(id: 'd1').copyWith(
        figures: [
          Figure(move: 'swing', params: const {'beats': 16}, note: plainNote),
        ],
      );
      await controller.load(dance: stored, fieldDefs: const []);
      expect(controller.figureDrafts.single.note, plainNote);

      final rebuilt = controller.buildDance();
      expect(figuresOf(rebuilt).single.note, plainNote);
    },
  );

  test(
    'a meanwhile group side note renders and canonicalizes too (#715)',
    () async {
      final repos = openTestRepositories();
      final controller = DanceEditorController(
        repositories: repos,
        danceId: 'd1',
        dialect: Dialect.larksRobins,
      );
      addTearDown(controller.dispose);

      final stored = sampleDance(id: 'd1').copyWith(
        figures: [
          Figure.meanwhile(
            beats: 8,
            figures: [
              Figure(
                move: 'allemande',
                params: const {'beats': 8},
                note: 'role2s lead',
              ),
              Figure(move: 'orbit', params: const {'beats': 8}),
            ],
          ),
        ],
      );
      await controller.load(dance: stored, fieldDefs: const []);

      final group = controller.figureDrafts.single;
      expect(group.meanwhileSides!.first.note, 'robins lead');

      final rebuilt = controller.buildDance();
      expect(figuresOf(rebuilt).single.subFigures.first.note, 'role2s lead');
    },
  );

  test('insertFreeTextFigures renders an imported canonical note into the '
      'active dialect (#715)', () async {
    final repos = openTestRepositories();
    final controller = await newDanceController(repos);
    addTearDown(controller.dispose);

    controller.insertFreeTextFigures([
      Figure(
        move: 'allemande',
        params: const {'beats': 8},
        note: 'role2s allemande right 1/2',
        customOrigin: CustomOrigin.importGap,
      ),
    ]);

    expect(controller.figureDrafts.last.note, 'robins allemande right 1/2');
  });

  test('duplicateFigure preserves the assumed-subject marker on the copy '
      '(#460)', () async {
    final repos = openTestRepositories();
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
    expect(figuresOf(dance), hasLength(2));
    expect(figuresOf(dance).every((f) => f.assumedSubject), isTrue);
  });

  group('meanwhile grouping (#590/#593)', () {
    test('addMeanwhile seeds configured side defaults', () async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultMeanwhileSideFiguresKey,
        encodeFigures([
          Figure(move: 'balance', params: const {'beats': 4}),
          Figure(move: 'swing', params: const {'who': 'partners', 'beats': 8}),
        ]),
      );
      final controller = await newDanceController(repos);
      addTearDown(controller.dispose);

      await controller.addMeanwhile();

      expect(controller.figureDrafts, hasLength(9));
      final group = controller.figureDrafts.last;
      expect(group.isMeanwhileGroup, isTrue);
      expect(group.meanwhileSides, hasLength(2));
      expect(group.meanwhileSides![0].move, 'balance');
      expect(group.meanwhileSides![1].move, 'swing');
      expect(group.beats, 4);
    });

    test(
      'addMeanwhile keeps an empty preference in editor-only draft state',
      () async {
        final repos = openTestRepositories();
        await repos.settings.set(kDefaultMeanwhileSideFiguresKey, '[]');
        final controller = await newDanceController(repos);
        addTearDown(controller.dispose);

        await controller.addMeanwhile();

        final group = controller.figureDrafts.last;
        expect(group.isMeanwhileGroup, isTrue);
        expect(group.meanwhileSides, hasLength(2));
        expect(group.toFigure(), isNull);
      },
    );

    test(
      'groupFigureWithNext merges two adjacent figures into one group draft',
      () async {
        final repos = openTestRepositories();
        final controller = DanceEditorController(
          repositories: repos,
          danceId: 'd1',
          dialect: Dialect.larksRobins,
        );
        addTearDown(controller.dispose);
        await controller.load(
          dance: Dance(
            id: 'd1',
            title: 'My Dance',
            figures: [
              Figure(
                move: 'swing',
                params: const {'who': 'partners', 'beats': 8},
              ),
              Figure(
                move: 'allemande',
                params: const {'who': 'neighbors', 'hand': 'left', 'beats': 8},
              ),
              Figure(move: 'balance', params: const {'beats': 4}),
            ],
            createdAt: now,
            updatedAt: now,
          ),
          fieldDefs: const [],
        );
        expect(controller.figureDrafts, hasLength(3));

        controller.groupFigureWithNext(controller.figureDrafts[0]);

        // Two sides merged into one group row; the third figure is untouched.
        expect(controller.figureDrafts, hasLength(2));
        final group = controller.figureDrafts[0];
        expect(group.isMeanwhileGroup, isTrue);
        expect(group.meanwhileSides, hasLength(2));
        expect(group.meanwhileSides![0].move, 'swing');
        expect(group.meanwhileSides![1].move, 'allemande');
        expect(controller.figureDrafts[1].move, 'balance');

        // Section/beat warnings count the group's beats exactly once — the
        // existing `_figures` getter already flattens via toFigure(), so this
        // falls out of the design without controller-side beat math.
        final dance = controller.buildDance();
        expect(figuresOf(dance), hasLength(2));
        expect(figuresOf(dance)[0].isMeanwhile, isTrue);
      },
    );

    test(
      'collapseMeanwhileGroup replaces the group with its remaining side',
      () async {
        final repos = openTestRepositories();
        final controller = DanceEditorController(
          repositories: repos,
          danceId: 'd1',
          dialect: Dialect.larksRobins,
        );
        addTearDown(controller.dispose);
        await controller.load(
          dance: Dance(
            id: 'd1',
            title: 'My Dance',
            figures: [
              Figure.meanwhile(
                figures: [
                  Figure(move: 'swing', params: const {'who': 'partners'}),
                  Figure(move: 'allemande', params: const {'who': 'neighbors'}),
                ],
                beats: 16,
              ),
            ],
            createdAt: now,
            updatedAt: now,
          ),
          fieldDefs: const [],
        );
        final group = controller.figureDrafts.single;
        final remaining = group.meanwhileSides!.first;

        controller.collapseMeanwhileGroup(group, remaining);

        expect(controller.figureDrafts, hasLength(1));
        expect(controller.figureDrafts.single.isMeanwhileGroup, isFalse);
        expect(controller.figureDrafts.single.move, 'swing');
      },
    );

    test(
      'groupFigureWithNext is a no-op when either row is already a meanwhile '
      'group, even if called directly without the menu guard (#679 review)',
      () async {
        final repos = openTestRepositories();
        final controller = DanceEditorController(
          repositories: repos,
          danceId: 'd1',
          dialect: Dialect.larksRobins,
        );
        addTearDown(controller.dispose);
        await controller.load(
          dance: Dance(
            id: 'd1',
            title: 'My Dance',
            figures: [
              Figure.meanwhile(
                figures: [
                  Figure(move: 'swing', params: const {'who': 'partners'}),
                  Figure(move: 'allemande', params: const {'who': 'neighbors'}),
                ],
                beats: 16,
              ),
              Figure(move: 'balance', params: const {'beats': 4}),
            ],
            createdAt: now,
            updatedAt: now,
          ),
          fieldDefs: const [],
        );
        expect(controller.figureDrafts, hasLength(2));
        final before = List.of(controller.figureDrafts);

        // The first row is already a group — grouping it with the next row
        // would nest a meanwhile inside a meanwhile (flat-only violation).
        controller.groupFigureWithNext(controller.figureDrafts[0]);

        expect(controller.figureDrafts, equals(before));
        expect(controller.figureDrafts[0].isMeanwhileGroup, isTrue);
        expect(controller.figureDrafts[0].meanwhileSides, hasLength(2));
      },
    );

    test('groupFigureWithNext permits a modifier inside meanwhile', () async {
      final repos = openTestRepositories();
      final controller = DanceEditorController(
        repositories: repos,
        danceId: 'd1',
        dialect: Dialect.larksRobins,
      );
      addTearDown(controller.dispose);
      await controller.load(
        dance: Dance(
          id: 'd1',
          title: 'My Dance',
          figures: [
            Figure.modifier(
              beats: 8,
              figures: [
                Figure(move: 'swing'),
                Figure(move: 'balance'),
              ],
            ),
            Figure(move: 'balance'),
          ],
          createdAt: now,
          updatedAt: now,
        ),
        fieldDefs: const [],
      );

      controller.groupFigureWithNext(controller.figureDrafts.first);

      expect(controller.figureDrafts.single.isMeanwhileGroup, isTrue);
      expect(
        controller.figureDrafts.single.meanwhileSides!.first.isModifierGroup,
        isTrue,
      );
    });

    test(
      'groupFigureWithNextAsModifier permits meanwhile inside modifier',
      () async {
        final repos = openTestRepositories();
        final controller = DanceEditorController(
          repositories: repos,
          danceId: 'd1',
          dialect: Dialect.larksRobins,
        );
        addTearDown(controller.dispose);
        await controller.load(
          dance: Dance(
            id: 'd1',
            title: 'My Dance',
            figures: [
              Figure.meanwhile(
                beats: 8,
                figures: [
                  Figure(move: 'swing'),
                  Figure(move: 'balance'),
                ],
              ),
              Figure(move: 'balance'),
            ],
            createdAt: now,
            updatedAt: now,
          ),
          fieldDefs: const [],
        );

        controller.groupFigureWithNextAsModifier(controller.figureDrafts.first);

        expect(controller.figureDrafts.single.isModifierGroup, isTrue);
        expect(
          controller
              .figureDrafts
              .single
              .modifierFigures!
              .first
              .isMeanwhileGroup,
          isTrue,
        );
      },
    );

    test('grouping rejects a third structural container level', () async {
      final repos = openTestRepositories();
      final controller = DanceEditorController(
        repositories: repos,
        danceId: 'd1',
        dialect: Dialect.larksRobins,
      );
      addTearDown(controller.dispose);
      await controller.load(
        dance: Dance(
          id: 'd1',
          title: 'My Dance',
          figures: [
            Figure(move: 'swing'),
            Figure(move: 'balance'),
          ],
          createdAt: now,
          updatedAt: now,
        ),
        fieldDefs: const [],
      );
      final nested = FigureDraft(
        modifierFigures: [
          FigureDraft(
            meanwhileSides: [
              FigureDraft(move: 'swing'),
              FigureDraft(move: 'balance'),
            ],
          ),
          FigureDraft(move: 'balance'),
        ],
      );
      controller.figureDrafts
        ..clear()
        ..addAll([nested, FigureDraft(move: 'swing')]);

      controller.groupFigureWithNextAsModifier(nested);

      expect(controller.figureDrafts, hasLength(2));
      expect(controller.figureDrafts.first, same(nested));
    });
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
      final controller = await emptyExistingController(repos);
      addTearDown(controller.dispose);

      controller.insertFreeTextFigures(
        parseFreeTextFigureEntry('Neighbor swing'),
      );

      expect(controller.figureDrafts, hasLength(1));
      final built = figuresOf(controller.buildDance()).single;
      expect(built.move, 'swing');
      expect(built.params['who'], 'neighbors');
      expect(built.customOrigin, CustomOrigin.userEntered);
      // An insert is undoable.
      expect(controller.canUndo, isTrue);
    });

    test('a `;`-compound appends one row per clause', () async {
      final repos = openTestRepositories();
      final controller = await emptyExistingController(repos);
      addTearDown(controller.dispose);

      controller.insertFreeTextFigures(
        parseFreeTextFigureEntry('circle left 3/4; turn alone'),
      );

      expect(controller.figureDrafts, hasLength(2));
      final figures = figuresOf(controller.buildDance());
      expect(figures[0].move, 'circle');
      expect(figures[1].move, 'turn_alone');
    });

    test('an unparsed line appends an importGap custom that survives '
        'assembly (reparse-eligible)', () async {
      final repos = openTestRepositories();
      final controller = await emptyExistingController(repos);
      addTearDown(controller.dispose);

      controller.insertFreeTextFigures(
        parseFreeTextFigureEntry('do a barrel roll into the sunset'),
      );

      expect(controller.figureDrafts, hasLength(1));
      final built = figuresOf(controller.buildDance()).single;
      expect(built.isCustom, isTrue);
      // The parser-gap origin is NOT laundered off by the editor round-trip,
      // so the saved custom keeps its #398 marker and stays reparse-eligible.
      expect(built.customOrigin, CustomOrigin.importGap);
    });

    test('an empty result is a no-op', () async {
      final repos = openTestRepositories();
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
      // ignore: unused_result
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
      final controller = await controllerWith(repos, choiceDef());
      addTearDown(controller.dispose);

      final result = await controller.addChoiceOption('adj', 'driving');

      expect(result, AddChoiceResult.duplicate);
      expect(controller.fieldDefs.single.choices, ['driving']);
      expect(controller.customValues['adj'], isNull);
    });

    test('rejects an empty / whitespace-only option', () async {
      final repos = openTestRepositories();
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
