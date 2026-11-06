import 'dart:async';
import 'dart:typed_data';

import 'package:compendium_app/src/data/calling_card_settings_scope.dart';
import 'package:compendium_app/src/export/calling_card_layout.dart';
import 'package:compendium_app/src/widgets/calling_card_print.dart';
import 'package:compendium_app/src/widgets/dance_export_menu.dart';
import 'package:compendium_app/src/widgets/program_export_menu.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'support/l10n_harness.dart';
import 'support/pdf_probe.dart';

/// Settings › Experimental › Calling cards adds a print action to the dance
/// and program Export menus, which prints one card-sized page per dance.

final _now = DateTime.utc(2026, 11, 6);

Dance _dance(String id, {String callingNotes = 'Watch the ends'}) => Dance(
  id: id,
  title: 'Dance $id',
  callingNotes: callingNotes,
  figures: [
    Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
  ],
  createdAt: _now,
  updatedAt: _now,
);

const _on = CallingCardSettings(enabled: true);

Widget _app(Widget menu, CallingCardSettings settings) => MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: CallingCardSettingsScope(
    notifier: ValueNotifier(settings),
    child: Scaffold(appBar: AppBar(actions: [menu])),
  ),
);

/// A print-dialog stand-in. Like the real dialog, it stays open (its future
/// pending) while the document is laid out: the test lays it out with
/// [letter], which then closes the dialog.
class _Capture {
  LayoutCallback? onLayout;
  String? name;
  final _closed = Completer<void>();

  Future<void> call({required String name, required LayoutCallback onLayout}) {
    this.name = name;
    this.onLayout = onLayout;
    return _closed.future;
  }

  /// Lays the document out on Letter paper, as a print dialog might offer,
  /// then closes the dialog.
  Future<Uint8List> letter(WidgetTester tester) async {
    final pdf = (await tester.runAsync(
      () async => onLayout!(PdfPageFormat.letter),
    ))!;
    _closed.complete();
    await tester.pumpAndSettle();
    return pdf;
  }
}

DanceExportMenu _danceMenu(Dance dance, _Capture capture) => DanceExportMenu(
  dance: dance,
  dialect: Dialect.canonical,
  authorNames: const ['Pat Author'],
  formationLabel: 'Improper',
  statusLabel: 'Active',
  pdfLayouter: capture.call,
);

Future<void> _open(WidgetTester tester, String menuKey) async {
  await tester.tap(find.byKey(ValueKey(menuKey)));
  await tester.pumpAndSettle();
}

