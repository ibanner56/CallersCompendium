import 'package:compendium_app/src/widgets/settings_dropdown_row.dart';
import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_fonts.dart';
import '../support/screen_size.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  await setScreenSize(tester, Size(width, 800));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsDropdownRow(
          title: const Text('Label', key: ValueKey('row-title')),
          subtitle: const Text('Subtitle'),
          dropdownBuilder: (expanded) => AppDropdownField<int>(
            key: const ValueKey('row-dropdown'),
            compact: true,
            fillWidth: expanded,
            value: 1,
            onChanged: (_) {},
            entries: const [
              AppDropdownEntry(value: 1, label: 'One'),
              AppDropdownEntry(value: 2, label: 'Two'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with room, the dropdown is the ListTile trailing', (
    tester,
  ) async {
    await _pump(tester, 800);

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.trailing, isNotNull);
    expect(
      tester
          .widget<AppDropdownField<int>>(
            find.byKey(const ValueKey('row-dropdown')),
          )
          .fillWidth,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 360 dp phone at default text size stays inline', (
    tester,
  ) async {
    await _pump(tester, 360);

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.trailing, isNotNull);
    expect(
      tester
          .widget<AppDropdownField<int>>(
            find.byKey(const ValueKey('row-dropdown')),
          )
          .fillWidth,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('without room, the expanded dropdown sits below the label', (
    tester,
  ) async {
    await _pump(tester, 320);

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.trailing, isNull);
    final dropdown = find.byKey(const ValueKey('row-dropdown'));
    expect(tester.widget<AppDropdownField<int>>(dropdown).fillWidth, isTrue);
    expect(
      tester.getTopLeft(dropdown).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const ValueKey('row-title'))).dy,
      ),
    );
    expect(find.text('Subtitle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide surface still wraps once the text scale is large', (
    tester,
  ) async {
    await setScreenSize(tester, const Size(700, 800));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsDropdownRow(
            title: const Text('Label'),
            dropdownBuilder: (expanded) => AppDropdownField<int>(
              key: const ValueKey('row-dropdown'),
              compact: true,
              fillWidth: expanded,
              value: 1,
              onChanged: (_) {},
              entries: const [AppDropdownEntry(value: 1, label: 'One')],
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<AppDropdownField<int>>(
            find.byKey(const ValueKey('row-dropdown')),
          )
          .fillWidth,
      isTrue,
    );
  });

  // On a wide screen a row stays inline at large text, where a list tile's
  // trailing slot is at most 56 dp tall (48 dp at a desktop's compact
  // density): the field must fit it, its value not cut off top or bottom.
  for (final scale in [1.5, 2.0]) {
    testWidgets('inline at ${scale}x text on a wide screen, the value is not '
        'cut off', (tester) async {
      await loadBundledFonts();
      await setScreenSize(tester, const Size(1600, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SettingsDropdownRow(
              title: const Text('Label'),
              dropdownBuilder: (expanded) => AppDropdownField<int>(
                key: const ValueKey('row-dropdown'),
                compact: true,
                fillWidth: expanded,
                value: 1,
                onChanged: (_) {},
                entries: const [
                  AppDropdownEntry(value: 1, label: 'Monthly'),
                  AppDropdownEntry(value: 2, label: 'Weekly'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListTile>(find.byType(ListTile)).trailing,
        isNotNull,
      );
      final editable = tester.renderObject<RenderEditable>(
        find.descendant(
          of: find.byKey(const ValueKey('row-dropdown')),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_Editable',
          ),
        ),
      );
      expect(
        editable.size.height,
        greaterThanOrEqualTo(editable.preferredLineHeight - 0.5),
      );
      final field = tester.getRect(find.byKey(const ValueKey('row-dropdown')));
      expect(field.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('inline at ${scale}x text on a wide desktop, the value is not '
        'cut off', (tester) async {
      await loadBundledFonts();
      await setScreenSize(tester, const Size(1600, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(visualDensity: VisualDensity.compact),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SettingsDropdownRow(
              title: const Text('Label'),
              dropdownBuilder: (expanded) => AppDropdownField<int>(
                key: const ValueKey('row-dropdown'),
                compact: true,
                fillWidth: expanded,
                value: 1,
                onChanged: (_) {},
                entries: const [
                  AppDropdownEntry(value: 1, label: 'Monthly'),
                  AppDropdownEntry(value: 2, label: 'Weekly'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListTile>(find.byType(ListTile)).trailing,
        isNotNull,
      );
      final editable = tester.renderObject<RenderEditable>(
        find.descendant(
          of: find.byKey(const ValueKey('row-dropdown')),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_Editable',
          ),
        ),
      );
      expect(
        editable.size.height,
        greaterThanOrEqualTo(editable.preferredLineHeight - 0.5),
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('above 2x text the dropdown always has its own line, however '
      'wide the screen', (tester) async {
    await setScreenSize(tester, const Size(2400, 800));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsDropdownRow(
            title: const Text('Label'),
            dropdownBuilder: (expanded) => AppDropdownField<int>(
              key: const ValueKey('row-dropdown'),
              compact: true,
              fillWidth: expanded,
              value: 1,
              onChanged: (_) {},
              entries: const [AppDropdownEntry(value: 1, label: 'One')],
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<ListTile>(find.byType(ListTile)).trailing, isNull);
  });
}
