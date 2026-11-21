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
    final item = resolveCustomGlossary([entry]).single;
    expect(item.definition, isNotNull);
    expect(item.definition!.figures.map((f) => f.move), [
      'ecd_set_and_link',
      'ecd_set_and_link',
    ]);
  });

  group('a name is checked against its own form\'s figures', () {
    UserGlossaryEntry figureNamed(String id, String name, DanceForm form) =>
        UserGlossaryEntry(
          id: id,
          kindName: UserGlossaryEntryKind.customFigure.name,
          name: name,
          definition: 'Mine.',
          description: '',
          payload: UserFigureDefinition(
            form: form.name,
            template: name,
            defaultBeats: 8,
            params: const [],
          ).toJson(),
          createdAt: DateTime.utc(2026, 11, 21),
        );

    test('an English figure named like a shipped English figure needs a '
        'new name', () {
      final item = resolveCustomGlossary([
        figureNamed('mine', 'Siding', DanceForm.ecd),
      ]).single;
      expect(item.renameNeeded, isTrue);
    });

    test('a contra figure of that name does not: contra has no siding', () {
      final item = resolveCustomGlossary([
        figureNamed('mine', 'Siding', DanceForm.contra),
      ]).single;
      expect(item.renameNeeded, isFalse);
    });

    test('a contra figure named like a shipped contra figure still does', () {
      final item = resolveCustomGlossary([
        figureNamed('mine', 'Swing', DanceForm.contra),
      ]).single;
      expect(item.renameNeeded, isTrue);
    });
  });
}
