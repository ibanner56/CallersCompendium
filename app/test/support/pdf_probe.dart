import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads back what a generated PDF contains, for tests that run a builder with
/// the plain Helvetica theme (see `export/pdf_export_format_test.dart`).

/// The words drawn in [pdf], in drawing order and space-separated, so a phrase
/// like `Page 2 of 3` can be searched for. Every deflated stream is read; the
/// `pdf` package writes one `[(word)]TJ` per word of a Helvetica run.
String pdfText(Uint8List pdf) {
  final raw = latin1.decode(pdf);
  final out = StringBuffer();
  for (final m in RegExp(
    r'stream\r?\n([\s\S]*?)\r?\nendstream',
  ).allMatches(raw)) {
    try {
      out.writeln(
        latin1.decode(ZLibDecoder().convert(latin1.encode(m.group(1)!))),
      );
    } on Object {
      // Not a deflate stream (an image, a font file): nothing to read.
    }
  }
  return [
    for (final m in RegExp(r'\[\((.*?)\)\]TJ').allMatches(out.toString()))
      m.group(1)!,
  ].join(' ');
}

int pdfPageCount(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page(?![A-Za-z])').allMatches(latin1.decode(pdf)).length;

/// The first page's `/MediaBox` as (width, height), rounded to whole points.
(int, int) pdfMediaBox(Uint8List pdf) {
  final m = RegExp(
    r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
  ).firstMatch(latin1.decode(pdf))!;
  return (double.parse(m.group(1)!).round(), double.parse(m.group(2)!).round());
}
