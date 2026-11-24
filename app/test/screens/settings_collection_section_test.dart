// Settings ▸ Collection ▸ Saved searches (#2325): every saved search, those
// this version cannot read last under Needs attention, each renamed or
// deleted with Undo, against a real in-memory database.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings/collection_section.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final _day = DateTime.utc(2026, 11, 23);

Future<SavedSearch> _seed(
  CompendiumRepositories repos,
  String name,
  String text,
) => repos.savedSearches.create(
  name: name,
  spec: SavedSearchSpec.fromPanelState(
    CollectionPanelState(text: text),
    today: _day,
  ).value!,
);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  ValueNotifier<bool>? inView,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      // The app shell keeps Settings mounted and turns tickers off while
      // another destination is shown; [inView] does the same.
      home: ValueListenableBuilder<bool>(
        valueListenable: inView ?? ValueNotifier(true),
        builder: (context, visible, child) =>
            TickerMode(enabled: visible, child: child!),
        child: const Scaffold(body: CollectionSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Dances comes first, then every saved search by name, and one '
      'that cannot be read last, under Needs attention', (tester) async {
    final repos = openTestRepositories();
    final b = await _seed(repos, 'Becket', 'becket');
    final a = await _seed(repos, 'Alpha', 'alpha');
    await repos.settings.set('${savedSearchKeyPrefix}future', const {
      'v': 99,
      'name': 'Newer',
    });
    await _pump(tester, repos);

    double top(Finder f) => tester.getTopLeft(f).dy;
    final dances = find.text('Dances');
    final rowA = find.byKey(ValueKey('settings-saved-search-${a.id}'));
    final rowB = find.byKey(ValueKey('settings-saved-search-${b.id}'));
    final attention = find.text('Needs attention');
    final future = find.byKey(
      const ValueKey('settings-saved-search-unreadable-future'),
    );
    expect(
      find.byKey(const ValueKey('collection-sort-ignore-articles')),
      findsOne,
    );
    expect(top(dances), lessThan(top(find.text('Saved searches'))));
    expect(top(rowA), lessThan(top(rowB)));
    expect(top(rowB), lessThan(top(attention)));
    expect(top(attention), lessThan(top(future)));
    expect(find.text('Newer'), findsNothing);
  });

  testWidgets('says so when there are none', (tester) async {
    await _pump(tester, openTestRepositories());

    expect(
      find.byKey(const ValueKey('settings-saved-searches-none')),
      findsOneWidget,
    );
  });

  testWidgets('Rename changes the name and keeps what is saved', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final pet = await _seed(repos, 'Pet', 'petronella');
    await _pump(tester, repos);

    await _tap(tester, 'settings-saved-search-rename-${pet.id}');
    await tester.enterText(
      find.byKey(const ValueKey('saved-search-name-field')),
      'Petronella only',
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'saved-search-name-save');

    final stored = await repos.savedSearches.get(pet.id);
    expect(stored!.name, 'Petronella only');
    expect(stored.spec.toJson(), pet.spec.toJson());
    expect(find.text('Petronella only'), findsOneWidget);
  });

  testWidgets('Delete removes it, and Undo brings back the same bytes', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final pet = await _seed(repos, 'Pet', 'petronella');
    final before = await repos.settings.get(pet.settingsKey);
    await _pump(tester, repos);

    await _tap(tester, 'settings-saved-search-delete-${pet.id}');

    expect(await repos.settings.get(pet.settingsKey), isNull);
    expect(
      find.byKey(ValueKey('settings-saved-search-${pet.id}')),
      findsNothing,
    );
    await _tap(tester, 'saved-search-undo');
    expect(await repos.settings.get(pet.settingsKey), before);
    expect(
      find.byKey(ValueKey('settings-saved-search-${pet.id}')),
      findsOneWidget,
    );
  });

  testWidgets('a saved search something uses is not deleted, and the '
      'message names each use', (tester) async {
    final repos = openTestRepositories();
    repos.savedSearches.usage.register(
      'test',
      (id) async => const [
        SavedSearchUse(kind: 'slotRule', label: 'Contra night, slot 3'),
      ],
    );
    final pet = await _seed(repos, 'Pet', 'petronella');
    await _pump(tester, repos);

    await _tap(tester, 'settings-saved-search-delete-${pet.id}');

    expect(find.byKey(const ValueKey('saved-search-in-use')), findsOneWidget);
    expect(find.text('Contra night, slot 3'), findsOneWidget);
    expect(await repos.savedSearches.get(pet.id), isNotNull);
  });

  testWidgets('one that cannot be read is explained, can be deleted, and '
      'Undo brings back its exact value', (tester) async {
    final repos = openTestRepositories();
    const key = '${savedSearchKeyPrefix}future';
    const value = {'v': 99, 'name': 'Newer', 'text': 'Petronella'};
    await repos.settings.set(key, value);
    await _pump(tester, repos);

    await _tap(tester, 'settings-saved-search-unreadable-future');
    expect(find.byKey(const ValueKey('saved-search-unreadable')), findsOne);
    await _tap(tester, 'saved-search-unreadable-delete');

    expect(await repos.settings.get(key), isNull);
    expect(
      find.byKey(const ValueKey('settings-saved-search-unreadable-future')),
      findsNothing,
    );
    await _tap(tester, 'saved-search-undo');
    expect(await repos.settings.get(key), value);
    expect(
      find.byKey(const ValueKey('settings-saved-search-unreadable-future')),
      findsOneWidget,
    );
  });

  testWidgets('shown again, it lists what was saved, renamed or deleted '
      'elsewhere meanwhile', (tester) async {
    final repos = openTestRepositories();
    final pet = await _seed(repos, 'Pet', 'petronella');
    final inView = ValueNotifier(true);
    addTearDown(inView.dispose);
    await _pump(tester, repos, inView: inView);

    inView.value = false;
    await tester.pumpAndSettle();
    final becket = await _seed(repos, 'Becket', 'becket');
    await repos.savedSearches.save(
      SavedSearch(id: pet.id, name: 'Petronella only', spec: pet.spec),
    );
    inView.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Becket'), findsOneWidget);
    expect(find.text('Petronella only'), findsOneWidget);

    inView.value = false;
    await tester.pumpAndSettle();
    await repos.savedSearches.delete(becket.id);
    inView.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Becket'), findsNothing);
  });

  testWidgets('Rename keeps what is stored now, not what was listed', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final pet = await _seed(repos, 'Pet', 'petronella');
    await _pump(tester, repos);
    // Updated by sync from another device after the list was read.
    final newer = SavedSearchSpec.fromPanelState(
      CollectionPanelState(text: 'chorus'),
      today: _day,
    ).value!;
    await repos.savedSearches.save(
      SavedSearch(id: pet.id, name: 'Pet', spec: newer),
    );

    await _tap(tester, 'settings-saved-search-rename-${pet.id}');
    await tester.enterText(
      find.byKey(const ValueKey('saved-search-name-field')),
      'Chorus',
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'saved-search-name-save');

    final stored = await repos.savedSearches.get(pet.id);
    expect(stored!.name, 'Chorus');
    expect(stored.spec.toJson(), newer.toJson());
  });

  testWidgets('Rename of one deleted elsewhere is refused and not brought '
      'back', (tester) async {
    final repos = openTestRepositories();
    final pet = await _seed(repos, 'Pet', 'petronella');
    await _pump(tester, repos);
    await repos.savedSearches.delete(pet.id);

    await _tap(tester, 'settings-saved-search-rename-${pet.id}');

    expect(find.byKey(const ValueKey('saved-search-name-field')), findsNothing);
    expect(await repos.settings.get(pet.settingsKey), isNull);
    expect(
      find.byKey(ValueKey('settings-saved-search-${pet.id}')),
      findsNothing,
    );
  });
}
