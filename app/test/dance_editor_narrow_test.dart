import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/real_fonts.dart';
import 'support/test_repositories.dart';

void main() {
  // #1868: the Ahem test font overflowed the formation dropdown by 152px; with
  // the real fonts only the Progression dropdown (half a row) overflowed.
  //
  // A11Y-3: at larger text the Type and Formation dropdowns overflowed too (74
  // px at 1.5x and 188 px at 2.0x on a 360dp phone) until they were expanded.
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('dance editor form fits at 360dp, ${scale}x text, real fonts', (
      tester,
    ) async {
      await loadBundledFonts();
      final repos = openTestRepositories();
      await tester.binding.setSurfaceSize(const Size(360, 4800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1;
      final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          theme: AppTheme.light,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(
              notifier: notifier,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
          home: const DanceEditorScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('formation-field')), findsOneWidget);
      // A RenderFlex overflow is reported as a framework exception.
      expect(tester.takeException(), isNull);
    });
  }
}
