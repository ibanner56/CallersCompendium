import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';

import 'support/test_repositories.dart';
import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  required String title,
  List<Figure> figures = const [],
  List<String> authorIds = const [],
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: figures,
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps the builder in its full-screen (routed) shape with a wide surface so
/// the inline picker pane engages, an [ActiveDialectScope], and embedded
/// callbacks (so save/duplicate/delete don't pop the navigator during tests).
Future<void> _pumpBuilder(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? programId,
  bool autoCommit = false,
  void Function(String)? onSaved,
  VoidCallback? onDeleted,
  void Function(String)? onNavigateTo,
  OnlineSearchService? callersBoxOnline,
  OnlineSearchService? contraDbOnline,
  Size size = const Size(1200, 2000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final autoCommitNotifier = ValueNotifier<bool>(autoCommit);
  addTearDown(autoCommitNotifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: notifier,
          child: ProgramAutoCommitScope(
            notifier: autoCommitNotifier,
            child: child!,
          ),
        ),
      ),
      home: ProgramEditorScreen(
        programId: programId,
        onSaved: onSaved ?? (_) {},
        onDeleted: onDeleted,
        onNavigateTo: onNavigateTo,
        callersBoxOnline: callersBoxOnline,
        contraDbOnline: contraDbOnline,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the collapsed Tier 2 metadata drawer when a test needs its fields.
/// Repeated calls are safe, which keeps tests focused on their actual action.
Future<void> _expandMoreDetails(WidgetTester tester) async {
  final tile = tester.widget<ExpansionTile>(
    find.byKey(const ValueKey('program-more-details-tile')),
  );
  if (!tile.controller!.isExpanded) {
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
  }
}

class _ProgramOnlineService implements OnlineSearchService {
  @override
  OnlineSource get source => OnlineSource.callersBox;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async => [
    const OnlineSearchResultRow(
      source: OnlineSource.callersBox,
      id: 'remote',
      name: 'Imported Dance',
      author: 'Imported Author',
      formation: 'Duple Improper',
    ),
  ];

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    final dance = _dance(
      id: '',
      title: result.name,
      authorIds: const ['imported-author'],
    );
    return OnlinePreview(
      result: result,
      detail: DanceDetailData(
        dance: dance,
        authorNames: const ['Imported Author'],
        tagNames: const [],
        customFields: const [],
        relatedDanceTitles: const {},
        sourcesById: const {},
        crossRefLinker: DanceTitleLinker.build(const [], excludeId: ''),
      ),
      plan: ImportRecordPlan(
        draft: StructuredDraft(
          dance: dance,
          raw: const RawRecord(
            source: ProvenanceSource.callersbox,
            externalId: 'remote',
            payload: '{}',
          ),
        ),
        verdict: DedupeVerdict.isNew(),
      ),
    );
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  }) async {
    // ignore: unused_result
    await repos.choreographers.upsert(
      Choreographer(id: 'imported-author', name: 'Imported Author'),
    );
    await repos.dances.create(
      _dance(
        id: 'imported',
        title: 'Imported Dance',
        authorIds: const ['imported-author'],
      ),
    );
    return const OnlineImportResult(
      kind: OnlineImportKind.created,
      title: 'Imported Dance',
      danceId: 'imported',
    );
  }
}

class _QueuedProgramOnlineService extends _ProgramOnlineService {
  final committed = [Completer<void>(), Completer<void>()];
  final release = [Completer<void>(), Completer<void>()];
  var _importIndex = 0;

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  }) async {
    final index = _importIndex++;
    final result = await super.import(
      repos,
      plan,
      now: now,
      ambiguousResolution: ambiguousResolution,
    );
    committed[index].complete();
    await release[index].future;
    return result;
  }
}

class _PreviewQueuedProgramOnlineService extends _ProgramOnlineService {
  final previewStarted = Completer<void>();
  final releasePreview = Completer<void>();

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    previewStarted.complete();
    await releasePreview.future;
    return super.loadPreview(repos, result, now: now, index: index);
  }
}

class _TwoQueuedPreviewProgramOnlineService extends _ProgramOnlineService {
  final firstPreviewStarted = Completer<void>();
  final secondPreviewStarted = Completer<void>();
  final releaseSecondPreview = Completer<void>();

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async =>
      const [
        OnlineSearchResultRow(
          source: OnlineSource.callersBox,
          id: 'first',
          name: 'First Preview',
          author: 'Imported Author',
          formation: 'Duple Improper',
        ),
        OnlineSearchResultRow(
          source: OnlineSource.callersBox,
          id: 'second',
          name: 'Second Preview',
          author: 'Imported Author',
          formation: 'Duple Improper',
        ),
      ];

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    if (result.id == 'first') {
      firstPreviewStarted.complete();
      return Completer<OnlinePreview>().future;
    }
    secondPreviewStarted.complete();
    await releaseSecondPreview.future;
    return super.loadPreview(repos, result, now: now, index: index);
  }
}

