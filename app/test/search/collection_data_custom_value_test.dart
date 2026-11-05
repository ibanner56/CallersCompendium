import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// A custom field's value in the dance list's column, as the list row shows it.
Future<String> _listedValue(Object value, CustomFieldType type) async {
  final repos = openTestRepositories();
  // ignore: unused_result
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'f1',
      key: 'tempo',
      label: 'Tempo',
      type: type,
      showInList: true,
    ),
  );
  await repos.dances.create(
    Dance(
      id: 'd1',
      title: 'Money Musk',
      figures: const [],
      status: DanceStatus.active,
      customFields: [CustomFieldValue(fieldId: 'f1', value: value)],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  final data = await CollectionData.load(repos);
  return data.entryFor(data.dancesById['d1']!).listCustomFields.single.value;
}

void main() {
  test('a whole-number custom value shows without a decimal', () async {
    expect(await _listedValue(3.0, CustomFieldType.number), '3');
  });

  test('a fractional custom value keeps its decimals', () async {
    expect(await _listedValue(2.5, CustomFieldType.number), '2.5');
  });

  test('a text value is shown as typed', () async {
    expect(await _listedValue('3.0', CustomFieldType.text), '3.0');
  });
}
