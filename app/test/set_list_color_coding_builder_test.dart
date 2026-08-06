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

final _slotsWithMixer = [
  ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
  ProgramSlot(id: 's1', position: 1, danceId: 'd2'),
  ProgramSlot(id: 's2', position: 2, danceId: 'd3'),
];

const _formations = {
  'd1': Formation(FormationShape.dupleImproper),
  'd2': Formation(FormationShape.sicilianCircle),
};

const _formationsWithMixer = {
  'd1': Formation(FormationShape.dupleImproper),
  'd2': Formation(FormationShape.sicilianCircle),
  'd3': Formation(FormationShape.dupleImproper), // mixer-flagged duple improper
};

const _titles = {'d1': 'Chase the Squirrel', 'd2': 'Big Circle'};
const _titlesWithMixer = {
  'd1': 'Chase the Squirrel',
  'd2': 'Big Circle',
  'd3': 'Mixer Dance',
};

bool _mixerFor(String id) => id == 'd3'; // only the third dance is a mixer

Future<void> _pump(WidgetTester tester, {bool? colorCoding}) async {
  Widget editor = ProgramSlotListEditor(
    slots: _slots,
    danceTitles: (id) => _titles[id],
    formationFor: (id) => _formations[id],
    mixerFor: (_) => false,
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

Future<void> _pumpWithMixer(WidgetTester tester, {bool? colorCoding}) async {
  Widget editor = ProgramSlotListEditor(
    slots: _slotsWithMixer,
    danceTitles: (id) => _titlesWithMixer[id],
    formationFor: (id) => _formationsWithMixer[id],
    mixerFor: _mixerFor,
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

  testWidgets(
    'mixer-flagged dance gets mixer accent, not its formation accent (issue #732)',
    (tester) async {
      await _pumpWithMixer(tester, colorCoding: true);

      final a2 = _accent(tester, 's2'); // the mixer-flagged duple improper
      expect(
        a2,
        setListAccentForShapeAndMixer(
          FormationShape.dupleImproper,
          true,
          highContrast: false,
        ),
      );
      // Must not be the plain contra teal.
      expect(
        a2,
        isNot(
          setListAccentForShape(
            FormationShape.dupleImproper,
            highContrast: false,
          ),
        ),
      );
    },
  );

  testWidgets('mixer row subtitle contains the Mixer term (accessibility)', (
    tester,
  ) async {
    await _pumpWithMixer(tester, colorCoding: true);
    // The word 'Mixer' must appear alongside the formation text so colour is
    // not the sole cue (ux.md §4).
    expect(find.textContaining('Mixer'), findsWidgets);
  });
}
