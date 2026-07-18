import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_app/src/widgets/program_export_menu.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({
  String title = 'Friday Contra',
  List<ProgramSlot> slots = const [],
  bool hideAlternates = false,
}) => Program(
  id: 'p1',
  title: title,
  eventDate: DateTime.utc(2026, 3, 9),
  venue: 'Town Hall',
  band: 'The Ripplers',
  caller: 'Isaac',
  dancerLevel: 'All',
  notes: 'Bring water.',
  slots: slots,
  hideAlternates: hideAlternates,
  createdAt: _now,
  updatedAt: _now,
);

String? _titles(String id) =>
    const {'d1': 'Rory O\'More', 'd2': 'The Nice Combination'}[id];

Future<void> _pumpMenu(WidgetTester tester, Program program) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [ProgramExportMenu(program: program, titleFor: _titles)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ProgramExportMenu', () {
    testWidgets('is present and labeled in an app bar', (tester) async {
      await _pumpMenu(tester, _program());

      final menu = find.byKey(const ValueKey('program-export-menu'));
      expect(menu, findsOneWidget);
      // Labeled (icon + accessible tooltip), not icon-only-color.
      expect(find.byTooltip('Export'), findsOneWidget);
    });

    testWidgets('offers share, copy, and PDF actions', (tester) async {
      await _pumpMenu(tester, _program());

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Share set list (text)'), findsOneWidget);
      expect(find.text('Copy set list'), findsOneWidget);
      expect(find.text('Export / print PDF'), findsOneWidget);
    });

    testWidgets('Copy set list puts the rendered text on the clipboard', (
      tester,
    ) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pumpMenu(
        tester,
        _program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Friday Contra'));
      expect(clipboardText, contains('1. Rory O\'More'));
      expect(find.text('Set list copied to clipboard.'), findsOneWidget);
    });

    testWidgets('Copy set list omits ALTs when hideAlternates is set', (
      tester,
    ) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pumpMenu(
        tester,
        _program(
          hideAlternates: true,
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
          ],
        ),
      );

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('1. Rory O\'More'));
      expect(clipboardText, isNot(contains('ALT:')));
      expect(clipboardText, isNot(contains('The Nice Combination')));
    });

    testWidgets('surfaces a SnackBar when sharing throws', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: _program(),
                  titleFor: _titles,
                  shareInvoker: (params) async =>
                      throw Exception('no share target'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share set list (text)'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't share this set list"), findsOneWidget);
    });

    testWidgets('share receives a non-null sharePositionOrigin', (
      tester,
    ) async {
      ShareParams? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: _program(),
                  titleFor: _titles,
                  shareInvoker: (params) async => captured = params,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share set list (text)'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.sharePositionOrigin, isNotNull);
    });

    testWidgets('surfaces a SnackBar when the PDF export throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: _program(),
                  titleFor: _titles,
                  pdfLayouter: ({required name, required onLayout}) async =>
                      throw Exception('no printer'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't export this set list"), findsOneWidget);
    });
  });

  group('buildProgramPdf', () {
    testWidgets('produces a non-empty PDF document', (tester) async {
      final bytes = await buildProgramPdf(
        _program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
            ProgramSlot(id: 's3', position: 2, text: 'Waltz break'),
          ],
        ),
        titleFor: _titles,
      );

      expect(bytes, isNotEmpty);
      // A valid PDF begins with the "%PDF" magic header.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    testWidgets('handles an empty program', (tester) async {
      final bytes = await buildProgramPdf(
        _program(title: 'Empty Night'),
        titleFor: _titles,
      );
      expect(bytes, isNotEmpty);
    });
  });
}
