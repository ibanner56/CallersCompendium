import 'package:compendium_app/src/widgets/figure_param_editors.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a single [FigureParamEditor] and returns a getter for the last value
/// reported through `onChanged`.
Future<Object? Function()> _pumpEditor(
  WidgetTester tester, {
  required String paramKey,
  required ParamSpec spec,
  required Object? value,
}) async {
  Object? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FigureParamEditor(
            keyPrefix: 'p',
            paramKey: paramKey,
            spec: spec,
            value: value,
            onChanged: (v) => captured = v,
          ),
        ),
      ),
    ),
  );
  return () => captured;
}

Future<void> _selectFromDropdown(
  WidgetTester tester,
  String fieldKey,
  String label,
) async {
  await tester.tap(find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dancerSet dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
      value: 'partners',
    );
    await _selectFromDropdown(tester, 'p-who', 'neighbors');
    expect(read(), 'neighbors');
  });

  testWidgets('dancerPair dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'who',
      spec: const ParamSpec(
        ParamKind.dancerPair,
        defaultValue: 'partners',
        choices: ['partners', 'neighbors'],
      ),
      value: 'partners',
    );
    await _selectFromDropdown(tester, 'p-who', 'neighbors');
    expect(read(), 'neighbors');
  });

  testWidgets('handedness dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'hand',
      spec: const ParamSpec(ParamKind.handedness, defaultValue: 'right'),
      value: 'right',
    );
    await _selectFromDropdown(tester, 'p-hand', 'left');
    expect(read(), 'left');
  });

  testWidgets('shoulder dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'shoulder',
      spec: const ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
      value: 'right',
    );
    await _selectFromDropdown(tester, 'p-shoulder', 'left');
    expect(read(), 'left');
  });

  testWidgets('spinDirection dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'spin',
      spec: const ParamSpec(ParamKind.spinDirection, defaultValue: 'clockwise'),
      value: 'clockwise',
    );
    await _selectFromDropdown(tester, 'p-spin', 'counterclockwise');
    expect(read(), 'counterclockwise');
  });

  testWidgets('fraction dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'amount',
      spec: const ParamSpec(ParamKind.fraction, defaultValue: 'quarter'),
      value: 'quarter',
    );
    await _selectFromDropdown(tester, 'p-amount', 'half');
    expect(read(), 'half');
  });

  testWidgets('direction dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'dir',
      spec: const ParamSpec(ParamKind.direction, defaultValue: 'along'),
      value: 'along',
    );
    await _selectFromDropdown(tester, 'p-dir', 'across');
    expect(read(), 'across');
  });

  testWidgets('choice dropdown round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'prefix',
      spec: const ParamSpec(
        ParamKind.choice,
        defaultValue: 'none',
        choices: ['none', 'balance', 'meltdown'],
      ),
      value: 'none',
    );
    await _selectFromDropdown(tester, 'p-prefix', 'balance');
    expect(read(), 'balance');
  });

  testWidgets('rotation stepper increments in quarter turns', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: const ParamSpec(ParamKind.rotation, defaultValue: 1.0),
      value: 1.0,
    );
    await tester.tap(find.byKey(const ValueKey('p-turn-inc')));
    await tester.pumpAndSettle();
    expect(read(), 1.25);
  });

  testWidgets('rotation stepper decrements and clamps at the minimum', (
    tester,
  ) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'turn',
      spec: const ParamSpec(ParamKind.rotation, defaultValue: 0.25),
      value: 0.25,
    );
    // At the minimum the decrement button is disabled.
    final decButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('p-turn-dec')),
    );
    expect(decButton.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('p-turn-inc')));
    await tester.pumpAndSettle();
    expect(read(), 0.5);
  });

  testWidgets('beats field round-trips an integer', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'beats',
      spec: const ParamSpec(ParamKind.beats, defaultValue: 8),
      value: 8,
    );
    await tester.enterText(find.byKey(const ValueKey('p-beats')), '16');
    expect(read(), 16);
  });

  testWidgets('beats field ignores out-of-range input', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'beats',
      spec: const ParamSpec(ParamKind.beats, defaultValue: 8),
      value: 8,
    );
    await tester.enterText(find.byKey(const ValueKey('p-beats')), '99');
    expect(read(), isNull);
  });

  testWidgets('text field round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'text',
      spec: const ParamSpec(ParamKind.text, defaultValue: ''),
      value: '',
    );
    await tester.enterText(find.byKey(const ValueKey('p-text')), 'scoop it up');
    expect(read(), 'scoop it up');
  });

  testWidgets('flag switch round-trips a value', (tester) async {
    final read = await _pumpEditor(
      tester,
      paramKey: 'balance',
      spec: const ParamSpec(ParamKind.flag, defaultValue: false),
      value: false,
    );
    await tester.tap(find.byKey(const ValueKey('p-balance')));
    await tester.pumpAndSettle();
    expect(read(), true);
  });

  test('humanizeToken spaces camelCase and lowercases', () {
    expect(humanizeToken('rightDiagonal'), 'right diagonal');
    expect(humanizeToken('threeQuarter'), 'three quarter');
    expect(humanizeToken('who'), 'who');
  });
}
