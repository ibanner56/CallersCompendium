import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String structure) => Dance(
  id: id,
  title: id,
  figures: const [],
  status: DanceStatus.active,
  phraseStructure: structure,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  test('only standard structures offer A1 A2 B1 B2', () {
    expect(sectionLabelsFor([_dance('d1', '')]), ['A1', 'A2', 'B1', 'B2']);
    // A long structure that isn't named adds no rows.
    expect(
      sectionLabelsFor([_dance('d1', '8*8*2'), _dance('d2', '1000*1*2')]),
      ['A1', 'A2', 'B1', 'B2'],
    );
    expect(sectionLabelsFor(const []), ['A1', 'A2', 'B1', 'B2']);
  });

  test('named phrases add their own labels, in order', () {
    expect(
      sectionLabelsFor([
        _dance('d1', ''),
        _dance('d2', 'A:2*4*2 + B:1*8*2'),
        _dance('d3', 'A:1*4*2 + B:1*4*2 + C:2*8*2'),
      ]),
      ['A', 'A1', 'A2', 'B', 'B1', 'B2', 'C1', 'C2'],
    );
  });
}
