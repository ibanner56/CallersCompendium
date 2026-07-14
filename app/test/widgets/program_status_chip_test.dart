import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/app_theme_extension.dart';
import 'package:compendium_app/src/widgets/program_status_chip.dart';

Future<void> _pump(WidgetTester tester, ProgramStatus status) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(child: ProgramStatusChip(status: status)),
      ),
    ),
  );
}

void main() {
  testWidgets('pairs an icon with a text label (never color alone)', (
    tester,
  ) async {
    await _pump(tester, ProgramStatus.finalized);
    expect(find.text('Finalized'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('tints the chip with the §2 status token for the theme', (
    tester,
  ) async {
    await _pump(tester, ProgramStatus.performed);

    final context = tester.element(find.byType(ProgramStatusChip));
    final theme = Theme.of(context);
    final expected = theme.extension<AppThemeExtension>()!.statusPerformed;

    // The avatar icon carries the themed status color.
    final icon = tester.widget<Icon>(
      find.byIcon(Icons.event_available_outlined),
    );
    expect(icon.color, expected);

    // ...which is distinct from the draft token, so different statuses read
    // differently (in addition to their distinct icon + label).
    expect(expected, isNot(theme.extension<AppThemeExtension>()!.statusDraft));
  });
}
