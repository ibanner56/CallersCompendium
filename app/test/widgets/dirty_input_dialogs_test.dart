import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/dance_editor/choice_option.dart'
    show AddChoiceResult;
import 'package:compendium_app/src/screens/dance_editor/custom_field_editor.dart';
import 'package:compendium_app/src/screens/settings/library_manager_list.dart';
import 'package:compendium_app/src/widgets/program_slot_list_editor.dart';
import 'package:compendium_app/src/widgets/published_source_details_dialog.dart';

import '../support/l10n_harness.dart';

Future<void> _pumpOpener(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tapOutside(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

void main() {
  final source = PublishedSource(id: 's1', title: 'Book');

  testWidgets('source dialog: outside tap keeps typed text; clean closes', (
    tester,
  ) async {
    await _pumpOpener(
      tester,
      (c) => PublishedSourceDetailsDialog.show(c, source),
    );
    const notes = ValueKey('source-notes-field');
    await tester.enterText(find.byKey(notes), 'a long note I typed');
    await tester.pumpAndSettle();

    await _tapOutside(tester);
    expect(find.byKey(notes), findsOneWidget);
    expect(find.text('a long note I typed'), findsOneWidget);

    // Cancel still closes it, on purpose.
    await tester.tap(find.byKey(const ValueKey('source-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(notes), findsNothing);
  });

  testWidgets('source dialog: untouched dialog closes on outside tap', (
    tester,
  ) async {
    await _pumpOpener(
      tester,
      (c) => PublishedSourceDetailsDialog.show(c, source),
    );
    await _tapOutside(tester);
    expect(find.byKey(const ValueKey('source-notes-field')), findsNothing);
  });

  testWidgets('rename dialog: outside tap keeps an edited name', (
    tester,
  ) async {
    await _pumpOpener(
      tester,
      (c) => showLibraryRenameDialog(c, currentName: 'Old', fieldLabel: 'Name'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('library-rename-field')),
      'New name',
    );
    await tester.pumpAndSettle();
    await _tapOutside(tester);
    expect(find.byKey(const ValueKey('library-rename-dialog')), findsOneWidget);
  });

  testWidgets('rename dialog: untouched dialog closes on outside tap', (
    tester,
  ) async {
    await _pumpOpener(
      tester,
      (c) => showLibraryRenameDialog(c, currentName: 'Old', fieldLabel: 'Name'),
    );
    await _tapOutside(tester);
    expect(find.byKey(const ValueKey('library-rename-dialog')), findsNothing);
  });

  testWidgets('add-choice dialog: outside tap keeps typed text', (
    tester,
  ) async {
    await _pumpOpener(
      tester,
      (c) => showAddChoiceOptionDialog(
        c,
        label: 'Level',
        onAddOption: (_) async => AddChoiceResult.added,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-option-input')),
      'Advanced',
    );
    await tester.pumpAndSettle();
    await _tapOutside(tester);
    expect(find.byKey(const ValueKey('add-option-input')), findsOneWidget);
  });

  group('slot edit dialog', () {
    Future<void> openSlotEdit(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: ProgramSlotListEditor(
              slots: [ProgramSlot(id: 's1', position: 0, text: 'Caller note')],
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
    }

    testWidgets('outside tap keeps an edited note', (tester) async {
      await openSlotEdit(tester);
      await tester.enterText(
        find.byKey(const ValueKey('slot-edit-note')),
        'Caller note, longer',
      );
      await tester.pumpAndSettle();
      await _tapOutside(tester);
      expect(find.byKey(const ValueKey('slot-edit-note')), findsOneWidget);
    });

    testWidgets('outside tap keeps a toggled alternate flag', (tester) async {
      await openSlotEdit(tester);
      await tester.tap(find.byKey(const ValueKey('slot-edit-alt')));
      await tester.pumpAndSettle();
      await _tapOutside(tester);
      expect(find.byKey(const ValueKey('slot-edit-note')), findsOneWidget);
    });

    testWidgets('outside tap keeps a picked replacement dance', (tester) async {
      await openSlotEdit(tester);
      await tester.tap(find.byKey(const ValueKey('slot-edit-replace-dance')));
      await tester.pumpAndSettle();
      await _tapOutside(tester);
      expect(find.byKey(const ValueKey('slot-edit-note')), findsOneWidget);
    });

    testWidgets('untouched dialog closes on outside tap', (tester) async {
      await openSlotEdit(tester);
      await _tapOutside(tester);
      expect(find.byKey(const ValueKey('slot-edit-note')), findsNothing);
    });
  });
}
