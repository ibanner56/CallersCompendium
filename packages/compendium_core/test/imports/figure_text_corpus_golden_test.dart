import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';

/// Byte-identity guard over the import text pipeline.
///
/// [_corpusPath] is a frozen copy of every short string literal in
/// `test/imports/**` plus the text of the import fixture files
/// (`test/imports/support/**`, `tools/seed/fixtures/*.html`), one per line. For
/// each line the golden records what the import scrub, the import fan-out
/// parser and the editor's free-text entry produce. A refactor of the parser
/// vocabulary or of the canonicalisation chokepoint must leave every record
/// unchanged; an intended behaviour change re-records the golden and shows up
/// as a reviewable diff.
///
/// Set `UPDATE_GOLDEN=1` to re-record it. The corpus is frozen on purpose, so
/// adding or editing a test elsewhere never changes this one.
const _corpusPath = 'test/imports/fixtures/figure_text_corpus.txt';
const _goldenPath = 'test/imports/fixtures/figure_text_corpus_golden.jsonl';

Map<String, Object?> _record(String line) {
  final scrub = scrubFigureText(line);
  final fanOut = encodeFigures(parseFigureLinesFanOut(line));
  final freeText = encodeFigures(parseFreeTextFigureEntry(line));
  return {
    'in': line,
    // Omitted when equal to the input / to `fanOut`, to keep the file small.
    if (scrub != line) 'scrub': scrub,
    'fanOut': fanOut,
    if (freeText != fanOut) 'freeText': freeText,
  };
}

void main() {
  test('import scrub and parsers match the recorded golden', () async {
    final root = await packageRootPath();
    final corpus = File(
      p.join(root, _corpusPath),
    ).readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(corpus.length, greaterThan(5000), reason: 'corpus went missing');
    final actual = [for (final line in corpus) jsonEncode(_record(line))];

    final golden = File(p.join(root, _goldenPath));
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync('${actual.join('\n')}\n');
    }
    final expected = golden
        .readAsLinesSync()
        .where((l) => l.isNotEmpty)
        .toList();
    expect(actual.length, expected.length);
    final mismatches = <String>[];
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) {
        mismatches.add('expected: ${expected[i]}\n  actual: ${actual[i]}');
      }
    }
    expect(
      mismatches,
      isEmpty,
      reason:
          '${mismatches.length} corpus line(s) changed:\n'
          '${mismatches.take(20).join('\n')}',
    );
  });
}
