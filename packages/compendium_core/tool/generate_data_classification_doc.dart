import 'dart:io';

import 'package:compendium_core/src/privacy/data_classification_doc.dart';

/// Regenerates the field-catalogue table in `docs/dev/data-classification.md`
/// from the registry in `lib/src/privacy/field_registry.dart`.
///
/// The registry is the source of truth; the doc is a rendering of it. Run from
/// the repository root:
///
/// ```sh
/// fvm dart run \
///   packages/compendium_core/tool/generate_data_classification_doc.dart
/// ```
///
/// `test/privacy/data_classification_doc_test.dart` fails when the committed
/// doc differs from what this emits, so forgetting to run it is caught in CI
/// rather than discovered as documentation drift months later.
void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'docs/dev/data-classification.md';
  final file = File(path);

  if (!file.existsSync()) {
    stderr.writeln(
      'Not found: $path\n'
      'Run this from the repository root, or pass the path explicitly.',
    );
    exitCode = 1;
    return;
  }

  final original = file.readAsStringSync();
  final updated = withRegeneratedCatalogue(original);

  if (original == updated) {
    stdout.writeln('Already up to date: $path');
    return;
  }

  file.writeAsStringSync(updated);
  stdout.writeln('Regenerated the field catalogue in $path');
}
