import 'dart:async';

import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/widgets/user_figure_use_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A choice of one of the user's figures with no default can be left
/// unchosen in a dance, as it starts (#1023): a swing copied as one's own
/// starts with no prefix, and must be able to go back to none.
void main() {
  Future<void> pump(WidgetTester tester, {Object? defaultValue}) async {
    final repos = openTestRepositories();
    await tester.runAsync(
      () => repos.userGlossary.upsert(
        UserGlossaryEntry(
          id: 'zoom-id',
          kindName: UserGlossaryEntryKind.customFigure.name,
          name: 'zoom',
          definition: 'A zoom.',
          description: 'Fast.',
          payload: {
            'template': '{prefix} {move}',
            'defaultBeats': 8,
            'params': [
              {
                'key': 'prefix',
                'kind': 'choice',
                'choices': [
                  {'id': 'bal', 'label': 'balance'},
                ],
                'default': ?defaultValue,
              },
            ],
          },
          createdAt: DateTime.utc(2026, 10, 16),
        ),
      ),
    );
    final controller = UserFiguresController(repos.userGlossary);
    addTearDown(controller.dispose);
    unawaited(controller.start());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: UserFiguresScope(
            controller: controller,
            child: UserFigureUseEditor(
              keyPrefix: 'use',
              params: userFigureUseFigure(
                id: 'zoom-id',
                args: const {'prefix': 'bal'},
                text: 'balance zoom',
              ).params,
              onChanged: (_) {},
              dialect: Dialect.canonical,
              showBeats: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('use-prefix')));
    await tester.pumpAndSettle();
  }

  testWidgets('with no default, the choice can be left unchosen', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('not stated'), findsWidgets);
  });

  testWidgets('with a default, it can\'t', (tester) async {
    await pump(tester, defaultValue: 'bal');
    expect(find.text('not stated'), findsNothing);
  });
}
