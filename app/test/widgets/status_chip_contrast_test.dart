import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/app_theme_extension.dart';
import 'package:compendium_app/src/theme/wcag.dart';
import 'package:compendium_app/src/widgets/program_status_chip.dart';
import '../support/l10n_harness.dart';

/// The status tokens shared by [StatusChip] (both program and dance status),
/// keyed by a human-readable role for failure messages.
Map<String, Color> _statusTokens(AppThemeExtension ext) => {
  'statusDraft': ext.statusDraft,
  'statusFinalized': ext.statusFinalized,
  'statusPerformed': ext.statusPerformed,
  'statusDeprecated': ext.statusDeprecated,
  'statusBroken': ext.statusBroken,
};

void main() {
  group('StatusChip text contrast — WCAG 2.2 AA across all bundled themes', () {
    // Every pinned selection (Default group + High contrast + every gallery
    // palette) is held to the bar; `system` has no fixed scheme.
    for (final selection in AppThemeSelection.values) {
      final scheme = selection.scheme;
      if (scheme == null) continue;

      test('${selection.name}: label clears 4.5:1 against the tinted fill', () {
        final ext = AppThemeExtension.fromColorScheme(scheme);
        // StatusChip draws its label in onSurface over a 10% color fill that
        // composites over the surface behind the chip.
        final textColor = scheme.onSurface;
        _statusTokens(ext).forEach((role, token) {
          final fill = Color.alphaBlend(
            token.withValues(alpha: 0.10),
            scheme.surface,
          );
          final ratio = Wcag.contrastRatio(textColor, fill);
          expect(
            ratio,
            greaterThanOrEqualTo(Wcag.aaText),
            reason:
                '${selection.name}: $role chip label contrast $ratio must '
                'clear AA text 4.5:1 against its own tinted fill',
          );
        });
      });
    }
  });

  Future<void> pumpDanceChip(WidgetTester tester, DanceStatus status) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,

        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: DanceStatusChip(status: status)),
        ),
      ),
    );
  }

  testWidgets('DanceStatusChip pairs an icon with a text label', (
    tester,
  ) async {
    await pumpDanceChip(tester, DanceStatus.deprecated);
    expect(find.text('Deprecated'), findsOneWidget);
    expect(find.byIcon(Icons.history_toggle_off), findsOneWidget);
  });

  testWidgets('DanceStatusChip tints with the §2 dance status token', (
    tester,
  ) async {
    await pumpDanceChip(tester, DanceStatus.broken);

    final context = tester.element(find.byType(DanceStatusChip));
    final theme = Theme.of(context);
    final expected = theme.extension<AppThemeExtension>()!.statusBroken;

    final icon = tester.widget<Icon>(
      find.byIcon(Icons.report_problem_outlined),
    );
    expect(icon.color, expected);
    // Deprecated and broken read differently (distinct token + icon + label).
    expect(
      expected,
      isNot(theme.extension<AppThemeExtension>()!.statusDeprecated),
    );
  });

  testWidgets('new dance statuses render distinct icon and text pairs', (
    tester,
  ) async {
    await pumpDanceChip(tester, DanceStatus.draft);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);

    await pumpDanceChip(tester, DanceStatus.variation);
    expect(find.text('Variation'), findsOneWidget);
    expect(find.byIcon(Icons.alt_route), findsOneWidget);
  });

  testWidgets('DanceStatusChip and ProgramStatusChip share StatusChip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,

        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              DanceStatusChip(status: DanceStatus.deprecated),
              ProgramStatusChip(status: ProgramStatus.draft),
            ],
          ),
        ),
      ),
    );
    // Both status chips delegate to the one shared construction.
    expect(find.byType(StatusChip), findsNWidgets(2));
  });
}
