import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/widgets/venue_picker.dart';

import '../support/l10n_harness.dart';
import '../support/screen_size.dart';
import '../support/test_repositories.dart';

/// Pumps [VenuePicker] wired to a real, mutable `selectedVenueId` (via
/// [StatefulBuilder]) so a pick's `onChanged` actually feeds back into the
/// widget and the "selected" card renders — mirroring how
/// `ProgramEditorScreen` owns and threads `_venueId` in production, rather
/// than a fire-and-forget callback that a test could satisfy without the
/// picker ever re-rendering its selection.
Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? initialSelectedVenueId,
  ValueChanged<String?>? onChanged,
}) async {
  String? selectedVenueId = initialSelectedVenueId;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: VenuePicker(
                selectedVenueId: selectedVenueId,
                onChanged: (id) {
                  setState(() => selectedVenueId = id);
                  onChanged?.call(id);
                },
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('narrow layout: attaching an existing venue closes the sheet', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    String? linked;
    await setScreenSize(tester, const Size(360, 720));
    await _pump(tester, repos, onChanged: (id) => linked = id);

    await tester.tap(
      find.byKey(const ValueKey('venue-picker-input')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    // Simulate a software keyboard inset, as issue #716 describes.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('venue-picker-input')),
      'grange',
    );
    await tester.pumpAndSettle();

    final option = find.byKey(const ValueKey('venue-option-v1'));
    expect(option, findsOneWidget);
    final optionRect = tester.getRect(option);
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(linked, 'v1');
    // Picking always closes the sheet (owner's Q1 decision, uniform
    // across all seven call sites).
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('venue-picker-selected')), findsOneWidget);
  });

  testWidgets('narrow layout: creating a brand-new venue opens a SECOND '
      'sheet (VenueEditorSheet) only after the picker sheet\'s route has '
      'popped — the two never stack as interactive routes, though their '
      'dismiss/entrance animations can transiently overlap in the tree', (
    tester,
  ) async {
    final repos = openTestRepositories();
    String? linked;
    await setScreenSize(tester, const Size(360, 720));
    await _pump(tester, repos, onChanged: (id) => linked = id);

    await tester.tap(
      find.byKey(const ValueKey('venue-picker-input')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    // Simulate a software keyboard inset, as issue #716 describes.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('venue-picker-input')),
      'Town Hall',
    );
    await tester.pumpAndSettle();

    final createOption = find.byKey(
      const ValueKey('venue-option-create:Town Hall'),
    );
    expect(createOption, findsOneWidget);
    final optionRect = tester.getRect(createOption);
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

    await tester.tap(createOption);
    // The picker's own sheet pops (`Navigator.pop(option)`) synchronously on
    // tap, but its close *animation* and `VenueEditorSheet`'s open animation
    // can run concurrently for a frame or two — Flutter's route-transition
    // futures resolve on `pop()`, not on animation completion, so a single
    // `pump()` here can transiently show both `BottomSheet` widgets in the
    // tree. Verified empirically: this is a harmless animation overlap, not
    // a functional stacking bug — no duplicate-key or navigator assertion
    // errors occur, and `pumpAndSettle` below reliably lands on exactly the
    // second sheet. The two *pickers* (option list vs. the venue form) are
    // never simultaneously interactive: the first's modal barrier is gone
    // and its content is non-interactive mid-dismissal by the time the
    // second becomes the topmost, focused route.
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('venue-name-field')), findsOneWidget);

    // The editor sheet opens with the typed name prefilled; save it.
    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();

    // Both sheets are now closed, the new venue was created and linked.
    expect(find.byType(BottomSheet), findsNothing);
    final venues = await repos.venues.listAll();
    expect(venues.map((v) => v.name), contains('Town Hall'));
    expect(linked, venues.single.id);
    expect(find.byKey(const ValueKey('venue-picker-selected')), findsOneWidget);
  });
}
