import 'dart:async';

import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/export/json_export.dart';
import 'package:compendium_app/src/widgets/dance_export_menu.dart';
import 'package:compendium_app/src/widgets/program_export_menu.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The dance and program export menus hand their bundles the user's own
/// figures (#1023), from [UserFiguresScope], so a shared file carries each one
/// its dances use.
void main() {
  final now = DateTime.utc(2026, 10, 16);
  final realBundleShareUnsupported = isBundleShareUnsupported;
  // Linux's Save path: the bundle reaches a save seam, not the share sheet.
  setUp(() => isBundleShareUnsupported = () => true);
  tearDown(() => isBundleShareUnsupported = realBundleShareUnsupported);

  final dance = Dance(
    id: 'd1',
    title: 'Zoom Reel',
    figures: [userFigureUseFigure(id: 'zoom-id', args: const {}, text: 'z')],
    createdAt: now,
    updatedAt: now,
  );

  Future<UserFiguresController> figures(WidgetTester tester) async {
    final repos = openTestRepositories();
    await tester.runAsync(
      () => repos.userGlossary.upsert(
        UserGlossaryEntry(
          id: 'zoom-id',
          kindName: UserGlossaryEntryKind.customFigure.name,
          name: 'zoom',
          definition: 'A zoom.',
          description: 'Fast.',
          payload: const {
            'template': '{move}',
            'defaultBeats': 8,
            'params': <Object?>[],
          },
          createdAt: now,
        ),
      ),
    );
    final controller = UserFiguresController(repos.userGlossary);
    addTearDown(controller.dispose);
    unawaited(controller.start());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    return controller;
  }

  Future<void> pick(
    WidgetTester tester,
    UserFiguresController controller,
    Widget menu,
    String menuKey,
    String item,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) =>
            UserFiguresScope(controller: controller, child: child!),
        home: Scaffold(appBar: AppBar(actions: [menu])),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(menuKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('the dance menu\'s file carries the dance\'s figures', (
    tester,
  ) async {
    final controller = await figures(tester);
    String? saved;
    await pick(
      tester,
      controller,
      DanceExportMenu(
        dance: dance,
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
        jsonExportDelivery: JsonExportDelivery(
          saveInvoker: (json, fileName) async {
            saved = json;
            return JsonSaveResult(path: '/x/$fileName', fileName: fileName);
          },
        ),
      ),
      'dance-export-menu',
      'Save dance file…',
    );
    expect(decodeArchive(saved!).archive.userFigures.map((f) => f.id), [
      'zoom-id',
    ]);
  });

  testWidgets('the program menu\'s file carries its dances\' figures', (
    tester,
  ) async {
    final controller = await figures(tester);
    String? saved;
    await pick(
      tester,
      controller,
      ProgramExportMenu(
        program: Program(
          id: 'p1',
          title: 'An evening',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: now,
          updatedAt: now,
        ),
        titleFor: (_) => 'Zoom Reel',
        venuesById: const {},
        danceFor: (id) => id == 'd1' ? dance : null,
        jsonExportDelivery: JsonExportDelivery(
          saveInvoker: (json, fileName) async {
            saved = json;
            return JsonSaveResult(path: '/x/$fileName', fileName: fileName);
          },
        ),
      ),
      'program-export-menu',
      'Save program file…',
    );
    expect(decodeArchive(saved!).archive.userFigures.map((f) => f.id), [
      'zoom-id',
    ]);
  });
}
