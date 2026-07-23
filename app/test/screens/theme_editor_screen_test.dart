import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/screens/theme_editor_screen.dart';

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
}
