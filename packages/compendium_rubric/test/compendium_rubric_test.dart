import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

void main() {
  test('package smoke test: version marker is exposed', () {
    expect(compendiumRubricVersion, '0.1.0');
  });
}
