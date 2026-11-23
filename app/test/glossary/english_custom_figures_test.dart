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

    test('a shared figure being imported is checked against its own form '
        'too', () {
      expect(
        importedFiguresWithTakenNames([
          UserFigureImportItem(
            incoming: figureNamed('english', 'Siding', DanceForm.ecd),
            kind: UserFigureImportKind.add,
          ),
        ], live: const []),
        {'english'},
      );
      expect(
        importedFiguresWithTakenNames([
          UserFigureImportItem(
            incoming: figureNamed('contra', 'Siding', DanceForm.contra),
            kind: UserFigureImportKind.add,
          ),
        ], live: const []),
        isEmpty,
      );
    });

    group(
      'a name only one form\'s dialect gives a word of its own (#2294)',
      () {
        // Contra words the roles "larks"; English gives `swing` the name
        // "zebra", which contra's dialect does not have.
        final contraDialect = Dialect.larksRobins;
        final english = Dialect.canonical.copyWith(moves: {'swing': 'zebra'});
        Iterable<Dialect> dialectsFor(Object? payload) => [
          glossaryEntryDanceForm(payload) == DanceForm.ecd
              ? english
              : contraDialect,
        ];
        Set<String> taken(UserGlossaryEntry figure, {bool perForm = true}) =>
            importedFiguresWithTakenNames(
              [
                UserFigureImportItem(
                  incoming: figure,
                  kind: UserFigureImportKind.add,
                ),
              ],
              live: const [],
              dialects: const [],
              dialectsFor: perForm ? dialectsFor : (_) => [contraDialect],
            );

        test('controls: only English\'s dialect has the name', () {
          final english1 = figureNamed('e', 'zebra', DanceForm.ecd);
          // The Glossary flags it with its form's dialect and not without.
          expect(
            resolveCustomGlossary([
              english1,
            ], dialectsFor: dialectsFor).single.renameNeeded,
            isTrue,
          );
          expect(
            resolveCustomGlossary(
              [english1],
              dialects: [contraDialect],
            ).single.renameNeeded,
            isFalse,
          );
        });

        test(
          'an English figure so named is taken, as the Glossary reads it',
          () {
            expect(taken(figureNamed('e', 'zebra', DanceForm.ecd)), {'e'});
          },
        );

        test('a contra figure so named is not', () {
          expect(taken(figureNamed('c', 'zebra', DanceForm.contra)), isEmpty);
        });

        test(
          'read with contra\'s dialect only, the English figure was not',
          () {
            expect(
              taken(figureNamed('e', 'zebra', DanceForm.ecd), perForm: false),
              isEmpty,
            );
          },
        );
      },
    );
  });
}
