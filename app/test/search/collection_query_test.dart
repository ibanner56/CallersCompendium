import 'package:compendium_app/src/search/collection_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distinctFolded', () {
    test('trims, drops blanks, keeps one spelling per folded value', () {
      expect(
        distinctFolded([
          ' 6/8',
          'D minor',
          '',
          '  ',
          'd minor',
          'Ré',
          're',
          '3/2',
        ]),
        ['3/2', '6/8', 'D minor', 'Ré'],
      );
    });

    test('reads the numbers in a meter as numbers', () {
      expect(distinctFolded(['12/8', '6/8', '2/2', '10/8', '3/2', '9/8']), [
        '2/2',
        '3/2',
        '6/8',
        '9/8',
        '10/8',
        '12/8',
      ]);
    });
  });
}
