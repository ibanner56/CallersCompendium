import 'dart:io';

import 'package:compendium_app/src/widgets/empty_state.dart';
import 'package:compendium_app/src/widgets/load_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('EmptyState', () {
    testWidgets('its title is a heading for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          EmptyState(
            icon: const Icon(Icons.add),
            title: 'No things yet',
            body: 'Choose New thing to add one.',
            actions: [FilledButton(onPressed: () {}, child: const Text('Go'))],
          ),
        ),
      );
      final title = tester.getSemantics(find.text('No things yet'));
      expect(
        title.flagsCollection.isHeader,
        isTrue,
        reason: 'the title must be reachable by heading navigation',
      );
      expect(find.bySemanticsLabel('Choose New thing to add one.'), findsOne);
      handle.dispose();
    });

    testWidgets('inline lays out inside a list with other content', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ListView(
            children: const [
              Text('intro'),
              EmptyState(inline: true, icon: Icon(Icons.add), title: 'Empty'),
              Text('after'),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Empty'), findsOneWidget);
      expect(find.text('after'), findsOneWidget);
    });
  });

  group('LoadErrorView', () {
    testWidgets('a retryable failure offers Retry and no Back', (tester) async {
      await tester.pumpWidget(
        _app(LoadErrorView(message: 'Could not load.', onRetry: () {})),
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('a failure that cannot be retried offers Back instead', (
      tester,
    ) async {
      var left = false;
      await tester.pumpWidget(
        _app(
          LoadErrorView(
            message: 'Gone.',
            body: 'It was removed.',
            onRetry: null,
            onBack: () => left = true,
          ),
        ),
      );
      expect(find.text('Retry'), findsNothing);
      expect(find.text('It was removed.'), findsOneWidget);
      await tester.tap(find.text('Back'));
      expect(left, isTrue);
    });

    testWidgets('with neither action it shows Retry, disabled', (tester) async {
      await tester.pumpWidget(
        _app(const LoadErrorView(message: 'Loading.', onRetry: null)),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  test('only the shared widget draws the whole-screen error glyph', () {
    // A whole-screen load failure uses LoadErrorView, which carries the one
    // Retry/Back wording; a hand-built column drifts from it.
    final handBuilt = RegExp(r'Icon\(\s*Icons\.error_outline,\s*size: 48');
    final offenders = <String>[
      for (final entity in Directory('lib/src').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('widgets/load_error_view.dart') &&
            handBuilt.hasMatch(entity.readAsStringSync()))
          entity.path,
    ];
    expect(offenders, isEmpty);
  });
}
