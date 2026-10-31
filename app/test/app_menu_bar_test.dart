// The macOS menu bar (PLAT-8): what it lists, that it lists no Edit menu, that
// its labels follow the app language, and that its items run the same intents
// as the desktop keys. The platform side is the `flutter/menu` channel, which
// these tests answer themselves.
import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_screen.dart';
import 'package:compendium_app/src/widgets/app_menu_bar.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_app_harness.dart';

/// The menus the app last sent to the platform, as the channel carries them.
List<Map<Object?, Object?>> _sentMenus = const [];

Future<void> _pump(
  WidgetTester tester, {
  bool menuBar = true,
  // Narrow by default, so the dance detail is a pushed route rather than the
  // inline pane.
  Size size = const Size(500, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.menu,
    (call) async {
      if (call.method == 'Menu.setMenus') {
        final windows = call.arguments as Map<Object?, Object?>;
        _sentMenus = [
          for (final menu in windows['0']! as List<Object?>)
            menu! as Map<Object?, Object?>,
        ];
      }
      return null;
    },
  );
  final appData = openTestAppData();
  final repos = appData.repositories;
  final stamp = DateTime.utc(2026, 1, 1);
  await repos.dances.create(
    Dance(id: 'd1', title: 'Petronella', createdAt: stamp, updatedAt: stamp),
  );
  await tester.pumpWidget(
    CompendiumApp(
      appData: appData,
      windowService: NoopWindowService(repos.settings),
      integrityCheck: () async => true,
      installPlatformMenuBar: menuBar,
    ),
  );
  await tester.pumpAndSettle();
}

/// Takes the app down while the channel is still answered, so removing the
/// menu bar has somewhere to send its empty menus.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

/// Every item under [menus], depth first.
Iterable<Map<Object?, Object?>> _items(List<Object?> menus) sync* {
  for (final item in menus.cast<Map<Object?, Object?>>()) {
    yield item;
    yield* _items((item['children'] as List<Object?>?) ?? const []);
  }
}

List<String> _topLevelLabels() => [
  for (final menu in _sentMenus) menu['label']! as String,
];

Map<Object?, Object?> _item(String label) =>
    _items(_sentMenus).singleWhere((item) => item['label'] == label);

Future<void> _select(WidgetTester tester, String label) async {
  final id = _item(label)['id']! as int;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.menu.name,
    SystemChannels.menu.codec.encodeMethodCall(
      MethodCall('Menu.selectedCallback', id),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

bool _showing(WidgetTester tester, Type type) =>
    find.byType(type).hitTestable().evaluate().isNotEmpty;

/// The system items exist only on macOS, and serialising one anywhere else
/// throws, so every test that installs the menu bar runs as macOS.
final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() {
    rootBundle.clear();
    _sentMenus = const [];
  });

  testWidgets('lists the app, File, View, Window and Help menus, and no Edit', (
    tester,
  ) async {
    await _pump(tester);

    expect(_topLevelLabels(), [
      "Caller's Compendium",
      'File',
      'View',
      'Window',
      'Help',
    ]);
    final labels = {
      for (final item in _items(_sentMenus)) item['label'],
    }.whereType<String>();
    expect(
      labels,
      containsAll([
        'Settings…',
        'New Dance',
        'Import Dances…',
        'Close',
        'User Guide',
      ]),
    );
    final provided = {
      for (final item in _items(_sentMenus)) item['platformProvidedMenu'],
    }.whereType<int>();
    expect(
      provided,
      containsAll([
        for (final type in [
          PlatformProvidedMenuItemType.about,
          PlatformProvidedMenuItemType.quit,
          PlatformProvidedMenuItemType.toggleFullScreen,
          PlatformProvidedMenuItemType.minimizeWindow,
        ])
          type.index,
      ]),
    );
    expect(
      _item('Settings…')['shortcutTrigger'],
      LogicalKeyboardKey.comma.keyId,
    );
    expect(
      _item('New Dance')['shortcutTrigger'],
      LogicalKeyboardKey.keyN.keyId,
    );
    expect(_item('Close')['shortcutTrigger'], LogicalKeyboardKey.keyW.keyId);

    await _unmount(tester);
  }, variant: _macOS);

  testWidgets('is not installed unless the app is told to', (tester) async {
    await _pump(tester, menuBar: false);

    expect(_sentMenus, isEmpty);
    expect(find.byType(PlatformMenuBar), findsNothing);

    await _unmount(tester);
  });

  test('labels follow the app language', () {
    final german = AppMenuBar.menusFor(
      lookupAppLocalizations(const Locale('de')),
    );
    expect(
      [for (final menu in german) (menu as PlatformMenu).label],
      ["Caller's Compendium", 'Ablage', 'Darstellung', 'Fenster', 'Hilfe'],
    );
  });

  testWidgets('Settings… shows Settings', (tester) async {
    await _pump(tester);
    expect(_showing(tester, SettingsScreen), isFalse);

    await _select(tester, 'Settings…');

    expect(_showing(tester, SettingsScreen), isTrue);
    await _unmount(tester);
  }, variant: _macOS);

  testWidgets('User Guide shows the Guide', (tester) async {
    await _pump(tester);

    await _select(tester, 'User Guide');

    expect(_showing(tester, UserGuideScreen), isTrue);
    await _unmount(tester);
  }, variant: _macOS);

  testWidgets('New Dance opens the new-dance editor', (tester) async {
    // Wide enough for the editor's form under the test font.
    await _pump(tester, size: const Size(1200, 1600));

    await _select(tester, 'New Dance');

    expect(find.byType(DanceEditorScreen), findsOneWidget);
    await _unmount(tester);
  }, variant: _macOS);

  testWidgets('Close leaves a pushed page', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Petronella'));
    await tester.pumpAndSettle();
    expect(find.byType(DanceDetailScreen), findsOneWidget);

    await _select(tester, 'Close');

    expect(find.byType(DanceDetailScreen), findsNothing);
    await _unmount(tester);
  }, variant: _macOS);

  testWidgets('Import Dances… opens the import view', (tester) async {
    await _pump(tester);

    await _select(tester, 'Import Dances…');

    expect(find.byType(ImportReviewScreen), findsOneWidget);
    await _unmount(tester);
  }, variant: _macOS);
}
