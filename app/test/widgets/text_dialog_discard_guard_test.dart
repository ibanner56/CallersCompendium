import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/dance_editor/choice_option.dart';
import 'package:compendium_app/src/screens/dance_editor/custom_field_editor.dart';
import 'package:compendium_app/src/widgets/batch_custom_field_dialog.dart';
import 'package:compendium_app/src/widgets/batch_tag_dialog.dart';
import 'package:compendium_app/src/widgets/batch_tunes_dialog.dart';
import 'package:compendium_app/src/widgets/color_edit_dialog.dart';

import '../support/l10n_harness.dart';

/// Opens a dialog from a button and reports its result through [result].
Future<void> _open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) show,
  List<Object?> result,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () async => result.add(await show(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

Future<void> _tapOutside(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

const _tagDialog = ValueKey('batch-tag-dialog');
const _tunesDialog = ValueKey('batch-tunes-dialog');
const _fieldDialog = ValueKey('batch-custom-field-dialog');

CustomFieldDef _textDef() => CustomFieldDef(
  id: 'f1',
  key: 'notes',
  label: 'Notes',
  type: CustomFieldType.text,
);

void main() {
  group('batch tag dialog', () {
    Future<void> open(WidgetTester tester) => _open(
      tester,
      (c) => showBatchTagDialog(
        c,
        mode: BatchTagMode.add,
        tags: [Tag(id: 't1', name: 'Alpha')],
      ),
      [],
    );

    testWidgets('typed new-tag text survives tap outside, Esc and Back', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-new-tag-field')),
        'Brand new',
      );
      await tester.pump();
      await _tapOutside(tester);
      await _escape(tester);
      await _back(tester);
      expect(find.byKey(_tagDialog), findsOneWidget);
      expect(find.text('Brand new'), findsOneWidget);
    });

    testWidgets('a staged tag keeps the dialog open', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-new-tag-field')),
        'Brand new',
      );
      await tester.tap(find.byKey(const ValueKey('batch-create-tag')));
      await tester.pumpAndSettle();
      await _tapOutside(tester);
      expect(find.byKey(_tagDialog), findsOneWidget);
      expect(find.text('Brand new'), findsOneWidget);
    });

    testWidgets('an untouched dialog still closes on a tap outside', (
      tester,
    ) async {
      await open(tester);
      await _tapOutside(tester);
      expect(find.byKey(_tagDialog), findsNothing);
    });

    testWidgets('Cancel still closes a dirty dialog', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-new-tag-field')),
        'Brand new',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('batch-tag-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(_tagDialog), findsNothing);
    });
  });

  group('batch tunes dialog', () {
    Future<void> open(WidgetTester tester) =>
        _open(tester, showBatchTunesDialog, []);

    testWidgets('typed tune text survives tap outside, Esc and Back', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-tunes-field')),
        'Reel A',
      );
      await tester.pump();
      await _tapOutside(tester);
      await _escape(tester);
      await _back(tester);
      expect(find.byKey(_tunesDialog), findsOneWidget);
      expect(find.text('Reel A'), findsOneWidget);
    });

    testWidgets('an added tune keeps the dialog open', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-tunes-field')),
        'Reel A',
      );
      await tester.tap(find.byKey(const ValueKey('batch-tunes-add')));
      await tester.pumpAndSettle();
      await _tapOutside(tester);
      expect(find.byKey(_tunesDialog), findsOneWidget);
    });

    testWidgets('an untouched dialog still closes on a tap outside', (
      tester,
    ) async {
      await open(tester);
      await _tapOutside(tester);
      expect(find.byKey(_tunesDialog), findsNothing);
    });
  });

  group('batch custom field dialog', () {
    Future<void> open(WidgetTester tester) => _open(
      tester,
      (c) => showBatchCustomFieldDialog(c, defs: [_textDef()]),
      [],
    );

    testWidgets('a typed value survives tap outside, Esc and Back', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-custom-field-value-f1')),
        'half-typed',
      );
      await tester.pump();
      await _tapOutside(tester);
      await _escape(tester);
      await _back(tester);
      expect(find.byKey(_fieldDialog), findsOneWidget);
      expect(find.text('half-typed'), findsOneWidget);
    });

    testWidgets('an untouched dialog still closes on a tap outside', (
      tester,
    ) async {
      await open(tester);
      await _tapOutside(tester);
      expect(find.byKey(_fieldDialog), findsNothing);
    });

    testWidgets('text hidden behind the Clear switch does not hold it open', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-custom-field-value-f1')),
        'x',
      );
      await tester.tap(find.byKey(const ValueKey('batch-custom-field-clear')));
      await tester.pumpAndSettle();
      await _tapOutside(tester);
      expect(find.byKey(_fieldDialog), findsNothing);
    });
  });

  group('add-an-option dialog', () {
    const input = ValueKey('add-option-input');
    Future<void> open(WidgetTester tester) => _open(
      tester,
      (c) => showAddChoiceOptionDialog(
        c,
        label: 'Mood',
        onAddOption: (_) async => AddChoiceResult.added,
      ),
      [],
    );

    testWidgets('typed text survives tap outside, Esc and Back', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byKey(input), 'Half typed');
      await tester.pump();
      await _tapOutside(tester);
      await _escape(tester);
      await _back(tester);
      expect(find.byKey(input), findsOneWidget);
      expect(find.text('Half typed'), findsOneWidget);
    });

    testWidgets('an untouched dialog still closes on a tap outside', (
      tester,
    ) async {
      await open(tester);
      await _tapOutside(tester);
      expect(find.byKey(input), findsNothing);
    });
  });

  group('colour edit dialog', () {
    Future<void> open(WidgetTester tester) => _open(
      tester,
      (c) => showDialog<Color>(
        context: c,
        builder: (_) =>
            const ColorEditDialog(title: 'Colour', initial: Color(0xFF804020)),
      ),
      [],
    );

    testWidgets('typed hex text survives tap outside, Esc and Back', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '#12');
      await tester.pump();
      await _tapOutside(tester);
      await _escape(tester);
      await _back(tester);
      expect(find.byType(ColorEditDialog), findsOneWidget);
      expect(find.text('#12'), findsOneWidget);
    });

    testWidgets('a moved slider keeps the dialog open', (tester) async {
      await open(tester);
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pumpAndSettle();
      await _tapOutside(tester);
      expect(find.byType(ColorEditDialog), findsOneWidget);
    });

    testWidgets('an untouched dialog still closes on a tap outside', (
      tester,
    ) async {
      await open(tester);
      await _tapOutside(tester);
      expect(find.byType(ColorEditDialog), findsNothing);
    });

    testWidgets('typing the opening colour back makes it dismissible', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '#12');
      await tester.enterText(find.byType(TextField), '#804020');
      await tester.pump();
      await _tapOutside(tester);
      expect(find.byType(ColorEditDialog), findsNothing);
    });
  });
}
