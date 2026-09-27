import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/color_edit_dialog.dart';

import '../support/l10n_harness.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: const Scaffold(
        body: ColorEditDialog(title: 'Colour', initial: Color(0xFF804020)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each channel slider is named by its channel', (tester) async {
    // A bare `Text('R')` beside a `Slider` reaches a screen reader as two
    // nodes: a static "R", then a slider whose label is its numeric value.
    // The channel name must be part of the slider's own node so it is heard
    // when the slider is focused directly.
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.byType(Slider), findsNWidgets(3));

    // Read the tree the way assistive technology does — in traversal order,
    // merged nodes already merged — and pick out the slider nodes.
    final sliders = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((node) => isSemantics(isSlider: true).matches(node, {}))
        .toList();
    expect(sliders, hasLength(3));

    // `getSemanticsData()` is what the platform receives: the node's own
    // label plus everything merged into it ("Red\n128"), not just its own.
    const channels = {'Red': '128', 'Green': '64', 'Blue': '32'};
    var i = 0;
    for (final MapEntry(key: channel, value: value) in channels.entries) {
      final data = sliders[i++].getSemanticsData();
      expect(data.label, startsWith(channel), reason: channel);
      expect(data.label, contains(value), reason: channel);
      expect(data.value, isNotEmpty, reason: channel);
    }

    handle.dispose();
  });

  testWidgets('the hex field stays a labelled text field', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Hex')),
      isSemantics(isTextField: true, value: '#804020'),
    );
    handle.dispose();
  });
}
