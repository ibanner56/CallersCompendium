import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_app_harness.dart';

const _palette = ValueKey('command-palette');

Future<AppData> _pump(WidgetTester tester) async {
  // Narrow, so the dance detail is a pushed route rather than the inline pane.
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final appData = openTestAppData();
  final repos = appData.repositories;
  final stamp = DateTime.utc(2026, 1, 1);
  await repos.dances.create(
    Dance(id: 'd1', title: 'Petronella', createdAt: stamp, updatedAt: stamp),
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Autumn Ball',
      slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
  await tester.pumpWidget(
    CompendiumApp(
      appData: appData,
      windowService: NoopWindowService(repos.settings),
      integrityCheck: () async => true,
    ),
  );
  await tester.pumpAndSettle();
  return appData;
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey modifier) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _openProgramSummary(WidgetTester tester) async {
  await tester.tap(find.text('Programs'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Autumn Ball'));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(rootBundle.clear);

  testWidgets(
    'Ctrl-K opens the palette from a pushed DanceDetailScreen (narrow layout)',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Petronella'));
      await tester.pumpAndSettle();
      expect(find.byType(DanceDetailScreen), findsOneWidget);

      await _chord(tester, LogicalKeyboardKey.controlLeft);

      expect(find.byKey(_palette), findsOneWidget);
    },
  );

  testWidgets('Cmd-K (meta) opens the palette from a pushed editor', (
    tester,
  ) async {
    await _pump(tester);
    await _openProgramSummary(tester);
    await tester.tap(find.byKey(const ValueKey('open-builder')));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramEditorScreen), findsOneWidget);

    await _chord(tester, LogicalKeyboardKey.metaLeft);

    expect(find.byKey(_palette), findsOneWidget);
  });

  testWidgets('picking a result from a pushed route lands on that item', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Petronella'));
    await tester.pumpAndSettle();

    await _chord(tester, LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byKey(const ValueKey('command-result-program-p1')));
    await tester.pumpAndSettle();

    expect(find.byKey(_palette), findsNothing);
    expect(find.text('Perform this program'), findsWidgets);
  });

  testWidgets('a repeated Ctrl-K does not stack a second palette', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Petronella'));
    await tester.pumpAndSettle();

    await _chord(tester, LogicalKeyboardKey.controlLeft);
    await _chord(tester, LogicalKeyboardKey.controlLeft);

    expect(find.byKey(_palette), findsOneWidget);
  });

  testWidgets('Ctrl-K does nothing while PerformProgramScreen is on top', (
    tester,
  ) async {
    await _pump(tester);
    await _openProgramSummary(tester);
    await tester.tap(find.byKey(const ValueKey('summary-perform')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsOneWidget);

    await _chord(tester, LogicalKeyboardKey.controlLeft);

    expect(find.byKey(_palette), findsNothing);
  });

  testWidgets('Ctrl-K does nothing over a dialog opened from Perform', (
    tester,
  ) async {
    await _pump(tester);
    await _openProgramSummary(tester);
    await tester.tap(find.byKey(const ValueKey('summary-perform')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('perform-exit-dialog')), findsOneWidget);

    await _chord(tester, LogicalKeyboardKey.controlLeft);

    expect(find.byKey(_palette), findsNothing);
  });

  testWidgets('Ctrl-K works again after leaving Perform', (tester) async {
    await _pump(tester);
    await _openProgramSummary(tester);
    await tester.tap(find.byKey(const ValueKey('summary-perform')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsNothing);

    await _chord(tester, LogicalKeyboardKey.controlLeft);

    expect(find.byKey(_palette), findsOneWidget);
  });

  testWidgets('Ctrl-K does nothing while PerformDanceScreen is on top', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Petronella'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-dance')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformDanceScreen), findsOneWidget);

    await _chord(tester, LogicalKeyboardKey.controlLeft);

    expect(find.byKey(_palette), findsNothing);
  });
}
