import 'package:compendium_app/src/widgets/program_slot_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

List<ProgramSlot> _slots() => [
  ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
  ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
];

void main() {
  // Regression for issue #628 (F-L1): `SemanticsService.sendAnnouncement` must
  // honour the ambient `Directionality`, not a hardcoded `TextDirection.ltr`,
  // matching the pattern already used in `figure_list_editor.dart`.
  testWidgets('slot-moved announcement uses the ambient RTL direction, not a '
      'hardcoded LTR (issue #628)', (tester) async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final List<Map<Object?, Object?>> announcements = [];
    messenger.setMockMessageHandler(SystemChannels.accessibility.name, (
      ByteData? message,
    ) async {
      final decoded = SystemChannels.accessibility.codec.decodeMessage(message);
      if (decoded is Map) announcements.add(decoded.cast());
      return null;
    });
    addTearDown(
      () => messenger.setMockMessageHandler(
        SystemChannels.accessibility.name,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Directionality(
          // Ambient RTL, established below the MaterialApp's own (LTR,
          // English-locale) Directionality — exactly the context the
          // announcement's `Directionality.maybeOf(context)` call reads.
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ProgramSlotListEditor(
              slots: _slots(),
              danceTitles: (id) => 'Dance $id',
              formationFor: (_) => null,
              mixerFor: (_) => false,
              onReorder: (_, _) {},
              onSlotChanged: (_, _) {},
              onRemove: (_) {},
            ),
          ),
        ),
      ),
    );

    // Slot 1 (index 1) has a "move up" action; slot 0 does not.
    await tester.tap(find.byKey(const ValueKey('slot-1-move-up')));
    await tester.pump();

    expect(announcements, isNotEmpty);
    final data = announcements.last['data'] as Map<Object?, Object?>;
    expect(data['textDirection'], TextDirection.rtl.index);
    expect(data['textDirection'], isNot(TextDirection.ltr.index));
  });
}
