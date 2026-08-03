import 'dart:io';

import 'package:compendium_core/src/privacy/data_classification_doc.dart';
import 'package:test/test.dart';

/// Guards that the committed developer doc still matches the registry.
///
/// The registry is the source of truth and the doc is a rendering of it, so the
/// two can only disagree if someone changed a classification and forgot to
/// regenerate. That is exactly the documentation drift this repository keeps
/// rediscovering, so it is caught here rather than in review.
void main() {
  /// Resolves the doc relative to this test file, so the test passes whether it
  /// is run from the package directory or the repository root.
  File docFile() {
    final here = File.fromUri(Platform.script).parent.path;
    for (final candidate in [
      'docs/dev/data-classification.md',
      '../docs/dev/data-classification.md',
      '../../docs/dev/data-classification.md',
      '$here/../../../../docs/dev/data-classification.md',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) return file;
    }
    fail(
      'Could not locate docs/dev/data-classification.md from '
      '${Directory.current.path}',
    );
  }

  test('the committed catalogue matches the registry', () {
    final file = docFile();
    final committed = file.readAsStringSync();

    expect(
      withRegeneratedCatalogue(committed),
      committed,
      reason:
          'docs/dev/data-classification.md is out of date with '
          'lib/src/privacy/field_registry.dart. Regenerate it:\n\n'
          '  fvm dart run '
          'packages/compendium_core/tool/generate_data_classification_doc.dart\n',
    );
  });

  test('the generated block markers are present and ordered', () {
    final committed = docFile().readAsStringSync();
    final begin = committed.indexOf(docBeginMarker);
    final end = committed.indexOf(docEndMarker);

    expect(begin, greaterThanOrEqualTo(0), reason: 'missing begin marker');
    expect(end, greaterThan(begin), reason: 'end marker missing or misordered');
  });
}
