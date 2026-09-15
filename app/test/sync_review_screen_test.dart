import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/sync_review_screen.dart';

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

  testWidgets('retains unsupported rows without exposing actions', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _enqueue(
      repos,
      localId: 'local-author',
      candidate: _tombstone(id: 'peer-author', name: 'Shared author'),
      reason: 'known UUID natural-key rename collides with another local row',
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
