import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_shapes.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/app_typography.dart';

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

  // Tonal tiers everywhere, and in High contrast only, a visible outline on
  // cards, sheets, menus and dialogs.
  group('High contrast outlines its containers; standard themes do not', () {
    BorderSide sideOf(ShapeBorder? shape) =>
        (shape as RoundedRectangleBorder?)?.side ?? BorderSide.none;
    Map<String, BorderSide> containerSides(ThemeData t) => {
      'card': sideOf(t.cardTheme.shape),
      'dialog': sideOf(t.dialogTheme.shape),
      'bottomSheet': sideOf(t.bottomSheetTheme.shape),
      'popupMenu': sideOf(t.popupMenuTheme.shape),
      'menu':
          t.menuTheme.style?.side?.resolve(<WidgetState>{}) ?? BorderSide.none,
    };

    test('highContrast', () {
      final theme = AppTheme.highContrast;
      containerSides(theme).forEach((name, side) {
        expect(side.style, BorderStyle.solid, reason: '$name has no outline');
        expect(side.width, greaterThanOrEqualTo(1.0), reason: name);
        expect(side.color, theme.colorScheme.outline, reason: name);
      });
    });

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      test(name, () {
        containerSides(theme).forEach((role, side) {
          expect(side, BorderSide.none, reason: '$name $role is outlined');
        });
      });
    }
  });

  group('C-10 / P-03 / P-04 / B-04: shared component themes', () {
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
      ('highContrast', AppTheme.highContrast),
    ]) {
      group(name, () {
        test(
          'app bar: leading title, no scrolled-under tint, display face',
          () {
            final bar = theme.appBarTheme;
            expect(bar.centerTitle, isFalse);
            expect(bar.scrolledUnderElevation, 0);
            expect(bar.surfaceTintColor, Colors.transparent);
            expect(bar.backgroundColor, theme.colorScheme.surface);
            expect(bar.titleTextStyle?.fontFamily, AppTypography.displayFamily);
          },
        );

        test('dialog titles are set explicitly in the display face', () {
          expect(
            theme.dialogTheme.titleTextStyle?.fontFamily,
            AppTypography.displayFamily,
          );
        });

        test('unthemed components now use AppShapes radii', () {
          BorderRadiusGeometry? radius(Object? shape) =>
              (shape as RoundedRectangleBorder?)?.borderRadius;
          expect(
            radius(theme.floatingActionButtonTheme.shape),
            AppShapes.borderRadiusLarge,
          );
          expect(
            radius(theme.popupMenuTheme.shape),
            AppShapes.borderRadiusSmall,
          );
          expect(
            radius(theme.menuTheme.style?.shape?.resolve({})),
            AppShapes.borderRadiusSmall,
          );
          expect(
            radius(theme.dropdownMenuTheme.menuStyle?.shape?.resolve({})),
            AppShapes.borderRadiusSmall,
          );
          expect(
            radius(theme.iconButtonTheme.style?.shape?.resolve({})),
            AppShapes.borderRadiusSmall,
          );
          expect(
            radius(theme.segmentedButtonTheme.style?.shape?.resolve({})),
            AppShapes.borderRadiusSmall,
          );
          expect(
            radius(theme.expansionTileTheme.shape),
            AppShapes.borderRadiusMedium,
          );
          expect(
            radius(theme.expansionTileTheme.collapsedShape),
            AppShapes.borderRadiusMedium,
          );
          expect(
            (theme.tooltipTheme.decoration as BoxDecoration?)?.borderRadius,
            AppShapes.borderRadiusSmall,
          );
          expect(
            theme.progressIndicatorTheme.borderRadius,
            AppShapes.borderRadiusSmall,
          );
        });

        test('High contrast, and only High contrast, outlines them', () {
          final hc = name == 'highContrast';
          BorderSide sideOf(Object? shape) =>
              (shape as RoundedRectangleBorder?)?.side ?? BorderSide.none;
          final sides = <String, BorderSide>{
            'fab': sideOf(theme.floatingActionButtonTheme.shape),
            'expansionTile': sideOf(theme.expansionTileTheme.shape),
            'segmentedButton':
                theme.segmentedButtonTheme.style?.side?.resolve({}) ??
                BorderSide.none,
            'appBar':
                (theme.appBarTheme.shape as Border?)?.bottom ?? BorderSide.none,
            'dropdownMenu':
                theme.dropdownMenuTheme.menuStyle?.side?.resolve({}) ??
                BorderSide.none,
            'checkbox (ticked)':
                WidgetStateProperty.resolveAs<BorderSide?>(
                  theme.checkboxTheme.side,
                  {WidgetState.selected},
                ) ??
                BorderSide.none,
          };
          sides.forEach((role, side) {
            if (hc) {
              expect(
                side.style,
                BorderStyle.solid,
                reason: '$role: no outline',
              );
              expect(side.color, theme.colorScheme.outline, reason: role);
            } else {
              expect(side, BorderSide.none, reason: '$name $role is outlined');
            }
          });
          expect(
            theme.switchTheme.trackOutlineColor?.resolve({
              WidgetState.selected,
            }),
            hc ? theme.colorScheme.outline : isNull,
          );
        });
      });
    }

    testWidgets('a long screen title at 2x text does not overflow the bar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Contra dance collection settings'),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.sort)),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final title = tester.getRect(
        find.text('Contra dance collection settings'),
      );
      final bar = tester.getRect(find.byType(AppBar));
      expect(
        bar.contains(title.topLeft) && bar.contains(title.bottomLeft),
        isTrue,
      );
    });
  });
}
