import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';

void main() {
  test('all shareable persistence choke points call the normalizer', () async {
    final root = await packageRootPath();
    const expected = {
      'lib/src/storage/repositories/choreographer_repository.dart': [
        'final name = normalizeShareableText(c.name)',
      ],
      'lib/src/storage/repositories/custom_field_repository.dart': [
        'final key = normalizeShareableText(def.key)',
      ],
      'lib/src/storage/repositories/dance_repository.dart': [
        'title: normalizeShareableText(normalisedDance.title)',
      ],
      'lib/src/storage/repositories/program_repository.dart': [
        'title: normalizeShareableText(program.title)',
      ],
      'lib/src/storage/repositories/published_source_repository.dart': [
        'title: normalizeShareableText(s.title)',
      ],
      'lib/src/storage/repositories/settings_repository.dart': [
        'normalizeShareableJson(value)',
      ],
      'lib/src/storage/repositories/tag_repository.dart': [
        'final name = normalizeShareableText(tag.name)',
      ],
      'lib/src/storage/repositories/venue_repository.dart': [
        'name: normalizeShareableText(v.name)',
      ],
    };

    for (final entry in expected.entries) {
      final source = File(p.join(root, entry.key)).readAsStringSync();
      for (final snippet in entry.value) {
        expect(
          source,
          contains(snippet),
          reason: '${entry.key} must normalize its shareable write inputs',
        );
      }
    }
  });
}
