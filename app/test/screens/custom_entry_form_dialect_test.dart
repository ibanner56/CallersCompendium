import 'dart:async';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/glossary/custom_figures.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/screens/glossary/compound_editor_screen.dart';
import 'package:compendium_app/src/screens/glossary/custom_figure_detail.dart';
import 'package:compendium_app/src/screens/glossary/custom_figures_screen.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';
import 'package:compendium_app/src/screens/shorthand_mappings_screen.dart';
import 'package:compendium_app/src/screens/sync_conflict_details.dart';
import 'package:compendium_app/src/widgets/shorthand_shadow_warning.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dropdown.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A figure, combination or term of the user's own reads in the dialect of the
/// form it was made for (#2294), so each test gives contra and English
/// different dialects: with the same one in both, reading either wrong could
/// not be told from reading it right.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Contra words the first role "larks", English leaves it as the canonical
  // dialect writes it, so the two read differently.
  final contraDialect = Dialect.larksRobins;
  final englishDialect = Dialect.canonical;
  final renderer = FigureRenderer(contraTaxonomy);
  String inContra(String text) => renderer.renderFreeText(text, contraDialect);
  String inEnglish(String text) =>
      renderer.renderFreeText(text, englishDialect);

  /// A control, so each reading below can tell the two dialects apart.
  void expectDialectsDiffer(String text) =>
      expect(inEnglish(text), isNot(inContra(text)));

  DialectsByForm byForm() => DialectsByForm({
    DanceForm.contra: contraDialect,
    DanceForm.ecd: englishDialect,
  });

  UserGlossaryEntry figure({
    required String id,
    required String name,
    required String form,
    String definition = 'role1s zoom around.',
  }) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: name,
    definition: definition,
    description: '',
    payload: {
      'form': form,
      'template': '{move}',
      'defaultBeats': 8,
      'params': <Object?>[],
    },
    createdAt: DateTime.utc(2026, 11, 20),
  );

  Future<CompendiumRepositories> pumpScreen(
    WidgetTester tester,
    Widget home, {
    List<UserGlossaryEntry> entries = const [],
    DialectsByForm? dialectsByForm,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    for (final e in entries) {
      await tester.runAsync(() => repos.userGlossary.upsert(e));
    }
    final dialects = ValueNotifier(dialectsByForm ?? byForm());
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(true);
    for (final n in <ChangeNotifier>[dialects, glossary, custom]) {
      addTearDown(n.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope.byForm(
            dialects: dialects,
            child: ShowGlossaryScope(
              notifier: glossary,
              child: ShowCustomFiguresScope(notifier: custom, child: child!),
            ),
          ),
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
    return repos;
  }

  group('a figure\'s title', () {
    testWidgets('reads in the dialect of the form the figure is for', (
      tester,
    ) async {
      expectDialectsDiffer('role1s zoom');
      await pumpScreen(
        tester,
        const Scaffold(
          body: Column(
            children: [
              CustomFigureTitle(entryId: 'e', fallback: 'fallback e'),
              CustomFigureTitle(entryId: 'c', fallback: 'fallback c'),
            ],
          ),
        ),
        entries: [
          figure(id: 'e', name: 'role1s zoom', form: 'ecd'),
          figure(id: 'c', name: 'role1s zoom', form: 'contra'),
        ],
      );
      // The title follows the stored entry; a frame lets the stream deliver.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      final titles = [
        for (final t in tester.widgetList<Text>(
          find.byKey(const ValueKey('glossary-custom-title')),
        ))
          t.data,
      ];
      expect(titles, [inEnglish('role1s zoom'), inContra('role1s zoom')]);
    });
  });

  group('the Glossary\'s copy action', () {
    testWidgets('names a copy of a built-in English figure in English\'s '
        'dialect', (tester) async {
      // English words the set "zebra"; contra has no such word for it.
      final english = englishDialect.copyWith(moves: {'ecd_set': 'zebra'});
      await pumpScreen(
        tester,
        const GlossaryScreen(),
        dialectsByForm: DialectsByForm({
          DanceForm.contra: contraDialect,
          DanceForm.ecd: english,
        }),
      );
      await tester.tap(find.byKey(const ValueKey('glossary-form-ecd')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('glossary-search')),
        'zebra',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('glossary-entry-ecd_set')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('glossary-copy-figure')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('compound-name')))
            .controller!
            .text,
        'zebra (copy)',
      );
    });
  });

  group('a figure\'s name', () {
    // English's active dialect words a move "zebra"; contra's does not. Both
    // are presets, so neither is among the user's own dialects, which a name
    // is already checked against whatever the form.
    final english = englishDialect.copyWith(moves: {'swing': 'zebra'});

    List<CustomGlossaryItem> resolve(List<UserGlossaryEntry> entries) =>
        resolveCustomGlossary(
          entries,
          dialectsFor: (payload) => [
            glossaryEntryDanceForm(payload) == DanceForm.ecd
                ? english
                : contraDialect,
          ],
        );

    // Each alone: a second figure of the same name would be flagged as a
    // duplicate whatever the dialect, so the dialect must be the only cause.
    bool flagged(String form) => resolve([
      figure(id: 'x', name: 'zebra', form: form),
    ]).single.renameNeeded;

    test('is checked against the active dialect of the form it is for', () {
      expect(flagged('ecd'), isTrue, reason: 'English\'s dialect has "zebra"');
      expect(flagged('contra'), isFalse, reason: 'contra\'s dialect does not');
    });
  });

  group('the figure editor', () {
    testWidgets('shows its fields again in the new form\'s dialect when the '
        'form changes, and stores them as canonical words (#2294)', (
      tester,
    ) async {
      expectDialectsDiffer('role1s zoom');
      final entry = figure(
        id: 'z',
        name: 'role1s zoom',
        form: 'contra',
        definition: 'role1s zoom around.',
      );
      final repos = await pumpScreen(
        tester,
        CompoundEditorScreen(initial: entry),
      );
      String field(String key) =>
          tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
      // Opened as a contra figure: shown in contra's words.
      expect(field('compound-name'), inContra('role1s zoom'));

      await pickDropdownEntry(
        tester,
        find.byKey(const ValueKey('glossary-entry-form')),
        'English (ECD)',
      );
      // Picking scrolled the form field into view; back to the top fields.
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      // Changed to English: shown in English's words, from what it meant.
      expect(field('compound-name'), inEnglish('role1s zoom'));
      expect(field('compound-definition'), inEnglish('role1s zoom around.'));

      await tester.tap(find.byKey(const ValueKey('compound-editor-save')));
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(
        () => repos.userGlossary.getById('z'),
      ))!;
      // Stored canonically, whichever dialect each field was shown in.
      expect(saved.name, 'role1s zoom');
      expect(saved.definition, 'role1s zoom around.');
      expect(glossaryEntryForm(saved.payload), 'ecd');
    });
  });

  group('a sync conflict on an entry of your own', () {
    String payloadOf(String form) => canonicalJson(
      UserFigureDefinition(
        form: form,
        template: '{move}',
        defaultBeats: 8,
        params: const [],
      ).toJson(),
    );

    Map<String, Object?> body({
      required String form,
      required String definition,
      required List<String> keywords,
    }) => {
      'id': 'g1',
      'kind': 'customFigure',
      'name': 'role1s spiral',
      'definition': definition,
      'description': 'Round.',
      'keywords': keywords,
      'notes': null,
      'payload': payloadOf(form),
      'createdAt': '2026-09-01T00:00:00.000Z',
    };

    test('is for the form its payload names, else contra', () {
      expect(
        syncConflictEntryForm(body(form: 'ecd', definition: '', keywords: [])),
        DanceForm.ecd,
      );
      expect(
        syncConflictEntryForm(
          body(form: 'future', definition: '', keywords: []),
        ),
        DanceForm.contra,
      );
      expect(
        syncConflictEntryForm({
          ...body(form: 'ecd', definition: '', keywords: []),
          'payload': '{not json',
        }),
        DanceForm.contra,
      );
      expect(syncConflictEntryForm(null), DanceForm.contra);
    });

    testWidgets('names the entry in the dialect of its form', (tester) async {
      expectDialectsDiffer('role1s spiral');
      final dialects = ValueNotifier(byForm());
      addTearDown(dialects.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: ActiveDialectScope.byForm(
            dialects: dialects,
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(
        syncConflictFreeText(context, DanceForm.ecd, 'role1s spiral'),
        inEnglish('role1s spiral'),
      );
      expect(
        syncConflictFreeText(context, DanceForm.contra, 'role1s spiral'),
        inContra('role1s spiral'),
      );
    });

    testWidgets('shows its text and keywords in the dialect of its form', (
      tester,
    ) async {
      expectDialectsDiffer('role1s lead.');
      expectDialectsDiffer('role1s');
      final theirs = SyncRecordBlob(
        kind: SyncRecordKind.glossaryEntry,
        id: 'g1',
        updatedAt: DateTime.utc(2026, 9, 30),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 9, 30),
        body: body(
          form: 'ecd',
          definition: 'role2s lead.',
          keywords: ['role2s'],
        ),
      );
      final dialects = ValueNotifier(byForm());
      addTearDown(dialects.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: ActiveDialectScope.byForm(
            dialects: dialects,
            child: Scaffold(
              body: SingleChildScrollView(
                child: SyncConflictComparison(
                  group: SyncConflictGroup(
                    kind: SyncRecordKind.glossaryEntry,
                    recordId: 'g1',
                    localBody: body(
                      form: 'ecd',
                      definition: 'role1s lead.',
                      keywords: ['role1s'],
                    ),
                    candidates: syncConflictGroupFor(
                      SyncConflictReconsideration(
                        kind: SyncRecordKind.glossaryEntry,
                        recordId: 'g1',
                        before: null,
                        offered: [theirs],
                        writtenWireHash: 'written',
                        writtenAt: DateTime.utc(2026, 9, 30),
                      ),
                    ).candidates,
                  ),
                  lookups: const SyncConflictLookups(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(inEnglish('role1s lead.')), findsOneWidget);
      expect(find.textContaining(inContra('role1s lead.')), findsNothing);
      // Each version's keywords are listed under the device they came from.
      expect(find.text('This device: ${inEnglish('role1s')}'), findsOneWidget);
      expect(find.text('This device: ${inContra('role1s')}'), findsNothing);
    });
  });

  group('the shorthand shadow warning', () {
    // A shorthand is matched in a dance of any form, so a token warns when it
    // reads as a figure under any form's own figures and dialect. Each token
    // here reads as one under only one form's pair: an English figure's name,
    // and a name only a square dialect gives one of contra's figures (square
    // has no figures of its own, so it reads with contra's).
    final english = englishDialect;
    final square = contraDialect.copyWith(moves: {'swing': 'whirlygig'});

    bool reads(String token, DanceForm taxonomy, Dialect dialect) =>
        shorthandTokenShadowsFigure(
          token,
          taxonomy: shippedTaxonomies.forForm(taxonomy),
          dialect: dialect,
        );

    // An English figure's name that no contra reading takes as a figure.
    final englishName = () {
      final ecd = shippedTaxonomies.forForm(DanceForm.ecd);
      final named = FigureRenderer(ecd);
      for (final id in ecd.moves.keys.where((id) => id.startsWith('ecd_'))) {
        final name = named.displayMoveName(id, english);
        if (reads(name, DanceForm.ecd, english) &&
            !reads(name, DanceForm.contra, contraDialect) &&
            !reads(name, DanceForm.contra, english)) {
          return name;
        }
      }
      return null;
    }();

    Future<void> pumpWarning(WidgetTester tester, String token) async {
      final controller = TextEditingController(text: token);
      addTearDown(controller.dispose);
      final dialects = ValueNotifier(
        DialectsByForm({
          DanceForm.contra: contraDialect,
          DanceForm.ecd: english,
          DanceForm.square: square,
        }),
      );
      addTearDown(dialects.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: ActiveDialectScope.byForm(
            dialects: dialects,
            child: Scaffold(
              body: ShorthandShadowWarning(
                warningKey: const ValueKey('warning'),
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('controls: each token reads as a figure under exactly one pair', () {
      expect(englishName, isNotNull, reason: 'an English-only figure name');
      expect(reads(englishName!, DanceForm.ecd, english), isTrue);
      expect(reads(englishName!, DanceForm.contra, contraDialect), isFalse);
      expect(reads('whirlygig', DanceForm.contra, square), isTrue);
      expect(reads('whirlygig', DanceForm.contra, contraDialect), isFalse);
      expect(reads('whirlygig', DanceForm.ecd, english), isFalse);
    });

    testWidgets('warns of a name only English\'s figures and dialect give a '
        'figure', (tester) async {
      await pumpWarning(tester, englishName!);
      expect(find.byKey(const ValueKey('warning')), findsOneWidget);
    });

    testWidgets('warns of a name only square\'s dialect gives one of contra\'s '
        'figures', (tester) async {
      await pumpWarning(tester, 'whirlygig');
      expect(find.byKey(const ValueKey('warning')), findsOneWidget);
    });

    testWidgets('says nothing of a token no form reads as a figure', (
      tester,
    ) async {
      await pumpWarning(tester, 'qqzz');
      expect(find.byKey(const ValueKey('warning')), findsNothing);
    });
  });

  group('a shorthand', () {
    UserGlossaryEntry zoom(String id, String form) => UserGlossaryEntry(
      id: id,
      kindName: UserGlossaryEntryKind.customFigure.name,
      name: 'zoom',
      definition: 'A zoom.',
      description: '',
      payload: {
        'form': form,
        'template': 'role1s {move}',
        'defaultBeats': 8,
        'params': <Object?>[],
      },
      createdAt: DateTime.utc(2026, 11, 20),
    );

    Future<void> pumpShorthands(
      WidgetTester tester, {
      required List<UserGlossaryEntry> figures,
      required List<UserFigureShorthand> shorthands,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        for (final f in figures) {
          await repos.userGlossary.upsert(f);
        }
        for (final sh in shorthands) {
          await controller.upsertUserFigure(sh);
        }
      });
      final userFigures = UserFiguresController(repos.userGlossary);
      addTearDown(userFigures.dispose);
      unawaited(userFigures.start());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      final dialects = ValueNotifier(byForm());
      final glossary = ValueNotifier(true);
      final custom = ValueNotifier(true);
      for (final n in <ChangeNotifier>[dialects, glossary, custom]) {
        addTearDown(n.dispose);
      }
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope.byForm(
              dialects: dialects,
              child: ShowGlossaryScope(
                notifier: glossary,
                child: ShowCustomFiguresScope(
                  notifier: custom,
                  child: UserFiguresScope(
                    controller: userFigures,
                    child: ShorthandMappingsScope(
                      controller: controller,
                      child: child!,
                    ),
                  ),
                ),
              ),
            ),
          ),
          home: const ShorthandMappingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
    }

    UserFigureShorthand shorthand(String token, String figureId) =>
        UserFigureShorthand(
          token: token,
          figureId: figureId,
          figureName: 'role1s zoom',
          args: const {},
        );

    testWidgets('reads in the dialect of the form of the figure it stands '
        'for, and in contra\'s when that figure is not here', (tester) async {
      expectDialectsDiffer('role1s zoom');
      await pumpShorthands(
        tester,
        figures: [zoom('e-id', 'ecd'), zoom('c-id', 'contra')],
        shorthands: [
          shorthand('en', 'e-id'),
          shorthand('co', 'c-id'),
          shorthand('gone', 'missing-id'),
        ],
      );
      Finder tile(String token) =>
          find.byKey(ValueKey('user-figure-shorthand-tile-$token'));
      for (final (token, read) in [
        ('en', inEnglish),
        ('co', inContra),
        ('gone', inContra),
      ]) {
        expect(
          find.descendant(
            of: tile(token),
            matching: find.textContaining(read('role1s zoom')),
          ),
          findsOneWidget,
          reason: token,
        );
      }
    });
  });

  group('the Custom Figures screen', () {
    testWidgets('names each figure, and describes it, in its own form\'s '
        'dialect', (tester) async {
      expectDialectsDiffer('role1s zoom');
      expectDialectsDiffer('role1s zoom around.');
      await pumpScreen(
        tester,
        const CustomFiguresScreen(),
        entries: [
          figure(id: 'c', name: 'role1s zoom', form: 'contra'),
          figure(id: 'e', name: 'role1s zoom', form: 'ecd'),
        ],
      );
      Finder row(String id) => find.byKey(ValueKey('custom-figure-$id'));
      for (final (id, read) in [('c', inContra), ('e', inEnglish)]) {
        expect(
          find.descendant(
            of: row(id),
            matching: find.text(read('role1s zoom')),
          ),
          findsOneWidget,
          reason: id,
        );
        expect(
          find.descendant(
            of: row(id),
            matching: find.text(read('role1s zoom around.')),
          ),
          findsOneWidget,
          reason: id,
        );
      }
    });
  });
}
