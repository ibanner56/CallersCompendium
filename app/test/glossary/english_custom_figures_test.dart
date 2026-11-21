import 'package:compendium_app/src/glossary/custom_figures.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A combination made for English dances is built from English figures, so
/// the Glossary must read them (ADR-006 leftovers).
void main() {
  final entry = UserGlossaryEntry(
    id: 'sl2',
    kindName: UserGlossaryEntryKind.compound.name,
    name: 'set and link twice',
    definition: 'Set and link, then again.',
    description: '',
    payload: CompoundDefinition(
      params: const [],
      figures: [
        Figure(move: 'ecd_set_and_link', params: const {'beats': 4}),
        Figure(move: 'ecd_set_and_link', params: const {'beats': 4}),
      ],
      bindings: const [],
      form: DanceForm.ecd.name,
    ).toJson(),
    createdAt: DateTime.utc(2026, 11, 20),
  );

  test('the Glossary decodes an English combination', () {
    final item = resolveCustomGlossary([
      entry,
    ], taxonomy: contraTaxonomy).single;
    expect(item.definition, isNotNull);
    expect(item.definition!.figures.map((f) => f.move), [
      'ecd_set_and_link',
      'ecd_set_and_link',
    ]);
  });
}
