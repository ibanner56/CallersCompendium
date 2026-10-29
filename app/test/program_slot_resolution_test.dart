import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/widgets/program_matrix_table.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title, {List<Figure> figures = const []}) =>
    Dance(
      id: id,
      title: title,
      figures: figures,
      status: DanceStatus.active,
      createdAt: _now,
      updatedAt: _now,
    );

Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: dialect, child: child!),
      ),
      home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _createProgram(
  CompendiumRepositories repos,
  List<ProgramSlot> slots,
) => repos.programs.create(
  Program(
    id: 'p1',
    title: 'Barn Dance',
    status: ProgramStatus.draft,
    slots: slots,
    createdAt: _now,
    updatedAt: _now,
  ),
);

/// The ordinal column of every slot row, top to bottom.
List<String> _ordinals(WidgetTester tester, int count) => [
  for (var i = 0; i < count; i++)
    tester.widget<Text>(find.byKey(ValueKey('slot-$i-ordinal'))).data!,
];

/// The messages of the accessibility events in [_events], read when used.
class _Announcements {
  _Announcements(this._events);
  final List<Map<Object?, Object?>> _events;

  List<Object?> get messages => _events
      .map((e) => e['data'])
      .whereType<Map<Object?, Object?>>()
      .map((data) => data['message'])
      .toList();
}

/// Records every accessibility announcement made while the test runs.
_Announcements _recordAnnouncements() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final events = <Map<Object?, Object?>>[];
  messenger.setMockMessageHandler(SystemChannels.accessibility.name, (
    ByteData? message,
  ) async {
    final decoded = SystemChannels.accessibility.codec.decodeMessage(message);
    if (decoded is Map) events.add(decoded.cast());
    return null;
  });
  addTearDown(
    () => messenger.setMockMessageHandler(
      SystemChannels.accessibility.name,
      null,
    ),
  );
  return _Announcements(events);
}

/// The program builder resolves every slot the way Perform does (GIG-11),
/// counts and numbers dances the way the set list does (GIG-10), and promotes
/// an alternate when its primary is cut or moved (LIFE-10). Kept out of
/// `program_editor_screen_test.dart` so it cannot conflict with other edits to
/// that file.
void main() {
  group('a dance in Recently deleted (GIG-11)', () {
    testWidgets('keeps its title in the slot list, marked as deleted, with no '
        'preview or details', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Gone Dance'));
      await _createProgram(repos, [
        ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
      ]);
      await repos.dances.softDelete('d1', at: _now);

      await _pumpEditor(tester, repos);

      expect(find.text('Gone Dance (deleted dance)'), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-0-view-details')), findsNothing);
    });

    testWidgets('keeps its figures in the matrix', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(
          'd1',
          'Gone Dance',
          figures: [
            Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
          ],
        ),
      );
      await _createProgram(repos, [
        ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
      ]);
      await repos.dances.softDelete('d1', at: _now);

      await _pumpEditor(tester, repos);
      await tester.tap(find.byKey(const ValueKey('program-matrix-tab')));
      await tester.pumpAndSettle();

      final matrix = tester
          .widget<ProgramMatrixTable>(find.byType(ProgramMatrixTable))
          .matrix;
      expect(matrix.rows.single.title, 'Gone Dance (deleted dance)');
      expect(matrix.rows.single.presentMoveIds, isNotEmpty);
    });
  });

  testWidgets('the slot heading counts planned dances and the break is '
      'unnumbered (GIG-10)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Petronella'));
    await repos.dances.create(_dance('d2', 'Chorus Jig'));
    await _createProgram(repos, [
      ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
      ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
      ProgramSlot(id: 's3', position: 2, text: Program.breakSlotText),
      ProgramSlot(id: 's4', position: 3, text: 'Waltz'),
      ProgramSlot(id: 's5', position: 4, danceId: 'd2'),
    ]);

    await _pumpEditor(tester, repos);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('program-slots-dance-count')))
          .data,
      '3 dances',
    );
    expect(_ordinals(tester, 5), ['1', 'ALT', '', '2', '3']);
  });

  testWidgets('the matrix toggles show their state (UX7-3d)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Petronella'));
    await _createProgram(repos, [
      ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
    ]);

    await _pumpEditor(tester, repos);
    await tester.tap(find.byKey(const ValueKey('program-matrix-tab')));
    await tester.pumpAndSettle();

    IconButton toggle(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    const alternates = 'program-matrix-toggle-alternates';
    const phrases = 'program-matrix-toggle-phrases';
    // Alternates are shown and phrases hidden by default.
    expect(toggle(alternates).isSelected, isTrue);
    expect(toggle(phrases).isSelected, isFalse);
    expect(toggle(alternates).selectedIcon, isNotNull);
    expect(toggle(phrases).selectedIcon, isNotNull);

    await tester.tap(find.byKey(const ValueKey(alternates)));
    await tester.tap(find.byKey(const ValueKey(phrases)));
    await tester.pumpAndSettle();

    expect(toggle(alternates).isSelected, isFalse);
    expect(toggle(phrases).isSelected, isTrue);
  });

  group(
    'cutting or moving a primary promotes its first alternate (LIFE-10)',
    () {
      Future<void> seed(CompendiumRepositories repos) async {
        await repos.dances.create(_dance('d1', 'Petronella'));
        await repos.dances.create(_dance('d2', 'Chorus Jig'));
        await repos.dances.create(_dance('d3', 'Rory O\'More'));
        await repos.dances.create(_dance('d4', 'Hull\'s Victory'));
        await _createProgram(repos, [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
          ProgramSlot(id: 's3', position: 2, danceId: 'd3', isAlt: true),
          ProgramSlot(id: 's4', position: 3, danceId: 'd4'),
        ]);
      }

      testWidgets('cut', (tester) async {
        final announcements = _recordAnnouncements();
        final repos = openTestRepositories();
        await seed(repos);
        await _pumpEditor(tester, repos);
        expect(_ordinals(tester, 4), ['1', '2', 'ALT', '3']);

        await tester.tap(find.byKey(const ValueKey('slot-1-remove')));
        await tester.pumpAndSettle();

        // Rory O'More takes Chorus Jig's place instead of becoming an
        // alternate of Petronella.
        expect(_ordinals(tester, 3), ['1', '2', '3']);
        expect(
          announcements.messages,
          contains('Removed Chorus Jig. Rory O\'More takes its place.'),
        );
      });

      testWidgets('move', (tester) async {
        final announcements = _recordAnnouncements();
        final repos = openTestRepositories();
        await seed(repos);
        await _pumpEditor(tester, repos);

        await tester.tap(find.byKey(const ValueKey('slot-1-move-up')));
        await tester.pumpAndSettle();

        // Chorus Jig now leads, and its alternate stays at its old position as
        // a dance in its own right rather than joining Petronella.
        expect(_ordinals(tester, 4), ['1', '2', '3', '4']);
        expect(
          announcements.messages,
          contains('Slot moved up. Rory O\'More takes its place.'),
        );
      });
    },
  );
}
