import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/widgets/command_palette.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Program _program(String id, String title) => Program(
  id: id,
  title: title,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Pumps a host that opens the palette and records its popped result into the
/// returned single-element holder (read `holder[0]` after the palette closes).
Future<List<CommandResult?>> _openPalette(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  final holder = <CommandResult?>[null];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  holder[0] = await showCommandPalette(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return holder;
}

void main() {
  testWidgets('lists dances and programs grouped, filtered by title', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Broken Sixpence'));
    await repos.dances.create(_dance('d2', 'Chorus Jig'));
    await repos.programs.create(_program('p1', 'Spring Social'));

    await _openPalette(tester, repos);

    // Groups + all items visible before typing.
    expect(find.text('Dances'), findsOneWidget);
    expect(find.text('Programs'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('command-result-dance-d1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('command-result-program-p1')),
      findsOneWidget,
    );

    // Typing filters by title (case-insensitive substring).
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-field')),
      'jig',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('command-result-dance-d2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('command-result-dance-d1')), findsNothing);
    expect(
      find.byKey(const ValueKey('command-result-program-p1')),
      findsNothing,
    );
  });

  testWidgets('arrow keys move the highlight and Enter selects the result', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Alpha'));
    await repos.dances.create(_dance('d2', 'Beta'));

    final resultFuture = _openPalette(tester, repos);
    final holder = await resultFuture;

    // Move down once (0 -> 1) then activate with Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final result = holder[0];
    expect(result, isNotNull);
    expect(result!.kind, CommandResultKind.dance);
    // Titles sort A→Z: index 1 is "Beta" (d2).
    expect(result.id, 'd2');
  });

  testWidgets('tapping a result selects it', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program('p1', 'Gala'));

    final holder = await _openPalette(tester, repos);
    await tester.tap(find.byKey(const ValueKey('command-result-program-p1')));
    await tester.pumpAndSettle();

    expect(holder[0]?.kind, CommandResultKind.program);
    expect(holder[0]?.id, 'p1');
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Alpha'));

    await _openPalette(tester, repos);
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-field')),
      'zzzzz',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('command-palette-empty')), findsOneWidget);
  });

  testWidgets(
    'keeps the highlighted row on-screen when navigating past the fold',
    (tester) async {
      final repos = openTestRepositories();
      // Enough dances to overflow the palette's max height, plus a program so
      // the list also contains a differently-sized group header.
      for (var i = 0; i < 8; i++) {
        await repos.dances.create(
          _dance('d$i', 'Dance ${i.toString().padLeft(2, '0')}'),
        );
      }
      await repos.programs.create(_program('p1', 'Program One'));

      await _openPalette(tester, repos);

      // Walk down to the last result (index 8: the program).
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();

      // The highlighted last row must be scrolled into the visible viewport.
      final tile = find.byKey(const ValueKey('command-result-program-p1'));
      expect(tile, findsOneWidget);
      final dialogRect = tester.getRect(
        find.byKey(const ValueKey('command-palette')),
      );
      final tileRect = tester.getRect(tile);
      expect(tileRect.top, greaterThanOrEqualTo(dialogRect.top));
      expect(tileRect.bottom, lessThanOrEqualTo(dialogRect.bottom + 0.5));
    },
  );

  group('assistive technology', () {
    // Arrow-key movement keeps focus in the text field, so a screen reader
    // never hears which row Enter will open unless the palette says so;
    // `ListTile.selected` only flips a flag on an unfocused node.
    testWidgets('moving the highlight announces the highlighted result', (
      tester,
    ) async {
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final announcements = <String>[];
      messenger.setMockMessageHandler(SystemChannels.accessibility.name, (
        ByteData? message,
      ) async {
        final decoded = SystemChannels.accessibility.codec.decodeMessage(
          message,
        );
        if (decoded is Map && decoded['type'] == 'announce') {
          final data = decoded['data'] as Map;
          announcements.add(data['message'] as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMessageHandler(
          SystemChannels.accessibility.name,
          null,
        ),
      );

      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Alpha Reel'));
      await repos.dances.create(_dance('d2', 'Beta Jig'));
      await _openPalette(tester, repos);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(announcements, hasLength(1));
      expect(announcements.single, contains('Beta Jig'));
      expect(announcements.single, contains('2 of 2'));

      // The highlighted row is also flagged selected for AT that inspects it.
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('command-result-dance-d2')),
        ),
        isSemantics(isSelected: true),
      );
      handle.dispose();
    });

    testWidgets('the result count is a live region that tracks the filter', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Alpha Reel'));
      await repos.dances.create(_dance('d2', 'Beta Jig'));
      await repos.programs.create(_program('p1', 'Spring Social'));
      await _openPalette(tester, repos);

      Finder liveRegionWith(String text) => find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      );

      expect(liveRegionWith('3 results'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('command-palette-field')),
        'beta',
      );
      await tester.pumpAndSettle();
      expect(liveRegionWith('1 result'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('command-palette-field')),
        'zzz',
      );
      await tester.pumpAndSettle();
      // The empty state is announced the same way.
      expect(liveRegionWith('No matches for that search.'), findsOneWidget);
    });
  });

  group('matching and order (FIND-12)', () {
    List<String> dancesShown(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(
        find.byWidgetPredicate(
          (w) =>
              w is ListTile &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'command-result-dance-',
              ),
        ),
      ))
        (tile.key! as ValueKey<String>).value.substring(
          'command-result-dance-'.length,
        ),
    ];

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(
        find.byKey(const ValueKey('command-palette-field')),
        text,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an exact title is listed before mid-title matches, even '
        'past the per-group cap', (tester) async {
      final repos = openTestRepositories();
      // Ten "...cheyenne..." titles sort ahead of "Hey" alphabetically.
      for (var i = 0; i < 10; i++) {
        await repos.dances.create(_dance('c$i', 'Cheyenne $i'));
      }
      await repos.dances.create(_dance('hey', 'Hey'));
      await repos.dances.create(_dance('heyday', 'Heyday Reel'));
      await _openPalette(tester, repos);

      await type(tester, 'hey');

      expect(dancesShown(tester).take(2), ['hey', 'heyday']);
    });

    testWidgets('folds diacritics in the title and in the query', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('e', 'École Reel'));
      await repos.dances.create(_dance('o', 'Other'));
      await _openPalette(tester, repos);

      await type(tester, 'ecole');
      expect(dancesShown(tester), ['e']);

      await type(tester, 'ÉCOLE');
      expect(dancesShown(tester), ['e']);
    });

    testWidgets('orders case-insensitively, ignoring a leading article', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('a', 'apple Jig'));
      await repos.dances.create(_dance('b', 'The Banana Reel'));
      await repos.dances.create(_dance('c', 'Cherry Waltz'));
      await _openPalette(tester, repos);

      // Binary order would put "The Banana Reel" and "Cherry Waltz" before
      // "apple Jig", and "The ..." under T.
      expect(dancesShown(tester), ['a', 'b', 'c']);
    });

    testWidgets('keeps the article in the order when the setting is off', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('b', 'The Banana Reel'));
      await repos.dances.create(_dance('c', 'Cherry Waltz'));
      final holder = ValueNotifier<bool>(false);
      addTearDown(holder.dispose);
      await tester.pumpWidget(
        SortIgnoreArticlesScope(
          notifier: holder,
          child: MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            builder: (context, child) =>
                RepositoriesScope(repositories: repos, child: child!),
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCommandPalette(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(dancesShown(tester), ['c', 'b']);
    });
  });
}
