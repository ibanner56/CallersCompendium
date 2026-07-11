import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('uuidV4', () {
    final v4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('produces RFC 4122 v4 formatted ids', () {
      for (var i = 0; i < 100; i++) {
        expect(uuidV4(), matches(v4));
      }
    });

    test('produces unique ids', () {
      final ids = {for (var i = 0; i < 1000; i++) uuidV4()};
      expect(ids, hasLength(1000));
    });
  });
}
