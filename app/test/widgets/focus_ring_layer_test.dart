import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/app_theme_extension.dart';
import 'package:compendium_app/src/theme/palette_schemes.dart';
import 'package:compendium_app/src/theme/wcag.dart';
import 'package:compendium_app/src/widgets/focus_ring_layer.dart';

/// Keyboard focus draws the theme's focus ring round controls
/// whose Material themes cannot draw one themselves.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget body, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        builder: (context, child) => FocusRingLayer(child: child!),
        home: Scaffold(body: body),
      ),
    );
  }

  Rect? ring(WidgetTester tester) =>
      tester.state<FocusRingLayerState>(find.byType(FocusRingLayer)).ringRect;

  /// Tabs until [finder]'s widget holds primary focus (or gives up).
  Future<void> tabTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused != null &&
          find
              .descendant(of: finder, matching: find.byWidget(focused.widget))
              .evaluate()
              .isNotEmpty) {
        return;
      }
    }
    fail('could not tab to $finder');
  }

  Rect boundsOfFocused(WidgetTester tester) {
    final box =
        FocusManager.instance.primaryFocus!.context!.findRenderObject()!
            as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  for (final (name, widget) in <(String, Widget)>[
    ('ListTile', ListTile(title: const Text('Row'), onTap: () {})),
    ('Checkbox', Checkbox(value: false, onChanged: (_) {})),
    ('Switch', Switch(value: false, onChanged: (_) {})),
    (
      'Radio',
      RadioGroup<int>(
        groupValue: 0,
        onChanged: (_) {},
        child: const Radio<int>(value: 1),
      ),
    ),
    ('IconButton', IconButton(icon: const Icon(Icons.add), onPressed: () {})),
    ('FilledButton', FilledButton(onPressed: () {}, child: const Text('Go'))),
    (
      'NavigationRail',
      NavigationRail(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: const [
          NavigationRailDestination(icon: Icon(Icons.home), label: Text('A')),
          NavigationRailDestination(icon: Icon(Icons.star), label: Text('B')),
        ],
      ),
    ),
  ]) {
    testWidgets('a keyboard-focused $name gets the ring round its bounds', (
      tester,
    ) async {
      await pump(tester, Center(child: SizedBox(width: 400, child: widget)));
      expect(ring(tester), isNull);
      await tabTo(tester, find.byWidget(widget));
      expect(ring(tester), boundsOfFocused(tester));
    });
  }

  testWidgets('the ring is painted outside the bounds in the theme colour', (
    tester,
  ) async {
    final tile = ListTile(title: const Text('Row'), onTap: () {});
    await pump(tester, Center(child: SizedBox(width: 300, child: tile)));
    await tabTo(tester, find.byWidget(tile));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<FocusRingPainter>()
        .single;
    final theme = Theme.of(tester.element(find.byType(ListTile)));
    expect(painter.color, theme.colorScheme.primary);
    expect(painter.width, 2);
    expect(painter.rect, boundsOfFocused(tester));
  });

  testWidgets('no ring for a focused text field (its border is the ring)', (
    tester,
  ) async {
    const field = TextField();
    await pump(tester, const Center(child: SizedBox(width: 300, child: field)));
    await tabTo(tester, find.byWidget(field));
    expect(ring(tester), isNull);
  });

  testWidgets('no ring when focus came from a pointer, not the keyboard', (
    tester,
  ) async {
    final tile = ListTile(title: const Text('Row'), onTap: () {});
    await pump(tester, Center(child: SizedBox(width: 300, child: tile)));
    await tester.tap(find.text('Row'));
    await tester.pumpAndSettle();
    expect(ring(tester), isNull);
  });

  testWidgets('no ring round a page-level shortcut receiver', (tester) async {
    await pump(
      tester,
      Focus(autofocus: true, child: const SizedBox.expand(child: Text('page'))),
    );
    // Put the manager in keyboard mode without moving focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isA<Focus>());
    expect(ring(tester), isNull);
  });

  testWidgets('the ring follows a focused row as it scrolls', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      ListView(
        controller: controller,
        children: [
          for (var i = 0; i < 40; i++)
            ListTile(title: Text('Row $i'), onTap: () {}),
        ],
      ),
    );
    await tabTo(tester, find.widgetWithText(ListTile, 'Row 2'));
    final before = ring(tester)!;
    controller.jumpTo(40);
    await tester.pump();
    await tester.pump();
    expect(ring(tester), before.shift(const Offset(0, -40)));
    // Scrolled out of the viewport: no ring painted over whatever is above.
    controller.jumpTo(2000);
    await tester.pump();
    await tester.pump();
    expect(ring(tester), isNull);
  });

  testWidgets('after a layout-only move, the ring asks for the frame that '
      'repaints it', (tester) async {
    // A wheel tick or a resize produces one frame. The ring measures after
    // that frame's layout, so it must schedule the next frame itself, or it
    // stays where the row used to be until something else asks for a frame.
    final top = ValueNotifier<double>(0);
    addTearDown(top.dispose);
    final tile = ListTile(title: const Text('Row'), onTap: () {});
    await pump(
      tester,
      ValueListenableBuilder<double>(
        valueListenable: top,
        builder: (_, t, _) => Padding(
          padding: EdgeInsets.only(top: t),
          child: SizedBox(width: 300, child: tile),
        ),
      ),
    );
    await tabTo(tester, find.byWidget(tile));
    FocusRingPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<FocusRingPainter>()
        .single;
    top.value = 50;
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(painter().rect, boundsOfFocused(tester));
  });

  // Perform's stage mode re-themes its own route (and its dialogs and sheets)
  // in the dark stage theme, under whatever the app theme is. The ring is
  // drawn over the stage's surfaces there, so its colour must be the one tuned
  // for them, not the app theme's primary, which a light theme tunes for a
  // light canvas.
  for (final (name, appTheme) in <(String, ThemeData)>[
    ('Light', AppTheme.light),
    ('Tokyo Night Light', AppTheme.fromScheme(GalleryPalettes.tokyoNightLight)),
    // A custom light theme with a dark accent: fine on white, near-black.
    (
      'a custom light theme with a near-black accent',
      AppTheme.fromScheme(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A1A),
        ).copyWith(primary: const Color(0xFF1A1A1A)),
      ),
    ),
  ]) {
    testWidgets('on the Perform stage under $name, the ring clears 3:1 on '
        "every stage surface and is the stage theme's own", (tester) async {
      final button = IconButton(icon: const Icon(Icons.add), onPressed: () {});
      await pump(
        tester,
        PerformStageTheme(
          enabled: true,
          child: Builder(
            builder: (context) => ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(child: button),
            ),
          ),
        ),
        theme: appTheme,
      );
      await tabTo(tester, find.byWidget(button));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<FocusRingPainter>()
          .single;
      final stage = AppTheme.highContrast;
      final stageExt = stage.extension<AppThemeExtension>()!;
      final scheme = stage.colorScheme;
      for (final (role, tier) in [
        ('surface', scheme.surface),
        ('surfaceContainerLowest', scheme.surfaceContainerLowest),
        ('surfaceContainerLow', scheme.surfaceContainerLow),
        ('surfaceContainer', scheme.surfaceContainer),
        ('surfaceContainerHigh', scheme.surfaceContainerHigh),
        ('surfaceContainerHighest', scheme.surfaceContainerHighest),
      ]) {
        expect(
          Wcag.contrastRatio(painter.color, tier),
          greaterThanOrEqualTo(Wcag.aaNonText),
          reason: 'ring ${painter.color} on the stage $role $tier',
        );
      }
      expect(painter.color, stageExt.focusRing);
      expect(painter.width, stageExt.focusRingWidth);
    });
  }

  testWidgets("a dialog opened from the stage gets the stage theme's ring", (
    tester,
  ) async {
    // Perform's exit dialog and its sheets are shown from a context under the
    // stage theme, which a dialog route captures.
    final appTheme = AppTheme.fromScheme(GalleryPalettes.tokyoNightLight);
    await pump(
      tester,
      PerformStageTheme(
        enabled: true,
        child: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: const Text('Leave?'),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('Stay')),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      theme: appTheme,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tabTo(tester, find.widgetWithText(TextButton, 'Stay'));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<FocusRingPainter>()
        .single;
    expect(
      painter.color,
      AppTheme.highContrast.extension<AppThemeExtension>()!.focusRing,
    );
  });

  testWidgets('off the stage the ring keeps the app theme', (tester) async {
    final appTheme = AppTheme.fromScheme(GalleryPalettes.tokyoNightLight);
    final button = IconButton(icon: const Icon(Icons.add), onPressed: () {});
    await pump(
      tester,
      PerformStageTheme(enabled: false, child: Center(child: button)),
      theme: appTheme,
    );
    await tabTo(tester, find.byWidget(button));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<FocusRingPainter>()
        .single;
    expect(painter.color, appTheme.extension<AppThemeExtension>()!.focusRing);
  });
}
