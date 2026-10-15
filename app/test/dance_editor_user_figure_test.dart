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

  test('a use\'s line is not canonicalized as a typed line is, which would '
      'detach it, but a detached one is', () {
    final entry = zoom();
    final params = userFigureDraftParams(
      entry,
      decodeUserFigureDefinition(entry.payload)!,
    );
    String shout(String text) => text.toUpperCase();

    final attached = FigureDraft(
      move: customMove,
      params: params,
    ).toFigure(canonicalizeNote: shout)!;
    expect(attached.params['text'], 'role1s zoom zoom-id around');
    expect(userFigureUseOf(attached)!.attached, isTrue);

    final detached = FigureDraft(
      move: customMove,
      params: {...params, userFigureCheckKey: '00000000'},
    ).toFigure(canonicalizeNote: shout)!;
    expect(detached.params['text'], 'ROLE1S ZOOM ZOOM-ID AROUND');
  });

  FigureDraft useDraft(UserGlossaryEntry entry, {int? beats}) => FigureDraft(
    move: customMove,
    params: userFigureDraftParams(
      entry,
      decodeUserFigureDefinition(entry.payload)!,
      beats: beats,
    ),
  );

  test(
    'a use inside a group takes the group\'s beats, which its line reads',
    () async {
      final repos = openTestRepositories();
      final entry = zoom(template: '{who} {move} for {beats}');
      await repos.userGlossary.upsert(entry);
      final controller = await loaded(repos);
      controller.figureDrafts.add(
        FigureDraft(
          meanwhileSides: [
            useDraft(entry, beats: 6),
            FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 6}),
          ],
        )..params['beats'] = 16,
      );

      final group = figuresOf(controller.buildDance()).single;
      final side = group.subFigures.first;
      expect(side.params['beats'], 16);
      final use = userFigureUseOf(side)!;
      expect(use.text, 'role1s zoom zoom-id for 16');
      expect(use.attached, isTrue);
    },
  );

  test('a use of a figure deleted while the dance was open is saved as plain '
      'text with its line; one this device never had stays a use', () async {
    final repos = openTestRepositories();
    await repos.userGlossary.upsert(zoom());
    final controller = await loaded(repos);
    final unknown = zoom(id: 'elsewhere');
    controller.figureDrafts
      ..add(useDraft(zoom()))
      ..add(useDraft(unknown));
    expect(controller.hasUserFigureUses, isTrue);

    await repos.userGlossary.delete('zoom-id');
    await controller.refreshCompounds();
    final figures = figuresOf(controller.buildDance());
    expect(userFigureUseOf(figures[0]), isNull);
    expect(hasUserFigureReferenceKeys(figures[0]), isFalse);
    expect(figures[0].params['text'], 'role1s zoom zoom-id around');
    expect(userFigureUseOf(figures[1])!.attached, isTrue);
  });

  test('a row whose arguments are not a use\'s is plain text in the editor '
      'too', () {
    final entry = zoom();
    final params = userFigureDraftParams(
      entry,
      decodeUserFigureDefinition(entry.payload)!,
    );
    expect(
      isUserFigureDraft(FigureDraft(move: customMove, params: params)),
      isTrue,
    );
    expect(
      isUserFigureDraft(
        FigureDraft(
          move: customMove,
          params: {
            ...params,
            userFigureArgsKey: {
              'who': ['role1s'],
            },
          },
        ),
      ),
      isFalse,
    );
  });
}
