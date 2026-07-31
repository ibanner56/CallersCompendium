import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('Provenance value equality', () {
    Provenance make({
      ProvenanceSource source = ProvenanceSource.callersbox,
      String? externalId = 'ext-1',
      DateTime? importedAt,
      String? permission = 'full',
      String? license = 'CC-BY',
      String? rawPayload = '{"a":1}',
      String? sourceVersion = 'v1',
    }) => Provenance(
      source: source,
      externalId: externalId,
      importedAt: importedAt ?? DateTime.utc(2024, 1, 1),
      permission: permission,
      license: license,
      rawPayload: rawPayload,
      sourceVersion: sourceVersion,
    );

    test('equal instances compare equal and share hashCode', () {
      final a = make();
      final b = make();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing source is not equal', () {
      expect(make(), isNot(make(source: ProvenanceSource.contradb)));
    });

    test('differing externalId is not equal', () {
      expect(make(), isNot(make(externalId: 'ext-2')));
    });

    test('differing importedAt is not equal', () {
      expect(make(), isNot(make(importedAt: DateTime.utc(2024, 1, 2))));
    });

    test('differing permission is not equal', () {
      expect(make(), isNot(make(permission: 'search')));
    });

    test('differing license is not equal', () {
      expect(make(), isNot(make(license: 'CC0')));
    });

    test('differing rawPayload is not equal', () {
      expect(make(), isNot(make(rawPayload: '{"a":2}')));
    });

    test('differing sourceVersion is not equal', () {
      expect(make(), isNot(make(sourceVersion: 'v2')));
    });

    test('null optional fields compare equal to each other', () {
      final a = make(
        externalId: null,
        permission: null,
        license: null,
        rawPayload: null,
        sourceVersion: null,
      );
      final b = make(
        externalId: null,
        permission: null,
        license: null,
        rawPayload: null,
        sourceVersion: null,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
