import 'package:compendium_app/src/search/collection_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CollectionSelection', () {
    test('toggle adds, then removes, and keeps tap order', () {
      final s = CollectionSelection()
        ..toggle('b')
        ..toggle('a');
      expect(s.snapshot().toList(), ['b', 'a']);
      s.toggle('b');
      expect(s.snapshot(), {'a'});
    });

    test('snapshot is a copy', () {
      final s = CollectionSelection()..add('a');
      final copy = s.snapshot()..add('z');
      expect(s.length, 1);
      expect(copy, {'a', 'z'});
    });

    test('notShown counts selected ids the list does not show', () {
      final s = CollectionSelection()
        ..add('a')
        ..add('b')
        ..add('c');
      expect(s.notShown({'a', 'x'}), 2);
      expect(s.notShown({'a', 'b', 'c'}), 0);
      expect(s.notShown(const {}), 3);
    });

    test('coversAll is false for an empty list', () {
      final s = CollectionSelection()..add('a');
      expect(s.coversAll(const []), isFalse);
      expect(s.coversAll(['a']), isTrue);
      expect(s.coversAll(['a', 'b']), isFalse);
    });

    test('selectAll and deselectAll leave selections outside the list', () {
      final s = CollectionSelection()..add('hidden');
      s.selectAll(['a', 'b']);
      expect(s.snapshot(), {'hidden', 'a', 'b'});
      s.deselectAll(['a', 'b']);
      expect(s.snapshot(), {'hidden'});
    });

    test('deselectNotShown keeps only the shown selections', () {
      final s = CollectionSelection()
        ..add('a')
        ..add('hidden');
      s.deselectNotShown({'a', 'b'});
      expect(s.snapshot(), {'a'});
    });

    test('reconcile drops ids that no longer exist and reports it', () {
      final s = CollectionSelection()
        ..add('a')
        ..add('gone');
      expect(s.reconcile({'a', 'b'}), isTrue);
      expect(s.snapshot(), {'a'});
      expect(s.reconcile({'a', 'b'}), isFalse);
    });
  });
}
