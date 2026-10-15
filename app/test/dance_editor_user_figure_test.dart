import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/editor/user_figure_draft.dart';
import 'package:compendium_app/src/screens/dance_editor/dance_editor_controller.dart';

import 'figures_support.dart';
import 'support/test_repositories.dart';

/// The dance editor's controller and the user's own new figures (#1023):
/// which it offers, and the line a saved use holds.
void main() {
  final created = DateTime.utc(2026, 10, 15, 9);

  UserGlossaryEntry zoom({
    String id = 'zoom-id',
    String template = '{who} {move} around',
    String? form,
  }) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'zoom $id',
    definition: 'A zoom.',
    description: 'Fast.',
    payload: {
      'form': ?form,
      'template': template,
      'defaultBeats': 8,
      'params': [
        {'key': 'who', 'kind': 'dancerSet', 'default': 'role1s'},
      ],
    },
    createdAt: created,
  );

  UserGlossaryEntry compound(String id, {String? form}) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.compound.name,
    name: 'combo $id',
    definition: 'd',
    description: 'd',
    payload: {
      ...CompoundDefinition(
        params: const [],
        figures: [
          Figure(move: 'swing', params: const {'who': 'partners', 'beats': 8}),
        ],
        bindings: const [],
      ).toJson(),
      'form': ?form,
    },
    createdAt: created,
  );

  Future<DanceEditorController> loaded(
    CompendiumRepositories repos, {
    Dance? dance,
    Dialect? dialect,
  }) async {
    final controller = DanceEditorController(
      repositories: repos,
      danceId: dance?.id,
      dialect: dialect ?? Dialect.larksRobins,
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    await controller.load(dance: dance, fieldDefs: const []);
    if (dance == null) {
      controller.titleController.text = 'A dance';
      controller.figureDrafts.clear();
    }
    return controller;
  }

  test('offers the figures and compounds for the dance\'s form, untagged '
      'ones as contra', () async {
    final repos = openTestRepositories();
    await repos.userGlossary.upsert(zoom(id: 'plain'));
    await repos.userGlossary.upsert(zoom(id: 'english', form: 'ecd'));
    await repos.userGlossary.upsert(compound('c-plain'));
    await repos.userGlossary.upsert(compound('c-english', form: 'ecd'));
    final controller = await loaded(repos);

    expect([for (final e in controller.userFigureEntries) e.id], ['plain']);
    expect([for (final e in controller.compoundEntries) e.id], ['c-plain']);
    controller.setForm(DanceForm.ecd);
    expect([for (final e in controller.userFigureEntries) e.id], ['english']);
    expect([for (final e in controller.compoundEntries) e.id], ['c-english']);
  });

  test('a saved use holds its figure\'s wording as stored when the dance is '
      'built, with the check beside it', () async {
    final repos = openTestRepositories();
    await repos.userGlossary.upsert(zoom());
    final controller = await loaded(repos);
    final entry = zoom();
    controller.figureDrafts.add(
      FigureDraft(
        move: customMove,
        params: userFigureDraftParams(
          entry,
          decodeUserFigureDefinition(entry.payload)!,
        ),
      ),
    );

    await repos.userGlossary.upsert(zoom(template: '{who} {move} twice'));
    await controller.refreshCompounds();
    final use = userFigureUseOf(figuresOf(controller.buildDance()).single)!;
    expect(use.text, 'role1s zoom zoom-id twice');
    expect(use.attached, isTrue);
  });

  test('opening a dance in another dialect leaves a use\'s line as stored, so '
      'it stays attached', () async {
    final repos = openTestRepositories();
    await repos.userGlossary.upsert(zoom());
    final dance = Dance(
      id: 'd1',
      title: 'Zoom Reel',
      createdAt: created,
      updatedAt: created,
      figures: [
        userFigureUseFigure(
          id: 'zoom-id',
          args: const {'who': 'role1s'},
          text: 'role1s zoom zoom-id around',
        ),
      ],
    );
    final controller = await loaded(
      repos,
      dance: dance,
      dialect: Dialect.leadsFollows,
    );

    final draft = controller.figureDrafts.single;
    expect(draft.params['text'], 'role1s zoom zoom-id around');
    expect(isUserFigureDraft(draft), isTrue);
    final use = userFigureUseOf(figuresOf(controller.buildDance()).single)!;
    expect(use.text, 'role1s zoom zoom-id around');
    expect(use.attached, isTrue);
  });
}
