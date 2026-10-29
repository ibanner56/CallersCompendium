import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/screens/theme_editor_screen.dart';

import 'package:compendium_app/l10n/app_localizations.dart';

import '../support/l10n_harness.dart';

/// A [CustomTheme] whose `Text on primary` pair is deliberately unreadable:
/// white text on a white primary resolves to a 1:1 ratio, well below WCAG AA.
CustomTheme _failingTheme() => CustomTheme(
  id: 'failing',
  name: 'Low contrast',
  brightness: Brightness.light,
  roles: {'primary': 0xFFFFFFFF, 'onPrimary': 0xFFFFFFFF},
);

/// A [CustomTheme] with no overrides, so every badged pair inherits the
/// AA-compliant Material 3 light defaults and no warning is shown.
CustomTheme _passingTheme() => const CustomTheme(
  id: 'passing',
  name: 'Default light',
  brightness: Brightness.light,
  roles: {},
);

Finder _liveRegions() => find.byWidgetPredicate(
  (w) => w is Semantics && (w.properties.liveRegion ?? false),
);

void main() {
  group('ThemeEditorScreen low-contrast warning (issue #448)', () {
    testWidgets(
      'a failing-contrast pair surfaces the warning inside a live region',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: ThemeEditorScreen(initial: _failingTheme()),
          ),
        );
        await tester.pumpAndSettle();

        // The existing visual warning is intact.
        final warning = find.textContaining('below WCAG AA');
        expect(warning, findsOneWidget);

        // ...and it now lives in a live region so assistive tech announces it
        // when it appears / when the failing-pair count changes.
        expect(
          find.ancestor(of: warning, matching: _liveRegions()),
          findsOneWidget,
        );
      },
    );

    testWidgets('an AA-passing theme shows no warning and no live region', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: ThemeEditorScreen(initial: _passingTheme()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('below WCAG AA'), findsNothing);
      expect(
        find.text('All checked pairs pass WCAG AA contrast.'),
        findsOneWidget,
      );
      expect(_liveRegions(), findsNothing);
    });
  });

  group('ThemeEditorScreen labels are localized (CS-47)', () {
    testWidgets('role, group and contrast-pair labels are German', (
      tester,
    ) async {
      final de = lookupAppLocalizations(const Locale('de'));
      await tester.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: ThemeEditorScreen(initial: _passingTheme()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('On primary'), findsNothing);
      expect(find.text('Primary container'), findsNothing);
      expect(find.text('Surface & text'), findsNothing);
      expect(find.text('Text on primary'), findsNothing);
      expect(find.text(de.themeEditorRoleOnPrimary), findsOneWidget);
      expect(find.text(de.themeEditorGroupSurfaceText), findsOneWidget);
      expect(find.textContaining(de.themeEditorPairOnPrimary), findsWidgets);
    });
  });

  // UX2-1c: backing out of an edited theme asks before losing it.
  group('ThemeEditorScreen leaving with unsaved changes', () {
    /// Pushes the editor for [_passingTheme] and records whether it popped.
    Future<bool Function()> pushEditor(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var popped = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ThemeEditorScreen(initial: _passingTheme()),
                    ),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => popped;
    }

    testWidgets('an untouched theme leaves on Back without asking', (
      tester,
    ) async {
      final popped = await pushEditor(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(popped(), isTrue);
    });

    testWidgets('a blank name is not a change, since Save keeps the old one', (
      tester,
    ) async {
      final popped = await pushEditor(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(popped(), isTrue);
    });

    testWidgets('a new name asks on Back; Keep editing stays', (tester) async {
      final popped = await pushEditor(tester);
      await tester.enterText(find.byType(TextField), 'Mine');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Mine'), findsOneWidget);
      expect(popped(), isFalse);
    });

    testWidgets('a changed colour asks on the back arrow; Discard leaves', (
      tester,
    ) async {
      final popped = await pushEditor(tester);
      await tester.tap(find.byKey(const ValueKey('role-primary')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '00AA00',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(popped(), isTrue);
    });
  });
}