void main() {
  test('cards are numbered as the set list numbers the slots', () {
    final program = Program(
      id: 'p',
      title: 'Friday',
      createdAt: _now,
      updatedAt: _now,
      slots: [
        // A leading alternate with no primary: the set list prints it ALT:.
        ProgramSlot(id: 's0', position: 0, danceId: 'orphan', isAlt: true),
        ProgramSlot(id: 's1', position: 1, danceId: 'a'),
        ProgramSlot(id: 's2', position: 2, danceId: 'alt', isAlt: true),
        // A note slot takes a number in the set list; the break does not.
        ProgramSlot(id: 's3', position: 3, text: 'Waltz'),
        ProgramSlot(id: 's4', position: 4, text: Program.breakSlotText),
        ProgramSlot(id: 's5', position: 5, danceId: 'b'),
        // A repeat keeps its first slot's number.
        ProgramSlot(id: 's6', position: 6, danceId: 'a'),
      ],
    );
    expect(callingCardPlaces(program, 'Alt'), {
      'orphan': 'Alt',
      'a': '1',
      'alt': 'Alt',
      'b': '3',
    });
  });

  group('dance Export menu', () {
    testWidgets('offers no calling card while the setting is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _danceMenu(_dance('d1'), _Capture()),
          CallingCardSettings.defaults,
        ),
      );
      await _open(tester, 'dance-export-menu');
      expect(
        find.byKey(const ValueKey('dance-export-calling-card')),
        findsNothing,
      );
      expect(find.text('Export / print PDF'), findsOneWidget);
    });

    testWidgets('prints one card at the card size, not the dialog paper', (
      tester,
    ) async {
      final capture = _Capture();
      await tester.pumpWidget(_app(_danceMenu(_dance('d1'), capture), _on));
      await _open(tester, 'dance-export-menu');
      await tester.tap(find.text('Print calling card'));
      await tester.pumpAndSettle();

      expect(capture.name, 'Dance_d1');
      final pdf = await capture.letter(tester);
      expect(pdfPageCount(pdf), 1);
      expect(pdfMediaBox(pdf), (360, 216));
    });

    testWidgets('uses the stored size and orientation', (tester) async {
      final capture = _Capture();
      await tester.pumpWidget(
        _app(
          _danceMenu(_dance('d1'), capture),
          const CallingCardSettings(
            enabled: true,
            size: CallingCardSize(4, 6, CallingCardUnit.inch),
          ),
        ),
      );
      await _open(tester, 'dance-export-menu');
      await tester.tap(find.text('Print calling card'));
      await tester.pumpAndSettle();
      expect(pdfMediaBox(await capture.letter(tester)), (288, 432));
    });

    testWidgets('says when the card was cut off', (tester) async {
      final capture = _Capture();
      await tester.pumpWidget(
        _app(
          _danceMenu(_dance('d1', callingNotes: 'word ' * 3000), capture),
          const CallingCardSettings(enabled: true, layout: 'title\nnotes'),
        ),
      );
      await _open(tester, 'dance-export-menu');
      await tester.tap(find.text('Print calling card'));
      await tester.pumpAndSettle();
      await capture.letter(tester);
      expect(
        find.text("1 card didn't fit and is cut off at the bottom."),
        findsOneWidget,
      );
    });

    testWidgets('says nothing when every card fits', (tester) async {
      final capture = _Capture();
      await tester.pumpWidget(_app(_danceMenu(_dance('d1'), capture), _on));
      await _open(tester, 'dance-export-menu');
      await tester.tap(find.text('Print calling card'));
      await tester.pumpAndSettle();
      await capture.letter(tester);
      expect(find.textContaining("didn't fit"), findsNothing);
    });
  });

  group('program Export menu', () {
    final dances = {'d1': _dance('d1'), 'd2': _dance('d2'), 'd3': _dance('d3')};
    Program program(List<ProgramSlot> slots) => Program(
      id: 'p1',
      title: 'Friday Contra',
      slots: slots,
      createdAt: _now,
      updatedAt: _now,
    );
    ProgramExportMenu menu(Program p, _Capture capture) => ProgramExportMenu(
      program: p,
      titleFor: (id) => dances[id]?.title,
      danceFor: (id) => dances[id],
      pdfLayouter: capture.call,
    );

    testWidgets('offers no calling cards while the setting is off', (
      tester,
    ) async {
      final p = program([ProgramSlot(id: 's1', position: 0, danceId: 'd1')]);
      await tester.pumpWidget(
        _app(menu(p, _Capture()), CallingCardSettings.defaults),
      );
      await _open(tester, 'program-export-menu');
      expect(
        find.byKey(const ValueKey('program-export-calling-cards')),
        findsNothing,
      );
    });

    testWidgets('one card per dance, alternates included', (tester) async {
      final capture = _Capture();
      final p = program([
        ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
        ProgramSlot(id: 's3', position: 2, danceId: 'd3'),
        ProgramSlot(id: 's4', position: 3, text: 'Waltz'),
      ]);
      await tester.pumpWidget(_app(menu(p, capture), _on));
      await _open(tester, 'program-export-menu');
      await tester.tap(find.text('Print calling cards'));
      await tester.pumpAndSettle();

      final pdf = await capture.letter(tester);
      expect(pdfPageCount(pdf), 3);
      expect(pdfMediaBox(pdf), (360, 216));
    });

    testWidgets('is unavailable while the program has no dance', (
      tester,
    ) async {
      final capture = _Capture();
      final p = program([ProgramSlot(id: 's1', position: 0, text: 'Waltz')]);
      await tester.pumpWidget(_app(menu(p, capture), _on));
      await _open(tester, 'program-export-menu');
      await tester.tap(find.text('Print calling cards'));
      await tester.pumpAndSettle();
      expect(capture.onLayout, isNull);
    });
  });
}
