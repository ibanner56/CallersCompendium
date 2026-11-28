import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// The shared test helper builds its repositories with the taxonomies the
/// app runs with (`AppData`): each dance is read under its own form's
/// taxonomy (pre-release audit finding A1-07). Under contra's alone, an
/// English dance's `ecd_` figures would be unknown moves.
void main() {
  test("openTestRepositories reads an English dance's figures as English "
      'moves', () async {
    final repos = openTestRepositories();
    final t = DateTime.utc(2026);
    await repos.dances.create(
      Dance(
        id: 'english',
        title: 'Hole in the Wall',
        form: DanceForm.ecd,
        figures: [
          testFigure(move: 'ecd_set', params: {'beats': 8}),
        ],
        createdAt: t,
        updatedAt: t,
      ),
    );
    final row = await repos.db
        .customSelect(
          "SELECT canonical_text FROM dance_figures WHERE dance_id = 'english'",
        )
        .getSingle();
    // The English taxonomy names the move; an unknown move keeps its id.
    expect(row.read<String>('canonical_text'), 'set');
  });
}
