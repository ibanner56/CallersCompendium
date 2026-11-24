// A measurement, not a check: how long the programs list takes with many
// programs of mixed types (ADR-006 program types). Seeds PROGRAMS_BENCH
// programs (16 slots each, a third contra, a third English, a third both) and
// times, through the real screen and an in-memory database:
//
// * opening the list until it settles;
// * the first chip tap's frame, and clearing it until it settles;
// * choosing a type chip;
// * switching to Includes;
// * a dance edit that changes a type, until the list has re-read and settled.
//
// Skipped unless PROGRAMS_BENCH names how many programs to seed:
//
//     PROGRAMS_BENCH=1000 flutter test test/programs_list_bench_test.dart
//
// The figures are wall-clock times in a debug (JIT) test run, so they read
// high next to a release build and vary with the machine; compare them with
// each other, not with a budget. Nothing is asserted on them. The checks that
// gate are in programs_list_screen_test.dart ("the list builds only the rows
// on screen").
import 'dart:io';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

void main() {
  final count = int.tryParse(Platform.environment['PROGRAMS_BENCH'] ?? '');
  final now = DateTime.utc(2026, 1, 1);

  testWidgets(
    'programs list with ${count ?? 'PROGRAMS_BENCH'} programs',
    (tester) async {
      final n = count!;
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      await tester.runAsync(() async {
        for (var i = 0; i < 48; i++) {
          await repos.dances.create(
            Dance(
              id: 'd$i',
              title: 'Dance $i',
              form: i < 24 ? DanceForm.contra : DanceForm.ecd,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
        for (var p = 0; p < n; p++) {
          // A third contra, a third English, a third both.
          final kind = p % 3;
          String danceFor(int slot) => switch (kind) {
            0 => 'd${slot % 24}',
            1 => 'd${24 + slot % 24}',
            _ => slot.isEven ? 'd${slot % 24}' : 'd${24 + slot % 24}',
          };
          await repos.programs.create(
            Program(
              id: 'p$p',
              title: 'Program ${p.toString().padLeft(4, '0')}',
              slots: [
                for (var s = 0; s < 16; s++)
                  ProgramSlot(id: 'p$p-s$s', position: s, danceId: danceFor(s)),
              ],
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      });

      final results = <String, Duration>{};
      Future<void> timed(String label, Future<void> Function() body) async {
        final watch = Stopwatch()..start();
        await body();
        watch.stop();
        results[label] = watch.elapsed;
      }

      Future<void> settle() async {
        // Let the database's stream deliver, then lay out.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
      }

      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await timed('open the list', () async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            builder: (context, child) =>
                RepositoriesScope(repositories: repos, child: child!),
            home: const ProgramsListScreen(),
          ),
        );
        await settle();
      });
      expect(find.byType(ProgramListTile), findsWidgets);
      final built = tester
          .widgetList(find.byType(ProgramListTile, skipOffstage: false))
          .length;

      // The first tap also pays for first use (hit testing, the chip's
      // animation), so it reads high at any size.
      await timed('first chip tap, one frame', () async {
        await tester.tap(find.byKey(const ValueKey('programs-form-contra')));
        await tester.pump();
      });
      await tester.pumpAndSettle();
      var frames = 0;
      await timed('clear it, until it settles', () async {
        await tester.tap(find.byKey(const ValueKey('programs-form-contra')));
        frames = await tester.pumpAndSettle();
      });
      final settleFrames = frames;
      await timed('choose the Contra chip', () async {
        await tester.tap(find.byKey(const ValueKey('programs-form-contra')));
        await tester.pumpAndSettle();
      });
      await timed('switch to Includes', () async {
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('programs-form-match')),
            matching: find.text('Includes'),
          ),
        );
        await tester.pumpAndSettle();
      });
      await timed('a dance changes type, until the list settles', () async {
        final dance = (await tester.runAsync(
          () => repos.dances.getById('d0'),
        ))!;
        await tester.runAsync(
          () => repos.dances.update(dance.copyWith(form: DanceForm.ecd)),
        );
        await settle();
      });

      // ignore: avoid_print
      print(
        'Programs list, $n programs x 16 slots ($built rows built; a chip '
        'settles in $settleFrames frames):',
      );
      for (final MapEntry(:key, :value) in results.entries) {
        // ignore: avoid_print
        print('  ${key.padRight(48)} ${value.inMilliseconds} ms');
      }
    },
    // testWidgets takes no skip reason; the name says how to run it.
    skip: count == null,
  );
}
