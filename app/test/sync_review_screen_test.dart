import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/sync_review_screen.dart';
import 'package:compendium_core/testing.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _stamp = DateTime.utc(2025, 1, 2, 12);

class _FailReviewQueueReads extends drift.QueryInterceptor {
  bool fail = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (fail && statement.contains('review_queue')) {
      return Future.error(StateError('injected review queue read failure'));
    }
    return executor.runSelect(statement, args);
  }
}

SyncRecordBlob _tombstone({required String id, required String name}) =>
    SyncRecordBlob(
      kind: SyncRecordKind.choreographer,
      id: id,
      updatedAt: _stamp.add(const Duration(minutes: 1)),
      deletedAt: _stamp.add(const Duration(minutes: 1)),
      existenceAt: _stamp.add(const Duration(minutes: 1)),
      body: syncBodyForEntity(
        SyncRecordKind.choreographer,
        Choreographer(id: id, name: name),
      ),
    );

Future<void> _enqueue(
  CompendiumRepositories repos, {
  required String localId,
  required SyncRecordBlob candidate,
  String reason = syncBaselineAbsenceTombstoneReason,
}) async {
  await repos.syncLocal.enqueueReview(
    kind: candidate.kind,
    recordId: localId,
    counterpartId: candidate.id,
    reason: reason,
    candidateBlob: encodeSyncRecordBlob(candidate),
    candidateHash: sha256Hex(encodeSyncRecordBlobUtf8(candidate)),
    localHash: (await CompendiumSyncStorage(
      repos,
    ).snapshot()).local[(kind: candidate.kind, recordId: localId)]?.wireHash,
    queuedAt: _stamp.add(const Duration(minutes: 2)),
  );
}

Future<void> _seedActionable(CompendiumRepositories repos) async {
  final _ = await repos.choreographers.upsert(
    Choreographer(id: 'local-author', name: 'Shared author'),
    at: _stamp,
  );
  await _enqueue(
    repos,
    localId: 'local-author',
    candidate: _tombstone(id: 'peer-author', name: 'Shared author'),
  );
}

Future<void> _seedDanceAmbiguity(CompendiumRepositories repos) async {
  await repos.dances.create(
    Dance(
      id: 'a-left',
      title: 'Shared dance',
      figures: [
        testFigure(move: 'balance', params: const {'hand': 'left'}),
      ],
      createdAt: _stamp,
      updatedAt: _stamp,
    ),
  );
  await repos.dances.create(
    Dance(
      id: 'b-right',
      title: 'The shared dance',
      figures: [
        testFigure(move: 'balance', params: const {'hand': 'right'}),
      ],
      createdAt: _stamp,
      updatedAt: _stamp,
    ),
  );
  await CompendiumSyncStorage(repos).deduplicateFreshAttach();
}

/// Seeds a §6.6 step-1 rename collision through the production apply path.
///
/// Hand-enqueueing would not do: a step-1 row's `record_id` is the candidate's
/// own id and its `counterpart_id` is the other local row, the reverse of a
/// tombstone row, so a hand-written row would only ever agree with whatever
/// the screen already believed.
Future<void> _seedRenameCollision(CompendiumRepositories repos) async {
  for (final entry in const [
    (id: 'aaa-author', name: 'Alice Smith'),
    (id: 'zzz-author', name: 'Sam Jones'),
  ]) {
    final _ = await repos.choreographers.upsert(
      Choreographer(
        id: entry.id,
        name: entry.name,
        email: '${entry.id}@example.com',
      ),
      at: _stamp,
    );
  }
  final renameStamp = _stamp.add(const Duration(minutes: 1));
  await const SyncApplyEngine().apply(
    candidates: [
      SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: 'aaa-author',
          updatedAt: renameStamp,
          deletedAt: null,
          existenceAt: renameStamp,
          body: syncBodyForEntity(
            SyncRecordKind.choreographer,
            Choreographer(id: 'aaa-author', name: 'Sam Jones'),
          ),
        ),
      ),
    ],
    storage: CompendiumSyncStorage(repos),
  );
}