Future<void> _startInlineOnlineImport(WidgetTester tester) async {
  final picker = find.byKey(const ValueKey('inline-picker'));
  await tester.tap(
    find.descendant(
      of: picker,
      matching: find.byKey(const ValueKey('picker-advanced-panel')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: picker,
      matching: find.byKey(const ValueKey('picker-online-search-enable')),
    ),
  );
  await tester.enterText(
    find.descendant(
      of: picker,
      matching: find.byKey(const ValueKey('picker-search')),
    ),
    'Imported Dance',
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: picker, matching: find.byType(OnlineResultTile)),
  );
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? programId,
  void Function(String)? onSaved,
  VoidCallback? onDeleted,
  void Function(String)? onNavigateTo,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: ProgramEditorScreen(
        programId: programId,
        onSaved: onSaved,
        onDeleted: onDeleted,
        onNavigateTo: onNavigateTo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Program _program({
  required String id,
  String title = 'Existing',
  DateTime? eventDate,
  String? venue,
  String? band,
  String? caller,
  String notes = '',
  ProgramStatus status = ProgramStatus.draft,
  List<ProgramSlot> slots = const [],
}) => Program(
  id: id,
  title: title,
  eventDate: eventDate,
  venue: venue,
  band: band,
  caller: caller,
  notes: notes,
  status: status,
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

class _EditorHost extends StatefulWidget {
  const _EditorHost({required this.onResult, this.programId});

  final ValueChanged<Object?> onResult;
  final String? programId;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final result = await Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          builder: (_) => ProgramEditorScreen(programId: widget.programId),
        ),
      );
      if (mounted) widget.onResult(result);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: ValueKey('editor-sentinel'));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('Tier 2 event details start collapsed', (tester) async {
    final repos = openTestRepositories();
    await _pumpBuilder(tester, repos);

    expect(
      find.byKey(const ValueKey('program-more-details-tile')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('program-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-event-date')), findsOneWidget);
    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(const ValueKey('program-more-details-tile')),
          )
          .controller!
          .isExpanded,
      isFalse,
    );

    await _expandMoreDetails(tester);

    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(const ValueKey('program-more-details-tile')),
          )
          .controller!
          .isExpanded,
      isTrue,
    );
    expect(find.byKey(const ValueKey('program-venue')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-band')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-caller')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-dancer-level')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-notes')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-status')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('program-hide-alternates')),
      findsOneWidget,
    );

    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(const ValueKey('program-more-details-tile')),
          )
          .controller!
          .isExpanded,
      isFalse,
    );
  });

  testWidgets('create requires a title', (tester) async {
    final repos = openTestRepositories();
    String? savedId;
    await _pump(tester, repos, onSaved: (id) => savedId = id);

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    expect(find.text('A title is required.'), findsOneWidget);
    expect(savedId, isNull);
    expect(await repos.programs.listAll(), isEmpty);
  });

  testWidgets('missing program shows the no-longer-exists message', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, programId: 'does-not-exist');

    // The editor stores a language-neutral sentinel (not the resolved string)
    // for the missing case and resolves the message at build time, so a live
    // locale switch would re-localise it. In English it renders unchanged.
    expect(find.text('This program no longer exists.'), findsOneWidget);
  });

  testWidgets('create persists a new program', (tester) async {
    final repos = openTestRepositories();
    String? savedId;
    await _pump(tester, repos, onSaved: (id) => savedId = id);

    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Barn Dance',
    );
    await _expandMoreDetails(tester);
    await tester.enterText(
      find.byKey(const ValueKey('program-venue')),
      'The Grange',
    );
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    expect(savedId, isNotNull);
    final saved = await repos.programs.getById(savedId!);
    expect(saved!.title, 'Barn Dance');
    expect(saved.venue, 'The Grange');
    expect(saved.status, ProgramStatus.draft);
  });

  testWidgets('clean Back after auto-create returns the persisted id', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final autoCommit = ValueNotifier(true);
    final results = <Object?>[];
    addTearDown(autoCommit.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ProgramAutoCommitScope(notifier: autoCommit, child: child!),
        ),
        home: _EditorHost(onResult: results.add),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Back selects me',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final id = (await repos.programs.listAll()).single.id;

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(results, [id]);
  });

  testWidgets('edit updates existing metadata', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(id: 'p1', title: 'Before', venue: 'Old Hall'),
    );
    await _pump(tester, repos, programId: 'p1', onSaved: (_) {});

    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'After',
    );
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final updated = await repos.programs.getById('p1');
    expect(updated!.title, 'After');
    expect(updated.venue, 'Old Hall');
  });

  testWidgets('toggling "Hide alternates" persists the flag', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pump(tester, repos, programId: 'p1', onSaved: (_) {});

    await _expandMoreDetails(tester);
    final toggle = find.byKey(const ValueKey('program-hide-alternates'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    // Default is off.
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final updated = await repos.programs.getById('p1');
    expect(updated!.hideAlternates, isTrue);
  });

  testWidgets('expanded Tier 2 metadata persists on save', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pump(tester, repos, programId: 'p1', onSaved: (_) {});

    await _expandMoreDetails(tester);
    await tester.enterText(
      find.byKey(const ValueKey('program-venue')),
      'Grange Hall',
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-band')),
      'The Fiddleheads',
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-caller')),
      'Alex Caller',
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-dancer-level')),
      'All welcome',
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-notes')),
      'Doors at seven.',
    );
    await tester.tap(find.byKey(const ValueKey('program-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finalized').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('program-hide-alternates')));
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.venue, 'Grange Hall');
    expect(saved.band, 'The Fiddleheads');
    expect(saved.caller, 'Alex Caller');
    expect(saved.dancerLevel, 'All welcome');
    expect(saved.notes, 'Doors at seven.');
    expect(saved.status, ProgramStatus.finalized);
    expect(saved.hideAlternates, isTrue);
  });

  testWidgets('clearing venue and event date persists as null', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Has Meta',
        eventDate: DateTime.utc(2026, 4, 4),
        venue: 'Somewhere',
      ),
    );
    await _pump(tester, repos, programId: 'p1', onSaved: (_) {});

    // Clear event date via the clear button.
    await tester.tap(find.byKey(const ValueKey('clear-event-date')));
    await tester.pumpAndSettle();
    // Clear venue text.
    await _expandMoreDetails(tester);
    await tester.enterText(find.byKey(const ValueKey('program-venue')), '');
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final updated = await repos.programs.getById('p1');
    expect(updated!.eventDate, isNull);
    expect(updated.venue, isNull);
  });

  testWidgets('duplicate creates a copy', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Original'));
    String? navigatedTo;
    await _pump(
      tester,
      repos,
      programId: 'p1',
      onNavigateTo: (id) => navigatedTo = id,
    );

    await tester.tap(find.byKey(const ValueKey('duplicate-program')));
    await tester.pumpAndSettle();

    expect(navigatedTo, isNotNull);
    expect(navigatedTo, isNot('p1'));
    final all = await repos.programs.listAll();
    expect(all, hasLength(2));
    expect(all.map((p) => p.title), contains('Original (copy)'));
  });

  testWidgets('delete soft-deletes and calls onDeleted', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Doomed'));
    var deleted = false;
    await _pump(
      tester,
      repos,
      programId: 'p1',
      onDeleted: () => deleted = true,
    );

    await tester.tap(find.byKey(const ValueKey('delete-program')));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(await repos.programs.listAll(), isEmpty);
    expect(await repos.programs.getById('p1', includeDeleted: true), isNotNull);
  });

  // --- Phase 4.2 builder -----------------------------------------------------

  testWidgets('adds a dance slot from the inline picker', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    String? savedId;
    await _pumpBuilder(
      tester,
      repos,
      programId: 'p1',
      onSaved: (id) => savedId = id,
    );

    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slot-d1-title')), findsNothing);
    // The slot uses a minted uuid; assert via the title text instead.
    expect(find.text('Chase the Squirrel'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    expect(savedId, 'p1');
    final saved = await repos.programs.getById('p1');
    expect(saved!.slots, hasLength(1));
    expect(saved.slots.single.danceId, 'd1');
    expect(saved.slots.single.position, 0);
  });

  testWidgets('two-pane layout splits editor and picker evenly', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    const surface = Size(1200, 2000);
    await _pumpBuilder(tester, repos, programId: 'p1', size: surface);

    final pickerFinder = find.byKey(const ValueKey('inline-picker'));
    expect(pickerFinder, findsOneWidget);

    final pickerWidth = tester.getSize(pickerFinder).width;
    final dividerWidth = tester.getSize(find.byType(VerticalDivider)).width;
    // Two equal-flex Expanded panes share the surface minus the divider.
    final expectedPaneWidth = (surface.width - dividerWidth) / 2;
    expect(pickerWidth, closeTo(expectedPaneWidth, 2));
  });

  testWidgets(
    'holding a saved picker result temporarily previews it in editor pane',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(_program(id: 'p1', title: 'Night'));
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        size: const Size(1200, 2000),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('picker-tile-d1'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('program-preview-d1')), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('program-preview-d1')), findsNothing);
    },
  );

  testWidgets('closing a wide dance preview stays in the program editor', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    final results = <Object?>[];
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: dialect, child: child!),
        ),
        home: _EditorHost(onResult: results.add, programId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('slot-0-view-details')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('program-preview-d1')), findsOneWidget);
    expect(find.byKey(const ValueKey('dance-detail-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('reimport-dance')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dance-detail-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('program-preview-d1')), findsNothing);
    expect(find.byKey(const ValueKey('program-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-sentinel')), findsNothing);
    expect(results, isEmpty);
  });

  testWidgets(
    'holding a dance slot in compact layout opens read-only details',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(
        _program(
          id: 'p1',
          title: 'Night',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        size: const Size(600, 2000),
      );

      await tester.longPress(find.byKey(const ValueKey('slot-s1-title')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('program-preview-sheet-d1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('edit-dance')), findsNothing);
      expect(find.byKey(const ValueKey('reimport-dance')), findsOneWidget);
    },
  );

  testWidgets(
    'ending an older online hold does not clear a newer loading preview',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Night'));
      final online = _TwoQueuedPreviewProgramOnlineService();
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        callersBoxOnline: online,
        size: const Size(1200, 2000),
      );

      final picker = find.byKey(const ValueKey('inline-picker'));
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-advanced-panel')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-online-search-enable')),
        ),
      );
      await tester.enterText(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-search')),
        ),
        'Preview',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final first = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('picker-online-result-callersBox-first')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await online.firstPreviewStarted.future;

      final second = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('picker-online-result-callersBox-second')),
        ),
        pointer: 2,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await online.secondPreviewStarted.future;

      await first.up();
      online.releaseSecondPreview.complete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('program-online-preview-callersBox-second')),
        findsOneWidget,
      );
      await second.up();
    },
  );

  testWidgets('adds a free-text slot', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('add-free-text-slot')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('free-text-slot-input')),
      'Break',
    );
    await tester.tap(find.byKey(const ValueKey('free-text-slot-add')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots, hasLength(1));
    expect(saved.slots.single.text, 'Break');
    expect(saved.slots.single.danceId, isNull);
  });

  testWidgets('one-tap insert break adds a canonical break slot', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    // No dialog: a single tap appends the break with the canonical text the
    // half-derivation keys off, so the caller never hand-types "break".
    await tester.tap(find.byKey(const ValueKey('insert-break-slot')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots, hasLength(1));
    expect(saved.slots.single.text, Program.breakSlotText);
    expect(saved.slots.single.danceId, isNull);
    expect(saved.slots.single.isBreak, isTrue);
  });

  testWidgets('slot cards number primaries and mark alternates', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [
          ProgramSlot(id: 's0', position: 0, text: 'First'),
          ProgramSlot(id: 's1', position: 1, text: 'Alt of first', isAlt: true),
          ProgramSlot(id: 's2', position: 2, text: 'Second'),
        ],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    // Primaries carry 1-based running-order numbers; the alt in the middle is
    // grouped under its primary and shows "ALT", not its own number — so the
    // slot after it is #2, not #3.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('slot-0-ordinal'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('slot-1-ordinal'))).data,
      'ALT',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('slot-2-ordinal'))).data,
      '2',
    );
  });

  testWidgets('reorders slots via move-up keeping positions contiguous', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [
          ProgramSlot(id: 's0', position: 0, text: 'First'),
          ProgramSlot(id: 's1', position: 1, text: 'Second'),
        ],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('slot-1-move-up')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots.map((s) => s.text).toList(), ['Second', 'First']);
    expect(saved.slots.map((s) => s.position).toList(), [0, 1]);
  });

  testWidgets('reorders slots via cut then paste', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [
          ProgramSlot(id: 's0', position: 0, text: 'First'),
          ProgramSlot(id: 's1', position: 1, text: 'Second'),
          ProgramSlot(id: 's2', position: 2, text: 'Third'),
        ],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    // Cut the first slot, then paste it after the last.
    await tester.tap(find.byKey(const ValueKey('slot-0-cut')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('slot-paste-after-s2')),
        matching: find.text('Paste here'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots.map((s) => s.text).toList(), [
      'Second',
      'Third',
      'First',
    ]);
    expect(saved.slots.map((s) => s.position).toList(), [0, 1, 2]);
  });

  testWidgets('toggling ALT indents the slot and persists isAlt', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [
          ProgramSlot(id: 's0', position: 0, text: 'Primary'),
          ProgramSlot(id: 's1', position: 1, text: 'Maybe'),
        ],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    expect(find.byKey(const ValueKey('slot-s1-alt-badge')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('slot-1-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as alternate'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slot-s1-alt-badge')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots[1].isAlt, isTrue);
  });

  testWidgets('a leading alternate surfaces an orphaned_alt warning', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's0', position: 0, text: 'Alt', isAlt: true)],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    expect(find.byKey(const ValueKey('program-warnings-card')), findsOneWidget);
    expect(find.textContaining('has no'), findsOneWidget);
  });

  testWidgets('edits program band/caller/dancerLevel and persists', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    await _expandMoreDetails(tester);
    await tester.enterText(
      find.byKey(const ValueKey('program-band')),
      'The Fiddleheads',
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-caller')),
      'Alex Caller',
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-dancer-level')),
      'All welcome',
    );
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.band, 'The Fiddleheads');
    expect(saved.caller, 'Alex Caller');
    expect(saved.dancerLevel, 'All welcome');
  });

  testWidgets('edits per-slot guest caller and planned minutes', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit slot'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('slot-edit-guest')),
      'Guest Caller',
    );
    await tester.enterText(
      find.byKey(const ValueKey('slot-edit-minutes')),
      '12',
    );
    await tester.tap(find.byKey(const ValueKey('slot-edit-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots.single.guestCaller, 'Guest Caller');
    expect(saved.slots.single.plannedMinutes, 12);
  });

  // M1 (issue #964): the replacement must rebuild the slot preserving
  // everything but danceId — never as a bare `ProgramSlot(id, position,
  // danceId)`, which is the shape both `_addDanceSlot` (a brand-new slot with
  // nothing yet to preserve) and `#960`'s note→dance rebuild (which
  // deliberately drops only `text`) would produce if copied verbatim here.
  testWidgets(
    'replacing a dance keeps the slot\'s other metadata (issue #964)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.dances.create(_dance(id: 'd2', title: 'Rory O\'Moore'));
      final performedAt = DateTime.utc(2026, 2, 2);
      await repos.programs.create(
        _program(
          id: 'p1',
          title: 'Night',
          slots: [
            ProgramSlot(
              id: 's0',
              position: 0,
              danceId: 'd1',
              guestCaller: 'Guest Caller',
              plannedMinutes: 12,
              isAlt: true,
              performedAt: performedAt,
            ),
          ],
        ),
      );
      await _pumpBuilder(tester, repos, programId: 'p1');

      await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit slot'));
      await tester.pumpAndSettle();

      // The dialog shows the dance currently in the slot before any pick.
      // Scoped to the dialog itself: the same title also renders in the slot
      // list and (on this wide surface) the inline picker pane underneath.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Chase the Squirrel'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('slot-edit-replace-dance')));
      await tester.pumpAndSettle();
      // Scoped to the replacement sheet's own picker: the inline picker pane
      // underneath renders a same-keyed 'picker-add-d2' row too.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('replace-picker')),
          matching: find.byKey(const ValueKey('picker-add-d2')),
        ),
      );
      await tester.pumpAndSettle();

      // Back in the (still-open) dialog, showing the replacement.
      expect(find.byKey(const ValueKey('slot-edit-save')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Rory O\'Moore'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('slot-edit-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();

      final saved = await repos.programs.getById('p1');
      final slot = saved!.slots.single;
      expect(slot.danceId, 'd2');
      expect(slot.guestCaller, 'Guest Caller');
      expect(slot.plannedMinutes, 12);
      expect(slot.isAlt, isTrue);
      expect(slot.performedAt, performedAt);
    },
  );

  // M2 (issue #964): a pick must be held in the dialog's own state, not
  // applied immediately — otherwise text typed into the note/guest/minutes
  // fields before the replacement would be lost when the pick pops the dialog
  // back open on top of a rebuilt slot.
  testWidgets(
    'in-flight dialog edits survive a dance replacement (issue #964)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.dances.create(_dance(id: 'd2', title: 'Rory O\'Moore'));
      await repos.programs.create(
        _program(
          id: 'p1',
          title: 'Night',
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
        ),
      );
      await _pumpBuilder(tester, repos, programId: 'p1');

      await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit slot'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('slot-edit-guest')),
        'Guest Caller',
      );
      await tester.enterText(
        find.byKey(const ValueKey('slot-edit-minutes')),
        '12',
      );

      await tester.tap(find.byKey(const ValueKey('slot-edit-replace-dance')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('replace-picker')),
          matching: find.byKey(const ValueKey('picker-add-d2')),
        ),
      );
      await tester.pumpAndSettle();

      // The typed fields must still show what was typed, not reset defaults.
      expect(find.widgetWithText(TextField, 'Guest Caller'), findsOneWidget);
      expect(find.widgetWithText(TextField, '12'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('slot-edit-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();

      final saved = await repos.programs.getById('p1');
      final slot = saved!.slots.single;
      expect(slot.danceId, 'd2');
      expect(slot.guestCaller, 'Guest Caller');
      expect(slot.plannedMinutes, 12);
    },
  );

  testWidgets(
    'inline online add hydrates imported dance and author before adding',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Night'));
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        callersBoxOnline: _ProgramOnlineService(),
      );

      final picker = find.byKey(const ValueKey('inline-picker'));
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-advanced-panel')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-online-search-enable')),
        ),
      );
      await tester.enterText(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-search')),
        ),
        'Imported Dance',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: picker, matching: find.byType(OnlineResultTile)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Imported Dance'), findsAtLeastNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('perform-program')));
      await tester.pumpAndSettle();
      expect(find.text('Imported Author'), findsOneWidget);
    },
  );

  testWidgets(
    'responsive picker replacement keeps editor locked until every import ends',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Existing Dance'));
      await repos.programs.create(
        _program(
          id: 'p1',
          title: 'Night',
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
        ),
      );
      final online = _QueuedProgramOnlineService();
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        callersBoxOnline: online,
      );

      await _startInlineOnlineImport(tester);
      await online.committed[0].future;
      await tester.pump();

      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('save-program')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('picker-online-search-enable')),
            )
            .onChanged,
        isNull,
        reason: 'an in-flight import cannot expose a second selection flow',
      );
      for (final key in [
        'perform-program',
        'duplicate-program',
        'delete-program',
      ]) {
        expect(
          tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
        );
      }

      await tester.binding.setSurfaceSize(const Size(600, 2000));
      await tester.pump();
      expect(find.byKey(const ValueKey('inline-picker')), findsNothing);
      await tester.binding.setSurfaceSize(const Size(1200, 2000));
      await tester.pumpAndSettle();

      online.release[0].complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('save-program')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();
      final saved = await repos.programs.getById('p1');
      expect(
        saved!.slots.where((slot) => slot.danceId == 'imported'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'responsive removal during preview still adds the imported dance',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Night'));
      final online = _PreviewQueuedProgramOnlineService();
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        callersBoxOnline: online,
      );

      await _startInlineOnlineImport(tester);
      await online.previewStarted.future;
      await tester.binding.setSurfaceSize(const Size(600, 2000));
      await tester.pump();
      expect(find.byKey(const ValueKey('inline-picker')), findsNothing);

      online.releasePreview.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();

      final saved = await repos.programs.getById('p1');
      expect(saved!.slots.single.danceId, 'imported');
    },
  );

  testWidgets(
    'online replacement returns the imported dance to the slot dialog',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Original Dance'));
      await repos.programs.create(
        _program(
          id: 'p1',
          title: 'Night',
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
        ),
      );
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        size: const Size(600, 2000),
        callersBoxOnline: _ProgramOnlineService(),
      );

      await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit slot'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-edit-replace-dance')));
      await tester.pumpAndSettle();

      final picker = find.byKey(const ValueKey('replace-picker'));
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-advanced-panel')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-online-search-enable')),
        ),
      );
      await tester.enterText(
        find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('picker-search')),
        ),
        'Imported Dance',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: picker, matching: find.byType(OnlineResultTile)),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Imported Dance'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('slot-edit-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();

      expect(
        (await repos.programs.getById('p1'))!.slots.single.danceId,
        'imported',
      );
    },
  );

  testWidgets('mark all performed stamps performedAt on dance slots', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [
          ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's1', position: 1, text: 'Break'),
        ],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('mark-all-performed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots[0].performedAt, isNotNull);
    expect(saved.slots[0].performedAt!.isUtc, isTrue);
    // Free-text slots are not stamped.
    expect(saved.slots[1].performedAt, isNull);
  });

  testWidgets(
    'persists a mark-performed made via the builder-routed Perform path',
    (tester) async {
      // Perform enables the wake-lock; install the fake so the platform
      // channel call doesn't leak an unhandled error into the test.
      installFakeWakelock();
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(
        _program(
          id: 'p1',
          title: 'Night',
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
        ),
      );
      // Pump the full-screen builder at a NARROW width (800px, below both the
      // ProgramsShell 900px entry breakpoint and the builder's own 820px
      // two-pane breakpoint) — the tablet/phone gig form factor this fix
      // targets, and the layout the narrow entry point routes through.
      await _pumpBuilder(
        tester,
        repos,
        programId: 'p1',
        size: const Size(800, 1600),
      );

      // The pre-persist value the immediate write must change.
      final before = (await repos.programs.getById('p1'))!.updatedAt;

      // Enter the live Perform view, open the in-event adjust sheet, and mark
      // the current dance performed — then close the sheet.
      await tester.tap(find.byKey(const ValueKey('perform-program')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('perform-adjust')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-mark-performed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-done')));
      await tester.pumpAndSettle();

      // Simulate a background/relaunch: WITHOUT ever tapping Save, re-read the
      // program straight from the repository. The persistent store survives a
      // kill; the widget tree does not. The performed stamp must have been
      // written immediately during Perform.
      final saved = await repos.programs.getById('p1');
      expect(saved!.slots.single.performedAt, isNotNull);
      expect(saved.slots.single.performedAt!.isUtc, isTrue);
      expect(
        saved.updatedAt,
        isNot(before),
        reason:
            'the immediate persist changed updatedAt from its pre-persist '
            'value',
      );
    },
  );

  testWidgets('serializes Perform persistence behind a pending auto-commit', (
    tester,
  ) async {
    installFakeWakelock();
    final delayed = openTestRepositoriesWithDelayedPrograms();
    await delayed.repos.dances.create(
      _dance(id: 'd1', title: 'Chase the Squirrel'),
    );
    await delayed.repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
      ),
    );
    final writesBeforeEditor = delayed.programs.writesStarted;
    await _pumpBuilder(
      tester,
      delayed.repos,
      programId: 'p1',
      autoCommit: true,
      size: const Size(800, 1600),
    );

    delayed.programs.holdNextWrite();
    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Updated metadata',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await delayed.programs.writeStarted;

    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-adjust')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-mark-performed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-done')));
    await tester.pump();

    // The Perform update must be queued behind the held metadata update.
    expect(delayed.programs.writesStarted, writesBeforeEditor + 1);
    delayed.programs.releaseWrite();
    await tester.pumpAndSettle();

    final saved = await delayed.repos.programs.getById('p1');
    expect(saved!.title, 'Updated metadata');
    expect(saved.slots.single.performedAt, isNotNull);
  });

  testWidgets('blocks clearing a free-text slot to empty', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's0', position: 0, text: 'Break')],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit slot'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('slot-edit-note')), '');
    await tester.tap(find.byKey(const ValueKey('slot-edit-save')));
    await tester.pumpAndSettle();

    // Dialog stays open with an error; original text is preserved.
    expect(find.text('Enter some text for this slot.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slot-edit-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final saved = await repos.programs.getById('p1');
    expect(saved!.slots.single.text, 'Break');
  });

  testWidgets('save advances updatedAt', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Night',
        createdAt: DateTime.utc(2000),
        updatedAt: DateTime.utc(2000),
      ),
    );
    final before = (await repos.programs.getById('p1'))!.updatedAt;
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Night Revised',
    );
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();

    final after = (await repos.programs.getById('p1'))!.updatedAt;
    expect(after.isAfter(before), isTrue);
  });

  testWidgets('Matrix tab renders the programming matrix from draft slots', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Matrix Dance',
        figures: [
          Figure(move: 'swing'),
          Figure(move: 'balance'),
        ],
      ),
    );
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    // Build tab is showing first; switch to the Matrix tab.
    await tester.tap(find.byKey(const ValueKey('program-matrix-tab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('program-matrix-table')), findsOneWidget);
    expect(find.text('Matrix Dance'), findsOneWidget);
    // Swing splits into per-role columns; the partner baseline carries the
    // no-`who` swing.
    expect(find.text('partner swing'), findsOneWidget);
    expect(find.text('balance'), findsOneWidget);
    // The save FAB hides on the read-only Matrix tab.
    expect(find.byKey(const ValueKey('save-program')), findsNothing);
  });

  testWidgets('Matrix tab exposes an enabled export/print PDF control', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Matrix Dance',
        figures: [
          Figure(move: 'swing'),
          Figure(move: 'balance'),
        ],
      ),
    );
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('program-matrix-tab')));
    await tester.pumpAndSettle();

    final control = find.byKey(const ValueKey('program-matrix-export-pdf'));
    expect(control, findsOneWidget);
    expect(find.byTooltip('Export or print matrix as PDF'), findsOneWidget);
    // Actionable: the button has an onPressed callback.
    expect(tester.widget<IconButton>(control).onPressed, isNotNull);

    // Assistive-tech reachable: the control exposes an enabled, tappable button
    // with the expected accessible label in the semantics tree (not colour/icon
    // alone).
    final handle = tester.ensureSemantics();
    final semantics = tester.getSemantics(control).getSemanticsData();
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    expect(semantics.tooltip, 'Export or print matrix as PDF');
    handle.dispose();

    // Keyboard-reachable: the enabled button establishes a focus node that can
    // accept focus and, once requested, becomes the primary focus. Resolved via
    // Focus.of from a descendant (the icon) with scopeOk: false, so it returns
    // the IconButton's own (non-scope) focus node and cannot silently fall back
    // to a surrounding FocusScope — exercising the real focus path a keyboard/Tab
    // user relies on.
    final iconContext = tester.element(
      find.descendant(
        of: control,
        matching: find.byIcon(Icons.picture_as_pdf_outlined),
      ),
    );
    final focusNode = Focus.of(iconContext, scopeOk: false);
    expect(focusNode.canRequestFocus, isTrue);
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('Matrix export control is disabled for an empty matrix', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // A dances-free program (only a free-text slot) yields an empty matrix:
    // no dance rows means no columns at all, not even the swing baseline.
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        slots: [ProgramSlot(id: 's1', position: 0, text: 'Welcome & notes')],
      ),
    );
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('program-matrix-tab')));
    await tester.pumpAndSettle();

    final control = find.byKey(const ValueKey('program-matrix-export-pdf'));
    expect(control, findsOneWidget);
    expect(tester.widget<IconButton>(control).onPressed, isNull);
  });

  group('hide/reset matrix columns (#669)', () {
    Future<void> pumpMatrixTab(
      WidgetTester tester,
      CompendiumRepositories repos,
    ) async {
      await _pumpBuilder(tester, repos, programId: 'p1');
      await tester.tap(find.byKey(const ValueKey('program-matrix-tab')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'reset control starts disabled, enables once a column is hidden, and '
      'restores it on tap',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(
          _dance(
            id: 'd1',
            title: 'Matrix Dance',
            figures: [
              Figure(move: 'swing'),
              Figure(move: 'balance'),
            ],
          ),
        );
        await repos.programs.create(
          _program(
            id: 'p1',
            title: 'Night',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
        );
        await pumpMatrixTab(tester, repos);

        final reset = find.byKey(
          const ValueKey('program-matrix-reset-hidden-columns'),
        );
        expect(reset, findsOneWidget);
        expect(find.byTooltip('Show all columns'), findsOneWidget);
        expect(tester.widget<IconButton>(reset).onPressed, isNull);
        expect(find.text('balance'), findsOneWidget);

        await tester.tap(find.byTooltip('Hide balance column'));
        await tester.pumpAndSettle();

        expect(find.text('balance'), findsNothing);
        expect(tester.widget<IconButton>(reset).onPressed, isNotNull);

        await tester.tap(reset);
        await tester.pumpAndSettle();

        expect(find.text('balance'), findsOneWidget);
        expect(tester.widget<IconButton>(reset).onPressed, isNull);
      },
    );

    testWidgets(
      'the reset control is keyboard-reachable and its accessible label '
      'matches its visible tooltip',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(
          _dance(
            id: 'd1',
            title: 'Matrix Dance',
            figures: [
              Figure(move: 'swing'),
              Figure(move: 'balance'),
            ],
          ),
        );
        await repos.programs.create(
          _program(
            id: 'p1',
            title: 'Night',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
        );
        await pumpMatrixTab(tester, repos);

        await tester.tap(find.byTooltip('Hide balance column'));
        await tester.pumpAndSettle();

        final reset = find.byKey(
          const ValueKey('program-matrix-reset-hidden-columns'),
        );
        final handle = tester.ensureSemantics();
        final semantics = tester.getSemantics(reset).getSemanticsData();
        expect(semantics.hasAction(SemanticsAction.tap), isTrue);
        expect(semantics.tooltip, 'Show all columns');
        handle.dispose();

        final iconContext = tester.element(
          find.descendant(of: reset, matching: find.byIcon(Icons.visibility)),
        );
        final focusNode = Focus.of(iconContext, scopeOk: false);
        expect(focusNode.canRequestFocus, isTrue);
        focusNode.requestFocus();
        await tester.pump();
        expect(focusNode.hasPrimaryFocus, isTrue);
      },
    );

    testWidgets(
      'PDF/print export keeps the full matrix even while a column is hidden '
      'on-screen',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(
          _dance(
            id: 'd1',
            title: 'Matrix Dance',
            figures: [
              Figure(move: 'swing'),
              Figure(move: 'balance'),
            ],
          ),
        );
        await repos.programs.create(
          _program(
            id: 'p1',
            title: 'Night',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          ),
        );
        await pumpMatrixTab(tester, repos);

        await tester.tap(find.byTooltip('Hide balance column'));
        await tester.pumpAndSettle();
        expect(find.text('balance'), findsNothing);

        // Export/print stays enabled and unaffected by the on-screen hide —
        // the host always builds `_exportMatrixPdf` from the full,
        // unfiltered matrix regardless of `_hiddenMatrixColumns` (#669).
        final export = find.byKey(const ValueKey('program-matrix-export-pdf'));
        expect(tester.widget<IconButton>(export).onPressed, isNotNull);
      },
    );
  });

  testWidgets('G.3: new program prefills caller/band from saved defaults', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDefaultProgramCallerKey, 'Folk Process');
    await repos.settings.set(kDefaultProgramBandKey, 'The Syncopators');

    await _pump(tester, repos);
    await _expandMoreDetails(tester);

    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('program-caller')))
          .controller
          ?.text,
      'Folk Process',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('program-band')))
          .controller
          ?.text,
      'The Syncopators',
    );
  });

  testWidgets('G.3: existing program is not overridden by saved defaults', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDefaultProgramCallerKey, 'Folk Process');
    await repos.settings.set(kDefaultProgramBandKey, 'The Syncopators');
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Night',
        caller: 'Grace Hopper',
        band: 'The Debuggers',
      ),
    );

    await _pumpBuilder(tester, repos, programId: 'p1');
    await _expandMoreDetails(tester);

    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('program-caller')))
          .controller
          ?.text,
      'Grace Hopper',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('program-band')))
          .controller
          ?.text,
      'The Debuggers',
    );
  });

  testWidgets('G.3: new program opens blank when no defaults are saved', (
    tester,
  ) async {
    final repos = openTestRepositories();

    await _pump(tester, repos);
    await _expandMoreDetails(tester);

    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('program-caller')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('program-band')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  // Pins the two feedback channels #796 must not disturb. The picker's new
  // row-level confirmation exists because the modal *sheet* covers the
  // SnackBar; outside the sheet — the two-pane inline picker, which
  // `_pumpBuilder`'s default 1200x2000 surface engages — both the SnackBar and
  // the announcement were always visible and correct, and must stay so.
  testWidgets('adding from the inline picker still shows the SnackBar and '
      'announces the add (#796)', (tester) async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final List<Map<Object?, Object?>> announcements = [];
    messenger.setMockMessageHandler(SystemChannels.accessibility.name, (
      ByteData? message,
    ) async {
      final decoded = SystemChannels.accessibility.codec.decodeMessage(message);
      if (decoded is Map) announcements.add(decoded.cast());
      return null;
    });
    addTearDown(
      () => messenger.setMockMessageHandler(
        SystemChannels.accessibility.name,
        null,
      ),
    );

    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    expect(find.byKey(const ValueKey('inline-picker')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(SnackBar, 'Added "Chase the Squirrel".'),
      findsOneWidget,
    );

    final messages = announcements
        .map((a) => a['data'])
        .whereType<Map<Object?, Object?>>()
        .map((data) => data['message'])
        .toList();
    expect(messages, contains('Added Chase the Squirrel to program.'));
  });

  // --- Already-in-program counts (#796) --------------------------------------

  Map<String, int> countsOf(WidgetTester tester, String pickerKey) => tester
      .widget<CollectionPicker>(find.byKey(ValueKey(pickerKey)))
      .addedDanceCounts;

  testWidgets('the inline picker sees the program contents, and sees them '
      'change as dances are added (#796)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.dances.create(_dance(id: 'd2', title: 'Petronella Reel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    expect(countsOf(tester, 'inline-picker'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();
    expect(countsOf(tester, 'inline-picker'), {'d1': 1});

    // A dance may legitimately appear twice, so this is a count, not a flag.
    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();
    expect(countsOf(tester, 'inline-picker'), {'d1': 2});
  });

  testWidgets('the sheet picker sees the counts change while the sheet stays '
      'open (#796)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    // Narrow: the picker is the modal bottom sheet, not the inline pane.
    await _pumpBuilder(
      tester,
      repos,
      programId: 'p1',
      size: const Size(600, 2000),
    );

    await tester.tap(find.byKey(const ValueKey('add-dance-slot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sheet-picker')), findsOneWidget);
    expect(countsOf(tester, 'sheet-picker'), isEmpty);

    // The sheet deliberately stays open so several dances can be added, so its
    // picker must observe each add — it is a separate Navigator route, and the
    // screen's setState does not rebuild it.
    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();
    expect(countsOf(tester, 'sheet-picker'), {'d1': 1});
  });

  testWidgets('free-text and break slots contribute no dance counts (#796)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    await tester.tap(find.byKey(const ValueKey('insert-break-slot')));
    await tester.pumpAndSettle();

    expect(countsOf(tester, 'inline-picker'), isEmpty);
  });

  // --- Already-in-program visual marker (#796) -------------------------------

  testWidgets('the in-program marker appears on a row after the dance is added, '
      'and is absent before (#796)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.dances.create(_dance(id: 'd2', title: 'Petronella Reel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    // Before any add: no marker. We verify this finder would succeed below, so
    // this is not a vacuous findsNothing (AGENTS.md §Tests).
    expect(find.byKey(const ValueKey('picker-in-program-d1')), findsNothing);
    expect(find.byKey(const ValueKey('picker-in-program-d2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();

    // The marker now appears for d1 — same finder that was absent above.
    expect(find.byKey(const ValueKey('picker-in-program-d1')), findsOneWidget);
    // d2 was not added, so it still has no marker.
    expect(find.byKey(const ValueKey('picker-in-program-d2')), findsNothing);
  });

  testWidgets('the in-program marker shows a count when the dance appears more '
      'than once (#796)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    await _pumpBuilder(tester, repos, programId: 'p1');

    // Add once: marker present, no count badge.
    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picker-in-program-d1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('picker-in-program-d1')),
        matching: find.text('1'),
      ),
      findsNothing,
    );

    // Add again: count badge "2" appears alongside the marker.
    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('picker-in-program-d1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the sheet picker renders the in-program marker while the sheet '
      'stays open (#796)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.programs.create(_program(id: 'p1', title: 'Night'));
    // Narrow layout: picker is the modal sheet.
    await _pumpBuilder(
      tester,
      repos,
      programId: 'p1',
      size: const Size(600, 2000),
    );

    await tester.tap(find.byKey(const ValueKey('add-dance-slot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sheet-picker')), findsOneWidget);

    // No marker yet — verified against the positive case below.
    expect(find.byKey(const ValueKey('picker-in-program-d1')), findsNothing);

    // Add d1 while the sheet is still open.
    await tester.tap(find.byKey(const ValueKey('picker-add-d1')));
    await tester.pumpAndSettle();

    // The marker must render in the sheet without closing and reopening it.
    // This test would fail if the sheet's CollectionPicker were wired with a
    // plain read of _danceSlotCounts() at construction time rather than through
    // the ValueNotifier + ValueListenableBuilder: showModalBottomSheet pushes a
    // separate Navigator route, so setState in the screen never rebuilds it,
    // and the marker would stay absent no matter how many dances were added.
    expect(find.byKey(const ValueKey('picker-in-program-d1')), findsOneWidget);
    expect(find.byKey(const ValueKey('sheet-picker')), findsOneWidget);
  });

  group('create a dance from a note slot (issue #881)', () {
    testWidgets(
      'the menu item appears only on a qualifying note slot — not a dance '
      'slot, not a break, not a blank note',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(_dance(id: 'd1', title: 'Chorus Jig'));
        await repos.programs.create(
          _program(
            id: 'p1',
            title: 'Night',
            slots: [
              ProgramSlot(id: 's0', position: 0, text: 'Petronella'),
              ProgramSlot(id: 's1', position: 1, danceId: 'd1'),
              ProgramSlot(id: 's2', position: 2, text: Program.breakSlotText),
            ],
          ),
        );
        await _pumpBuilder(tester, repos, programId: 'p1');

        // s0: a qualifying note slot — the item is offered.
        await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('slot-menu-create-dance')),
          findsOneWidget,
        );
        await tester.tapAt(const Offset(5, 5)); // dismiss without selecting
        await tester.pumpAndSettle();

        // s1: a dance slot — never offered.
        await tester.tap(find.byKey(const ValueKey('slot-1-menu')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('slot-menu-create-dance')),
          findsNothing,
        );
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        // s2: the structural break token — never offered (it has nothing to
        // seed a title from, and offering it would mint a dance called
        // "Break").
        await tester.tap(find.byKey(const ValueKey('slot-2-menu')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('slot-menu-create-dance')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'converts the note slot to reference the newly created dance and '
      'clears its text',
      (tester) async {
        final repos = openTestRepositories();
        await repos.programs.create(
          _program(
            id: 'p1',
            title: 'Night',
            slots: [ProgramSlot(id: 's0', position: 0, text: 'Petronella')],
          ),
        );
        await _pumpBuilder(tester, repos, programId: 'p1');

        await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('slot-menu-create-dance')));
        await tester.pumpAndSettle();

        // The dance editor is open, seeded from the note text.
        expect(
          find.widgetWithText(TextFormField, 'Petronella'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('save-dance')));
        await tester.pumpAndSettle();

        // Back on the program editor: the slot now shows the new dance's
        // title immediately (the created-dance overlay, not the stream
        // snapshot, which may not have caught up yet), and the leftover note
        // text is gone rather than surviving as a redundant "Note: …"
        // subtitle (Isaac decided: the note only ever stood in for the
        // missing dance).
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('slot-s0-title'))).data,
          'Petronella',
        );
        expect(find.textContaining('Note:'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('save-program')));
        await tester.pumpAndSettle();

        final saved = await repos.programs.getById('p1');
        final slot = saved!.slots.single;
        expect(slot.danceId, isNotNull);
        expect(slot.text, isNull);

        final createdDance = await repos.dances.getById(slot.danceId!);
        expect(createdDance!.title, 'Petronella');
      },
    );

    testWidgets(
      'cancelling the dance editor leaves the slot exactly as it was',
      (tester) async {
        final repos = openTestRepositories();
        await repos.programs.create(
          _program(
            id: 'p1',
            title: 'Night',
            slots: [ProgramSlot(id: 's0', position: 0, text: 'Petronella')],
          ),
        );
        await _pumpBuilder(tester, repos, programId: 'p1');

        await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('slot-menu-create-dance')));
        await tester.pumpAndSettle();

        expect(find.text('New dance'), findsOneWidget);

        // Back out without saving. The seed alone does not mark the
        // controller dirty, so this is a plain (unconfirmed) pop.
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Still on the program editor, slot untouched: still a note, same
        // text, no dance created.
        expect(find.byKey(const ValueKey('slot-s0-title')), findsOneWidget);
        expect(find.text('Petronella'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('save-program')));
        await tester.pumpAndSettle();

        final saved = await repos.programs.getById('p1');
        final slot = saved!.slots.single;
        expect(slot.danceId, isNull);
        expect(slot.text, 'Petronella');
        expect(await repos.dances.listAll(), isEmpty);
      },
    );
  });
}
