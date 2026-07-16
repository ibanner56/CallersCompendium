import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_spacing.dart';
import 'package:compendium_app/src/widgets/section_header.dart';

void main() {
  testWidgets('renders its title in the primary colour', (tester) async {
    final theme = ThemeData(
      colorScheme: const ColorScheme.light(primary: Color(0xFF0055AA)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: SectionHeader(title: 'Details')),
      ),
    );

    expect(find.text('Details'), findsOneWidget);

    // Compare against the theme resolved in the widget tree (MaterialApp fills
    // in Typography geometry that the raw ThemeData does not).
    final resolved = Theme.of(tester.element(find.text('Details')));
    final text = tester.widget<Text>(find.text('Details'));
    expect(text.style?.color, resolved.colorScheme.primary);
    // Matches labelLarge so it reads as a consistent section heading.
    expect(text.style?.fontSize, resolved.textTheme.labelLarge?.fontSize);
    expect(text.style?.fontWeight, resolved.textTheme.labelLarge?.fontWeight);
  });

  testWidgets('uses the AppSpacing-based section-header padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SectionHeader(title: 'Figures')),
      ),
    );

    final padding = tester.widget<Padding>(
      find.ancestor(of: find.text('Figures'), matching: find.byType(Padding)),
    );
    expect(
      padding.padding,
      const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxs,
      ),
    );
  });
}
