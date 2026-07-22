import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/editor/program_editor_draft_codec.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

final _now = DateTime.utc(2026, 1, 1);

ProgramSlot _danceSlot(String id, int position, String danceId) =>
    ProgramSlot(id: id, position: position, danceId: danceId);

ProgramSlot _textSlot(String id, int position, String text) =>
    ProgramSlot(id: id, position: position, text: text);

ProgramEditorDraft _draft({
  String title = 'Draft Program',
  DateTime? eventDate,
  String? venue,
  String? venueId,
  String? band,
  String? caller,
  String? dancerLevel,
  String notes = '',
  ProgramStatus status = ProgramStatus.draft,
  bool hideAlternates = false,
  List<ProgramSlot> slots = const [],
}) => ProgramEditorDraft(
  title: title,
  eventDate: eventDate,
  venue: venue,
  venueId: venueId,
  band: band,
  caller: caller,
  dancerLevel: dancerLevel,
  notes: notes,
  status: status,
  hideAlternates: hideAlternates,
  slots: slots,
);

Program _program({
  required String id,
  String title = 'Existing',
  List<ProgramSlot> slots = const [],
}) => Program(
  id: id,
  title: title,
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps the program editor in its (embedded) full-screen shape on a narrow
/// surface (single pane, so the add-slot buttons render inline). Fires the
/// post-frame draft-restore callback and settles any dialog it schedules.
Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? programId,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: ProgramEditorScreen(programId: programId, onSaved: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
  // Fire any post-frame callbacks (e.g. the draft-restore dialog trigger) and
  // settle the dialog entrance animation if one was scheduled.
  await tester.pump();
  await tester.pumpAndSettle();
}

/// The current text of the program title field.
String _titleText(WidgetTester tester) {
  final field = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(const ValueKey('program-title')),
      matching: find.byType(EditableText),
    ),
  );
  return field.controller.text;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // -------------------------------------------------------------------------
  // Codec
  // -------------------------------------------------------------------------
  group('ProgramEditorDraftCodec', () {
    test('round-trips every metadata field and slot kind', () {
      final draft = _draft(
        title: 'Autumn Ball',
        eventDate: DateTime.utc(2026, 9, 12),
        venue: 'The Grange',
        venueId: 'venue-42',
        band: 'The Reelers',
        caller: 'Pat',
        dancerLevel: 'Intermediate',
        notes: 'Doors at 7',
        status: ProgramStatus.finalized,
        hideAlternates: true,
        slots: [
          _danceSlot('s1', 0, 'dance-a'),
          _textSlot('s2', 1, 'Waltz interlude'),
          _textSlot('s3', 2, Program.breakSlotText),
          ProgramSlot(
            id: 's4',
            position: 3,
            danceId: 'dance-b',
            isAlt: true,
            guestCaller: 'Sam',
            plannedMinutes: 12,
            performedAt: DateTime.utc(2026, 9, 12, 20, 30),
          ),
        ],
      );

      final decoded = decodeProgramDraft(encodeProgramDraft(draft));

      expect(decoded.title, 'Autumn Ball');
      expect(decoded.eventDate, DateTime.utc(2026, 9, 12));
      expect(decoded.venue, 'The Grange');
      expect(decoded.venueId, 'venue-42');
      expect(decoded.band, 'The Reelers');
      expect(decoded.caller, 'Pat');
      expect(decoded.dancerLevel, 'Intermediate');
      expect(decoded.notes, 'Doors at 7');
      expect(decoded.status, ProgramStatus.finalized);
      expect(decoded.hideAlternates, isTrue);
      expect(decoded.slots, hasLength(4));
      expect(decoded.slots[0].danceId, 'dance-a');
      expect(decoded.slots[1].text, 'Waltz interlude');
      expect(decoded.slots[2].isBreak, isTrue);
      final alt = decoded.slots[3];
      expect(alt.danceId, 'dance-b');
      expect(alt.isAlt, isTrue);
      expect(alt.guestCaller, 'Sam');
      expect(alt.plannedMinutes, 12);
      expect(alt.performedAt, DateTime.utc(2026, 9, 12, 20, 30));
    });

    test('round-trips an in-progress draft with an empty title', () {
      final draft = _draft(title: '', slots: [_textSlot('s1', 0, 'A note')]);
      final decoded = decodeProgramDraft(encodeProgramDraft(draft));
      expect(decoded.title, isEmpty);
      expect(decoded.slots.single.text, 'A note');
    });

    test('null metadata is omitted and decodes back to null', () {
      final decoded = decodeProgramDraft(encodeProgramDraft(_draft()));
      expect(decoded.eventDate, isNull);
      expect(decoded.venue, isNull);
      expect(decoded.venueId, isNull);
      expect(decoded.band, isNull);
      expect(decoded.caller, isNull);
      expect(decoded.dancerLevel, isNull);
    });

    test('rejects a future schema version', () {
      expect(
        () => decodeProgramDraft(
          '{"v":999,"title":"x","notes":"","status":'
          '"draft","hideAlternates":false,"slots":[]}',
        ),
        throwsFormatException,
      );
    });

    test('rejects a below-range schema version', () {
      expect(
        () => decodeProgramDraft(
          '{"v":0,"title":"x","notes":"","status":'
          '"draft","hideAlternates":false,"slots":[]}',
        ),
        throwsFormatException,
      );
    });

    test('tolerates unknown top-level keys (forward-compat)', () {
      final decoded = decodeProgramDraft(
        '{"v":1,"title":"x","notes":"","status":"draft",'
        '"hideAlternates":false,"slots":[],"somethingNew":42}',
      );
      expect(decoded.title, 'x');
    });

    test('rejects a wrong-typed field', () {
      expect(
        () => decodeProgramDraft(
          '{"v":1,"title":123,"notes":"","status":"draft",'
          '"hideAlternates":false,"slots":[]}',
        ),
        throwsFormatException,
      );
    });

    test('rejects an unknown status enum value', () {
      expect(
        () => decodeProgramDraft(
          '{"v":1,"title":"x","notes":"","status":"bogus",'
          '"hideAlternates":false,"slots":[]}',
        ),
        throwsFormatException,
      );
    });

    test('rejects a slot with neither danceId nor text as FormatException', () {
      // The ProgramSlot constructor would throw an ArgumentError; the codec must
      // surface it as a FormatException so the load path treats it as corrupt.
      expect(
        () => decodeProgramDraft(
          '{"v":1,"title":"x","notes":"","status":"draft",'
          '"hideAlternates":false,"slots":[{"id":"s1","position":0,'
          '"isAlt":false}]}',
        ),
        throwsFormatException,
      );
    });

    test(
      'decodes a value round-tripped through a settings repository',
      () async {
        final repos = openTestRepositories();
        await repos.settings.set(
          'program_editor_draft:new',
          encodeProgramDraft(_draft(title: 'Via Settings')),
        );
        // SettingsRepository.get returns the raw JSON string; decode handles it.
        final decoded = decodeProgramDraft(
          await repos.settings.get('program_editor_draft:new'),
        );
        expect(decoded.title, 'Via Settings');
      },
    );
  });

  // -------------------------------------------------------------------------
  // Widget: autosave / restore
  // -------------------------------------------------------------------------
  group('Program autosave drafts', () {
    testWidgets('draft saved after a title edit (debounced)', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Draft Title',
      );
      // Before the debounce fires, no draft yet.
      expect(
        await repos.settings.contains('program_editor_draft:new'),
        isFalse,
      );

      await tester.pump(const Duration(milliseconds: 600));
      expect(await repos.settings.contains('program_editor_draft:new'), isTrue);

      final decoded = decodeProgramDraft(
        await repos.settings.get('program_editor_draft:new'),
      );
      expect(decoded.title, 'Draft Title');
    });

    testWidgets('structural change (insert break) autosaves the set list', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.tap(find.byKey(const ValueKey('insert-break-slot')));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(milliseconds: 600));
      expect(await repos.settings.contains('program_editor_draft:new'), isTrue);
      final decoded = decodeProgramDraft(
        await repos.settings.get('program_editor_draft:new'),
      );
      expect(decoded.slots, hasLength(1));
      expect(decoded.slots.single.isBreak, isTrue);
    });

    testWidgets(
      'interrupted build restores the title and set list from a draft',
      (tester) async {
        final repos = openTestRepositories();
        // Simulate a prior session killed mid-build: a draft already on disk.
        await repos.settings.set(
          'program_editor_draft:new',
          encodeProgramDraft(
            _draft(
              title: 'Recovered Program',
              slots: [
                _textSlot('s1', 0, 'Grand March'),
                _textSlot('s2', 1, Program.breakSlotText),
              ],
            ),
          ),
        );

        await _pumpEditor(tester, repos);

        // The restore prompt appears.
        expect(find.text('Unsaved draft'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('program-draft-restore')));
        await tester.pumpAndSettle();

        // Title and the in-progress set list are back.
        expect(_titleText(tester), 'Recovered Program');
        expect(find.text('Grand March'), findsOneWidget);
        // The draft is preserved (still unsaved work).
        expect(
          await repos.settings.contains('program_editor_draft:new'),
          isTrue,
        );
      },
    );

    testWidgets('discarding the prompt removes the draft and starts clean', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        'program_editor_draft:new',
        encodeProgramDraft(_draft(title: 'Should Not Show')),
      );

      await _pumpEditor(tester, repos);
      await tester.tap(find.byKey(const ValueKey('program-draft-discard')));
      await tester.pumpAndSettle();

      expect(_titleText(tester), '');
      expect(
        await repos.settings.contains('program_editor_draft:new'),
        isFalse,
      );
    });

    testWidgets('explicit save clears the draft', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'To Save',
      );
      await tester.tap(find.byKey(const ValueKey('insert-break-slot')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(await repos.settings.contains('program_editor_draft:new'), isTrue);

      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();

      expect(
        await repos.settings.contains('program_editor_draft:new'),
        isFalse,
      );
      // The program was actually persisted.
      final all = await repos.programs.listAll();
      expect(all.single.title, 'To Save');
    });

    testWidgets('draft is keyed by programId for an existing program', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program(id: 'p1', title: 'On Disk', slots: [_textSlot('s0', 0, 'x')]),
      );
      await repos.settings.set(
        'program_editor_draft:p1',
        encodeProgramDraft(
          _draft(
            title: 'Draft Override',
            slots: [_textSlot('s1', 0, 'Reel of Eight')],
          ),
        ),
      );

      await _pumpEditor(tester, repos, programId: 'p1');

      expect(find.text('Unsaved draft'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('program-draft-restore')));
      await tester.pumpAndSettle();

      expect(_titleText(tester), 'Draft Override');
      expect(find.text('Reel of Eight'), findsOneWidget);
    });
  });
}
