import 'package:compendium_core/src/imports/formation_set_names.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('classifyFormationSetName', () {
    test('reads the set shape ahead of the start word', () {
      expect(classifyFormationSetName('proper triplet (231)'), (
        shape: FormationShape.triplet,
        qualifier: 'Proper (231)',
      ));
      expect(classifyFormationSetName('improper quadruplet (2341)'), (
        shape: FormationShape.quadruplet,
        qualifier: 'Improper (2341)',
      ));
      expect(classifyFormationSetName('indecent triplet'), (
        shape: FormationShape.triplet,
        qualifier: 'Indecent',
      ));
    });

    test(
      'keeps the order the couples end in, with or without a start word',
      () {
        expect(classifyFormationSetName('triplet ( 312 )'), (
          shape: FormationShape.triplet,
          qualifier: '(312)',
        ));
        expect(classifyFormationSetName('indecent triplet'), (
          shape: FormationShape.triplet,
          qualifier: 'Indecent',
        ));
        // Only digits in brackets are an order.
        expect(
          classifyFormationSetName('proper triplet (from the top)')?.qualifier,
          'Proper',
        );
      },
    );

    test('triplet is not read as triple minor', () {
      expect(
        classifyFormationSetName('triplet')?.shape,
        FormationShape.triplet,
      );
      expect(classifyFormationSetName('triple minor - improper'), (
        shape: FormationShape.tripleMinor,
        qualifier: 'Improper',
      ));
    });

    test('names with no set shape, or a bare "triple", are left alone', () {
      expect(classifyFormationSetName('improper'), isNull);
      expect(classifyFormationSetName('duple minor - proper'), isNull);
      expect(classifyFormationSetName('improper (triple progression)'), isNull);
    });
  });

  group('joinFormationDetail', () {
    test('joins, skips empties, and is null when both are absent', () {
      expect(joinFormationDetail('Proper', 'x'), 'Proper; x');
      expect(joinFormationDetail('Proper', ''), 'Proper');
      expect(joinFormationDetail(null, 'x'), 'x');
      expect(joinFormationDetail(null, ''), isNull);
      expect(joinFormationDetail(null, null), isNull);
    });
  });
}
