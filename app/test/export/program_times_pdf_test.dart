import 'package:compendium_app/src/export/program_matrix_pdf.dart';
import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/pdf_probe.dart';

/// The set-list PDF prints a program's start, end and lesson times, and never
/// its Arrive by time: that is the caller's own logistics, and the PDF is made
/// for other people (maintainer ruling, #2350). The builder takes the plain
/// Helvetica theme so [pdfText] can read each drawn word back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 1, 1);

  test('start, end and lesson are printed; Arrive by is not', () async {
    final text = pdfText(
      await buildProgramPdf(
        Program(
          id: 'p',
          title: 'Program',
          eventDate: DateTime.utc(2026, 5, 1),
          startMinute: 1170,
          endMinute: 1350,
          lessonMinute: 1140,
          // 18:13: a time no other field holds, so any trace of it is Arrive by.
          arrivalMinute: 1093,
          createdAt: now,
          updatedAt: now,
        ),
        titleFor: (_) => null,
        formatTime: (m) => 'minute$m',
        theme: pw.ThemeData.base(),
      ),
    );
    expect(text, contains('minute1170'));
    expect(text, contains('minute1350'));
    expect(text, contains('minute1140'));
    expect(text, isNot(contains('minute1093')));
    expect(text, isNot(contains('18:13')));
  });

  group('the venue block and the program\'s own times', () {
    final venues = {'v1': Venue(id: 'v1', name: 'Grange Hall', time: '8-11pm')};
    Program linked({int? start, int? end, int? lesson}) => Program(
      id: 'p',
      title: 'Program',
      venueId: 'v1',
      startMinute: start,
      endMinute: end,
      lessonMinute: lesson,
      createdAt: now,
      updatedAt: now,
    );
    bool printsVenueTime(Program p) => programPdfVenueText(
      p,
      venues,
      const ProgramExportLabels(),
    ).blockLines.contains('Time: 8-11pm');

    test('a program without times keeps the venue\'s usual time', () {
      expect(printsVenueTime(linked()), isTrue);
    });

    test('a start or an end replaces it', () {
      expect(printsVenueTime(linked(start: 1170)), isFalse);
      expect(printsVenueTime(linked(end: 1350)), isFalse);
      expect(printsVenueTime(linked(start: 1170, end: 1350)), isFalse);
    });

    test('a lesson time alone does not', () {
      expect(printsVenueTime(linked(lesson: 1140)), isTrue);
    });

    test('the printed PDF shows only the program\'s times', () async {
      final text = pdfText(
        await buildProgramPdf(
          linked(start: 1170, end: 1350),
          titleFor: (_) => null,
          venuesById: venues,
          formatTime: (m) => 'minute$m',
          theme: pw.ThemeData.base(),
        ),
      );
      expect(text, contains('minute1170'));
      expect(text, isNot(contains('8-11pm')));
      // Positive control: the probe reads the venue's time when it is drawn.
      final without = pdfText(
        await buildProgramPdf(
          linked(),
          titleFor: (_) => null,
          venuesById: venues,
          theme: pw.ThemeData.base(),
        ),
      );
      expect(without, contains('8-11pm'));
    });
  });

  test('the matrix PDF header prints the dance\'s times between the date and '
      'the venue', () async {
    final text = pdfText(
      await buildProgramMatrixPdf(
        buildProgramMatrix(const []),
        taxonomy: contraTaxonomy,
        dialect: Dialect.canonical,
        programTitle: 'Program',
        eventDate: DateTime.utc(2026, 5, 1),
        times: danceTimesText(
          startMinute: 1170,
          endMinute: 1350,
          formatTime: (m) => 'minute$m',
        ),
        venue: 'Grange',
        theme: pw.ThemeData.base(),
      ),
    );
    expect(text, contains('2026-05-01 · minute1170'));
    expect(text, contains('minute1350 · Grange'));
  });
}
