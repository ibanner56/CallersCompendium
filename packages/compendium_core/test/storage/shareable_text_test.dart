import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'normalizes NFC and removes invisible controls while keeping newlines',
    () {
      expect(normalizeShareableText('Cafe\u0301\u200B\nnext'), 'Café\nnext');
    },
  );

  test('normalizes nested JSON values and object keys', () {
    expect(
      normalizeShareableJson({
        'Cafe\u0301': [
          'a\u200B',
          {'b': 'e\u0301'},
        ],
      }),
      {
        'Café': [
          'a',
          {'b': 'é'},
        ],
      },
    );
  });

  test('leaves non-text JSON values unchanged', () {
    expect(normalizeShareableJson([true, 1, null]), [true, 1, null]);
  });

  test('rejects object keys that collide after normalization', () {
    expect(
      () => normalizeShareableJson({'café': 'first', 'cafe\u0301': 'second'}),
      throwsA(isA<ShareableJsonKeyCollision>()),
    );
  });
}
