import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/custom_fields_screen.dart';
import 'package:compendium_app/src/screens/tag_colors_screen.dart';
import 'package:compendium_app/src/screens/venue_manager_screen.dart';
import 'package:compendium_app/src/widgets/tag_chip.dart';
import 'package:compendium_app/src/widgets/venue_picker.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Issue #768: the reference-data surfaces render from a stream rather than
/// from a one-shot read plus a reload after each of their own writes.
///
/// ## What every test here does, and why it is the only shape that works
///
/// Each writes through the repository **from outside the widget** and asserts
/// the render changes with no interaction. That is the whole property: before
/// the conversion these screens learned about a write only by performing it
/// themselves, so a write made anywhere else was invisible to them.
///
/// Driving the screen's own buttons would prove nothing — those paths used to
/// call `_load()` and would have passed either way. The external write is what
/// makes the assertion discriminate.
///
/// ## On the staleness being latent
///
/// These four are modal routes today: while one is mounted, nothing else is on
/// screen to write its table, so no user can currently reach the stale state
/// these guards describe. They are worth having anyway, and the reason is
/// visible elsewhere in this issue — the Collection and Programs lists had the
/// same "I am the only writer while I am mounted" property, and it stopped
/// being true when they were re-parented into a kept-alive `IndexedStack`,
/// without a line of their code changing. These tests fail if that recurs here.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> pump(
    WidgetTester tester,
    CompendiumRepositories repos,
    Widget home,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) =>
            RepositoriesScope(repositories: repos, child: child!),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('venue manager: a venue created elsewhere appears', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await pump(tester, repos, const VenueManagerScreen());
    expect(find.text('Grange Hall'), findsOneWidget);
    expect(find.text('Town Hall'), findsNothing);

    await repos.venues.upsert(Venue(id: 'v2', name: 'Town Hall'));
    await tester.pumpAndSettle();

    expect(find.text('Town Hall'), findsOneWidget);
  });

  testWidgets('venue manager: a rename made elsewhere is rendered', (
    tester,
  ) async {
    // Narrower than the create, and the more interesting half: the row count is
    // unchanged, so a list that merely rebuilt without re-reading would still
    // show the right NUMBER of venues and the wrong name.
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await pump(tester, repos, const VenueManagerScreen());
    expect(find.text('Grange Hall'), findsOneWidget);

    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall Annexe'));
    await tester.pumpAndSettle();

    expect(find.text('Grange Hall Annexe'), findsOneWidget);
    expect(find.text('Grange Hall'), findsNothing);
  });

  testWidgets('tag colours: a tag created elsewhere appears', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await pump(tester, repos, const TagColorsScreen());
    expect(find.text('smooth'), findsOneWidget);

    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'tricky'));
    await tester.pumpAndSettle();

    expect(find.text('tricky'), findsOneWidget);
  });

  testWidgets('tag colours: a colour set elsewhere reaches the chip '
      '(the assertion the deleted local splice made unfailable)', (
    tester,
  ) async {
    // This screen used to apply its own colour edits with a `setState`
    // splice, so a test asserting "the colour changed" passed whether or not
    // the data layer delivered anything. Writing the colour from OUTSIDE is
    // what removes that escape route: nothing in the widget has been told.
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await pump(tester, repos, const TagColorsScreen());

    // Read the colour off the rendered `TagChip` — the same widget the
    // Collection and dance detail draw — rather than off something private to
    // this screen. If the chip stops carrying the colour this stops testing
    // it, which should surface as a failure rather than a quiet pass.
    int? renderedColour() => tester.widget<TagChip>(find.byType(TagChip)).color;

    expect(renderedColour(), isNull, reason: 'no colour set yet');

    // ignore: unused_result
    await repos.tags.upsert(
      Tag(id: 't1', name: 'smooth').withColor(0xFF00FF00),
    );
    await tester.pumpAndSettle();

    expect(
      renderedColour(),
      0xFF00FF00,
      reason: 'the colour must arrive through the stream, not a local splice',
    );
  });

  testWidgets('custom fields: a definition created elsewhere appears', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await pump(tester, repos, const CustomFieldsScreen());
    expect(find.text('Difficulty'), findsNothing);

    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'difficulty',
        label: 'Difficulty',
        type: CustomFieldType.text,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Difficulty'), findsOneWidget);
  });

  testWidgets(
    'venue picker: a rename made elsewhere is rendered in the embedded picker',
    (tester) async {
      // The picker is the only surface here that is not a screen. It lives
      // inside `ProgramEditorScreen`, converted earlier in this issue, so
      // before this change a stream-driven parent hosted a one-shot child.
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      var selected = 'v1';
      await pump(
        tester,
        repos,
        Scaffold(
          body: VenuePicker(
            selectedVenueId: selected,
            onChanged: (id) => selected = id ?? '',
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('venue-picker-selected')),
        findsOneWidget,
      );

      // Renaming the LINKED venue is the assertion that discriminates: the
      // picker renders the selected venue's name from its own list, so a stale
      // list shows the old name while everything else looks correct.
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall Annexe'));
      await tester.pumpAndSettle();

      expect(find.text('Grange Hall Annexe'), findsOneWidget);
      expect(find.text('Grange Hall'), findsNothing);
    },
  );
}
