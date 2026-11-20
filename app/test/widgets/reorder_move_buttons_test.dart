import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/reorder_move_buttons.dart';

import '../support/l10n_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? up,
  VoidCallback? down,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: testSupportedLocales,
    home: Scaffold(
      body: ReorderMoveButtons(
        keyPrefix: 'row',
        name: 'Beginner',
        onMoveUp: up,
        onMoveDown: down,
      ),
    ),
  ),
);

void main() {
  testWidgets('buttons are full-size, named for the item, and act', (
    tester,
  ) async {
    var ups = 0;
    var downs = 0;
    final handle = tester.ensureSemantics();
    await _pump(tester, up: () => ups++, down: () => downs++);
    for (final key in ['row-move-up', 'row-move-down']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
    }
    // A screen reader reads the button's tooltip as its name.
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('row-move-up')))
          .getSemanticsData()
          .tooltip,
      'Move Beginner up',
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('row-move-down')))
          .getSemanticsData()
          .tooltip,
      'Move Beginner down',
    );

    handle.dispose();

    await tester.tap(find.byKey(const ValueKey('row-move-up')));
    await tester.tap(find.byKey(const ValueKey('row-move-down')));
    expect((ups, downs), (1, 1));
  });

  testWidgets('a null callback disables the button', (tester) async {
    await _pump(tester, down: () {});
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('row-move-up')))
          .onPressed,
      isNull,
    );
  });
}
