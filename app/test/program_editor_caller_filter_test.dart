import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/track_history_for_all_callers_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Issue #948: the program editor captured the "track calling history for all
/// callers" setting once, inside its first-load guard, and never re-read it.
///
/// The mechanism is worth stating because it is not "the screen never hears
/// about the change": [TrackHistoryForAllCallersScope] is an
/// `InheritedNotifier`, so a toggle **does** rebuild this screen and **does**
/// call `didChangeDependencies`. The dependency fired, the screen rebuilt, and
/// the branch that would have acted on it did not exist. The picker then served
/// call counts scoped to the previous setting for the rest of the screen's life.
///
/// ## Why this asserts on snapshot loads rather than on rendered counts
///
/// The setting changes the caller filter, which changes `CollectionData`'s call
/// tallies and last-called values. The embedded picker does not render either —
/// it lists titles and metadata — so there is no number on screen that moves
/// when the filter does. What is observable, and is exactly the behaviour under
/// test, is that the screen must re-open its subscription: that costs one
/// `CollectionData.load`, and not re-reading the setting costs none.
///
/// Both directions are asserted. Re-subscribing when the value has NOT changed
/// would be issue #340's over-firing — the mirror failure of the staleness this
/// fixes — so the no-op case is pinned to zero extra loads.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  /// Counts `CollectionData.load` runs. `custom_field_defs` is read by that
  /// load and by nothing else this screen does, so it marks a snapshot load —
  /// the same marker `refresh_scopes_test.dart` uses, and it carries the same
  /// caveat: any unrelated read of that table added to this flow would inflate
  /// the count silently.
  final counter = _SnapshotLoadCounter();

  late CompendiumDatabase db;
  late CompendiumRepositories repos;
  late ValueNotifier<bool> trackAll;

  setUp(() async {
    counter.count = 0;
    db = openWidgetTestDatabase(
      executor: NativeDatabase.memory().interceptWith(counter),
      closeOnTearDown: false,
    );
    repos = CompendiumRepositories(db, contraTaxonomy);
    trackAll = ValueNotifier<bool>(false);
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Chase the Squirrel',
        createdAt: now,
        updatedAt: now,
      ),
    );
    // A default caller is what makes the two settings resolve to DIFFERENT
    // filters. Without one the resolver returns null either way — "track all"
    // — and the toggle would be a no-op the screen is right to ignore, so the
    // test would pass without the fix.
    await repos.settings.set(kDefaultProgramCallerKey, 'Ann');
  });

  tearDown(() async {
    trackAll.dispose();
    await db.close();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: TrackHistoryForAllCallersScope(
            notifier: trackAll,
            child: child!,
          ),
        ),
        home: const ProgramEditorScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'toggling "track all callers" re-scopes the picker without reloading the '
    'program under the user',
    (tester) async {
      await pumpEditor(tester);
      final afterLoad = counter.count;
      expect(afterLoad, greaterThan(0), reason: 'the editor loaded');

      // The user types into the title field, then changes the setting. The
      // draft must survive: this screen holds a working copy with debounced
      // autosave, so answering the change with a full reload — which is what
      // the Collection list correctly does — would discard the edit here.
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Unsaved Draft Title',
      );
      await tester.pump();

      trackAll.value = true;
      await tester.pumpAndSettle();

      expect(
        counter.count,
        greaterThan(afterLoad),
        reason:
            'the picker must re-subscribe under the new caller filter; '
            'before #948 the setting was never re-read, so nothing reloaded',
      );
      expect(
        find.text('Unsaved Draft Title'),
        findsOneWidget,
        reason:
            'and the in-progress draft must survive it — reference data only',
      );
    },
  );

  testWidgets('two changes that cancel out within one frame cost NOTHING '
      '(issue #340: the mirror failure)', (tester) async {
    await pumpEditor(tester);
    final afterLoad = counter.count;

    // Toggled away and back before the frame is built. Flutter coalesces the
    // two notifications into one `didChangeDependencies`, which observes the
    // value it started at.
    //
    // Zero re-subscribes is the CORRECT answer here, and it is a consequence
    // of the design rather than luck: the gate compares against the value the
    // live subscription was opened with, not against the previous value seen.
    // Comparing against the previous value would fire twice for a round trip
    // that changed nothing — over-firing, which is the failure that pulls
    // opposite to the staleness #948 reports. Both have to hold at once.
    //
    // This assertion was written expecting 2 and the code returned 0. The
    // expectation was wrong, not the code; recorded because a test bent to
    // match an implementation is worth less than one that caught a design
    // being better than assumed.
    trackAll
      ..value = true
      ..value = false;
    await tester.pumpAndSettle();

    expect(
      counter.count,
      afterLoad,
      reason:
          'the subscription is already serving this filter, so nothing was '
          'asked for and nothing must be reloaded',
    );
  });
}

class _SnapshotLoadCounter extends drift.QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('custom_field_defs')) count++;
    return executor.runSelect(statement, args);
  }
}
