import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/widgets/dialect_quick_switch.dart';

import '../support/test_repositories.dart';

/// Renders the active dialect's name through [ActiveDialectScope] — the live
/// path every screen uses — so the test can assert the switch propagates.
class _ActiveDialectLabel extends StatelessWidget {
  const _ActiveDialectLabel();

  @override
  Widget build(BuildContext context) =>
      Text('active: ${ActiveDialectScope.of(context).name}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'lists all dialects with the active checked and switches on selection',
    (tester) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();

      final controller = DialectLibraryController(repos.settings);
      await controller.load();
      await controller.setActive(Dialect.larksRobins.name);

      // Bridge the controller into ActiveDialectScope exactly like main.dart.
      final notifier = ValueNotifier<Dialect>(controller.active);
      void sync() => notifier.value = controller.active;
      controller.addListener(sync);
      addTearDown(() {
        controller.removeListener(sync);
        controller.dispose();
        notifier.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DialectLibraryScope(
            controller: controller,
            child: ActiveDialectScope(
              notifier: notifier,
              child: const Scaffold(
                body: Column(
                  children: [DialectQuickSwitch(), _ActiveDialectLabel()],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('active: ${Dialect.larksRobins.name}'), findsOneWidget);

      // Open the menu: it lists every dialect in the library.
      await tester.tap(find.byKey(const ValueKey('dialect-quick-switch')));
      await tester.pumpAndSettle();
      for (final dialect in controller.all) {
        expect(
          find.byKey(ValueKey('dialect-quick-switch-${dialect.name}')),
          findsOneWidget,
        );
      }

      // The active dialect's item is checked.
      final activeItem = tester.widget<CheckedPopupMenuItem<String>>(
        find.byKey(
          ValueKey('dialect-quick-switch-${Dialect.larksRobins.name}'),
        ),
      );
      expect(activeItem.checked, isTrue);
      final otherItem = tester.widget<CheckedPopupMenuItem<String>>(
        find.byKey(
          ValueKey('dialect-quick-switch-${Dialect.leadsFollows.name}'),
        ),
      );
      expect(otherItem.checked, isFalse);

      // Selecting another dialect switches the active one live.
      await tester.tap(
        find.byKey(
          ValueKey('dialect-quick-switch-${Dialect.leadsFollows.name}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.activeName, Dialect.leadsFollows.name);
      expect(find.text('active: ${Dialect.leadsFollows.name}'), findsOneWidget);
    },
  );

  testWidgets(
    'uses the Dialect glyph (groups_outlined), not the language glyph translate',
    (tester) async {
      // Regression for UX review 6.8: the quick-switch must NOT share
      // `Icons.translate` with Settings › Language & region — dialect selection
      // and app-locale selection are different concepts. It uses the app's
      // Dialect glyph, outlined (an idle affordance per the 6.3 convention).
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final controller = DialectLibraryController(repos.settings);
      await controller.load();
      final notifier = ValueNotifier<Dialect>(controller.active);
      addTearDown(() {
        controller.dispose();
        notifier.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DialectLibraryScope(
            controller: controller,
            child: ActiveDialectScope(
              notifier: notifier,
              child: const Scaffold(body: DialectQuickSwitch()),
            ),
          ),
        ),
      );

      final button = tester.widget<PopupMenuButton<String>>(
        find.byKey(const ValueKey('dialect-quick-switch')),
      );
      expect(button.icon, isA<Icon>());
      expect((button.icon! as Icon).icon, Icons.groups_outlined);
      expect(find.byIcon(Icons.translate), findsNothing);
    },
  );
}
