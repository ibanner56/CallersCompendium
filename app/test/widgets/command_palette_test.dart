import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
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
}
