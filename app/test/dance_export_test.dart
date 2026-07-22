import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:compendium_app/src/export/dance_pdf.dart';
import 'package:compendium_app/src/widgets/dance_export_menu.dart';

final _now = DateTime.utc(2026, 1, 1);

/// A [FigureRenderer] spy that counts calls to [render] vs [renderSummary] while
/// delegating to the real implementation, so a test can assert which path an
/// export takes (#457 regression guard).
class _SpyRenderer extends FigureRenderer {
  _SpyRenderer() : super(contraTaxonomy);

  int renderCalls = 0;
  int renderSummaryCalls = 0;

  @override
  String render(Figure figure, Dialect dialect, {bool decimals = false}) {
    renderCalls++;
    return super.render(figure, dialect, decimals: decimals);
  }

  @override
  String renderSummary(
    Figure figure,
    Dialect dialect, {
    bool verbose = false,
    bool decimals = false,
  }) {
    renderSummaryCalls++;
    return super.renderSummary(
      figure,
      dialect,
      verbose: verbose,
      decimals: decimals,
    );
  }
}

Dance _dance({
  String title = 'Rory O\'More',
  List<String> authorIds = const [],
  List<Figure> figures = const [],
  String callingNotes = '',
  DanceStatus status = DanceStatus.active,
}) => Dance(
  id: 'd1',
  title: title,
  authorIds: authorIds,
  figures: figures,
  callingNotes: callingNotes,
  status: status,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpMenu(
  WidgetTester tester,
  Dance dance, {
  Dialect? dialect,
  List<String> authorNames = const [],
  String statusLabel = 'Active',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            DanceExportMenu(
              dance: dance,
              dialect: dialect ?? Dialect.canonical,
              authorNames: authorNames,
              formationLabel: 'Duple improper',
              levelLabel: 'Intermediate',
              statusLabel: statusLabel,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Copies the dance card via the menu and returns the text placed on the
/// clipboard (the same [danceToPlainText] output the share action uses).
Future<String?> _copyAndReadClipboard(
  WidgetTester tester,
  Dance dance, {
  String statusLabel = 'Active',
}) async {
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

  await _pumpMenu(tester, dance, statusLabel: statusLabel);
  await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Copy dance'));
  await tester.pumpAndSettle();
  return clipboardText;
}

void main() {
  group('DanceExportMenu', () {
    testWidgets('is present and labeled in an app bar', (tester) async {
      await _pumpMenu(tester, _dance());

      final menu = find.byKey(const ValueKey('dance-export-menu'));
      expect(menu, findsOneWidget);
      expect(find.byTooltip('Export'), findsOneWidget);
    });

    testWidgets('the control is reachable to assistive tech', (tester) async {
      await _pumpMenu(tester, _dance());

      // Assert accessibility via the semantics tree, not onPressed != null:
      // the export button exposes the "Export" label and a tap action.
      final semantics = tester.getSemantics(find.byTooltip('Export'));
      expect(
        semantics,
        isSemantics(tooltip: 'Export', isButton: true, hasTapAction: true),
      );
    });

    testWidgets('offers share, copy, and PDF actions', (tester) async {
      await _pumpMenu(tester, _dance());

      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Share dance (text)'), findsOneWidget);
      expect(find.text('Copy dance'), findsOneWidget);
      expect(find.text('Export / print PDF'), findsOneWidget);
    });

    testWidgets('Copy dance puts the rendered card on the clipboard', (
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
        _dance(
          figures: [
            Figure(move: 'swing', params: {'who': 'role1s', 'beats': 16}),
          ],
        ),
        dialect: Dialect.larksRobins,
        authorNames: const ['Ted Sannella'],
      );

      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy dance'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Rory O\'More'));
      expect(clipboardText, contains('Ted Sannella'));
      // Dialect is applied to the copied card (role token substituted).
      expect(clipboardText, contains('larks swing'));
      expect(find.text('Dance copied to clipboard.'), findsOneWidget);
    });

    testWidgets('an active dance omits the Status line from the export', (
      tester,
    ) async {
      final text = await _copyAndReadClipboard(
        tester,
        _dance(status: DanceStatus.active),
        statusLabel: 'Active',
      );

      expect(text, isNotNull);
      // Mirrors the on-screen card, which only banners a non-active status.
      expect(text, isNot(contains('Status:')));
    });

    testWidgets('a non-active dance includes the Status line in the export', (
      tester,
    ) async {
      final text = await _copyAndReadClipboard(
        tester,
        _dance(status: DanceStatus.deprecated),
        statusLabel: 'Deprecated',
      );

      expect(text, isNotNull);
      expect(text, contains('Status: Deprecated'));
    });

    testWidgets('surfaces a SnackBar when sharing throws', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                DanceExportMenu(
                  dance: _dance(),
                  dialect: Dialect.canonical,
                  authorNames: const [],
                  formationLabel: 'Duple improper',
                  statusLabel: 'Active',
                  shareInvoker: (params) async =>
                      throw Exception('no share target'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share dance (text)'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't share this dance"), findsOneWidget);
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
                DanceExportMenu(
                  dance: _dance(),
                  dialect: Dialect.canonical,
                  authorNames: const [],
                  formationLabel: 'Duple improper',
                  statusLabel: 'Active',
                  shareInvoker: (params) async => captured = params,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share dance (text)'));
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
                DanceExportMenu(
                  dance: _dance(),
                  dialect: Dialect.canonical,
                  authorNames: const [],
                  formationLabel: 'Duple improper',
                  statusLabel: 'Active',
                  pdfLayouter: ({required name, required onLayout}) async =>
                      throw Exception('no printer'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't export this dance"), findsOneWidget);
    });

    testWidgets('sanitizes the dance title in the PDF print-job name', (
      tester,
    ) async {
      String? capturedName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                DanceExportMenu(
                  dance: _dance(title: 'Rory/O\u0007More: 3\\9'),
                  dialect: Dialect.canonical,
                  authorNames: const [],
                  formationLabel: 'Duple improper',
                  statusLabel: 'Active',
                  pdfLayouter: ({required name, required onLayout}) async =>
                      capturedName = name,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      // Path separators and control characters never reach the print-job name.
      expect(capturedName, 'Rory_O_More__3_9');
      expect(capturedName, isNot(contains('/')));
      expect(capturedName, isNot(contains('\\')));
    });

    testWidgets('falls back to "dance" when the title has no safe content', (
      tester,
    ) async {
      String? capturedName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                DanceExportMenu(
                  dance: _dance(title: '///'),
                  dialect: Dialect.canonical,
                  authorNames: const [],
                  formationLabel: 'Duple improper',
                  statusLabel: 'Active',
                  pdfLayouter: ({required name, required onLayout}) async =>
                      capturedName = name,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dance-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export / print PDF'));
      await tester.pumpAndSettle();

      expect(capturedName, 'dance');
    });
  });

  group('buildDancePdf', () {
    testWidgets('produces a non-empty PDF document', (tester) async {
      final bytes = await buildDancePdf(
        _dance(
          authorIds: ['a1'],
          figures: [
            Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
            Figure(move: 'do_si_do', params: {'who': 'partners', 'beats': 8}),
          ],
          callingNotes: 'Teach the swing first.',
        ),
        dialect: Dialect.larksRobins,
        authorNames: const ['Ted Sannella'],
        formationLabel: 'Duple improper',
        levelLabel: 'Intermediate',
        statusLabel: 'Active',
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    // Regression (#457): the PDF figure path must use renderSummary(), not the
    // terse render(), so on-screen modifiers survive to the printed card. A bare
    // down-the-hall carries a default turn-couple ender that renderSummary
    // surfaces and render() drops, so the two genuinely differ; a spy renderer
    // asserts the export invoked renderSummary and never render() for the figure.
    // This FAILS if dance_pdf.dart reverts the call site back to render().
    testWidgets('renders figures via renderSummary so modifiers survive (#457)', (
      tester,
    ) async {
      final figure = Figure(move: 'down_the_hall', params: {'beats': 8});
      // Guard: the chosen figure must actually differ between the two renderers,
      // otherwise the spy assertions below would prove nothing.
      final plain = FigureRenderer(contraTaxonomy);
      expect(
        plain.renderSummary(figure, Dialect.canonical),
        isNot(equals(plain.render(figure, Dialect.canonical))),
      );

      final spy = _SpyRenderer();
      final bytes = await buildDancePdf(
        _dance(title: 'Hall Dance', figures: [figure]),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
        renderer: spy,
      );

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(spy.renderSummaryCalls, greaterThan(0));
      expect(spy.renderCalls, 0);
    });

    testWidgets('handles a figureless, note-less dance', (tester) async {
      final bytes = await buildDancePdf(
        _dance(title: 'Stub'),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
      );
      expect(bytes, isNotEmpty);
    });

    // The PDF's rendered text is glyph-encoded and stream-compressed, so it
    // can't be grep'd for "Status:". Instead we hold every input constant
    // except the dance's status and pass the SAME non-empty statusLabel to
    // both: the guard omits the Status line for an active dance but keeps it
    // for a non-active one, so the non-active PDF must be strictly larger.
    // If the guard were dropped (active also printing "Status: Active"), the
    // two documents would render identically and this test would fail.
    testWidgets('omits the Status line for an active dance in the PDF', (
      tester,
    ) async {
      Future<int> pdfLen(DanceStatus status) async {
        final bytes = await buildDancePdf(
          _dance(title: 'Rory O\'More', status: status),
          dialect: Dialect.canonical,
          authorNames: const [],
          formationLabel: 'Duple improper',
          statusLabel: 'Deprecated',
        );
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        return bytes.length;
      }

      final activeLen = await pdfLen(DanceStatus.active);
      final nonActiveLen = await pdfLen(DanceStatus.deprecated);

      expect(nonActiveLen, greaterThan(activeLen));
    });
  });
}
