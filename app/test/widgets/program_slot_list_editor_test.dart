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
              onPromoteAlternate: (_, _) {},
              onRemove: (_) {},
              onCreateDance: (_) {},
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

  // A note's replacement is held locally until Save, just like a dance's
  // replacement. Saving converts the note slot into a dance slot.
  testWidgets('replacing a free-text slot converts it to a dance slot', (
    tester,
  ) async {
    final changes = <ProgramSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: ProgramSlotListEditor(
            slots: [
              ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
              ProgramSlot(id: 's2', position: 1, text: 'Caller note'),
            ],
            danceTitles: (id) => 'Dance $id',
            formationFor: (_) => null,
            mixerFor: (_) => false,
            onReorder: (_, _) {},
            onSlotChanged: (_, updated) => changes.add(updated),
            onPromoteAlternate: (_, _) {},
            onRemove: (_) {},
            onCreateDance: (_) {},
            onPickReplacementDance: () async => 'd2',
          ),
        ),
      ),
    );

    // Dance slot: the replace affordance is present.
    await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit slot'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('slot-edit-replace-dance')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('slot-edit-cancel')));
    await tester.pumpAndSettle();

    // Free-text slots offer the same replacement flow.
    await tester.tap(find.byKey(const ValueKey('slot-1-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit slot'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('slot-edit-replace-dance')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('slot-edit-replace-dance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-edit-save')));
    await tester.pumpAndSettle();

    expect(changes, hasLength(1));
    expect(changes.single.danceId, 'd2');
    expect(changes.single.text, isNull);
  });

  testWidgets('break slots do not offer dance replacement', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: ProgramSlotListEditor(
            slots: [
              ProgramSlot(
                id: 'break',
                position: 0,
                text: Program.breakSlotText,
              ),
            ],
            danceTitles: (id) => 'Dance $id',
            formationFor: (_) => null,
            mixerFor: (_) => false,
            onReorder: (_, _) {},
            onSlotChanged: (_, _) {},
            onPromoteAlternate: (_, _) {},
            onRemove: (_) {},
            onCreateDance: (_) {},
            onPickReplacementDance: () async => 'd2',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit slot'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slot-edit-replace-dance')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('slot-edit-note')),
      'Breakdance',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('slot-edit-replace-dance')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('slot-edit-note')),
      'Break',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('slot-edit-replace-dance')), findsNothing);
  });

  testWidgets('replacing after a note validation error clears the error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: ProgramSlotListEditor(
            slots: [ProgramSlot(id: 'note', position: 0, text: 'Caller note')],
            danceTitles: (id) => 'Dance $id',
            formationFor: (_) => null,
            mixerFor: (_) => false,
            onReorder: (_, _) {},
            onSlotChanged: (_, _) {},
            onPromoteAlternate: (_, _) {},
            onRemove: (_) {},
            onCreateDance: (_) {},
            onPickReplacementDance: () async => 'd2',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit slot'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('slot-edit-note')), '');
    await tester.tap(find.byKey(const ValueKey('slot-edit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter some text for this slot.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-edit-replace-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Enter some text for this slot.'), findsNothing);
  });

  // M3 (issue #964): a pick must be held in the dialog's own state and only
  // committed by Save — otherwise Cancel (or dismissing the dialog any other
  // way) would still have applied the replacement.
  testWidgets('cancelling the slot edit dialog discards a picked replacement '
      '(issue #964)', (tester) async {
    final changes = <ProgramSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: ProgramSlotListEditor(
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
            danceTitles: (id) => 'Dance $id',
            formationFor: (_) => null,
            mixerFor: (_) => false,
            onReorder: (_, _) {},
            onSlotChanged: (_, updated) => changes.add(updated),
            onPromoteAlternate: (_, _) {},
            onRemove: (_) {},
            onCreateDance: (_) {},
            onPickReplacementDance: () async => 'd2',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit slot'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('slot-edit-replace-dance')));
    await tester.pumpAndSettle();

    // The dialog now shows the picked replacement's title...
    expect(find.text('Dance d2'), findsOneWidget);

    // ...but Cancel must discard it: onSlotChanged is never invoked.
    await tester.tap(find.byKey(const ValueKey('slot-edit-cancel')));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });

  // Issue #1270: the scissors button removes the slot (it used to start a
  // cut/paste reorder, leaving "Remove slot" only in the overflow menu). The
  // tooltip keeps its "Cut …" wording by maintainer decision, so these tests
  // find the button by that tooltip and not by key.
  group('scissors button removes the slot (issue #1270)', () {
    Future<void> pumpEditor(
      WidgetTester tester, {
      required List<ProgramSlot> slots,
      required void Function(int index) onRemove,
    }) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: ProgramSlotListEditor(
            slots: slots,
            danceTitles: (id) => 'Dance $id',
            formationFor: (_) => null,
            mixerFor: (_) => false,
            onReorder: (_, _) {},
            onSlotChanged: (_, _) {},
            onPromoteAlternate: (_, _) {},
            onRemove: onRemove,
            onCreateDance: (_) {},
          ),
        ),
      ),
    );

    testWidgets('removes exactly the tapped slot and starts no cut/paste', (
      tester,
    ) async {
      final removed = <int>[];
      await pumpEditor(
        tester,
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ProgramSlot(id: 's3', position: 2, danceId: 'd3'),
        ],
        onRemove: removed.add,
      );

      await tester.tap(find.byTooltip('Cut Dance d2'));
      await tester.pumpAndSettle();

      expect(removed, [1]);
      expect(find.byKey(const ValueKey('slot-cut-banner')), findsNothing);
      expect(find.text('Paste here'), findsNothing);
      // The list stays reorderable: every row keeps a live drag handle (the
      // icon alone would also render on an inert placeholder).
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));
    });

    for (final (kind, slot, tooltip) in [
      (
        'dance',
        ProgramSlot(id: 's', position: 0, danceId: 'd1'),
        'Cut Dance d1',
      ),
      (
        'free-text note',
        ProgramSlot(id: 's', position: 0, text: 'Caller note'),
        'Cut Caller note',
      ),
      (
        'break',
        ProgramSlot(id: 's', position: 0, text: Program.breakSlotText),
        'Cut ${Program.breakSlotText}',
      ),
    ]) {
      testWidgets('works for a $kind slot', (tester) async {
        final removed = <int>[];
        await pumpEditor(tester, slots: [slot], onRemove: removed.add);

        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();

        expect(removed, [0]);
      });
    }

    testWidgets('the overflow menu no longer offers Remove slot', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        onRemove: (_) {},
      );

      await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Remove slot'), findsNothing);
      // The rest of the menu is untouched.
      expect(find.text('Edit slot'), findsOneWidget);
      expect(find.text('Mark as alternate'), findsOneWidget);
      expect(find.text('Mark performed'), findsOneWidget);
    });

    testWidgets('announces the removal by slot name', (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final announcements = <String>[];
      messenger.setMockMessageHandler(SystemChannels.accessibility.name, (
        ByteData? message,
      ) async {
        final decoded = SystemChannels.accessibility.codec.decodeMessage(
          message,
        );
        if (decoded is Map) {
          final data = decoded['data'];
          if (data is Map && data['message'] is String) {
            announcements.add(data['message'] as String);
          }
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMessageHandler(
          SystemChannels.accessibility.name,
          null,
        ),
      );
      await pumpEditor(
        tester,
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
        ],
        onRemove: (_) {},
      );

      await tester.tap(find.byTooltip('Cut Dance d2'));
      await tester.pump();

      expect(announcements, ['Removed Dance d2.']);
    });
  });
}
