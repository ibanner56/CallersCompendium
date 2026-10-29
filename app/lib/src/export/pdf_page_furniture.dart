import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The running title shown at the top of every page after the first.
///
/// Page one already carries the document's own large title, so it gets an empty
/// header; repeating the title there would print it twice.
pw.Widget pdfRunningHeader(pw.Context context, String title) {
  if (context.pageNumber == 1) return pw.SizedBox();
  return pw.Container(
    alignment: pw.Alignment.centerLeft,
    margin: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      title,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
    ),
  );
}

/// The "Page x of y" footer shown on every page.
pw.Widget pdfPageFooter(
  pw.Context context,
  String Function(int page, int pages) pageOf,
) => pw.Container(
  alignment: pw.Alignment.centerRight,
  margin: const pw.EdgeInsets.only(top: 8),
  child: pw.Text(
    pageOf(context.pageNumber, context.pagesCount),
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
);
