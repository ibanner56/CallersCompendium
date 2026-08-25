import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/editor/program_editor_draft_codec.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({
  String id = 'p1',
  String title = 'Existing',
  String? venue,
  String? venueId,
}) => Program(
  id: id,
  title: title,
  venue: venue,
  venueId: venueId,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps the editor wrapped with the venue-entity-mode scope so a test can flip
/// the toggle live. Returns the notifier so the test can drive it.
Future<ValueNotifier<bool>> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required bool enriched,
  String? programId,
  void Function(String)? onSaved,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final mode = ValueNotifier<bool>(enriched);
  addTearDown(mode.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: dialect,
          child: VenueEntityModeScope(notifier: mode, child: child!),
        ),
      ),
      home: ProgramEditorScreen(
        programId: programId,
        onSaved: onSaved ?? (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return mode;
}

/// Opens the program editor's Tier 2 metadata drawer if it is still collapsed.
Future<void> _expandMoreDetails(WidgetTester tester) async {
  final tile = tester.widget<ExpansionTile>(
    find.byKey(const ValueKey('program-more-details-tile')),
  );
  if (!tile.controller!.isExpanded) {
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('simple mode shows the free-text field, not the picker', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(venue: 'Old Hall'));
    await _pumpEditor(tester, repos, enriched: false, programId: 'p1');
    await _expandMoreDetails(tester);

    expect(find.byKey(const ValueKey('program-venue')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-venue-picker')), findsNothing);
  });

  testWidgets('enriched mode shows the picker, not the free-text field', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(venue: 'Old Hall'));
    await _pumpEditor(tester, repos, enriched: true, programId: 'p1');
    await _expandMoreDetails(tester);

    expect(find.byKey(const ValueKey('program-venue-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-venue')), findsNothing);
    // Legacy free text is surfaced (non-destructive) since no venue is linked.
    expect(
      find.byKey(const ValueKey('program-venue-legacy-text')),
      findsOneWidget,
    );
  });

  testWidgets('all Tier 2 controls work with either venue mode', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(venue: 'Old Hall'));
    final mode = await _pumpEditor(
      tester,
      repos,
      enriched: false,
      programId: 'p1',
    );

    await _expandMoreDetails(tester);
    expect(find.byKey(const ValueKey('program-venue')), findsOneWidget);
    for (final key in const [
      'program-band',
      'program-caller',
      'program-dancer-level',
      'program-notes',
      'program-status',
      'program-hide-alternates',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    mode.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('program-venue')), findsNothing);
    expect(find.byKey(const ValueKey('program-venue-picker')), findsOneWidget);
    for (final key in const [
      'program-band',
      'program-caller',
      'program-dancer-level',
      'program-notes',
      'program-status',
      'program-hide-alternates',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
  });

  testWidgets(
    'flipping the toggle is lossless: free text survives linking a venue',
    (tester) async {
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(_program(venue: 'Old Hall'));

      String? savedId;
      final mode = await _pumpEditor(
        tester,
        repos,
        enriched: false,
        programId: 'p1',
        onSaved: (id) => savedId = id,
      );
      await _expandMoreDetails(tester);

      // Simple mode: free-text field prefilled.
      expect(
        tester.widget<TextFormField>(
          find.byKey(const ValueKey('program-venue')),
        ),
        isNotNull,
      );

      // Flip to enriched and link a saved venue via the picker.
      mode.value = true;
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('venue-picker-input')),
        'grange',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('venue-option-v1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('venue-picker-selected')),
        findsOneWidget,
      );

      // Save and assert BOTH values persisted (lossless).
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();

      expect(savedId, 'p1');
      final saved = await repos.programs.getById('p1');
      expect(saved!.venueId, 'v1');
      expect(saved.venue, 'Old Hall');
    },
  );

  testWidgets(
    'autosave captures a linked venueId and an interrupted build restores it',
    (tester) async {
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(_program(id: 'p1', title: 'Barn Dance'));

      await _pumpEditor(tester, repos, enriched: true, programId: 'p1');
      await _expandMoreDetails(tester);

      // Link a saved venue via the enriched-mode picker.
      await tester.enterText(
        find.byKey(const ValueKey('venue-picker-input')),
        'grange',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('venue-option-v1')));
      await tester.pumpAndSettle();

      // Let the 500 ms autosave debounce fire; the draft carries the venue id.
      await tester.pump(const Duration(milliseconds: 600));
      const key = 'program_editor_draft:p1';
      expect(await repos.settings.contains(key), isTrue);
      expect(decodeProgramDraft(await repos.settings.get(key)).venueId, 'v1');

      // Tear the editor down so the relaunch gets a fresh State (otherwise
      // Flutter reuses the element and never re-runs load/restore).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Simulate an interrupted relaunch: a fresh editor detects the draft and
      // offers to restore it.
      await _pumpEditor(tester, repos, enriched: true, programId: 'p1');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved draft'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('program-draft-restore')));
      await tester.pumpAndSettle();
      await _expandMoreDetails(tester);

      // The restored editor shows the linked venue selected — the venue link
      // survived the interruption.
      expect(
        find.byKey(const ValueKey('venue-picker-selected')),
        findsOneWidget,
      );
    },
  );

  testWidgets('saving in simple mode never clears a pre-existing venueId', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await repos.programs.create(_program(venue: 'Old Hall', venueId: 'v1'));

    await _pumpEditor(tester, repos, enriched: false, programId: 'p1');
    await _expandMoreDetails(tester);
    // Simple mode surfaces the linked venue read-only, non-destructively.
    expect(
      find.byKey(const ValueKey('program-venue-linked-hint')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('program-venue')),
      'Renamed Hall',
    );
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.venue, 'Renamed Hall');
    expect(saved.venueId, 'v1');
  });

  testWidgets('inline-create from the picker adds and links a new venue', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p2', title: 'New night'));

    String? savedId;
    await _pumpEditor(
      tester,
      repos,
      enriched: true,
      programId: 'p2',
      onSaved: (id) => savedId = id,
    );
    await _expandMoreDetails(tester);

    await tester.enterText(
      find.byKey(const ValueKey('venue-picker-input')),
      'Town Hall',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('venue-option-create:Town Hall')),
    );
    await tester.pumpAndSettle();

    // The inline editor sheet opens with the name prefilled; save it.
    expect(find.byKey(const ValueKey('venue-name-field')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();

    // A venue now exists and is linked in the picker.
    final venues = await repos.venues.listAll();
    expect(venues.map((v) => v.name), contains('Town Hall'));
    expect(find.byKey(const ValueKey('venue-picker-selected')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();
    expect(savedId, 'p2');
    final saved = await repos.programs.getById('p2');
    expect(saved!.venueId, venues.single.id);
  });

  testWidgets(
    'inline-create is suppressed on an exact display-name match, not just name',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p3', title: 'Night'));
      // displayName = "Grange Hall, Nelson, NH" — richer than the bare name,
      // and what the picker search matches against.
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Grange Hall', city: 'Nelson', stateProv: 'NH'),
      );

      await _pumpEditor(tester, repos, enriched: true, programId: 'p3');
      await _expandMoreDetails(tester);

      await tester.enterText(
        find.byKey(const ValueKey('venue-picker-input')),
        'Grange Hall, Nelson, NH',
      );
      await tester.pumpAndSettle();

      // The existing venue is offered...
      expect(find.byKey(const ValueKey('venue-option-v1')), findsOneWidget);
      // ...and "Add new venue…" is NOT, so typing a venue's full display name
      // can't slip past the suppression and create a duplicate.
      expect(
        find.byKey(
          const ValueKey('venue-option-create:Grange Hall, Nelson, NH'),
        ),
        findsNothing,
      );
    },
  );
}
