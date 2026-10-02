import 'dart:async';
import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/dance_pdf.dart';
import 'package:compendium_app/src/export/export_labels_l10n.dart';
import 'package:compendium_app/src/export/program_matrix_pdf.dart';
import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRG-01 / PRG-02: the PDF builders must draw Japanese text with real glyphs
/// and must let a note longer than a page flow onto the next one.

final _now = DateTime.utc(2026, 7, 13);

/// One unbroken paragraph of [n] words — the case `MultiPage` rejects with
/// "Widget won't fit into the page" unless the `pw.Text` can span pages.
String _words(int n) => List.filled(n, 'swing').join(' ');

Dance _dance(
  String id,
  String title, {
  String callingNotes = '',
  String walkthrough = '',
}) => Dance(
  id: id,
  title: title,
  figures: [
    testFigure(move: 'swing'),
    testFigure(move: 'balance'),
  ],
  callingNotes: callingNotes,
  walkthrough: walkthrough,
  createdAt: _now,
  updatedAt: _now,
  formation: const Formation(FormationShape.dupleImproper),
);

Program _program({
  String title = 'Friday Contra',
  String notes = '',
  List<ProgramSlot> slots = const [],
}) => Program(
  id: 'p1',
  title: title,
  eventDate: DateTime.utc(2026, 3, 9),
  notes: notes,
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

DanceCardLabels _cardLabels(Dance _) => (
  authorNames: const ['山田'],
  formationLabel: '二列・デュープル',
  levelLabel: null,
  statusLabel: '現役',
);

Future<T> _capturePrints<T>(
  Future<T> Function() body,
  List<String> lines,
) async => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) => lines.add(line),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CJK glyph coverage (PRG-01)', () {
    // The `pdf` package prints "Unable to find a font…" only from inside an
    // `assert`, so it fires in test/debug builds and release builds silently
    // draw boxes — capture `print` to see it.
    final ja = lookupAppLocalizations(const Locale('ja'));
    const title = '春のコントラ Ærø Søndag';

    void expectNoMissingFont(List<String> lines) {
      expect(lines.where((l) => l.contains('Unable to find a font')), isEmpty);
    }

    test('program PDF with ja labels and a Japanese title', () async {
      final lines = <String>[];
      final bytes = await _capturePrints(
        () => buildProgramPdf(
          _program(
            title: title,
            notes: 'お知らせ',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
          titleFor: (_) => title,
          labels: programExportLabels(ja),
          danceLabels: danceExportLabels(ja),
          appendDances: [
            (
              dance: _dance('d1', title, callingNotes: '注意', walkthrough: '手順'),
              isAlternate: false,
            ),
          ],
          cardLabelsFor: _cardLabels,
        ),
        lines,
      );
      expect(bytes, isNotEmpty);
      expectNoMissingFont(lines);
    });

    test('dance PDF with ja labels and a Japanese title', () async {
      final lines = <String>[];
      final bytes = await _capturePrints(
        () => buildDancePdf(
          _dance('d1', title, callingNotes: '注意', walkthrough: '手順'),
          dialect: Dialect.canonical,
          authorNames: const ['山田'],
          formationLabel: '二列・デュープル',
          statusLabel: '現役',
          labels: danceExportLabels(ja),
        ),
        lines,
      );
      expect(bytes, isNotEmpty);
      expectNoMissingFont(lines);
    });

    test('matrix PDF with ja labels and a Japanese title', () async {
      final lines = <String>[];
      final bytes = await _capturePrints(
        () => buildProgramMatrixPdf(
          buildProgramMatrix([_dance('d1', title)]),
          taxonomy: contraTaxonomy,
          dialect: Dialect.canonical,
          programTitle: title,
          labels: programMatrixExportLabels(ja),
        ),
        lines,
      );
      expect(bytes, isNotEmpty);
      expectNoMissingFont(lines);
    });
  });

  group('long text spans pages (PRG-02)', () {
    final long = _words(3000);

    test('program notes', () async {
      final bytes = await buildProgramPdf(
        _program(notes: long),
        titleFor: (_) => 'Dance',
      );
      expect(bytes, isNotEmpty);
    });

    test('appendix calling notes and walkthrough', () async {
      final bytes = await buildProgramPdf(
        _program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
        titleFor: (_) => 'Dance',
        appendDances: [
          (
            dance: _dance('d1', 'Dance', callingNotes: long),
            isAlternate: false,
          ),
        ],
        cardLabelsFor: _cardLabels,
      );
      expect(bytes, isNotEmpty);

      final walk = await buildProgramPdf(
        _program(
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
        titleFor: (_) => 'Dance',
        appendDances: [
          (dance: _dance('d1', 'Dance', walkthrough: long), isAlternate: false),
        ],
        cardLabelsFor: _cardLabels,
      );
      expect(walk, isNotEmpty);
    });

    test('a slot note, primary and alternate', () async {
      final bytes = await buildProgramPdf(
        _program(
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1', text: long),
            ProgramSlot(
              id: 's2',
              position: 1,
              danceId: 'd2',
              isAlt: true,
              text: long,
            ),
          ],
        ),
        titleFor: (_) => 'Dance',
      );
      expect(bytes, isNotEmpty);
    });

    test('dance calling notes and walkthrough', () async {
      final bytes = await buildDancePdf(
        _dance('d1', 'Dance', callingNotes: long, walkthrough: long),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
      );
      expect(bytes, isNotEmpty);
    });
  });
}
