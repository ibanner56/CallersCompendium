import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/widgets/readable_width.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/screen_size.dart';
import 'support/test_repositories.dart';

void main() {
  group('readableContentPadding', () {
    test('adds nothing at or below the readable width', () {
      expect(readableContentPadding(kReadableContentWidth), EdgeInsets.zero);
      expect(readableContentPadding(360), EdgeInsets.zero);
    });

    test('splits the surplus evenly between both sides', () {
      final padding = readableContentPadding(kReadableContentWidth + 400);
      expect(padding.left, 200);
      expect(padding.right, 200);
    });

    test('keeps the base gutter where it is already wider', () {
      const base = EdgeInsets.fromLTRB(16, 8, 16, 88);
      expect(readableContentPadding(360, base), base);
      final wide = readableContentPadding(kReadableContentWidth + 400, base);
      expect(wide, const EdgeInsets.fromLTRB(200, 8, 200, 88));
    });
  });

  group('ReadableListView / ReadableScrollView', () {
    testWidgets('cap the column but keep the scroll area full width', (
      tester,
    ) async {
      await setScreenSize(tester, const Size(1600, 900));
      const key = ValueKey('row');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadableListView(
              children: const [SizedBox(key: key, height: 40)],
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(key)).width, kReadableContentWidth);
      expect(
        tester.getCenter(find.byKey(key)).dx,
        800,
        reason: 'the column is centred',
      );
      // The viewport (and so the scrollbar) still spans the window.
      expect(tester.getSize(find.byType(ListView)).width, 1600);
    });

    testWidgets('leave a narrow window exactly as laid out before', (
      tester,
    ) async {
      await setScreenSize(tester, const Size(360, 800));
      const key = ValueKey('child');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReadableScrollView(
              padding: EdgeInsets.all(16),
              child: SizedBox(key: key, width: double.infinity, height: 40),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(key)).width, 360 - 32);
    });
  });

  group('dance editor form', () {
    Future<void> pumpEditor(WidgetTester tester, Size size) async {
      await setScreenSize(tester, size);
      final repos = openTestRepositories();
      final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(notifier: notifier, child: child!),
          ),
          home: const DanceEditorScreen(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('stops stretching on a wide window', (tester) async {
      await pumpEditor(tester, const Size(1600, 3200));
      expect(
        tester.getSize(find.byKey(const ValueKey('title-field'))).width,
        lessThanOrEqualTo(kReadableContentWidth),
      );
    });

    testWidgets('Type and Formation carry floating labels, not headings', (
      tester,
    ) async {
      await pumpEditor(tester, const Size(1600, 3200));
      for (final key in const ['form-field', 'formation-field']) {
        final field = find.byKey(ValueKey(key));
        expect(
          tester
              .widget<InputDecorator>(
                find.descendant(
                  of: field,
                  matching: find.byType(InputDecorator),
                ),
              )
              .decoration
              .labelText,
          isNotNull,
          reason: key,
        );
      }
      // Each label is drawn once (in the field), not also as a heading.
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Formation'), findsOneWidget);
    });
  });
}
