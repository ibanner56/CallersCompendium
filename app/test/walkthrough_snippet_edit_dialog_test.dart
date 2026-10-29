import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_scope.dart';
import 'package:compendium_app/src/screens/walkthrough_snippets_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

const _field = ValueKey('walkthrough-snippet-edit-field');

Future<WalkthroughSnippetLibraryController> _pumpWithSnippet(
  WidgetTester tester,
) async {
  final repos = openTestRepositories();
  final controller = WalkthroughSnippetLibraryController(repos.settings);
  addTearDown(controller.dispose);
  await controller.setSnippet('swing', 'Swing your neighbor');
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: dialect,
          child: WalkthroughSnippetLibraryScope(
            controller: controller,
            child: const WalkthroughSnippetsScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Swing your neighbor'));
  await tester.pumpAndSettle();
  expect(find.byKey(_field), findsOneWidget);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a tap outside keeps the snippet dialog once the text changes', (
    tester,
  ) async {
    final controller = await _pumpWithSnippet(tester);
    await tester.enterText(find.byKey(_field), 'Swing your partner');
    await tester.pump();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byKey(_field), findsOneWidget);
    expect(find.text('Swing your partner'), findsOneWidget);
    expect(controller.resolve('swing'), 'Swing your neighbor');
  });

  testWidgets('a tap outside still closes an unchanged snippet dialog', (
    tester,
  ) async {
    await _pumpWithSnippet(tester);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('typing the original text back makes it dismissible again', (
    tester,
  ) async {
    await _pumpWithSnippet(tester);
    await tester.enterText(find.byKey(_field), 'Swing your partner');
    await tester.enterText(find.byKey(_field), 'Swing your neighbor');
    await tester.pump();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('Cancel closes it with edits, discarding them', (tester) async {
    final controller = await _pumpWithSnippet(tester);
    await tester.enterText(find.byKey(_field), 'Swing your partner');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byKey(_field), findsNothing);
    expect(controller.resolve('swing'), 'Swing your neighbor');
  });
}
