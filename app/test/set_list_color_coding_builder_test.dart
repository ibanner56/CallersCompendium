import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/set_list_color_coding_scope.dart';
import 'package:compendium_app/src/theme/set_list_accents.dart';
import 'package:compendium_app/src/widgets/program_slot_list_editor.dart';
import 'support/l10n_harness.dart';

final _slots = [
  ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
  ProgramSlot(id: 's1', position: 1, danceId: 'd2'),
];

const _formations = {
  'd1': Formation(FormationShape.dupleImproper),
  'd2': Formation(FormationShape.sicilianCircle),
};

const _titles = {'d1': 'Chase the Squirrel', 'd2': 'Big Circle'};

Future<void> _pump(WidgetTester tester, {bool? colorCoding}) async {
  Widget editor = ProgramSlotListEditor(
    slots: _slots,
    danceTitles: (id) => _titles[id],
    formationFor: (id) => _formations[id],
    onReorder: (_, _) {},
    onSlotChanged: (_, _) {},
    onRemove: (_) {},
  );
  if (colorCoding != null) {
    editor = SetListColorCodingScope(
      notifier: ValueNotifier<bool>(colorCoding),
      child: editor,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

      home: Scaffold(body: SingleChildScrollView(child: editor)),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _accent(WidgetTester tester, String slotId) {
  final finder = find.byKey(ValueKey('slot-$slotId-accent'));
  if (finder.evaluate().isEmpty) return null;
  final container = tester.widget<Container>(finder);
  final border = (container.decoration as BoxDecoration?)?.border as Border?;
  return border?.left.color;
}

void main() {
  testWidgets('builder rows carry the formation accent + text when on', (
    tester,
  ) async {
    await _pump(tester, colorCoding: true);

    // Formation text is present on each row (so colour is redundant).
    expect(find.textContaining('Duple improper'), findsOneWidget);
    expect(find.textContaining('Sicilian circle'), findsOneWidget);

    final a0 = _accent(tester, 's0');
    final a1 = _accent(tester, 's1');
    expect(
      a0,
      setListAccentForShape(FormationShape.dupleImproper, highContrast: false),
    );
    expect(
      a1,
      setListAccentForShape(FormationShape.sicilianCircle, highContrast: false),
    );
    expect(a0, isNot(a1));
  });

  testWidgets('disabling colour-coding removes the accent, keeps the text', (
    tester,
  ) async {
    await _pump(tester, colorCoding: false);

    expect(find.byKey(const ValueKey('slot-s0-accent')), findsNothing);
    expect(find.byKey(const ValueKey('slot-s1-accent')), findsNothing);
    // Formation text remains, so the row's type/form is readable without hue.
    expect(find.textContaining('Duple improper'), findsOneWidget);
    expect(find.textContaining('Sicilian circle'), findsOneWidget);
  });
}
