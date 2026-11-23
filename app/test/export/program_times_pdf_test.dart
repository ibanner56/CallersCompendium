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
}
