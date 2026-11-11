import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/search_panel_bar.dart';

const _a = ValueKey('panel-a');
const _b = ValueKey('panel-b');

List<SearchPanelSpec> _panels() => [
  SearchPanelSpec(
    key: _a,
    label: 'Alpha',
    builder: (_) => const Column(
      children: [
        ExpansionTile(
          key: ValueKey('nested-1'),
          title: Text('Nested one'),
          children: [Text('Nested one body')],
        ),
        ExpansionTile(
          key: ValueKey('nested-2'),
          title: Text('Nested two'),
          children: [Text('Nested two body')],
        ),
      ],
    ),
  ),
  SearchPanelSpec(
    key: _b,
    label: 'Beta',
    builder: (_) => const Text('Beta body'),
  ),
];

Future<void> _pump(WidgetTester tester, {int fillerRows = 0}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                SearchPanelBar(storageId: 'test', panels: _panels()),
                for (var i = 0; i < fillerRows; i++)
                  SizedBox(height: 100, child: Text('Row $i')),
              ]),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a toggle opens its tool; opening another closes the first', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Nested one'), findsNothing);

    await tester.tap(find.byKey(_a));
    await tester.pumpAndSettle();
    expect(find.text('Nested one'), findsOneWidget);

    await tester.tap(find.byKey(_b));
    await tester.pumpAndSettle();
    expect(find.text('Beta body'), findsOneWidget);
    expect(find.text('Nested one'), findsNothing);

    await tester.tap(find.byKey(_b));
    await tester.pumpAndSettle();
    expect(find.text('Beta body'), findsNothing);
  });

  testWidgets('the toggles announce whether their tool is open on every '
      'platform, and an open tool is not read as a selected filter', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final l10n = MaterialLocalizations.of(tester.element(find.byKey(_a)));

    // The expanded flag reaches desktop and web; the state hint is what iOS
    // and older Android screen readers read, as for a collapsible header.
    expect(
      tester.getSemantics(find.byKey(_a)),
      isSemantics(
        hasExpandedState: true,
        isExpanded: false,
        hint: l10n.expandedHint,
        isButton: true,
        hasSelectedState: false,
        label: 'Alpha',
      ),
    );
    await tester.tap(find.byKey(_a));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(_a)),
      isSemantics(
        hasExpandedState: true,
        isExpanded: true,
        hint: l10n.collapsedHint,
        isButton: true,
        hasSelectedState: false,
        label: 'Alpha',
      ),
    );
    handle.dispose();
  });

  testWidgets('a short label is spelled out for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanelBar(
            storageId: 'test',
            panels: [
              SearchPanelSpec(
                key: _a,
                label: 'Filters · 3',
                semanticsLabel: 'Filters (3 active)',
                builder: (_) => const Text('Filters body'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Filters · 3'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(_a)),
      isSemantics(label: 'Filters (3 active)', isButton: true),
    );
    handle.dispose();
  });

  testWidgets('a trailing control shares the toggles\' row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanelBar(
            storageId: 'test',
            panels: _panels(),
            trailing: const SizedBox(
              key: ValueKey('trail'),
              width: 40,
              height: 40,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('trail'))).dy,
      closeTo(tester.getCenter(find.byKey(_b)).dy, 1),
    );
  });

  testWidgets('a tool that stops being offered is not open when it returns', (
    tester,
  ) async {
    Future<void> pump({required bool withA}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPanelBar(
            storageId: 'test',
            panels: withA ? _panels() : [_panels().last],
          ),
        ),
      ),
    );
    await pump(withA: true);
    await tester.tap(find.byKey(_a));
    await tester.pumpAndSettle();
    expect(find.text('Nested one'), findsOneWidget);

    await pump(withA: false);
    await pump(withA: true);
    await tester.pumpAndSettle();
    expect(find.text('Nested one'), findsNothing);
  });

  testWidgets('the open tool survives the bar scrolling out of view and back', (
    tester,
  ) async {
    await _pump(tester, fillerRows: 40);
    await tester.tap(find.byKey(_b));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byKey(_b), findsNothing, reason: 'scrolled out and disposed');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 6000));
    await tester.pumpAndSettle();

    expect(find.text('Beta body'), findsOneWidget);
  });

  testWidgets('sections inside a tool keep their own state when the user '
      'visits another tool and comes back', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_a));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nested one'));
    await tester.pumpAndSettle();
    expect(find.text('Nested one body'), findsOneWidget);
    expect(find.text('Nested two body'), findsNothing);

    await tester.tap(find.byKey(_b));
    await tester.pumpAndSettle();
    expect(find.text('Nested one'), findsNothing, reason: 'hidden while B');
    await tester.tap(find.byKey(_a));
    await tester.pumpAndSettle();

    // Restored, and not shared: keying the bar with a page-storage key made
    // every nested section read one stored state.
    expect(tester.takeException(), isNull);
    expect(find.text('Nested one body'), findsOneWidget);
    expect(find.text('Nested two body'), findsNothing);
  });

  Future<void> pumpWide(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    Widget? trailing,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SearchPanelBar(
                  storageId: 'wide',
                  panels: _panels(),
                  trailing: trailing,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the toggles fill the row at any width', (tester) async {
    for (final width in [320.0, 411.0, 700.0]) {
      await pumpWide(
        tester,
        width: width,
        trailing: const SizedBox(key: ValueKey('trail'), width: 40, height: 40),
      );
      final a = tester.getRect(find.byKey(_a));
      final b = tester.getRect(find.byKey(_b));
      final trail = tester.getRect(find.byKey(const ValueKey('trail')));
      // Flush with the padded edges: the trailing control keeps its size and
      // the tools share what is left, equally.
      expect(a.left, 16);
      expect(trail.right, closeTo(width - 16, 0.01), reason: 'width $width');
      expect(trail.width, 40);
      expect(a.width, closeTo(b.width, 0.01), reason: 'width $width');
      expect(b.right + 4, closeTo(trail.left, 0.01));
      // A stretched chip's label stays centred rather than hugging its start.
      final label = tester.getRect(find.text('Alpha'));
      expect(label.center.dx, closeTo(a.center.dx, 8), reason: 'width $width');
      // The slot's size is not what the eye sees: the painted chip body must
      // fill it too, so spare width is padding inside the chip rather than gaps
      // between chips that stayed at their natural width.
      for (final key in [_a, _b]) {
        final slot = tester.getRect(find.byKey(key));
        final body = tester.getRect(
          find
              .descendant(of: find.byKey(key), matching: find.byType(Material))
              .first,
        );
        expect(body.left, closeTo(slot.left, 0.01), reason: '$key at $width');
        expect(body.right, closeTo(slot.right, 0.01), reason: '$key at $width');
      }
    }
  });

  testWidgets('toggles wrap and still fill each row when text is large', (
    tester,
  ) async {
    await pumpWide(tester, width: 200, textScale: 2);
    final a = tester.getRect(find.byKey(_a));
    final b = tester.getRect(find.byKey(_b));
    expect(b.top, greaterThan(a.bottom - 1), reason: 'wrapped to a second run');
    expect(a.right, closeTo(200 - 16, 0.01));
    expect(b.right, closeTo(200 - 16, 0.01));
  });
}
