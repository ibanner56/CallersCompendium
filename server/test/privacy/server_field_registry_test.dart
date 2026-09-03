import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:test/test.dart';

void main() {
  test('every persisted server field has all three classifications', () {
    final expected = {...serverSqliteFields, ...serverConfigurationFields};
    expect(serverFieldClassifications.keys.toSet(), equals(expected));
    for (final field in expected) {
      final classification = serverFieldClassifications[field]!;
      expect(classification.category, isNotNull, reason: field);
      expect(classification.subject, isNotNull, reason: field);
      expect(classification.egress, isNotNull, reason: field);
    }
  });
}
