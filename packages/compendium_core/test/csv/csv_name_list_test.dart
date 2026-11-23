import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The `, `-separated name lists of the dances CSV (#2332, #2329).
void main() {
  group('joinNameList', () {
    test('a name without a comma or backslash is written as it always was', () {
      expect(
        joinNameList(['Jig', 'Hey Ho', "Rory O'More"]),
        "Jig, Hey Ho, Rory O'More",
      );
      expect(joinNameList(const []), '');
    });

    test('a comma is written \\, and a backslash \\\\', () {
      expect(joinNameList(['Hey, Ho', r'A\B', r'\,']), r'Hey\, Ho, A\\B, \\\,');
    });
  });

  group('splitNameList', () {
    test('hand-typed lists with no backslash split on commas as before', () {
      expect(splitNameList('Jig, Favourite,,  Reel '), [
        'Jig',
        'Favourite',
        'Reel',
      ]);
      expect(splitNameList(''), isEmpty);
      expect(splitNameList('A; B\nC, D', extraSeparators: {';', '\n'}), [
        'A',
        'B',
        'C',
        'D',
      ]);
    });

    test('an escaped comma stays in the name and \\\\ is a backslash', () {
      expect(splitNameList(r'Hey\, Ho, Jig'), ['Hey, Ho', 'Jig']);
      expect(splitNameList(r'A\\B, C\\'), [r'A\B', r'C\']);
      expect(splitNameList(r'\\,x'), [r'\', 'x']);
    });

    test('an unrecognised backslash stays literal', () {
      expect(splitNameList(r'C:\temp, a\'), [r'C:\temp', r'a\']);
      expect(splitNameList(r'\'), [r'\']);
      expect(splitNameList(r'a\;b', extraSeparators: {';'}), [
        r'a\',
        'b',
      ], reason: 'only the comma is escapable');
    });

    test('every list of names survives a join and a split', () {
      const names = [
        'Hey, Ho',
        r'back\slash',
        r'ends with\',
        r'\,',
        r'\\',
        ',',
        'plain',
      ];
      expect(splitNameList(joinNameList(names)), names);
    });
  });
}
