// Flutter's accessibility guidelines, run against the real app .
//
// `docs/research/accessibility-baseline.md` promises automated checks; until
// now no test ran `meetsGuideline`. Each case here pumps the full app once,
// navigates to a core screen through the app's own UI, and checks it three
// ways:
//
//  1. `labeledTapTargetGuideline` — every tappable semantics node has a label
//     (catches an inert, unlabelled extra stop such as an right-click
//     recogniser).
//  2. A 24×24 px minimum tap target — the baseline's own floor (WCAG 2.5.8),
//     not Android's 48.
//  3. A RenderFlex-overflow sweep at 360×780 and 412×915 logical px with the
//     system text scale at 2.0×, using the bundled fonts (Ahem roughly
//     doubles some overflows and hides others).
//
// Cost: one full-app pump and navigation per screen, then a resize and a text
// scale change for the overflow passes, so each screen is a single test.
// Screens are separate `testWidgets` so a failure names its screen and CI can
// shard them.
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/tag_manager_screen.dart';
import 'package:compendium_app/src/widgets/advanced_query_builder.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_wakelock.dart';
import 'support/full_app_harness.dart';
import 'support/real_fonts.dart';

const _phone = Size(360, 780);
const _bigPhone = Size(412, 915);

/// The baseline's minimum tap target, in logical px (WCAG 2.5.8).
const _minimumTapTarget = MinimumTapTargetGuideline(
  size: Size(24, 24),
  link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html',
);

Future<AppData> _seed() async {
  final appData = openTestAppData();
  final repos = appData.repositories;
  final stamp = DateTime.utc(2026, 1, 1);
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(id: 'c1', name: 'Gene Hubert'),
  );
  for (final (id, title) in [
    ('d1', 'Petronella'),
    ('d2', 'The Baby Rose'),
    ('d3', 'Rory O\'More'),
  ]) {
    await repos.dances.create(
      Dance(
        id: id,
        title: title,
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
  }
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 't1', name: 'chestnut'));
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Autumn Ball',
      slots: [
        ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
        ProgramSlot(id: 's3', position: 2, text: 'Waltz'),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
  return appData;
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

/// Runs [body] collecting every framework error, so a test reports all the
/// overflows on a screen rather than only the first.
Future<List<String>> _collectErrors(Future<void> Function() body) async {
  final original = FlutterError.onError;
  final errors = <String>[];
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return errors;
}

/// Pumps the full app at [_phone], runs [navigate] to reach a screen, then
/// applies the three checks above.
void _screen(
  String name,
  Future<void> Function(WidgetTester tester) navigate, {
  required Finder landedOn,
  Future<void> Function(WidgetTester tester)? atLargeText,
}) {
  testWidgets(name, (tester) async {
    await loadBundledFonts();
    installFakeWakelock();
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final appData = await _seed();
    await _setSize(tester, _phone);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();
      await navigate(tester);
      expect(tester.takeException(), isNull, reason: 'navigating to $name');
      // Guards against a sweep that quietly checks the wrong screen.
      expect(landedOn, findsWidgets, reason: 'did not reach $name');

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(_minimumTapTarget));

      final overflows = <String>[];
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      for (final size in [_phone, _bigPhone]) {
        final errors = await _collectErrors(() => _setSize(tester, size));
        overflows.addAll([
          for (final e in errors)
            if (e.contains('overflowed')) '${size.width.toInt()}dp: $e',
        ]);
        // Anything that is not an overflow is a real failure of its own.
        expect(
          errors.where((e) => !e.contains('overflowed')),
          isEmpty,
          reason: '$name at ${size.width.toInt()}dp, 2.0x',
        );
      }
      expect(overflows, isEmpty, reason: '$name overflows at 2.0x text');
      if (atLargeText != null) {
        await _setSize(tester, _phone);
        await atLargeText(tester);
      }
    } finally {
      // Disposed in the body: the framework checks handles before teardowns
      // run, and a failing expect must not leak the handle.
      semantics.dispose();
    }
  });
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _openProgramSummary(WidgetTester tester) async {
  await tester.tap(find.text('Programs'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Autumn Ball'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _screen('Collection', (_) async {}, landedOn: find.text('Petronella'));

  _screen('Collection, selection mode', (tester) async {
    await _tapKey(tester, 'collection-more-actions');
    await _tapKey(tester, 'batch-select');
  }, landedOn: find.byKey(const ValueKey('batch-exit')));

  _screen('Advanced search', (tester) async {
    await _tapKey(tester, 'advanced-panel');
  }, landedOn: find.byType(AdvancedQueryBuilder));

  _screen('Programs list', (tester) async {
    await tester.tap(find.text('Programs'));
    await tester.pumpAndSettle();
  }, landedOn: find.byKey(const ValueKey('new-program')));

  _screen(
    'Program summary',
    _openProgramSummary,
    landedOn: find.byKey(const ValueKey('summary-screen-p1')),
  );

  _screen('Program builder', (tester) async {
    await _openProgramSummary(tester);
    await _tapKey(tester, 'open-builder');
  }, landedOn: find.byType(ProgramEditorScreen));

  _screen('Perform', (tester) async {
    await _openProgramSummary(tester);
    await _tapKey(tester, 'summary-perform');
  }, landedOn: find.byType(PerformProgramScreen));

  _screen(
    'Perform, Adjust sheet',
    (tester) async {
      await _openProgramSummary(tester);
      await _tapKey(tester, 'summary-perform');
      // On a phone Adjust lives in the toolbar's overflow menu.
      await _tapKey(tester, 'perform-overflow-menu');
      await _tapKey(tester, 'perform-adjust-menu');
    },
    landedOn: find.byKey(const ValueKey('adjust-done')),
    atLargeText: (tester) async {
      // Done was pushed past the right edge of a 360dp screen. Closing
      // the sheet any other way discards the edits, so Done must stay reachable.
      final done = find.byKey(const ValueKey('adjust-done'));
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.getRect(done).right, lessThanOrEqualTo(_phone.width));
    },
  );

  // The form is a lazy list, so on a 780dp surface this sees only its first
  // screenful; the Type and Formation dropdowns are covered on a tall surface
  // by `dance_editor_narrow_test.dart`.
  _screen('Dance editor', (tester) async {
    await _tapKey(tester, 'new-dance');
  }, landedOn: find.byType(DanceEditorScreen));

  _screen('Tags manager', (tester) async {
    Navigator.of(
      tester.element(find.byType(AppShell)),
    ).push(MaterialPageRoute<void>(builder: (_) => const TagManagerScreen()));
    await tester.pumpAndSettle();
    // The longest sort label ("by dance count") is the one that overflowed
    // the filter row .
    await _tapKey(tester, 'tag-sort');
    await _tapKey(tester, 'tag-sort-count');
  }, landedOn: find.byType(TagManagerScreen));

  _screen('Import review', (tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).importDances();
    await tester.pumpAndSettle();
  }, landedOn: find.byType(ImportReviewScreen));
}
