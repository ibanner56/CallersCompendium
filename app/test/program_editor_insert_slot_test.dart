// "Add a dance before" / "Add a dance after" in the program builder (#2339):
// the slot menu items, the wide-screen banner and highlight, the narrow-screen
// picker title, where the dance lands with alternates, the online-import path,
// the one-shot rule and the screen-reader announcement.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

/// A primary with two alternates between two lone primaries and a break.
List<ProgramSlot> _groupedSlots() => [
  ProgramSlot(id: 'a', position: 0, danceId: 'd-a'),
  ProgramSlot(id: 'b', position: 1, danceId: 'd-b'),
  ProgramSlot(id: 'b-alt1', position: 2, danceId: 'd-b1', isAlt: true),
  ProgramSlot(id: 'b-alt2', position: 3, danceId: 'd-b2', isAlt: true),
  ProgramSlot(id: 'brk', position: 4, text: Program.breakSlotText),
  ProgramSlot(id: 'c', position: 5, danceId: 'd-c'),
];

Future<CompendiumRepositories> _seed() async {
  final repos = openTestRepositories();
  for (final (id, title) in [
    ('d-a', 'Dance A'),
    ('d-b', 'Chorus Jig'),
    ('d-b1', 'Backup One'),
    ('d-b2', 'Backup Two'),
    ('d-c', 'Dance C'),
    ('d-new', "Rory O'More"),
    ('d-next', 'Petronella'),
  ]) {
    await repos.dances.create(_dance(id, title));
  }
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Night',
      slots: _groupedSlots(),
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return repos;
}

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  Size size = const Size(1200, 2000),
  OnlineSearchService? callersBoxOnline,
}) async {
  // The view, not setSurfaceSize: the slot list's compact rule reads
  // MediaQuery.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: ProgramEditorScreen(
        programId: 'p1',
        onSaved: (_) {},
        callersBoxOnline: callersBoxOnline,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Records the screen-reader announcements sent while the test runs.
List<String> _recordAnnouncements() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final messages = <String>[];
  messenger.setMockMessageHandler(SystemChannels.accessibility.name, (
    ByteData? message,
  ) async {
    final decoded = SystemChannels.accessibility.codec.decodeMessage(message);
    if (decoded is Map && decoded['data'] is Map) {
      final text = (decoded['data'] as Map)['message'];
      if (text is String) messages.add(text);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMessageHandler(
      SystemChannels.accessibility.name,
      null,
    ),
  );
  return messages;
}

Future<void> _chooseFromSlotMenu(
  WidgetTester tester,
  int index,
  String action,
) async {
  await tester.tap(find.byKey(ValueKey('slot-$index-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('slot-$index-$action')));
  await tester.pumpAndSettle();
}

Future<List<ProgramSlot>> _saveAndRead(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.tap(find.byKey(const ValueKey('save-program')));
  await tester.pumpAndSettle();
  final saved = await repos.programs.getById('p1');
  return saved!.slots;
}

/// Slot ids with the minted id of an added dance replaced by its dance id.
List<String> _order(List<ProgramSlot> slots) => [
  for (final slot in slots)
    switch (slot.danceId) {
      'd-new' => 'NEW',
      'd-next' => 'NEXT',
      'imported' => 'IMPORTED',
      _ => slot.id,
    },
];

class _OnlineService implements OnlineSearchService {
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
    final dance = _dance('', result.name);
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
    List<String> defaultTagIds = const [],
  }) async {
    await repos.dances.create(_dance('imported', 'Imported Dance'));
    return const OnlineImportResult(
      kind: OnlineImportKind.created,
      title: 'Imported Dance',
      danceId: 'imported',
    );
  }
}

void main() {
  group('wide screen: banner beside the program', () {
    testWidgets("after an alternate lands after its group's last alternate, "
        'is announced, and the next add goes to the end', (tester) async {
      final announcements = _recordAnnouncements();
      final repos = await _seed();
      await _pump(tester, repos);
      expect(find.byKey(const ValueKey('insertion-banner')), findsNothing);

      // b-alt1's menu: the same position as its primary's.
      await _chooseFromSlotMenu(tester, 2, 'add-after');

      final banner = find.byKey(const ValueKey('insertion-banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(
          of: banner,
          matching: find.text('Adding after Chorus Jig'),
        ),
        findsOneWidget,
      );
      // The whole target group is highlighted, and nothing else.
      for (final id in ['b', 'b-alt1', 'b-alt2']) {
        expect(
          find.byKey(ValueKey('slot-$id-insertion-target')),
          findsOneWidget,
        );
      }
      for (final id in ['a', 'brk', 'c']) {
        expect(find.byKey(ValueKey('slot-$id-insertion-target')), findsNothing);
      }
      expect(announcements, contains('Adding after Chorus Jig'));

      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();

      expect(announcements, contains("Added Rory O'More after Chorus Jig."));
      // One-shot: the banner and highlight are gone.
      expect(find.byKey(const ValueKey('insertion-banner')), findsNothing);
      expect(
        find.byKey(const ValueKey('slot-b-insertion-target')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('picker-add-d-next')));
      await tester.pumpAndSettle();
      expect(announcements, contains('Added Petronella to program.'));

      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), [
        'a',
        'b',
        'b-alt1',
        'b-alt2',
        'NEW',
        'brk',
        'c',
        'NEXT',
      ]);
      expect(slots.map((s) => s.position), [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(slots[4].isAlt, isFalse);
      // The alternates still belong to Chorus Jig.
      expect(Program.alternateGroupsForSlots(slots), [0, 1, 1, 1, 2, 3, 4, 5]);
    });

    testWidgets('before an alternate lands ahead of its whole group', (
      tester,
    ) async {
      final repos = await _seed();
      await _pump(tester, repos);

      await _chooseFromSlotMenu(tester, 3, 'add-before');
      expect(find.text('Adding before Chorus Jig'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();

      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), ['a', 'NEW', 'b', 'b-alt1', 'b-alt2', 'brk', 'c']);
      expect(Program.alternateGroupsForSlots(slots), [0, 1, 2, 2, 2, 3, 4]);
    });

    testWidgets('a break is a group of one', (tester) async {
      final repos = await _seed();
      await _pump(tester, repos);

      await _chooseFromSlotMenu(tester, 4, 'add-before');
      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();

      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), ['a', 'b', 'b-alt1', 'b-alt2', 'NEW', 'brk', 'c']);
    });

    testWidgets('Cancel ends the insertion without adding, and is at least '
        '24 x 24 and keyboard-operable', (tester) async {
      final announcements = _recordAnnouncements();
      final repos = await _seed();
      await _pump(tester, repos);

      await _chooseFromSlotMenu(tester, 1, 'add-before');
      final cancel = find.byKey(const ValueKey('insertion-banner-cancel'));
      final size = tester.getSize(cancel);
      expect(size.width, greaterThanOrEqualTo(24));
      expect(size.height, greaterThanOrEqualTo(24));

      // Keyboard: focus Cancel and press Enter.
      Focus.of(
        tester.element(
          find.descendant(of: cancel, matching: find.byType(Text)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('insertion-banner')), findsNothing);
      expect(announcements, contains('Canceled. New dances go at the end.'));
      final unchanged = await repos.programs.getById('p1');
      expect(_order(unchanged!.slots), _order(_groupedSlots()));

      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();
      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), ['a', 'b', 'b-alt1', 'b-alt2', 'brk', 'c', 'NEW']);
    });

    testWidgets('cutting the target ends the insertion', (tester) async {
      final repos = await _seed();
      await _pump(tester, repos);

      await _chooseFromSlotMenu(tester, 5, 'add-before');
      expect(find.byKey(const ValueKey('insertion-banner')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('slot-5-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insertion-banner')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();
      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), ['a', 'b', 'b-alt1', 'b-alt2', 'brk', 'NEW']);
    });

    testWidgets("an alternate's insertion follows its primary: cutting the "
        'alternate keeps it, cutting the primary ends it and says so', (
      tester,
    ) async {
      final announcements = _recordAnnouncements();
      final repos = await _seed();
      await _pump(tester, repos);

      // b-alt1's menu targets the group, named by its primary b.
      await _chooseFromSlotMenu(tester, 2, 'add-after');
      final banner = find.byKey(const ValueKey('insertion-banner'));
      await tester.tap(find.byKey(const ValueKey('slot-2-remove')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: banner,
          matching: find.text('Adding after Chorus Jig'),
        ),
        findsOneWidget,
      );

      // Cutting the primary b promotes b-alt2, but ends the insertion: the
      // banner never names a dance that is no longer in the program.
      await tester.tap(find.byKey(const ValueKey('slot-1-remove')));
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
      expect(announcements, contains('Canceled. New dances go at the end.'));

      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();
      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), ['a', 'b-alt2', 'brk', 'c', 'NEW']);
    });

    testWidgets('dropping below two-pane while the banner is up ends the '
        'insertion and says so', (tester) async {
      final announcements = _recordAnnouncements();
      final repos = await _seed();
      await _pump(tester, repos);

      await _chooseFromSlotMenu(tester, 5, 'add-before');
      expect(find.byKey(const ValueKey('insertion-banner')), findsOneWidget);
      tester.view.physicalSize = const Size(600, 2000);
      await tester.pumpAndSettle();
      expect(announcements, contains('Canceled. New dances go at the end.'));

      tester.view.physicalSize = const Size(1200, 2000);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insertion-banner')), findsNothing);
    });

    testWidgets('a dance imported from online search lands at the target', (
      tester,
    ) async {
      final announcements = _recordAnnouncements();
      final repos = await _seed();
      await _pump(tester, repos, callersBoxOnline: _OnlineService());

      // From an alternate's menu, so a raw-index insert would split the group.
      await _chooseFromSlotMenu(tester, 2, 'add-after');
      final picker = find.byKey(const ValueKey('inline-picker'));
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

      expect(announcements, contains('Added Imported Dance after Chorus Jig.'));
      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), [
        'a',
        'b',
        'b-alt1',
        'b-alt2',
        'IMPORTED',
        'brk',
        'c',
      ]);
    });
  });

  group('narrow screen: the picker sheet', () {
    testWidgets('is titled with the target, closes on the first dance, and '
        'the next Add dance goes to the end', (tester) async {
      final announcements = _recordAnnouncements();
      final repos = await _seed();
      await _pump(tester, repos, size: const Size(600, 2000));

      await _chooseFromSlotMenu(tester, 2, 'add-before');
      expect(find.byKey(const ValueKey('sheet-picker')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('picker-sheet-title')))
            .data,
        'Add before Chorus Jig',
      );
      // The title takes the row's free width beside the close button, not
      // half of it, so a long target name is not cut short.
      expect(
        tester.getSize(find.byKey(const ValueKey('picker-sheet-title'))).width,
        greaterThan(400),
      );
      expect(find.byKey(const ValueKey('insertion-banner')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sheet-picker')), findsNothing);
      expect(announcements, contains("Added Rory O'More before Chorus Jig."));

      await tester.tap(find.byKey(const ValueKey('add-dance-slot')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('picker-sheet-title')))
            .data,
        'Add a dance',
      );
      await tester.tap(find.byKey(const ValueKey('picker-add-d-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-sheet-close')));
      await tester.pumpAndSettle();

      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots), [
        'a',
        'NEW',
        'b',
        'b-alt1',
        'b-alt2',
        'brk',
        'c',
        'NEXT',
      ]);
    });

    testWidgets('closing the sheet without a dance ends the insertion', (
      tester,
    ) async {
      final repos = await _seed();
      await _pump(tester, repos, size: const Size(600, 2000));

      await _chooseFromSlotMenu(tester, 1, 'add-after');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('picker-sheet-title')))
            .data,
        'Add after Chorus Jig',
      );
      await tester.tap(find.byKey(const ValueKey('picker-sheet-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('slot-b-insertion-target')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('add-dance-slot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-add-d-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-sheet-close')));
      await tester.pumpAndSettle();

      final slots = await _saveAndRead(tester, repos);
      expect(_order(slots).last, 'NEW');
    });
  });
}
