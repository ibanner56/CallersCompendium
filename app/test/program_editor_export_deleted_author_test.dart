import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/dance_share_fields_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// Guards [ProgramEditorScreen]'s export menu: a slot dance in Recently deleted
/// whose author is also in Recently deleted still credits that author by name
/// in the text export, as the program summary does (the summary's twin is in
/// `program_summary_perform_deleted_dance_test.dart`).
void main() {
  testWidgets(
    'the program editor copied set list names the author of a soft-deleted dance whose '
    'choreographer is also soft-deleted',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Gene Hubert'),
      );
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'c2', name: 'Ann Live'),
      );
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Gone Dance',
          authorIds: const ['c1', 'c2'],
          figures: const [],
          status: DanceStatus.active,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      await repos.dances.softDelete('d1', at: _now);
      await repos.choreographers.delete('c1', at: _now);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
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
          home: DanceShareFieldsScope(
            notifier: ValueNotifier(DanceShareField.allExceptTunes),
            child: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      // In credit order, the trashed author first.
      expect(copied, contains('by Gene Hubert, Ann Live'));
    },
  );

  testWidgets(
    'the program editor copied set list credits a restored dance from the '
    'collection, not from its stale deleted record',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Gene Hubert'),
      );
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'c2', name: 'Ann Live'),
      );
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Gone Dance',
          authorIds: const ['c1', 'c2'],
          figures: const [],
          status: DanceStatus.active,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      await repos.dances.softDelete('d1', at: _now);
      await repos.choreographers.delete('c1', at: _now);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
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
          home: DanceShareFieldsScope(
            notifier: ValueNotifier(DanceShareField.allExceptTunes),
            child: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The dance comes back from Recently deleted with a different author
      // while the editor is open.
      await repos.dances.restore('d1', at: _now.add(const Duration(days: 1)));
      final restored = (await repos.dances.getById('d1'))!;
      await repos.dances.update(
        restored.copyWith(
          authorIds: const ['c2'],
          updatedAt: _now.add(const Duration(days: 2)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy set list'));
      await tester.pumpAndSettle();

      expect(copied, contains('by Ann Live'));
      expect(copied, isNot(contains('Gene Hubert')));
    },
  );
}
