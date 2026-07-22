import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/screens/shorthand_mapping_editor_screen.dart';
import 'package:compendium_app/src/screens/shorthand_mappings_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

Figure _swing() =>
    Figure(move: 'swing', params: {'who': 'neighbors', 'beats': 16});

/// Pumps [ShorthandMappingsScreen] backed by [controller], with the dialect +
/// shorthand scopes wrapping the whole navigator so pushed editor routes also
/// resolve them.
Future<void> _pumpManager(
  WidgetTester tester,
  ShorthandMappingsController controller,
) async {
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => ActiveDialectScope(
        notifier: dialect,
        child: ShorthandMappingsScope(controller: controller, child: child!),
      ),
      home: const ShorthandMappingsScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the empty state when there are no mappings', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    await _pumpManager(tester, controller);

    expect(find.byKey(const ValueKey('shorthand-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-shorthand')), findsOneWidget);
  });

  testWidgets('lists a mapping row with its token and figure summary', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await controller.upsert(
      ShorthandMapping(token: 'BnS', figures: [_swing()]),
    );

    await _pumpManager(tester, controller);

    expect(find.byKey(const ValueKey('shorthand-tile-bns')), findsOneWidget);
    expect(find.text('BnS'), findsOneWidget);
    // The row previews the target figure rendered via the active dialect.
    expect(find.textContaining('swing'), findsOneWidget);
  });

  testWidgets('deleting a mapping removes it from the store', (tester) async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await controller.upsert(ShorthandMapping(token: 'ns', figures: [_swing()]));

    await _pumpManager(tester, controller);

    await tester.tap(find.byKey(const ValueKey('shorthand-menu-ns')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // Confirm the destructive action.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(controller.mappings, isEmpty);
    expect(find.byKey(const ValueKey('shorthand-empty')), findsOneWidget);
  });

  testWidgets('New shorthand opens the editor', (tester) async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    await _pumpManager(tester, controller);

    await tester.tap(find.byKey(const ValueKey('new-shorthand')));
    await tester.pumpAndSettle();

    expect(find.byType(ShorthandMappingEditorScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('shorthand-token-field')), findsOneWidget);
  });
}