/// Seeds a §6.10 fuzzy near-duplicate pair: above the score threshold, with
/// titles that are *not* equal, so keeping both needs no rename.
Future<void> _seedFuzzyDuplicate(CompendiumRepositories repos) async {
  final _ = await repos.choreographers.upsert(
    Choreographer(id: 'shared-author', name: 'Sam Jones'),
    at: _stamp,
  );
  for (final entry in const [
    (id: 'a-rory', title: "Rory O'More", hand: 'left'),
    (id: 'z-rory', title: "Rory O'Moore", hand: 'right'),
  ]) {
    await repos.dances.create(
      Dance(
        id: entry.id,
        title: entry.title,
        authorIds: const ['shared-author'],
        figures: [testFigure(move: 'balance', params: {'hand': entry.hand})],
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
    );
  }
  await CompendiumSyncStorage(repos).deduplicateFreshAttach();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: const SyncReviewScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the empty persisted decision state', (tester) async {
    final repos = openTestRepositories();

    await _pumpScreen(tester, repos);

    expect(find.byKey(const ValueKey('sync-review-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-review-list')), findsNothing);
  });

  testWidgets('merges an actionable decision and reloads the queue', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _seedActionable(repos);

    await _pumpScreen(tester, repos);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'sync-review-merge-choreographer:local-author:peer-author',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync-review-empty')), findsOneWidget);
  });

  testWidgets('validates and completes a Keep both decision', (tester) async {
    final repos = openTestRepositories();
    await _seedActionable(repos);

    await _pumpScreen(tester, repos);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'sync-review-keep-both-choreographer:local-author:peer-author',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('sync-review-keep-both-confirm')),
    );
    await tester.pump();
    expect(find.text('Enter a name.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Shared author');
    await tester.tap(
      find.byKey(const ValueKey('sync-review-keep-both-confirm')),
    );
    await tester.pump();
    expect(find.text('Choose a different name.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Retained author');
    await tester.tap(
      find.byKey(const ValueKey('sync-review-keep-both-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync-review-empty')), findsOneWidget);
  });

  testWidgets('shows actions for a live dance ambiguity', (tester) async {
    final repos = openTestRepositories();
    await _seedDanceAmbiguity(repos);

    await _pumpScreen(tester, repos);

    expect(
      find.text('Live dances have the same title but different choreography.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sync-review-merge-dance:a-left:b-right')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sync-review-keep-both-dance:a-left:b-right')),
      findsOneWidget,
    );
  });

  testWidgets('keeps both sides of a step-1 rename collision', (tester) async {
    final repos = openTestRepositories();
    await _seedRenameCollision(repos);

    await _pumpScreen(tester, repos);

    // Before #1355 this row rendered the "no safe action" copy and no buttons,
    // while the peer's rename was skipped on every pass.
    expect(
      find.text(
        'Another device renamed this record to a name a different record '
        'here already uses.',
      ),
      findsOneWidget,
    );
    const key = 'choreographer:aaa-author:zzz-author';
    await tester.tap(
      find.byKey(const ValueKey('sync-review-keep-both-$key')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Sam Jones the second');
    await tester.tap(
      find.byKey(const ValueKey('sync-review-keep-both-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync-review-empty')), findsOneWidget);
    expect(
      (await repos.choreographers.getById('aaa-author'))!.name,
      'Sam Jones',
    );
    expect(
      (await repos.choreographers.getById('zzz-author'))!.name,
      'Sam Jones the second',
    );
  });

  testWidgets('confirms before a step-1 merge discards contact details', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _seedRenameCollision(repos);

    await _pumpScreen(tester, repos);
    const key = 'choreographer:aaa-author:zzz-author';
    await tester.tap(find.byKey(const ValueKey('sync-review-merge-$key')));
    await tester.pumpAndSettle();

    // §6.6 forbids coalescing at step 1, so the losing row's email, location
    // and deceased marker are lost and no peer can return them. Cancelling
    // must leave both rows exactly as they were.
    expect(find.text('Merge these choreographers?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await repos.choreographers.getById('zzz-author'), isNotNull);
    expect(
      await repos.syncLocal.listReviewQueue(),
      hasLength(1),
    );

    await tester.tap(find.byKey(const ValueKey('sync-review-merge-$key')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('sync-review-merge-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync-review-empty')), findsOneWidget);
    expect(await repos.choreographers.getById('zzz-author'), isNull);
    final survivor = await repos.choreographers.getById('aaa-author');
    expect(survivor!.name, 'Sam Jones');
    expect(survivor.email, 'aaa-author@example.com');
  });

  testWidgets('keeps both fuzzy duplicates without asking for a name', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _seedFuzzyDuplicate(repos);

    await _pumpScreen(tester, repos);

    expect(
      find.text(
        'These dances look like the same dance under slightly different '
        'titles.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('sync-review-keep-both-dance:a-rory:z-rory')),
    );
    await tester.pumpAndSettle();

    // No name dialog: the two titles already differ, which is exactly what
    // kept this pair out of the exact-title tier. Prompting would be asking
    // the user to invent a problem.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byKey(const ValueKey('sync-review-empty')), findsOneWidget);
    expect(await repos.dances.getById('a-rory'), isNotNull);
    expect(await repos.dances.getById('z-rory'), isNotNull);
  });

  testWidgets('retains unsupported rows without exposing actions', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // A reason that is still outside the action contract. The §6.6 step-1
    // reason stood here until #1355 made it resolvable; leaving it would have
    // left this test green while no longer testing an unsupported row.
    await _enqueue(
      repos,
      localId: 'local-author',
      candidate: _tombstone(id: 'peer-author', name: 'Shared author'),
      reason:
          'natural-key collision has different bodies at the same updatedAt',
    );

    await _pumpScreen(tester, repos);

    expect(find.byKey(const ValueKey('sync-review-list')), findsOneWidget);
    expect(
      find.text(
        'This sync conflict is retained for now; no safe action is available here.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'sync-review-merge-choreographer:local-author:peer-author',
        ),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey(
          'sync-review-keep-both-choreographer:local-author:peer-author',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('unmounts safely while the queue load is in flight', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: const SyncReviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('shows a retry state when queue loading fails', (tester) async {
    final interceptor = _FailReviewQueueReads();
    final repos = CompendiumRepositories(
      openWidgetTestDatabase(
        executor: NativeDatabase.memory().interceptWith(interceptor),
      ),
      contraTaxonomy,
    );
    interceptor.fail = true;

    await _pumpScreen(tester, repos);

    expect(find.text('Sync decisions could not be loaded.'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-review-retry')), findsOneWidget);
  });
}
