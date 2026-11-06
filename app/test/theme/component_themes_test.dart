import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_shapes.dart';
import 'package:compendium_app/src/theme/app_theme.dart';

/// UX-2 (`ux-modernization.md` §5, §7): the app-level component sub-themes are
/// present and satisfy the interactive-target and shape acceptance criteria.
void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'highContrast': AppTheme.highContrast,
  };

  themes.forEach((name, theme) {
    group('Component themes are wired ($name)', () {
      test('every component sub-theme is set (no bare defaults)', () {
        expect(theme.cardTheme.shape, isNotNull);
        expect(theme.dialogTheme.shape, isNotNull);
        expect(theme.inputDecorationTheme.border, isNotNull);
        expect(theme.dividerTheme.color, isNotNull);
        expect(theme.filledButtonTheme.style, isNotNull);
        expect(theme.outlinedButtonTheme.style, isNotNull);
        expect(theme.textButtonTheme.style, isNotNull);
        expect(theme.chipTheme.shape, isNotNull);
        expect(theme.listTileTheme.shape, isNotNull);
        expect(theme.navigationRailTheme.indicatorColor, isNotNull);
        expect(theme.navigationBarTheme.indicatorColor, isNotNull);
      });

      test('interactive targets are ≥24px (UX-2 AC)', () {
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
        ]) {
          final min = style.minimumSize!.resolve(<WidgetState>{})!;
          expect(min.height, greaterThanOrEqualTo(24.0));
        }
      });

      test('dialogs use the 28dp dialog radius (§1d)', () {
        final shape = theme.dialogTheme.shape as RoundedRectangleBorder;
        expect(shape.borderRadius, const BorderRadius.all(Radius.circular(28)));
      });

      testWidgets('a long dialog is capped at a readable width on desktop', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: AlertDialog(
              title: const Text('Title'),
              content: Text('A long dialog body. ' * 60),
            ),
          ),
        );
        final surface = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Material),
        );
        expect(tester.getSize(surface.first).width, 560);
      });

      testWidgets('a disabled field keeps the theme\'s field corners, even '
          'under a local OutlineInputBorder()', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Material(
              child: TextField(
                enabled: false,
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ),
        );
        final decoration = tester
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration;
        final border = decoration.disabledBorder as OutlineInputBorder;
        final themed = theme.inputDecorationTheme.border as OutlineInputBorder;
        expect(border.borderRadius, themed.borderRadius);
      });

      test('navigation uses a pill (stadium) selected indicator', () {
        expect(theme.navigationBarTheme.indicatorShape, isA<StadiumBorder>());
        expect(theme.navigationRailTheme.useIndicator, isTrue);
        expect(theme.navigationRailTheme.indicatorShape, isA<StadiumBorder>());
      });

      test('snackbars float rather than dock to the bottom edge', () {
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      });
    });
  });

  group('Standard (light/dark) treatment specifics', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      test('inputs are filled with rounded borders', () {
        expect(theme.inputDecorationTheme.filled, isTrue);
        final border = theme.inputDecorationTheme.border as OutlineInputBorder;
        expect(
          border.borderRadius,
          const BorderRadius.all(Radius.circular(12)),
        );
      });
    }
  });

  group('the date picker is exempt from the dialog width cap', () {
    Future<double> pickerWidth(
      WidgetTester tester, {
      required bool uncapped,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDatePicker(
                context: context,
                initialDate: DateTime(2026, 10, 23),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                builder: uncapped ? uncappedDialogBuilder : null,
              ),
              child: const Text('pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      final surface = find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(Material),
      );
      return tester.getSize(surface.first).width;
    }

    testWidgets('it sizes itself to large text with uncappedDialogBuilder', (
      tester,
    ) async {
      expect(
        await pickerWidth(tester, uncapped: true),
        greaterThan(AppShapes.dialogConstraints.maxWidth),
      );
    });

    testWidgets('without the builder the cap would crowd it', (tester) async {
      expect(
        await pickerWidth(tester, uncapped: false),
        AppShapes.dialogConstraints.maxWidth,
      );
    });
  });
}
