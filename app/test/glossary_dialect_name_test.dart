import 'package:compendium_app/src/glossary/custom_figures.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dialect's own name for one of the user's figures (#1023) is a name taken
/// for every other entry, but never a clash with the figure it names.
void main() {
  UserGlossaryEntry figure(String id, String name) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: name,
    definition: 'A figure.',
    description: 'Of your own.',
    payload: const {
      'template': '{move}',
      'defaultBeats': 8,
      'params': <Object?>[],
    },
    createdAt: DateTime.utc(2026, 10, 16),
  );

  test('the named figure is not flagged, another with that name is', () {
    // The dialect names zoom "zoom" too, and gives it "whizz" elsewhere.
    final dialect = Dialect.larksRobins.copyWith(
      name: 'Mine',
      moves: {userFigureKeyFor('zoom-id'): 'zoom'},
    );
    final other = Dialect.larksRobins.copyWith(
      name: 'Other',
      moves: {userFigureKeyFor('zoom-id'): 'whizz'},
    );
    final items = resolveCustomGlossary(
      [figure('zoom-id', 'zoom'), figure('whizz-id', 'whizz')],
      taxonomy: contraTaxonomy,
      dialects: [dialect, other],
    );
    expect(
      {
        for (final item in items)
          if (item.renameNeeded) item.entry.id,
      },
      {'whizz-id'},
    );
  });
}
