import 'dart:ui' show PointerDeviceKind;

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/collection_filter_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';
import 'package:compendium_app/src/widgets/selectable_content.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  required String title,
  List<String> tagIds = const [],
  List<Figure> figures = const [],
  String hook = '',
  String callingNotes = '',
}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: tagIds,
  figures: figures,
  hook: hook,
  callingNotes: callingNotes,
  createdAt: _now,
  updatedAt: _now,
);

/// The text a Ctrl-A, Ctrl-C copy puts on the clipboard.
Future<String> _copyAll(WidgetTester tester, Finder focusOn) async {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  // A primary click inside the region gives it focus; Ctrl-A / Ctrl-C then act
  // on the whole region.
  await tester.tap(focusOn);
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  return copied ?? '';
}

Future<CollectionFilterController> _pumpDetail(
  WidgetTester tester,
  CompendiumRepositories repos,
  String danceId,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final filter = CollectionFilterController();
  addTearDown(filter.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: dialect,
          child: CollectionFilterScope(controller: filter, child: child!),
        ),
      ),
      home: DanceDetailScreen(danceId: danceId),
    ),
  );
  await tester.pumpAndSettle();
  return filter;
}

/// [testWidgets] on [platform]. The override is cleared in a `finally` because
/// the framework checks that debug variables are unset *before* tear-downs run.
void _testOn(
  TargetPlatform platform,
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelectableContent platform gate', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SelectableContent(child: Text('hello'))),
      ),
    );

    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      _testOn(platform, 'wraps its child in a SelectionArea on $platform', (
        tester,
      ) async {
        await pump(tester);
        expect(find.byType(SelectionArea), findsOneWidget);
      });
    }

    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      _testOn(platform, 'returns the child unchanged on $platform', (
        tester,
      ) async {
        await pump(tester);
        expect(find.byType(SelectionArea), findsNothing);
        expect(find.byType(SelectableRegion), findsNothing);
        expect(find.text('hello'), findsOneWidget);
      });
    }
  });

  group('figure rows', () {
    Future<void> pumpTable(WidgetTester tester, Figure figure) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              body: SelectableContent(
                child: FigureTable(
                  figures: [figure],
                  phraseStructure: PhraseStructure.parse('1*2*4'),
                  renderer: FigureRenderer(contraTaxonomy),
                  dialect: Dialect.larksRobins,
                ),
              ),
            ),
          ),
        );

    final figure = Figure(
      move: 'swing',
      params: const {'beats': 8},
      note: 'with your neighbor',
    );

    _testOn(
      TargetPlatform.linux,
      'a copy is the figure and its note, without the beats',
      (tester) async {
        await pumpTable(tester, figure);
        final copied = await _copyAll(tester, find.text('with your neighbor'));
        // The figure and its note are separate lines, not run together.
        final lines = copied.trim().split('\n');
        expect(lines.last, 'with your neighbor');
        expect(lines[lines.length - 2].toLowerCase(), contains('swing'));
        expect(copied, isNot(contains('8 beats')));
      },
    );

    testWidgets('a figure row announces the same label with selection on', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      Future<String> label(TargetPlatform platform) async {
        debugDefaultTargetPlatformOverride = platform;
        await pumpTable(tester, figure);
        await tester.pumpAndSettle();
        final row = find.ancestor(
          of: find.text('with your neighbor'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label != null,
          ),
        );
        return tester.getSemantics(row.first).label;
      }

      late final String phone;
      late final String desktop;
      try {
        phone = await label(TargetPlatform.android);
        desktop = await label(TargetPlatform.linux);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        handle.dispose();
      }
      expect(phone, contains('8 beats'));
      expect(desktop, phone);
      // One announcement of the beats, not two.
      expect('8 beats'.allMatches(desktop), hasLength(1));
    });
  });

  group('dance detail', () {
    void detailTest(
      String description,
      Future<void> Function(WidgetTester) body, {
      TargetPlatform platform = TargetPlatform.linux,
    }) => _testOn(platform, description, body);

    detailTest('a tag chip click still filters the Collection', (tester) async {
      final repos = openTestRepositories();
      await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
      await repos.dances.create(
        _dance(id: 'd1', title: 'Tagged', tagIds: ['t1']),
      );
      final filter = await _pumpDetail(tester, repos, 'd1');
      await tester.tap(find.byKey(const ValueKey('tag-filter-chip-t1')));
      await tester.pumpAndSettle();
      expect(filter.pending?.tagId, 't1');
    });

    detailTest('the tag names stay out of a copy', (tester) async {
      final repos = openTestRepositories();
      await repos.tags.upsert(Tag(id: 't1', name: 'zesty-tag'));
      await repos.dances.create(
        _dance(id: 'd1', title: 'Tagged', tagIds: ['t1'], hook: 'a hook'),
      );
      await _pumpDetail(tester, repos, 'd1');
      final copied = await _copyAll(tester, find.text('a hook'));
      expect(copied, contains('a hook'));
      expect(copied, isNot(contains('zesty-tag')));
    });

    detailTest('a link in the notes copies once and a click opens it', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(id: 'target', title: 'Target Dance', hook: 'target-hook-marker'),
      );
      await repos.dances.create(
        _dance(
          id: 'd1',
          title: 'Source Dance',
          callingNotes: 'Adapted from Target Dance for beginners.',
        ),
      );
      await _pumpDetail(tester, repos, 'd1');
      final copied = await _copyAll(tester, find.text('Source Dance'));
      // The link is part of its sentence: no line break around its text.
      expect(copied, contains('Adapted from Target Dance for beginners.'));
      expect(copied, contains('Source Dance\n'));
      expect('Target Dance'.allMatches(copied), hasLength(1));

      await tester.tap(find.text('Target Dance'));
      await tester.pumpAndSettle();
      expect(find.text('target-hook-marker'), findsOneWidget);
    });

    detailTest('a secondary tap on text shows Copy and Select all', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(id: 'd1', title: 'Source Dance', hook: 'a hook'),
      );
      await _pumpDetail(tester, repos, 'd1');
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a hook')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      // Nothing is selected yet, so the menu offers Select all alone.
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      final again = await tester.startGesture(
        tester.getCenter(find.text('a hook')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await again.up();
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
    });

    detailTest('on a phone nothing in the detail is selectable', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(id: 'd1', title: 'Source Dance', hook: 'a hook'),
      );
      await _pumpDetail(tester, repos, 'd1');
      expect(find.byType(SelectionArea), findsNothing);
    }, platform: TargetPlatform.android);
  });
}
