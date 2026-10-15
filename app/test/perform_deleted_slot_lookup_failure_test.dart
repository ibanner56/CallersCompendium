import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

class _RecordingSink implements CrashLogSink {
  final List<String> sources = [];

  @override
  void record(Object error, StackTrace? stack, {required String source}) =>
      sources.add(source);
}

class _ThrowingDances extends Fake implements DanceRepository {
  @override
  Future<Dance?> getById(
    String id, {
    bool includeDeleted = false,
    bool includeDeletedAuthors = false,
  }) async => throw StateError('dance read failed');
}

class _DeletedDance extends Fake implements DanceRepository {
  @override
  Future<Dance?> getById(
    String id, {
    bool includeDeleted = false,
    bool includeDeletedAuthors = false,
  }) async => Dance(
    id: id,
    title: 'Gone Dance',
    authorIds: const ['c1'],
    createdAt: _now,
    updatedAt: _now,
  );
}

class _ThrowingChoreographers extends Fake implements ChoreographerRepository {
  @override
  Future<List<Choreographer>> listAll({bool includeDeleted = false}) async =>
      throw StateError('choreographer read failed');
}

/// Perform resolves soft-deleted slot dances before it opens (CS-06, #1486,
/// #1661). That lookup is a convenience: before it existed Perform opened
/// without it, so a failed read must not stop the caller reaching Perform
/// mid-gig. It is logged and the overrides degrade instead.
void main() {
  late _RecordingSink sink;
  late CompendiumRepositories repos;
  late CollectionData data;
  final program = Program(
    id: 'p1',
    title: 'Barn Dance',
    status: ProgramStatus.draft,
    slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
    createdAt: _now,
    updatedAt: _now,
  );

  setUp(() async {
    sink = _RecordingSink();
    installCaughtErrorLog(sink);
    repos = openTestRepositories();
    data = await CollectionData.load(repos);
  });

  tearDown(resetCaughtErrorLogForTesting);

  test('a failed dance lookup gives no overrides and is logged', () async {
    final result = await resolveDeletedSlotDances(
      _ThrowingDances(),
      repos.choreographers,
      program,
      data,
    );
    expect(result.dances, isEmpty);
    expect(result.authorNames, isEmpty);
    expect(sink.sources, ['perform_program_screen.resolveDeletedSlotDances']);
  });

  test(
    'a failed author lookup keeps the dances without author names',
    () async {
      final result = await resolveDeletedSlotDances(
        _DeletedDance(),
        _ThrowingChoreographers(),
        program,
        data,
      );
      expect(result.dances.keys, ['d1']);
      expect(result.authorNames, isEmpty);
      expect(sink.sources, ['perform_program_screen.resolveDeletedSlotDances']);
    },
  );
}
