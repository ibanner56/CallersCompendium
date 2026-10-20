import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/glossary/compound_editor_screen.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The editor for the user's own compound figures (#709).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final created = DateTime.utc(2026, 10, 14, 9);

  UserGlossaryEntry twoPullBys({
    List<CompoundParam> params = const [
      CompoundParam(key: 'hand', kind: ParamKind.handedness),
    ],
    List<CompoundSlotBinding> bindings = const [
      CompoundSlotBinding(figureIndex: 0, slotKey: 'hand', paramKey: 'hand'),
      CompoundSlotBinding(
        figureIndex: 1,
        slotKey: 'hand',
        paramKey: 'hand',
        source: CompoundBindingSource.opposite,
      ),
    ],
  }) {
    Figure pullBy() => Figure(
      move: 'pull_by',
      params: const {'who': 'neighbors', 'hand': 'right', 'beats': 2},
    );
    return UserGlossaryEntry(
      id: 'pb2',
      kindName: UserGlossaryEntryKind.compound.name,
      name: 'two pull bys',
      definition: 'Pull by, then pull by back.',
      description: 'Two pull-bys, alternating hands.',
      payload: CompoundDefinition(
        params: params,
        figures: [pullBy(), pullBy()],
        bindings: bindings,
      ).toJson(),
      createdAt: created,
    );
  }

  Future<CompendiumRepositories> pump(
    WidgetTester tester, {
    UserGlossaryEntry? initial,
    List<UserGlossaryEntry> stored = const [],
    bool glossary = false,
    bool custom = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    for (final e in stored) {
      await tester.runAsync(() => repos.userGlossary.upsert(e));
    }
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final showGlossary = ValueNotifier<bool>(glossary);
    final showCustom = ValueNotifier<bool>(custom);
    addTearDown(dialect.dispose);
    addTearDown(showGlossary.dispose);
    addTearDown(showCustom.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ShowGlossaryScope(
              notifier: showGlossary,
              child: ShowCustomFiguresScope(
                notifier: showCustom,
                child: child!,
              ),
            ),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<UserGlossaryEntry>(
                    builder: (_) => CompoundEditorScreen(initial: initial),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return repos;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('compound-editor-save')));
    await tester.pumpAndSettle();
  }

  group('a new figure (#1023)', () {
    UserGlossaryEntry zoom({
      String template = '{who} zoom [{style}]',
      Object? whoDefault = 'role1s',
    }) => UserGlossaryEntry(
      id: 'zoom-id',
      kindName: UserGlossaryEntryKind.customFigure.name,
      name: 'zoom',
      definition: 'A zoom.',
      description: 'Fast.',
      payload: {
        'form': 'contra',
        'template': template,
        'defaultBeats': 6,
        'params': [
          {'key': 'who', 'kind': 'dancerSet', 'default': ?whoDefault},
          {
            'key': 'style',
            'kind': 'choice',
            'choices': [
              {'id': 'abc12345', 'label': 'fast'},
            ],
          },
        ],
      },
      createdAt: created,
    );

    Future<void> fillRequired(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const ValueKey('compound-name')),
        'zoomies',
      );
      await tester.enterText(
        find.byKey(const ValueKey('compound-definition')),
        'A zoom.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('compound-description')),
        'Larks zoom.',
      );
    }

    Future<void> chooseNewFigure(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('glossary-entry-kind')),
          matching: find.text('New figure'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> addParam(WidgetTester tester, int index, String key) async {
      await tester.tap(find.byKey(const ValueKey('compound-add-param')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ValueKey('compound-param-$index-name')),
        key,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is saved with its kind, its choices under stable ids, and '
        'its wording canonical', (tester) async {
      final repos = await pump(tester);
      await fillRequired(tester);
      await chooseNewFigure(tester);
      await addParam(tester, 0, 'style');
      await tester.tap(find.byKey(const ValueKey('compound-param-0-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('option').last);
      await tester.pumpAndSettle();
      for (final (i, label) in ['fast', 'slow'].indexed) {
        await tester.tap(
          find.byKey(const ValueKey('user-figure-param-0-add-choice')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(ValueKey('user-figure-param-0-choice-$i')),
          label,
        );
      }
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        'Larks {move} {style}',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Reads as: larks zoomies'),
        findsOneWidget,
        reason: 'no default style: its slot reads as nothing',
      );
      await save(tester);

      final saved = (await tester.runAsync(repos.userGlossary.listAll))!.single;
      expect(saved.kind, UserGlossaryEntryKind.customFigure);
      expect(saved.description, 'role1s zoom.');
      final figure = decodeUserFigureDefinition(saved.payload)!;
      expect(figure.template, 'role1s {move} {style}');
      expect(figure.defaultBeats, 8);
      final choices = figure.param('style')!.choices;
      expect([for (final c in choices) c.label], ['fast', 'slow']);
      expect([
        for (final c in choices) c.id,
      ], everyElement(matches(RegExp(r'^[a-z0-9]{8}$'))));
    });

    testWidgets('refuses wording that uses a slot it does not have', (
      tester,
    ) async {
      final repos = await pump(tester);
      await fillRequired(tester);
      await chooseNewFigure(tester);
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        '{move} {hand}',
      );
      await save(tester);
      expect(
        find.text(
          "The wording uses {hand}, which isn't one of this figure's "
          'parameters.',
        ),
        findsOneWidget,
      );
      expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);
    });

    testWidgets('a parameter the wording leaves out asks first', (
      tester,
    ) async {
      final repos = await pump(tester);
      await fillRequired(tester);
      await chooseNewFigure(tester);
      await addParam(tester, 0, 'who');
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        '{move}',
      );
      await save(tester);
      expect(
        find.text('Not in the wording, so choosing them changes nothing: who.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('compound-unused-save')));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(repos.userGlossary.listAll), hasLength(1));
    });

    Future<void> choose(WidgetTester tester, Key field, String item) async {
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    testWidgets('changing a parameter\'s kind drops its default: a choice\'s '
        'id is never kept as text', (tester) async {
      final repos = await pump(tester);
      await fillRequired(tester);
      await chooseNewFigure(tester);
      await addParam(tester, 0, 'style');
      await choose(tester, const ValueKey('compound-param-0-kind'), 'option');
      await tester.tap(
        find.byKey(const ValueKey('user-figure-param-0-add-choice')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-param-0-choice-0')),
        'fast',
      );
      await tester.pumpAndSettle();
      await choose(
        tester,
        const ValueKey('user-figure-param-0-default-style'),
        'fast',
      );
      await choose(tester, const ValueKey('compound-param-0-kind'), 'text');
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        '{move} {style}',
      );
      await save(tester);
      final figure = decodeUserFigureDefinition(
        (await tester.runAsync(repos.userGlossary.listAll))!.single.payload,
      )!;
      expect(figure.param('style')!.kind, ParamKind.text);
      expect(figure.param('style')!.defaultValue, isNull);
    });

    testWidgets('a default is chosen from its values, and a line break in the '
        'wording reads as a space', (tester) async {
      final repos = await pump(tester);
      await fillRequired(tester);
      await chooseNewFigure(tester);
      await addParam(tester, 0, 'n');
      await choose(tester, const ValueKey('compound-param-0-kind'), 'places');
      await choose(
        tester,
        const ValueKey('user-figure-param-0-default-n'),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        '{move}\n{n}',
      );
      await save(tester);
      final figure = decodeUserFigureDefinition(
        (await tester.runAsync(repos.userGlossary.listAll))!.single.payload,
      )!;
      expect(figure.param('n')!.defaultValue, 3);
      expect(figure.template, '{move} {n}');
    });

    testWidgets('a combination keeps the dance form chosen for it', (
      tester,
    ) async {
      final repos = await pump(tester, initial: twoPullBys());
      await choose(tester, const ValueKey('glossary-entry-form'), 'Square');
      await save(tester);
      final saved = (await tester.runAsync(
        () => repos.userGlossary.getById('pb2'),
      ))!;
      expect((saved.payload! as Map)['form'], 'square');
    });

    testWidgets('an edit keeps its kind and a renamed choice\'s id', (
      tester,
    ) async {
      final repos = await pump(tester, initial: zoom());
      expect(
        find.byKey(const ValueKey('glossary-entry-kind')),
        findsNothing,
        reason: 'a stored entry keeps its kind',
      );
      expect(find.text('Reads as: larks zoom'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-param-1-choice-0')),
        'quick',
      );
      await save(tester);
      final saved = (await tester.runAsync(
        () => repos.userGlossary.getById('zoom-id'),
      ))!;
      expect(saved.kind, UserGlossaryEntryKind.customFigure);
      final choice = decodeUserFigureDefinition(
        saved.payload,
      )!.param('style')!.choices.single;
      expect((choice.id, choice.label), ('abc12345', 'quick'));
    });

    testWidgets('a stored condition shows in words and saves back by '
        'meaning', (tester) async {
      const template =
          "[{?if style is 'abc12345' and who is 'role1s'}role1s zoom fast"
          '{?else}{who} zoom]';
      final repos = await pump(tester, initial: zoom(template: template));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('user-figure-wording')),
            )
            .controller!
            .text,
        '[if style is fast and who is larks then larks zoom fast else '
        '{who} zoom]',
      );
      expect(
        find.byKey(const ValueKey('user-figure-wording-error')),
        findsNothing,
      );
      // No default style: the else wording.
      expect(find.text('Reads as: larks zoom'), findsOneWidget);
      await save(tester);
      final saved = (await tester.runAsync(
        () => repos.userGlossary.getById('zoom-id'),
      ))!;
      expect(decodeUserFigureDefinition(saved.payload)!.template, template);
    });

    testWidgets('a mistake in a condition is explained under the wording, '
        'and stops the save with the same words', (tester) async {
      final repos = await pump(tester, initial: zoom());
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        '[if style is fats then {who} zoom fast else {who} zoom]',
      );
      await tester.pumpAndSettle();
      const expected =
          '“fats” isn’t one of the values style can have. Did you mean '
          '“fast”? style can be: fast.';
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('user-figure-wording-error')),
            )
            .data,
        expected,
      );
      expect(
        find.text('Finish the wording to see how it reads.'),
        findsOneWidget,
      );
      await save(tester);
      expect(find.byType(CompoundEditorScreen), findsOneWidget);
      expect(find.textContaining(expected), findsNWidgets(2));
      expect(
        await tester.runAsync(repos.userGlossary.listAll),
        isEmpty,
        reason: 'not saved',
      );
    });

    testWidgets('a figure stored with a parameter named a reserved word opens '
        'to be repaired, and saves once renamed', (tester) async {
      final broken = UserGlossaryEntry(
        id: 'broken-id',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'zoom',
        definition: 'A zoom.',
        description: 'Fast.',
        payload: const {
          'form': 'contra',
          'template': '{move}[ {is}]',
          'defaultBeats': 6,
          'params': [
            {'key': 'is', 'kind': 'flag', 'label': 'fast'},
          ],
        },
        createdAt: created,
      );
      expect(decodeUserFigureDefinition(broken.payload), isNull);
      final repos = await pump(tester, initial: broken);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('compound-param-0-name')),
            )
            .controller!
            .text,
        'is',
      );
      await tester.enterText(
        find.byKey(const ValueKey('compound-param-0-name')),
        'quick',
      );
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        '{move}[if quick then  fast]',
      );
      await tester.pumpAndSettle();
      await save(tester);
      final saved = (await tester.runAsync(
        () => repos.userGlossary.getById('broken-id'),
      ))!;
      final repaired = decodeUserFigureDefinition(saved.payload)!;
      expect(repaired.params.single.key, 'quick');
      expect(repaired.template, '{move}[{?if quick} fast]');
    });

    testWidgets('a parameter may not be named a word conditions use', (
      tester,
    ) async {
      final repos = await pump(tester);
      await fillRequired(tester);
      await chooseNewFigure(tester);
      await addParam(tester, 0, 'if');
      await tester.enterText(
        find.byKey(const ValueKey('user-figure-wording')),
        '{move} {if}',
      );
      await save(tester);
      expect(
        find.textContaining('if, then, else, not, and, or, is'),
        findsOneWidget,
      );
      expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);
    });
  });

  testWidgets('a name and a definition are required', (tester) async {
    final repos = await pump(tester);
    await save(tester);
    expect(
      find.text('Give the figure a name and a definition.'),
      findsOneWidget,
    );
    expect(find.text('Required'), findsNWidgets(2));
    expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);
  });

  testWidgets('More Details is optional: a figure saves without it', (
    tester,
  ) async {
    final repos = await pump(tester, initial: twoPullBys());
    expect(find.text('More Details'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('compound-name')),
      'zoomies',
    );
    await tester.enterText(
      find.byKey(const ValueKey('compound-definition')),
      'A zoom.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('compound-description')),
      '',
    );
    await save(tester);
    final saved = (await tester.runAsync(repos.userGlossary.listAll))!.single;
    expect(saved.name, 'zoomies');
    expect(saved.description, isEmpty);
  });

  testWidgets('a name taken by a term the hidden Glossary lists points to '
      'Show Glossary, not to a figure', (tester) async {
    final repos = await pump(
      tester,
      custom: true,
      initial: twoPullBys(),
      stored: [
        UserGlossaryEntry(
          id: 'term-1',
          kindName: UserGlossaryEntryKind.term.name,
          name: 'zesty corners',
          definition: 'A word.',
          description: '',
          createdAt: created,
        ),
      ],
    );
    await tester.enterText(
      find.byKey(const ValueKey('compound-name')),
      'zesty corners',
    );
    await save(tester);
    expect(find.textContaining('one of your own terms'), findsOneWidget);
    expect(await tester.runAsync(repos.userGlossary.listAll), hasLength(1));
  });

  testWidgets('a name a built-in figure has is refused', (tester) async {
    final repos = await pump(tester, initial: twoPullBys());
    await tester.enterText(
      find.byKey(const ValueKey('compound-name')),
      'Pull By',
    );
    await save(tester);
    expect(
      find.text(
        '“Pull By” is already the name of a figure or shorthand. Choose '
        'another name.',
      ),
      findsOneWidget,
    );
    expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);
  });

  testWidgets('a full Glossary says so, not that a field is too long', (
    tester,
  ) async {
    final repos = await pump(tester, initial: twoPullBys());
    // Rows written before there was a budget: past it by a few KB, in one
    // row, put there directly because the repository would now refuse it.
    await tester.runAsync(
      () => repos.db.customStatement(
        'INSERT INTO user_glossary_entries '
        '(id, kind, name, definition, description, created_at) '
        "VALUES ('old', 'compound', 'old', 'd', "
        "replace(hex(zeroblob(${maxUserGlossaryBytes + 1024})), '00', 'x'), 0)",
      ),
    );
    await save(tester);
    expect(find.textContaining('has reached its size limit'), findsOneWidget);
    expect(find.text('One of the fields is too long.'), findsNothing);
    expect(
      (await tester.runAsync(repos.userGlossary.listAll))!.map((e) => e.id),
      ['old'],
    );
  });

  testWidgets('a name is compared as it is stored, so two spellings of one '
      'role cannot both be saved', (tester) async {
    final existing = UserGlossaryEntry(
      id: 'other',
      kindName: UserGlossaryEntryKind.compound.name,
      name: 'role1s swing twice',
      definition: 'd',
      description: 'd',
      payload: twoPullBys().payload,
      createdAt: created,
    );
    final repos = await pump(tester, initial: twoPullBys(), stored: [existing]);
    await tester.enterText(
      find.byKey(const ValueKey('compound-name')),
      'Gents swing twice',
    );
    await save(tester);
    expect(find.textContaining('is already the name'), findsOneWidget);
    expect(
      [
        for (final e in (await tester.runAsync(repos.userGlossary.listAll))!)
          e.id,
      ],
      ['other'],
    );
  });

  testWidgets('editing a stored figure keeps its own name', (tester) async {
    final repos = await pump(
      tester,
      initial: twoPullBys(),
      stored: [twoPullBys()],
    );
    await tester.enterText(
      find.byKey(const ValueKey('compound-definition')),
      'Pull by twice.',
    );
    await save(tester);
    expect(find.byType(CompoundEditorScreen), findsNothing, reason: 'saved');
    final saved = (await tester.runAsync(
      () => repos.userGlossary.getById('pb2'),
    ))!;
    expect(saved.name, 'two pull bys');
    expect(saved.definition, 'Pull by twice.');
  });

  // The entry keeps its id, so two saves would still leave one row; what a
  // second save would also do is pop a second route, which is the check here.
  testWidgets('saving twice in quick succession saves and closes once', (
    tester,
  ) async {
    final repos = await pump(tester, initial: twoPullBys());
    await tester.enterText(
      find.byKey(const ValueKey('compound-name')),
      'my thing',
    );
    final button = find.byKey(const ValueKey('compound-editor-save'));
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(repos.userGlossary.listAll), hasLength(1));
    // A second save would also pop a second route: the page that opened the
    // editor.
    expect(find.byKey(const ValueKey('open')), findsOneWidget);
  });

  testWidgets('a figure\'s note is stored canonical and shown in the dialect', (
    tester,
  ) async {
    final initial = twoPullBys();
    final payload = Map<String, Object?>.of(
      initial.payload! as Map<String, Object?>,
    );
    final figures = [
      for (final f in payload['figures']! as List)
        Map<String, Object?>.of(f as Map<String, Object?>),
    ];
    figures[0]['note'] = 'role1s step in';
    payload['figures'] = figures;
    final repos = await pump(
      tester,
      initial: UserGlossaryEntry(
        id: initial.id,
        kindName: initial.kindName,
        name: initial.name,
        definition: initial.definition,
        description: initial.description,
        payload: payload,
        createdAt: initial.createdAt,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('figure-0-note')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'larks step in',
      reason: 'rendered into the dialect for editing',
    );
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-note')),
      'Larks step out',
    );
    await save(tester);
    final saved = (await tester.runAsync(
      () => repos.userGlossary.getById('pb2'),
    ))!;
    final definition = decodeCompoundDefinition(saved.payload, contraTaxonomy)!;
    expect(definition.figures.first.note, 'role1s step out');
  });

  testWidgets('custom figures are not offered as parts', (tester) async {
    await pump(tester, initial: twoPullBys());
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'custom',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('figure-0-move-option-custom')),
      findsNothing,
    );
    expect(
      tester
          .widget<FigureListEditor>(find.byType(FigureListEditor))
          .allowCustom,
      isFalse,
    );
  });

  testWidgets('a parameter of another kind is shown, disabled, with the '
      'reason', (tester) async {
    await pump(tester, initial: twoPullBys());
    await tester.tap(find.byKey(const ValueKey('compound-binding-0-who')));
    await tester.pumpAndSettle();
    final item = find.text(
      'hand (unavailable: its kind is hand; this setting\'s is dancers)',
    );
    expect(item, findsWidgets);
    final menuItem = tester.widget<DropdownMenuItem<dynamic>>(
      find
          .ancestor(
            of: item.last,
            matching: find.byWidgetPredicate((w) => w is DropdownMenuItem),
          )
          .first,
    );
    expect(menuItem.enabled, isFalse);
  });

  testWidgets('an existing figure saves back unchanged in meaning, with its '
      'text stored canonically', (tester) async {
    final repos = await pump(tester, initial: twoPullBys());
    await tester.enterText(
      find.byKey(const ValueKey('compound-description')),
      'Two pull-bys; Larks start.',
    );
    await save(tester);

    final saved = (await tester.runAsync(
      () => repos.userGlossary.getById('pb2'),
    ))!;
    expect(saved.description, 'Two pull-bys; role1s start.');
    expect(saved.createdAt, created);
    final definition = decodeCompoundDefinition(saved.payload, contraTaxonomy)!;
    expect(definition.bindings, twoPullBysBindings);
    final expanded = expandCompound(definition, {
      'hand': 'left',
    }, contraTaxonomy)!;
    expect(expanded.map((f) => f.params['hand']), ['left', 'right']);
    expect(find.byType(CompoundEditorScreen), findsNothing, reason: 'closed');
  });

  testWidgets('an edit keeps the compound\'s form and the payload keys this '
      'build does not know (#1023)', (tester) async {
    final stored = twoPullBys();
    final initial = UserGlossaryEntry(
      id: stored.id,
      kindName: stored.kindName,
      name: stored.name,
      definition: stored.definition,
      description: stored.description,
      payload: {
        ...stored.payload! as Map<String, Object?>,
        'form': 'ecd',
        'later': {'kept': true},
      },
      createdAt: stored.createdAt,
    );
    final repos = await pump(tester, initial: initial);
    await tester.enterText(
      find.byKey(const ValueKey('compound-description')),
      'Edited.',
    );
    await save(tester);

    final saved = (await tester.runAsync(
      () => repos.userGlossary.getById('pb2'),
    ))!;
    final payload = saved.payload! as Map<String, Object?>;
    expect(payload['form'], 'ecd');
    expect(payload['later'], {'kept': true});
  });

  testWidgets('an unused parameter warns, and the user can go back or save '
      'anyway', (tester) async {
    final repos = await pump(
      tester,
      initial: twoPullBys(
        params: const [
          CompoundParam(key: 'hand', kind: ParamKind.handedness),
          CompoundParam(key: 'who', kind: ParamKind.dancerSet),
        ],
      ),
    );
    await save(tester);
    expect(find.text('Some parameters aren\'t used'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compound-unused-back')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsOneWidget);
    expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);

    await save(tester);
    await tester.tap(find.byKey(const ValueKey('compound-unused-save')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsNothing);
    expect(await tester.runAsync(repos.userGlossary.listAll), hasLength(1));
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await pump(tester, initial: twoPullBys());
    await tester.enterText(
      find.byKey(const ValueKey('compound-notes')),
      'something',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text('You have unsaved changes to this figure.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('compound-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsNothing);
  });

  group('the toolbar at a phone\'s width and a large text size', () {
    final term = UserGlossaryEntry(
      id: 'term-id',
      kindName: UserGlossaryEntryKind.term.name,
      name: 'gypsy',
      definition: 'Walk around.',
      description: 'Eyes on your partner.',
      payload: glossaryTermPayload('contra'),
      createdAt: created,
    );

    Future<void> open(
      WidgetTester tester,
      CompoundEditorScreen screen, {
      required Locale locale,
      required double scale,
    }) async {
      await tester.binding.setSurfaceSize(const Size(320, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
      addTearDown(dialect.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepositoriesScope(
              repositories: repos,
              child: ActiveDialectScope(notifier: dialect, child: child!),
            ),
          ),
          home: screen,
        ),
      );
      await tester.pumpAndSettle();
    }

    // Every title the editor has: a new entry, a new term, an edit, and a
    // term being made a figure.
    final screens = {
      'new': () => const CompoundEditorScreen(),
      'new term': () => const CompoundEditorScreen(termsOnly: true),
      'edit': () => CompoundEditorScreen(initial: twoPullBys()),
      'make a figure': () =>
          CompoundEditorScreen(initial: term, convertToFigure: true),
    };
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      testWidgets('$name: in French at 2x, Save is an icon and nothing '
          'overflows', (tester) async {
        await open(tester, screen(), locale: const Locale('fr'), scale: 2);
        expect(tester.takeException(), isNull);
        final save = find.byKey(const ValueKey('compound-editor-save'));
        expect(
          find.descendant(of: save, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        expect(find.byTooltip('Enregistrer'), findsOneWidget);
      });
    }

    testWidgets('where it fits, Save is still a word', (tester) async {
      await open(
        tester,
        const CompoundEditorScreen(),
        locale: const Locale('en'),
        scale: 1,
      );
      final save = find.byKey(const ValueKey('compound-editor-save'));
      expect(
        find.descendant(of: save, matching: find.text('Save')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: save, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
    });
  });
}

const twoPullBysBindings = [
  CompoundSlotBinding(figureIndex: 0, slotKey: 'hand', paramKey: 'hand'),
  CompoundSlotBinding(
    figureIndex: 1,
    slotKey: 'hand',
    paramKey: 'hand',
    source: CompoundBindingSource.opposite,
  ),
];
