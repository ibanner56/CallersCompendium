import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('restoreRemovedDefaultsOrder', () {
    test('built-ins keep catalog order and precede all customs', () {
      final order = restoreRemovedDefaultsOrder(
        catalogOrder: const ['swing:partner', 'hey:full', 'do_si_do'],
        customs: const [
          (id: 'param:aaa', label: 'Balance'),
          (id: 'compound:bbb', label: 'Petronella'),
        ],
      );
      expect(order.take(3), ['swing:partner', 'hey:full', 'do_si_do']);
      expect(order.sublist(3).toSet(), {'param:aaa', 'compound:bbb'});
    });

    test(
      'customs are appended sorted by displayed label, case-insensitive',
      () {
        final order = restoreRemovedDefaultsOrder(
          catalogOrder: const ['do_si_do'],
          customs: const [
            (id: 'param:1', label: 'zeta'),
            (id: 'compound:2', label: 'Alpha'),
            (id: 'param:3', label: 'mike'),
          ],
        );
        // Sorted by label ignoring case: Alpha, mike, zeta — NOT by id.
        expect(order, ['do_si_do', 'compound:2', 'param:3', 'param:1']);
      },
    );

    test('equal labels break ties on id for a stable result', () {
      final order = restoreRemovedDefaultsOrder(
        catalogOrder: const [],
        customs: const [
          (id: 'param:zzz', label: 'Same'),
          (id: 'compound:aaa', label: 'same'),
        ],
      );
      expect(order, ['compound:aaa', 'param:zzz']);
    });

    test('no customs returns the catalog order unchanged', () {
      final order = restoreRemovedDefaultsOrder(
        catalogOrder: const ['swing:partner', 'chain:robin'],
        customs: const [],
      );
      expect(order, ['swing:partner', 'chain:robin']);
    });
  });
}
