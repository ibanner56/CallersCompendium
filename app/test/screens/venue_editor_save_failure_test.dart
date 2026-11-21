import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/venue_editor_sheet.dart';
import 'package:compendium_app/src/screens/venue_manager_screen.dart';
import 'package:compendium_app/src/widgets/venue_picker.dart';
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Fails every write to the `venues` table while [failing] is set, so a save
/// fails as a locked or full database would make it fail.
class _VenueWriteFailure extends drift.QueryInterceptor {
  bool failing = false;
  int fired = 0;

  bool _hit(String statement) =>
      failing && RegExp(r'\bvenues\b').hasMatch(statement);

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_hit(statement)) {
      fired++;
      throw Exception('injected venues write failure');
    }
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_hit(statement)) {
      fired++;
      throw Exception('injected venues write failure');
    }
    return executor.runUpdate(statement, args);
  }

  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_hit(statement)) {
      fired++;
      throw Exception('injected venues write failure');
    }
    return executor.runCustom(statement, args);
  }
}

void main() {
  testWidgets('a venue save that fails keeps the sheet open with the edits, '
      'says so, and claims nothing was saved; a retry saves it', (
    tester,
  ) async {
    final failure = _VenueWriteFailure();
    final repos = CompendiumRepositories(
      openWidgetTestDatabase(
        executor: NativeDatabase.memory().interceptWith(failure),
      ),
      contraTaxonomy,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: const VenueManagerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('venue-manager-empty-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('venue-name-field')),
      'Grange Hall',
    );
    await tester.enterText(
      find.byKey(const ValueKey('venue-city-field')),
      'Greenfield',
    );
    failure.failing = true;

    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();

    expect(failure.fired, greaterThan(0), reason: 'the failure must fire');
    // Still open, with the user's edits.
    expect(find.byKey(const ValueKey('venue-editor-save')), findsOneWidget);
    expect(find.text('Grange Hall'), findsWidgets);
    expect(find.text('Greenfield'), findsOneWidget);
    // Says the save failed, in the app's words.
    expect(
      find.byKey(const ValueKey('venue-editor-save-error')),
      findsOneWidget,
    );
    expect(
      find.text(
        "Couldn't save the venue. Your changes are still here. Try again.",
      ),
      findsOneWidget,
    );
    // And claims nothing: no venue in the list or the database.
    expect(find.byKey(const ValueKey('venue-manager-empty')), findsOneWidget);
    expect(await tester.runAsync(repos.venues.listAll), isEmpty);

    // The write works again: Save saves, and the sheet closes.
    failure.failing = false;
    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('venue-editor-save')), findsNothing);
    final saved = await tester.runAsync(repos.venues.listAll);
    expect(saved!.single.name, 'Grange Hall');
    expect(saved.single.city, 'Greenfield');
  });

  testWidgets('while a save is in flight, a second tap saves nothing more and '
      'the sheet cannot be closed; it closes once the save succeeds', (
    tester,
  ) async {
    final writes = <Venue>[];
    final done = Completer<void>();
    var closed = false;
    Venue? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await VenueEditorSheet.show(
                  context,
                  seedName: 'Grange Hall',
                  save: (venue) {
                    writes.add(venue);
                    return done.future;
                  },
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey('venue-editor-save'));
    // Two taps in one frame: the second must not start another write.
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(writes, hasLength(1));

    // Neither Cancel nor a tap above the sheet closes it mid-save.
    final cancel = tester.widget<TextButton>(
      find.byKey(const ValueKey('venue-editor-cancel')),
    );
    expect(cancel.onPressed, isNull);
    await tester.tapAt(const Offset(400, 10));
    await tester.pump();
    expect(closed, isFalse);
    expect(save, findsOneWidget);

    done.complete();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result?.name, 'Grange Hall');
  });

  testWidgets('creating a venue from the picker: a failed save links nothing '
      'and keeps the sheet; a retry saves, links and selects it', (
    tester,
  ) async {
    final failure = _VenueWriteFailure();
    final repos = CompendiumRepositories(
      openWidgetTestDatabase(
        executor: NativeDatabase.memory().interceptWith(failure),
      ),
      contraTaxonomy,
    );
    String? linked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: VenuePicker(
                selectedVenueId: linked,
                onChanged: (id) => setState(() => linked = id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('venue-picker-input')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('venue-picker-input')),
      'Town Hall',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('venue-option-create:Town Hall')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('venue-name-field')), findsOneWidget);

    failure.failing = true;
    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();
    expect(failure.fired, greaterThan(0), reason: 'the failure must fire');
    expect(
      find.byKey(const ValueKey('venue-editor-save-error')),
      findsOneWidget,
    );
    expect(linked, isNull);
    expect(await tester.runAsync(repos.venues.listAll), isEmpty);

    failure.failing = false;
    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('venue-editor-save')), findsNothing);
    final saved = await tester.runAsync(repos.venues.listAll);
    expect(saved!.single.name, 'Town Hall');
    expect(linked, saved.single.id);
    expect(find.byKey(const ValueKey('venue-picker-selected')), findsOneWidget);
  });
}
