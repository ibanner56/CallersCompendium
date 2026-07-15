import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  required String title,
  List<Figure> figures = const [],
}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
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
  void Function(String)? onSaved,
  VoidCallback? onDeleted,
  void Function(String)? onNavigateTo,
  Size size = const Size(1200, 2000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: ProgramEditorScreen(
        programId: programId,
        onSaved: onSaved ?? (_) {},
        onDeleted: onDeleted,
        onNavigateTo: onNavigateTo,
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  String notes = '',
  ProgramStatus status = ProgramStatus.draft,
  List<ProgramSlot> slots = const [],
}) => Program(
  id: id,
  title: title,
  eventDate: eventDate,
  venue: venue,
  notes: notes,
  status: status,
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  testWidgets('create persists a new program', (tester) async {
    final repos = openTestRepositories();
    String? savedId;
    await _pump(tester, repos, onSaved: (id) => savedId = id);

    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Barn Dance',
    );
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
    expect(find.text('swing'), findsOneWidget);
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
    await repos.dances.create(_dance(id: 'd1', title: 'No Figures Dance'));
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
    expect(tester.widget<IconButton>(control).onPressed, isNull);
  });
}
