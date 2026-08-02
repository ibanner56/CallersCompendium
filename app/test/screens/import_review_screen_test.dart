import 'dart:async';
import 'dart:typed_data';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/collection_refresh_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/widgets/figure_diff_view.dart';
import 'package:compendium_app/src/utils/undo_snack_bar.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fmp_fixture_builder.dart';
import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

/// A drift [drift.QueryInterceptor] that can hold the first write of a commit
/// open on a caller-controlled gate. Used to freeze [ImportReviewScreen] in its
/// `committing` phase deterministically (an in-memory DB otherwise resolves the
/// commit within a single microtask, so the transient committing frame would
/// never render). Reads and open-time work are never gated, so it only bites
/// once the test arms a gate right before pressing Import.
class _CommitGate extends drift.QueryInterceptor {
  Completer<void>? _gate;

  /// Arms the interceptor so the next data write awaits [gate] before running.
  void arm(Completer<void> gate) => _gate = gate;

  Future<void> _maybeBlock() async {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) {
      _gate = null; // Block only the first write of the armed commit.
      await gate.future;
    }
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await _maybeBlock();
    return executor.runInsert(statement, args);
  }

  @override
  Future<void> runBatched(
    drift.QueryExecutor executor,
    drift.BatchedStatements statements,
  ) async {
    await _maybeBlock();
    return executor.runBatched(statements);
  }
}

Dance _dance(
  String id,
  String title, {
  List<Figure> figures = const [],
  Provenance? provenance,
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  provenance: provenance,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Encodes a one-or-more-dance [CompendiumArchive] as the generic-JSON payload
/// the [GenericJsonAdapter] consumes.
String _archivePayload(List<Dance> dances) => encodeArchive(
  CompendiumArchive(exportedAt: DateTime.utc(2026, 7, 15), dances: dances),
);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required String payload,
  SourceAdapter Function()? adapterFactory,
  List<ImportSource>? sources,
  UrlFetcher? fetcher,
  ImportBytePicker? bytePicker,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: ImportReviewScreen(
          sources:
              sources ??
              [
                ImportSource(
                  kind: ImportSourceKind.genericJson,
                  adapterFactory: adapterFactory ?? GenericJsonAdapter.new,
                ),
              ],
          picker: () async => payload,
          bytePicker: bytePicker,
          fetcher: fetcher,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drives input → planning → review: taps "Choose file…" (canned picker) then
/// "Review import".
Future<void> _toReview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('import-choose-file')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('import-continue')));
  await tester.pumpAndSettle();
}

/// Types [url] into the URL field and taps "Fetch".
Future<void> _fetch(WidgetTester tester, String url) async {
  await tester.enterText(find.byKey(const ValueKey('import-url-field')), url);
  await tester.tap(find.byKey(const ValueKey('import-fetch-url')));
  await tester.pumpAndSettle();
}

/// Pumps the review screen with [RepositoriesScope] and [ActiveDialectScope]
/// installed **above** the Navigator (via [MaterialApp.builder], mirroring
/// `main.dart`) so the per-row **Edit** action can push the real
/// [DanceEditorScreen] route and have it find its inherited scopes.
Future<void> _pumpForEdit(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required String payload,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
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
      home: ImportReviewScreen(
        sources: [
          ImportSource(
            kind: ImportSourceKind.genericJson,
            adapterFactory: GenericJsonAdapter.new,
          ),
        ],
        picker: () async => payload,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an oversized text import file is rejected with a friendly '
      'SnackBar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: ImportReviewScreen(
            sources: [
              ImportSource(
                kind: ImportSourceKind.genericJson,
                adapterFactory: GenericJsonAdapter.new,
              ),
            ],
            picker: () async =>
                throw const ImportFileTooLargeException(30 * 1024 * 1024),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('import-choose-file')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-file-too-large')), findsOneWidget);
    expect(find.text('That file is too large to import.'), findsOneWidget);
  });

  testWidgets('renders a new-dance row and commits it into the collection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('d1', 'Brand New Reel')]),
    );

    await _toReview(tester);

    expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
    expect(find.text('Brand New Reel'), findsOneWidget);
    // A new dance defaults to import (importable count = 1).
    expect(find.text('1 of 1 will be imported'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-result-dialog')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('import-summary-Created')),
      findsOneWidget,
    );

    final all = await repos.dances.listAll();
    expect(all.map((d) => d.title), contains('Brand New Reel'));
  });

  testWidgets('reimport row updates the matched dance in place', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        'existing',
        'Old Title',
        provenance: Provenance(
          source: ProvenanceSource.json,
          externalId: 'ext1',
          importedAt: DateTime.utc(2026, 1, 1),
        ),
      ),
    );

    await _pump(
      tester,
      repos,
      payload: _archivePayload([
        _dance(
          'incoming',
          'Refreshed Title',
          provenance: Provenance(
            source: ProvenanceSource.json,
            externalId: 'ext1',
            importedAt: DateTime.utc(2026, 6, 1),
          ),
        ),
      ]),
    );
    await _toReview(tester);

    // The reimport option is offered but is NOT selected by default (issue
    // #446): the row defaults to skip/keep-local so a re-import never silently
    // overwrites local edits. The user must deliberately choose to overwrite.
    expect(find.byKey(const ValueKey('import-row-0-reimport')), findsOneWidget);
    expect(find.text('0 of 1 will be imported'), findsOneWidget);
    // No overwrite is queued yet, so the pre-commit warning is absent.
    expect(
      find.byKey(const ValueKey('import-overwrite-warning')),
      findsNothing,
    );

    // Deliberately choose to re-import (overwrite) the matched dance.
    await tester.tap(find.byKey(const ValueKey('import-row-0-reimport')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 will be imported'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    expect(all.length, 1);
    expect(all.single.id, 'existing');
    expect(all.single.title, 'Refreshed Title');
  });

  testWidgets(
    'reimport row defaults to keep-local (skip) and shows an accessible '
    'overwrite warning only once overwrite is chosen',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(
          'existing',
          'Old Title',
          provenance: Provenance(
            source: ProvenanceSource.json,
            externalId: 'ext1',
            importedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
      );

      await _pump(
        tester,
        repos,
        payload: _archivePayload([
          _dance(
            'incoming',
            'Refreshed Title',
            provenance: Provenance(
              source: ProvenanceSource.json,
              externalId: 'ext1',
              importedAt: DateTime.utc(2026, 6, 1),
            ),
          ),
        ]),
      );
      await _toReview(tester);

      // Default is skip: nothing importable, commit disabled, no warning.
      expect(find.text('0 of 1 will be imported'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('import-commit-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const ValueKey('import-overwrite-warning')),
        findsNothing,
      );

      // Choosing to overwrite surfaces the accessible count banner.
      await tester.tap(find.byKey(const ValueKey('import-row-0-reimport')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-overwrite-warning')),
        findsOneWidget,
      );
      expect(find.text('1 existing dance will be overwritten'), findsOneWidget);
      // The count is announced to assistive tech as a warning (not color-only).
      expect(
        find.bySemanticsLabel('Warning: 1 existing dance will be overwritten'),
        findsOneWidget,
      );

      // Switching back to skip removes the warning again.
      await tester.tap(find.byKey(const ValueKey('import-row-0-skip')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('import-overwrite-warning')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'the overwrite warning aggregates and pluralizes across reimport rows',
    (tester) async {
      final repos = openTestRepositories();
      for (final ext in ['ext1', 'ext2']) {
        await repos.dances.create(
          _dance(
            'existing-$ext',
            'Old $ext',
            provenance: Provenance(
              source: ProvenanceSource.json,
              externalId: ext,
              importedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        );
      }

      await _pump(
        tester,
        repos,
        payload: _archivePayload([
          for (final ext in ['ext1', 'ext2'])
            _dance(
              'incoming-$ext',
              'Fresh $ext',
              provenance: Provenance(
                source: ProvenanceSource.json,
                externalId: ext,
                importedAt: DateTime.utc(2026, 6, 1),
              ),
            ),
        ]),
      );
      await _toReview(tester);

      // Both rows default to skip (keep-local): no overwrites queued.
      expect(
        find.byKey(const ValueKey('import-overwrite-warning')),
        findsNothing,
      );

      // Choose overwrite on the first row → singular banner.
      await tester.tap(find.byKey(const ValueKey('import-row-0-reimport')));
      await tester.pumpAndSettle();
      expect(find.text('1 existing dance will be overwritten'), findsOneWidget);

      // Choose overwrite on the second row → aggregated, pluralized banner.
      await tester.tap(find.byKey(const ValueKey('import-row-1-reimport')));
      await tester.pumpAndSettle();
      expect(
        find.text('2 existing dances will be overwritten'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Warning: 2 existing dances will be overwritten'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the overwrite warning counts distinct target dances, not re-import rows',
    (tester) async {
      final repos = openTestRepositories();
      // A single existing local dance.
      await repos.dances.create(
        _dance(
          'existing',
          'Old Title',
          provenance: Provenance(
            source: ProvenanceSource.json,
            externalId: 'ext1',
            importedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
      );

      // Two incoming records that share the same provenance key, so both
      // dedupe onto the *same* local dance ('existing').
      await _pump(
        tester,
        repos,
        payload: _archivePayload([
          for (final id in ['incoming-a', 'incoming-b'])
            _dance(
              id,
              'Fresh $id',
              provenance: Provenance(
                source: ProvenanceSource.json,
                externalId: 'ext1',
                importedAt: DateTime.utc(2026, 6, 1),
              ),
            ),
        ]),
      );
      await _toReview(tester);

      // Both rows are re-import verdicts against the one existing dance.
      expect(
        find.byKey(const ValueKey('import-row-0-reimport')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-row-1-reimport')),
        findsOneWidget,
      );

      // Overwrite both rows: the banner counts the single distinct target once,
      // not two rows.
      await tester.tap(find.byKey(const ValueKey('import-row-0-reimport')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-row-1-reimport')));
      await tester.pumpAndSettle();

      expect(find.text('1 existing dance will be overwritten'), findsOneWidget);
      expect(find.text('2 existing dances will be overwritten'), findsNothing);
    },
  );

  testWidgets('ambiguous row defaults to skip and is not committed silently', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('existing', "Sackett's Harbor"));

    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('incoming', 'Sacketts Harbor')]),
    );
    await _toReview(tester);

    // Ambiguous → link/duplicate/skip offered; skip is the default, so nothing
    // is importable until the user chooses.
    expect(find.byKey(const ValueKey('import-row-0-skip')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('import-row-0-duplicate')),
      findsOneWidget,
    );
    expect(find.textContaining('Link to'), findsOneWidget);
    expect(find.text('0 of 1 will be imported'), findsOneWidget);
    // Commit is disabled while everything is skipped (no misleading control).
    final commit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('import-commit-button')),
    );
    expect(commit.onPressed, isNull);

    // Choosing "duplicate" makes it importable and commits a new dance.
    await tester.tap(find.byKey(const ValueKey('import-row-0-duplicate')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 will be imported'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    expect(all.length, 2);
  });

  testWidgets('linking an ambiguous row updates the chosen candidate', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('cand', "Sackett's Harbor"));

    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('incoming', 'Sacketts Harbor')]),
    );
    await _toReview(tester);

    await tester.tap(find.byKey(const ValueKey('import-row-0-link-cand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    expect(all.length, 1);
    expect(all.single.id, 'cand');
    expect(all.single.title, 'Sacketts Harbor');
    expect(find.byKey(const ValueKey('import-summary-Linked')), findsOneWidget);
  });

  testWidgets('batch errors are surfaced without blocking the good record', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      payload: 'ignored',
      adapterFactory: () => _PartlyBrokenAdapter(),
    );
    await _toReview(tester);

    // One record read, one couldn't be read.
    expect(find.byKey(const ValueKey('import-batch-errors')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-row-1')), findsNothing);
    expect(find.text('1 of 1 will be imported'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    final all = await repos.dances.listAll();
    expect(all.map((d) => d.title), contains('Good One'));
  });

  testWidgets('undo reverts a committed import', (tester) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('d1', 'Undo Me')]),
    );
    await _toReview(tester);
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    expect((await repos.dances.listAll()).length, 1);

    await tester.tap(find.byKey(const ValueKey('import-undo-button')));
    await tester.pumpAndSettle();

    expect((await repos.dances.listAll()).isEmpty, isTrue);
    expect(
      find.byKey(const ValueKey('import-undone-snackbar')),
      findsOneWidget,
    );
  });

  testWidgets('a payload with no dances shows an empty state', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, payload: _archivePayload([]));
    await _toReview(tester);
    expect(find.text('No dances found'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-commit-button')), findsNothing);
  });

  testWidgets('an undecodable payload shows an honest error', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, payload: 'not json at all');
    await _toReview(tester);
    expect(find.text("Couldn't read the import"), findsOneWidget);
  });

  group('figure-variation diff prompt (issue #686)', () {
    // A confident match (exact normalized title + an intersecting tokenized
    // author set — issue #685) whose figures genuinely differ (issue #686's
    // canonicalization-aware comparison) gets a richer "Variation?" block
    // instead of the plain link row: an inline diff plus a choice between
    // importing the incoming record as a distinct variation (with an
    // optional relatedDance link back) or treating it as the same dance.

    /// Encodes a self-contained archive whose only dance carries [authorName]
    /// via an embedded [Choreographer] — [GenericJsonAdapter] turns this into
    /// the draft's `authorNames`, matching a local dance's author by *name*
    /// regardless of either side's id (see `generic_json_adapter.dart`).
    String archivePayload(Dance dance, String authorName) => encodeArchive(
      CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: [dance],
        choreographers: [Choreographer(id: 'archive-author', name: authorName)],
      ),
    );

    testWidgets(
      'confident match with differing figures shows the Variation? block',
      (tester) async {
        final repos = openTestRepositories();
        await repos.choreographers.upsert(
          Choreographer(id: 'local-author', name: 'Bob Smith'),
        );
        await repos.dances.create(
          Dance(
            id: 'local-1',
            title: 'Money Musk',
            authorIds: const ['local-author'],
            figures: [customFigure('Circle left once around')],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        await _pumpForEdit(
          tester,
          repos,
          payload: archivePayload(
            Dance(
              id: 'incoming-1',
              title: 'Money Musk',
              authorIds: const ['archive-author'],
              figures: [customFigure('Circle right once around')],
              createdAt: DateTime.utc(2026, 6, 1),
              updatedAt: DateTime.utc(2026, 6, 1),
            ),
            'Bob Smith',
          ),
        );
        await _toReview(tester);

        expect(
          find.byKey(const ValueKey('import-row-0-variation')),
          findsOneWidget,
        );
        expect(find.byType(FigureDiffView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('import-row-0-variation-local-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('import-row-0-link-local-1')),
          findsOneWidget,
        );
        // The plain scored "Link to Money Musk (NN%)" row is NOT offered for
        // a confident+differing candidate — it's replaced by the richer pair
        // above.
        expect(find.textContaining('Link to "Money Musk"'), findsNothing);
      },
    );

    testWidgets(
      'confident match with identical figures keeps the plain (#685) UI',
      (tester) async {
        final repos = openTestRepositories();
        await repos.choreographers.upsert(
          Choreographer(id: 'local-author', name: 'Bob Smith'),
        );
        final sharedFigures = [customFigure('Circle left once around')];
        await repos.dances.create(
          Dance(
            id: 'local-1',
            title: 'Money Musk',
            authorIds: const ['local-author'],
            figures: sharedFigures,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        await _pumpForEdit(
          tester,
          repos,
          payload: archivePayload(
            Dance(
              id: 'incoming-1',
              title: 'Money Musk',
              authorIds: const ['archive-author'],
              figures: sharedFigures,
              createdAt: DateTime.utc(2026, 6, 1),
              updatedAt: DateTime.utc(2026, 6, 1),
            ),
            'Bob Smith',
          ),
        );
        await _toReview(tester);

        expect(
          find.byKey(const ValueKey('import-row-0-variation')),
          findsNothing,
        );
        expect(find.byType(FigureDiffView), findsNothing);
        // Falls through to the existing (#685) plain scored link row.
        expect(
          find.byKey(const ValueKey('import-row-0-link-local-1')),
          findsOneWidget,
        );
        expect(find.textContaining('Link to "Money Musk"'), findsOneWidget);
      },
    );

    testWidgets(
      'choosing "Import as a variation" imports a new dance and links back',
      (tester) async {
        final repos = openTestRepositories();
        await repos.choreographers.upsert(
          Choreographer(id: 'local-author', name: 'Bob Smith'),
        );
        await repos.dances.create(
          Dance(
            id: 'local-1',
            title: 'Money Musk',
            authorIds: const ['local-author'],
            figures: [customFigure('Circle left once around')],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        await _pumpForEdit(
          tester,
          repos,
          payload: archivePayload(
            Dance(
              id: 'incoming-1',
              title: 'Money Musk',
              authorIds: const ['archive-author'],
              figures: [customFigure('Circle right once around')],
              createdAt: DateTime.utc(2026, 6, 1),
              updatedAt: DateTime.utc(2026, 6, 1),
            ),
            'Bob Smith',
          ),
        );
        await _toReview(tester);

        await tester.tap(
          find.byKey(const ValueKey('import-row-0-variation-local-1')),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 of 1 will be imported'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pumpAndSettle();

        final all = await repos.dances.listAll();
        expect(all.length, 2);
        final imported = all.firstWhere((d) => d.id != 'local-1');
        expect(imported.title, 'Money Musk');
        expect(
          imported.links.any(
            (l) =>
                l.kind == LinkKind.relatedDance && l.targetDanceId == 'local-1',
          ),
          isTrue,
          reason: 'the new variation should link back to the original',
        );
        final original = all.firstWhere((d) => d.id == 'local-1');
        expect(
          original.links.any(
            (l) =>
                l.kind == LinkKind.relatedDance &&
                l.targetDanceId == imported.id,
          ),
          isTrue,
          reason: 'the original should gain a reciprocal relatedDance link',
        );
        expect(
          find.byKey(const ValueKey('import-summary-Variation')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'unchecking "link back" imports the variation without a relatedDance '
      'link',
      (tester) async {
        final repos = openTestRepositories();
        await repos.choreographers.upsert(
          Choreographer(id: 'local-author', name: 'Bob Smith'),
        );
        await repos.dances.create(
          Dance(
            id: 'local-1',
            title: 'Money Musk',
            authorIds: const ['local-author'],
            figures: [customFigure('Circle left once around')],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        await _pumpForEdit(
          tester,
          repos,
          payload: archivePayload(
            Dance(
              id: 'incoming-1',
              title: 'Money Musk',
              authorIds: const ['archive-author'],
              figures: [customFigure('Circle right once around')],
              createdAt: DateTime.utc(2026, 6, 1),
              updatedAt: DateTime.utc(2026, 6, 1),
            ),
            'Bob Smith',
          ),
        );
        await _toReview(tester);

        await tester.tap(
          find.byKey(const ValueKey('import-row-0-variation-local-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('import-row-0-variation-linkback')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pumpAndSettle();

        final all = await repos.dances.listAll();
        final imported = all.firstWhere((d) => d.id != 'local-1');
        expect(imported.links, isEmpty);
        final original = all.firstWhere((d) => d.id == 'local-1');
        expect(original.links, isEmpty);
      },
    );

    testWidgets(
      'choosing "Same dance (link/update)" behaves like the existing link '
      'option',
      (tester) async {
        final repos = openTestRepositories();
        await repos.choreographers.upsert(
          Choreographer(id: 'local-author', name: 'Bob Smith'),
        );
        await repos.dances.create(
          Dance(
            id: 'local-1',
            title: 'Money Musk',
            authorIds: const ['local-author'],
            figures: [customFigure('Circle left once around')],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        await _pumpForEdit(
          tester,
          repos,
          payload: archivePayload(
            Dance(
              id: 'incoming-1',
              title: 'Money Musk',
              authorIds: const ['archive-author'],
              figures: [customFigure('Circle right once around')],
              createdAt: DateTime.utc(2026, 6, 1),
              updatedAt: DateTime.utc(2026, 6, 1),
            ),
            'Bob Smith',
          ),
        );
        await _toReview(tester);

        await tester.tap(
          find.byKey(const ValueKey('import-row-0-link-local-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pumpAndSettle();

        final all = await repos.dances.listAll();
        expect(all.length, 1);
        expect(all.single.id, 'local-1');
        expect(
          find.byKey(const ValueKey('import-summary-Linked')),
          findsOneWidget,
        );
      },
    );
  });

  group('end-to-end through the real pipeline', () {
    test('GenericJsonAdapter + ImportPipeline lands multiple dances', () async {
      final repos = openTestRepositories();
      final payload = _archivePayload([
        _dance('a', 'Alpha'),
        _dance('b', 'Beta'),
      ]);

      final pipeline = ImportPipeline(repos.dances, repos.choreographers);
      final batch = await pipeline.plan(
        GenericJsonAdapter(),
        ImportRequest(payload: payload),
      );
      expect(batch.plannedCount, 2);
      expect(batch.hasErrors, isFalse);

      final session = await pipeline.commit(
        batch,
        now: DateTime.utc(2026, 7, 15),
        newId: uuidV4,
      );
      expect(session.committedCount, 2);
      final titles = (await repos.dances.listAll()).map((d) => d.title).toSet();
      expect(titles, containsAll(['Alpha', 'Beta']));
    });
  });

  group('Import from URL', () {
    testWidgets('a fetched archive drives the review queue and commits', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final payload = _archivePayload([_dance('u1', 'Fetched Reel')]);
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async => payload,
      );

      await _fetch(tester, 'https://example.com/archive.json');
      // The fetched body populates the payload field.
      expect(find.text(payload), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(find.text('Fetched Reel'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-result-dialog')),
        findsOneWidget,
      );
      final all = await repos.dances.listAll();
      expect(all.map((d) => d.title), contains('Fetched Reel'));
    });

    testWidgets('the fetched URL is carried onto ImportRequest.uri', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final adapter = _CapturingAdapter();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        adapterFactory: () => adapter,
        fetcher: (url) async => 'body',
      );

      await _fetch(tester, 'https://example.com/archive.json');
      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      expect(adapter.lastRequest?.uri, 'https://example.com/archive.json');
      expect(adapter.lastRequest?.payload, 'body');
    });

    testWidgets('a fetch failure shows the error and does not crash', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async => throw const UrlFetchException(
          UrlFetchFailureReason.httpStatus,
          statusCode: 404,
        ),
      );

      await _fetch(tester, 'https://example.com/missing.json');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(find.text('The server responded with HTTP 404.'), findsOneWidget);
      // Still on the input phase; nothing crashed and no review list appeared.
      expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty-body failure surfaces its message', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async =>
            throw const UrlFetchException(UrlFetchFailureReason.emptyResponse),
      );

      await _fetch(tester, 'https://example.com/empty.json');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(find.text('The URL returned an empty response.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-UrlFetchException is still surfaced without crashing', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async => throw StateError('boom'),
      );

      await _fetch(tester, 'https://example.com/x.json');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group("Caller's Box routing", () {
    // Minimal real-shaped TCB per-dance JSON (id=1, "The Nice Combination").
    const tcbJson =
        '{"ID":1,"Name":"The Nice Combination","Permission":"full"}';

    List<ImportSource> sourcesFor() => [
      ImportSource(
        kind: ImportSourceKind.genericJson,
        adapterFactory: GenericJsonAdapter.new,
      ),
      ImportSource(
        kind: ImportSourceKind.callersBox,
        adapterFactory: CallersBoxAdapter.new,
        urlBuilder: buildCallersBoxJsonUrl,
      ),
    ];

    Future<void> selectCallersBox(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("The Caller's Box").last);
      await tester.pumpAndSettle();
    }

    testWidgets('a bare id is resolved to the &format=JSON endpoint and '
        'parsed by CallersBoxAdapter', (tester) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchedUrl = url;
          return tcbJson;
        },
      );

      await selectCallersBox(tester);
      await _fetch(tester, '1');

      // The bare id became the canonical TCB JSON endpoint.
      expect(
        fetchedUrl,
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1&format=JSON',
      );

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      // The dance was parsed by CallersBoxAdapter and reached the review queue.
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(find.text('The Nice Combination'), findsOneWidget);
    });

    testWidgets('a pasted dance URL gains format=JSON and is fetched', (
      tester,
    ) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchedUrl = url;
          return tcbJson;
        },
      );

      await selectCallersBox(tester);
      await _fetch(
        tester,
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1',
      );

      expect(fetchedUrl, contains('id=1'));
      expect(fetchedUrl, contains('format=JSON'));
    });

    testWidgets('a bad Caller\'s Box input shows an inline error, no fetch', (
      tester,
    ) async {
      final repos = openTestRepositories();
      var fetchCalls = 0;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchCalls++;
          return tcbJson;
        },
      );

      await selectCallersBox(tester);
      // A URL with no dance id can't be turned into an endpoint.
      await _fetch(
        tester,
        'https://www.ibiblio.org/contradance/thecallersbox/dances.php',
      );

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(fetchCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a URL from a non-allowlisted host shows an inline error naming the '
      'supported hosts, and is never fetched (#621)',
      (tester) async {
        final repos = openTestRepositories();
        var fetchCalls = 0;
        await _pump(
          tester,
          repos,
          payload: 'unused',
          sources: sourcesFor(),
          fetcher: (url) async {
            fetchCalls++;
            return tcbJson;
          },
        );

        await selectCallersBox(tester);
        // A lookalike host must be rejected before any URL is built/fetched.
        await _fetch(
          tester,
          'https://ibiblio.org.evil.com/contradance/thecallersbox/dance.php?id=1',
        );

        expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('import-url-error')),
            matching: find.textContaining('ibiblio.org'),
          ),
          findsOneWidget,
        );
        // #766 removed thecallersbox.com from the allowlist, so the message
        // must no longer offer it as somewhere the user could paste from.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('import-url-error')),
            matching: find.textContaining('thecallersbox.com'),
          ),
          findsNothing,
        );
        expect(fetchCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('switching source clears stale URL provenance', (tester) async {
      final repos = openTestRepositories();
      final adapter = _CapturingAdapter();
      // A generic-JSON source using a provenance-capturing adapter, plus the
      // Caller's Box source. Fetch under Caller's Box, then switch back to
      // generic and plan: the previous fetch URL must NOT be reattached.
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: [
          ImportSource(
            kind: ImportSourceKind.genericJson,
            adapterFactory: () => adapter,
          ),
          ImportSource(
            kind: ImportSourceKind.callersBox,
            adapterFactory: CallersBoxAdapter.new,
            urlBuilder: buildCallersBoxJsonUrl,
          ),
        ],
        fetcher: (url) async => 'body',
      );

      await selectCallersBox(tester);
      await _fetch(tester, '1');

      // Switch back to the generic JSON source.
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("a Caller's Compendium JSON file").last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      // Provenance was dropped on the switch, so it plans as a paste.
      expect(adapter.lastRequest?.uri, isNull);
    });
  });

  group('ContraDB routing', () {
    // Minimal real-shaped ContraDB dance page (id=1, "The Rendezvous").
    const contraDbPage =
        '<!DOCTYPE html><html><body class="dances-show-body">'
        '<h1 class="dance-show-title">The Rendezvous</h1>'
        '<p class="dance-show-choreographer">by: '
        '<strong><a href="/choreographers/4">Adina Gordon</a></strong></p>'
        '<p class="dance-show-formation">formation: improper </p>'
        '<table class="contra-table-nonfluid">'
        '<tr><td>A1</td><td class=dance-show-beats>16</td>'
        '<td><div class="show-figure">neighbors balance &amp; swing</div></td>'
        '</tr></table></body></html>';

    List<ImportSource> sourcesFor() => [
      ImportSource(
        kind: ImportSourceKind.genericJson,
        adapterFactory: GenericJsonAdapter.new,
      ),
      ImportSource(
        kind: ImportSourceKind.contraDb,
        adapterFactory: ContraDbHtmlAdapter.new,
        urlBuilder: buildContraDbUrl,
      ),
    ];

    Future<void> selectContraDb(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ContraDB').last);
      await tester.pumpAndSettle();
    }

    testWidgets('a bare id resolves to the dance page and is scraped by '
        'ContraDbHtmlAdapter', (tester) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchedUrl = url;
          return contraDbPage;
        },
      );

      await selectContraDb(tester);
      await _fetch(tester, '1');

      // The bare id became the canonical ContraDB dance page URL.
      expect(fetchedUrl, 'https://contradb.com/dances/1');

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      // The dance was parsed by ContraDbHtmlAdapter and reached the queue.
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(find.text('The Rendezvous'), findsOneWidget);
    });

    testWidgets('a bad ContraDB input shows an inline error, no fetch', (
      tester,
    ) async {
      final repos = openTestRepositories();
      var fetchCalls = 0;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchCalls++;
          return contraDbPage;
        },
      );

      await selectContraDb(tester);
      // A URL with no dance id can't be turned into a dance page URL.
      await _fetch(tester, 'https://contradb.com/dances');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(fetchCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a URL from a non-allowlisted host shows an inline error naming the '
      'supported host, and is never fetched (#667/#621)',
      (tester) async {
        final repos = openTestRepositories();
        var fetchCalls = 0;
        await _pump(
          tester,
          repos,
          payload: 'unused',
          sources: sourcesFor(),
          fetcher: (url) async {
            fetchCalls++;
            return contraDbPage;
          },
        );

        await selectContraDb(tester);
        // A lookalike host must be rejected before any URL is built/fetched.
        await _fetch(tester, 'https://contradb.com.evil.com/dances/1');

        expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('import-url-error')),
            matching: find.textContaining('contradb.com'),
          ),
          findsOneWidget,
        );
        expect(fetchCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('URL source auto-detection', () {
    const tcbJson =
        '{"ID":1,"Name":"The Nice Combination","Permission":"full"}';

    ImportSource selectedSource(WidgetTester tester) => tester
        .widget<DropdownButton<ImportSource>>(
          find.byKey(const ValueKey('import-source-select')),
        )
        .value!;

    Future<void> typeUrl(WidgetTester tester, String url) async {
      await tester.enterText(
        find.byKey(const ValueKey('import-url-field')),
        url,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a Caller\'s Box URL flips the selector to The Caller\'s Box '
        'and routes through CallersBoxAdapter', (tester) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: defaultImportSources(),
        fetcher: (url) async {
          fetchedUrl = url;
          return tcbJson;
        },
      );

      // Default selection is the generic-JSON source.
      expect(selectedSource(tester).kind, ImportSourceKind.genericJson);

      await typeUrl(
        tester,
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1',
      );
      // The selector auto-flipped to Caller's Box without the user touching it.
      expect(selectedSource(tester).kind, ImportSourceKind.callersBox);

      await tester.tap(find.byKey(const ValueKey('import-fetch-url')));
      await tester.pumpAndSettle();
      expect(fetchedUrl, contains('format=JSON'));

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();
      // Parsed by CallersBoxAdapter (the auto-detected source).
      expect(find.text('The Nice Combination'), findsOneWidget);
    });

    testWidgets('a ContraDB URL flips the selector to ContraDB', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: defaultImportSources(),
        fetcher: (url) async => 'unused',
      );

      await typeUrl(tester, 'https://contradb.com/dances/42');
      expect(selectedSource(tester).kind, ImportSourceKind.contraDb);
    });

    testWidgets('a manual source choice is respected (no auto-flip after)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: defaultImportSources(),
        fetcher: (url) async => 'unused',
      );

      // User explicitly picks ContraDB…
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ContraDB').last);
      await tester.pumpAndSettle();
      expect(selectedSource(tester).kind, ImportSourceKind.contraDb);

      // …then pastes a Caller's Box URL: the manual choice wins, no auto-flip.
      await typeUrl(
        tester,
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1',
      );
      expect(selectedSource(tester).kind, ImportSourceKind.contraDb);
    });
  });

  group("Caller's Companion .USR import", () {
    // A minimal but structurally real CC `.USR` byte image: two dances
    // (external ids 4/7 → "Simplicity Swing", "Petronella"), one set whose
    // Location becomes the program title ("Grange Hall"), and a SetItem
    // referencing an absent dance (99) so a program note is produced.
    Uint8List ccUsrBytes() => buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
        rows: [
          MapEntry(10, {1: '4', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
          MapEntry(11, {1: '7', 2: 'Petronella', 3: 'Trad'}),
        ],
      ),
      FmpFixtureTable(
        index: 2,
        name: 'Set',
        columnNames: [
          'zk_Set_ID',
          'Date',
          'Location',
          'Band',
          'Caller',
          'Notes',
        ],
        rows: [
          MapEntry(20, {
            1: '1',
            2: '3/14/2020',
            3: 'Grange Hall',
            4: 'The Band',
            5: 'Jane',
            6: 'a good night',
          }),
        ],
      ),
      FmpFixtureTable(
        index: 3,
        name: 'SetItem',
        columnNames: [
          'zk_Set_ID',
          'zk_SetItem_ID',
          'zk_Dance_ID',
          'Order',
          'Time',
          'Break',
        ],
        rows: [
          MapEntry(30, {1: '1', 2: '101', 3: '4', 4: '1', 5: '8'}),
          MapEntry(31, {1: '1', 2: '102', 3: '7', 4: '2'}),
          MapEntry(32, {1: '1', 2: '103', 4: '3', 6: 'Waltz break'}),
          MapEntry(33, {1: '1', 2: '104', 3: '99', 4: '4'}),
        ],
      ),
    ]);

    List<ImportSource> sourcesFor(ImportBytePicker picker) => [
      ImportSource(
        kind: ImportSourceKind.genericJson,
        adapterFactory: GenericJsonAdapter.new,
      ),
      ImportSource(
        kind: ImportSourceKind.callersCompanionUsr,
        adapterFactory: CallersCompanionUsrAdapter.new,
        bytePicker: picker,
      ),
    ];

    Future<void> selectUsr(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("a Caller's Companion .USR file").last);
      await tester.pumpAndSettle();
    }

    Future<void> chooseAndReview(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-choose-usr-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();
    }

    testWidgets('the byte source shows a .USR file button, not URL/paste', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);

      expect(
        find.byKey(const ValueKey('import-choose-usr-file')),
        findsOneWidget,
      );
      // Text-only affordances are hidden for a binary source.
      expect(find.byKey(const ValueKey('import-url-field')), findsNothing);
      expect(find.byKey(const ValueKey('import-paste-field')), findsNothing);
      expect(find.byKey(const ValueKey('import-choose-file')), findsNothing);
    });

    testWidgets('an oversized .USR is rejected with a friendly SnackBar and '
        'nothing is loaded', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(
          () async => throw const ImportFileTooLargeException(30 * 1024 * 1024),
        ),
        bytePicker: () async =>
            throw const ImportFileTooLargeException(30 * 1024 * 1024),
      );

      await selectUsr(tester);
      await tester.tap(find.byKey(const ValueKey('import-choose-usr-file')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-file-too-large')),
        findsOneWidget,
      );
      expect(find.text('That file is too large to import.'), findsOneWidget);
      // The oversized file was refused before reading, so no payload loaded.
      expect(find.byKey(const ValueKey('import-usr-chosen')), findsNothing);
    });

    testWidgets('planning lists the .USR dances for review', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);

      expect(find.text('Simplicity Swing'), findsOneWidget);
      expect(find.text('Petronella'), findsOneWidget);
      expect(find.text('2 of 2 will be imported'), findsOneWidget);
    });

    testWidgets('committing persists dances AND programs and surfaces the '
        'program names + notes', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);

      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      // Result dialog surfaces both dances and programs.
      expect(
        find.byKey(const ValueKey('import-result-dialog')),
        findsOneWidget,
      );
      expect(find.text('Created: 2'), findsOneWidget);
      expect(find.text('Programs: 1'), findsOneWidget);
      // Program name-level confirmation (the Set's Location).
      expect(find.text('• Grange Hall'), findsOneWidget);
      // The SetItem referencing an absent dance (99) produced a note.
      expect(
        find.byKey(const ValueKey('import-program-notes')),
        findsOneWidget,
      );

      // Both dances and the program are actually in the database.
      final dances = await repos.dances.listAll();
      expect(
        dances.map((d) => d.title),
        containsAll(<String>['Simplicity Swing', 'Petronella']),
      );
      final programs = await repos.programs.listAll();
      expect(programs, hasLength(1));
      expect(programs.single.title, 'Grange Hall');
    });

    testWidgets('re-importing a Set dedupes onto the existing program and '
        'the dialog reports it as updated', (tester) async {
      final repos = openTestRepositories();
      // Pre-seed a CC-imported program whose provenance key matches the Set's
      // zk_Set_ID ('1') — simulating a prior import of the same file.
      await repos.programs.create(
        Program(
          id: 'existing-prog',
          title: 'Old Title',
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 1, 1),
          provenance: Provenance(
            source: ProvenanceSource.callersCompanion,
            externalId: '1',
            importedAt: DateTime.utc(2025, 1, 1),
            sourceVersion: 'cc-usr-1',
          ),
        ),
      );

      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      // The dialog reports one program, surfaced as updated (re-imported).
      expect(find.text('Programs: 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('import-programs-updated')),
        findsOneWidget,
      );
      expect(find.text('1 updated (re-imported)'), findsOneWidget);

      // No duplicate: the existing program was overwritten in place.
      final programs = await repos.programs.listAll();
      expect(programs, hasLength(1));
      expect(programs.single.id, 'existing-prog');
      expect(programs.single.title, 'Grange Hall');
    });

    testWidgets('Undo reverts the imported dances AND programs', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-undo-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-undone-snackbar')),
        findsOneWidget,
      );
      expect(await repos.dances.listAll(), isEmpty);
      expect(await repos.programs.listAll(), isEmpty);
    });
  });

  group('fetchImportUrl (default seam)', () {
    test('returns the body on a 200', () async {
      final client = MockClient(
        (_) async => http.Response('{"schemaVersion":1}', 200),
      );
      expect(
        await fetchImportUrl('https://example.com/a.json', client: client),
        '{"schemaVersion":1}',
      );
    });

    test('rejects an empty URL', () async {
      await expectLater(
        fetchImportUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('rejects a non-http(s) URL', () async {
      await expectLater(
        fetchImportUrl('ftp://example.com/a.json'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('throws on a non-2xx status', () async {
      final client = MockClient((_) async => http.Response('nope', 404));
      await expectLater(
        fetchImportUrl('https://example.com/a.json', client: client),
        throwsA(
          isA<UrlFetchException>()
              .having(
                (e) => e.reason,
                'reason',
                UrlFetchFailureReason.httpStatus,
              )
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('throws on an empty body', () async {
      final client = MockClient((_) async => http.Response('   ', 200));
      await expectLater(
        fetchImportUrl('https://example.com/a.json', client: client),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('wraps a transport failure', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      await expectLater(
        fetchImportUrl('https://example.com/a.json', client: client),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  group('edit prior to import (#266)', () {
    testWidgets('Edit commits the parsed dance faithfully and opens it in the '
        'editor, where a correction persists', (tester) async {
      final repos = openTestRepositories();
      await _pumpForEdit(
        tester,
        repos,
        payload: _archivePayload([_dance('d1', 'Parsed Reel')]),
      );
      await _toReview(tester);

      expect(find.text('Parsed Reel'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-row-0-edit')));
      await tester.pumpAndSettle();

      // The row's parsed dance was committed faithfully and the editor opened.
      expect(find.byType(DanceEditorScreen), findsOneWidget);
      final committed = await repos.dances.listAll();
      expect(committed.map((d) => d.title), ['Parsed Reel']);
      final committedId = committed.single.id;

      // Correcting the title in the editor and saving persists the edit.
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Corrected Reel',
      );
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById(committedId);
      expect(saved!.title, 'Corrected Reel');
    });

    testWidgets('Edit commits only its row; remaining rows still import as '
        'parsed via the batch Import button', (tester) async {
      final repos = openTestRepositories();
      await _pumpForEdit(
        tester,
        repos,
        payload: _archivePayload([
          _dance('d1', 'First Reel'),
          _dance('d2', 'Second Jig'),
        ]),
      );
      await _toReview(tester);
      expect(find.text('2 of 2 will be imported'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-row-0-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(DanceEditorScreen), findsOneWidget);

      // Leave the editor unchanged (no correction to the parsed dance).
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Back on review: row 0 is marked imported and only row 1 is left.
      expect(
        find.byKey(const ValueKey('import-row-0-imported')),
        findsOneWidget,
      );
      expect(find.text('1 of 2 will be imported'), findsOneWidget);

      // Batch-import the rest.
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      final titles = (await repos.dances.listAll())
          .map((d) => d.title)
          .toList();
      expect(titles, containsAll(['First Reel', 'Second Jig']));
      // The edited row was committed exactly once (not re-committed by Import).
      expect(titles.where((t) => t == 'First Reel'), hasLength(1));
    });

    testWidgets('Edit is disabled when the row is set to Skip', (tester) async {
      final repos = openTestRepositories();
      await _pumpForEdit(
        tester,
        repos,
        payload: _archivePayload([_dance('d1', 'Skippable')]),
      );
      await _toReview(tester);

      await tester.tap(find.byKey(const ValueKey('import-row-0-skip')));
      await tester.pumpAndSettle();

      final editButton = tester.widget<TextButton>(
        find.byKey(const ValueKey('import-row-0-edit')),
      );
      expect(editButton.onPressed, isNull);
    });
  });

  group('shared bundle (share-target consent, issue #432)', () {
    Dance sharedDance(String id, String title) => Dance(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    // A bundle carrying one new dance, one program referencing it, and one
    // venue the program is set at — exercising the full archive commit path.
    CompendiumArchive danceProgramVenueArchive() => CompendiumArchive(
      exportedAt: DateTime.utc(2026, 7, 15),
      dances: [sharedDance('d1', 'Shared Reel')],
      programs: [
        Program(
          id: 'p1',
          title: 'Shared Spring Fling',
          venueId: 'v1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026, 4, 1),
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
      ],
      venues: [Venue(id: 'v1', name: 'The Grange Hall')],
    );

    SharedBundleImport bundleFor(
      CompendiumArchive archive, {
      int? entityCount,
    }) {
      final json = encodeArchive(archive);
      return SharedBundleImport(
        json: json,
        archive: archive,
        entityCount: entityCount ?? compendiumArchiveEntityCount(archive),
      );
    }

    // Mounts the review screen for a shared [bundle], pushed on top of a home
    // scaffold (mirroring main.dart's `_navigatorKey.push`) so the post-commit
    // Undo snackbar — which rides the app-level ScaffoldMessenger and outlives
    // the popped review route — stays reachable, and returns the refresh
    // notifier so a test can assert it is bumped.
    Future<ValueNotifier<int>> pumpShared(
      WidgetTester tester,
      CompendiumRepositories repos,
      SharedBundleImport bundle,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final refresh = ValueNotifier<int>(0);
      addTearDown(refresh.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: CollectionRefreshScope(revision: refresh, child: child!),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open-review'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImportReviewScreen(
                        sources: [
                          ImportSource(
                            kind: ImportSourceKind.genericJson,
                            adapterFactory: GenericJsonAdapter.new,
                          ),
                        ],
                        sharedBundle: bundle,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-review')));
      await tester.pumpAndSettle();
      return refresh;
    }

    testWidgets(
      'lands directly on the review list and commits NOTHING until Import',
      (tester) async {
        final repos = openTestRepositories();
        addTearDown(repos.db.close);

        await pumpShared(tester, repos, bundleFor(danceProgramVenueArchive()));

        // Skipped the manual input phase — straight to the review/consent list.
        expect(
          find.byKey(const ValueKey('import-review-list')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
        expect(find.text('Shared Reel'), findsOneWidget);

        // The untrusted bundle has written nothing before the user confirms.
        expect(await repos.dances.listAll(), isEmpty);
        expect(await repos.programs.listAll(), isEmpty);
        expect(await repos.venues.listAll(), isEmpty);
      },
    );

    testWidgets(
      'Import commits dances + programs + venues via the archive importer, '
      'shows the transient undo snackbar (no result dialog)',
      (tester) async {
        final repos = openTestRepositories();
        addTearDown(repos.db.close);

        final refresh = await pumpShared(
          tester,
          repos,
          bundleFor(danceProgramVenueArchive()),
        );

        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pumpAndSettle();

        // The whole archive committed — not just the dance.
        final dances = await repos.dances.listAll();
        expect(dances.map((d) => d.title), contains('Shared Reel'));
        expect(await repos.programs.listAll(), hasLength(1));
        expect(await repos.venues.listAll(), hasLength(1));
        expect(refresh.value, greaterThan(0));

        // Share-target path uses the transient snackbar, NOT the manual-import
        // result dialog.
        expect(
          find.byKey(const ValueKey('shared-import-undo-snackbar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('import-result-dialog')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a bundle above the soft cap shows the warning yet still imports; '
      'at or below the cap shows no warning',
      (tester) async {
        final repos = openTestRepositories();
        addTearDown(repos.db.close);

        // entityCount drives the banner directly (computed pre-render by the
        // intake service); pass it explicitly so the commit stays cheap.
        await pumpShared(
          tester,
          repos,
          bundleFor(danceProgramVenueArchive(), entityCount: 501),
        );

        expect(
          find.byKey(const ValueKey('import-soft-cap-warning')),
          findsOneWidget,
        );
        // Soft, not a block: the Import button is still enabled and works.
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('import-commit-button')),
        );
        expect(button.onPressed, isNotNull);

        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pumpAndSettle();
        expect(await repos.programs.listAll(), hasLength(1));
      },
    );

    testWidgets('exactly at the soft cap (500) shows no warning', (
      tester,
    ) async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);

      await pumpShared(
        tester,
        repos,
        bundleFor(
          danceProgramVenueArchive(),
          entityCount: kSharedBundleSoftCapEntities,
        ),
      );

      expect(
        find.byKey(const ValueKey('import-soft-cap-warning')),
        findsNothing,
      );
    });

    testWidgets('the transient Undo removes EXACTLY the imported batch, leaving '
        'pre-existing rows untouched', (tester) async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      // A pre-existing dance the user already had — the undo must not touch it.
      await repos.dances.create(sharedDance('keeper', 'Keeper Jig'));

      await pumpShared(tester, repos, bundleFor(danceProgramVenueArchive()));

      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      // Imported alongside the keeper.
      expect(await repos.dances.listAll(), hasLength(2));
      expect(await repos.programs.listAll(), hasLength(1));
      expect(await repos.venues.listAll(), hasLength(1));

      // Undo the batch.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Precisely the imported batch is gone; the pre-existing row remains.
      final remaining = await repos.dances.listAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.title, 'Keeper Jig');
      expect(await repos.programs.listAll(), isEmpty);
      expect(await repos.venues.listAll(), isEmpty);
    });

    testWidgets(
      'the Undo is transient: after it auto-dismisses the snackbar is gone and '
      'the import is retained',
      (tester) async {
        final repos = openTestRepositories();
        addTearDown(repos.db.close);

        await pumpShared(tester, repos, bundleFor(danceProgramVenueArchive()));

        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('shared-import-undo-snackbar')),
          findsOneWidget,
        );

        // Let the transient timer elapse.
        await tester.pump(kUndoSnackBarDuration + const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('shared-import-undo-snackbar')),
          findsNothing,
        );
        // Undo never fired, so the committed batch is retained.
        expect(await repos.programs.listAll(), hasLength(1));
        expect(await repos.dances.listAll(), hasLength(1));
      },
    );

    testWidgets(
      'suppresses the per-row Edit affordance so nothing writes before the '
      'batch Import consent',
      (tester) async {
        final repos = openTestRepositories();
        addTearDown(repos.db.close);

        await pumpShared(tester, repos, bundleFor(danceProgramVenueArchive()));

        // The dance row renders, but its one-click Edit (which would commit that
        // dance immediately, outside the batch Undo) is gone on the share path.
        expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('import-row-0-edit')), findsNothing);
      },
    );

    testWidgets(
      'a program-only bundle (no dances) can still be imported with consent',
      (tester) async {
        final repos = openTestRepositories();
        addTearDown(repos.db.close);

        // A valid bundle carrying a program of only free-text slots and no
        // dances — intake accepts it, and the pre-#432 path imported it, so the
        // consent screen must still offer an Import.
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          programs: [
            Program(
              id: 'p1',
              title: 'Announcements Night',
              slots: [ProgramSlot(id: 's1', position: 0, text: 'Welcome!')],
              createdAt: DateTime.utc(2026, 4, 1),
              updatedAt: DateTime.utc(2026, 4, 1),
            ),
          ],
        );

        await pumpShared(tester, repos, bundleFor(archive));

        // Lands on the review list with an enabled Import and no dance rows —
        // not the dead-end "no dances" message — and writes nothing yet.
        expect(
          find.byKey(const ValueKey('import-review-list')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('import-row-0')), findsNothing);
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('import-commit-button')),
        );
        expect(button.onPressed, isNotNull);
        expect(await repos.programs.listAll(), isEmpty);

        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pumpAndSettle();

        expect(await repos.programs.listAll(), hasLength(1));
        expect(await repos.dances.listAll(), isEmpty);
        expect(
          find.byKey(const ValueKey('shared-import-undo-snackbar')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'embedded: the Close button is disabled while committing so a mid-commit '
      'close cannot strand the imported data',
      (tester) async {
        // A gate-wrapped in-memory DB lets us hold the commit open in the
        // `committing` phase long enough to inspect the guarded Close button.
        final gate = _CommitGate();
        final repos = CompendiumRepositories(
          CompendiumDatabase(NativeDatabase.memory().interceptWith(gate)),
          contraTaxonomy,
        );
        addTearDown(repos.db.close);
        var closed = 0;
        final refresh = ValueNotifier<int>(0);
        addTearDown(refresh.dispose);
        await tester.binding.setSurfaceSize(const Size(1000, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Embedded (onClose provided): the leading Close invokes onClose
        // directly, which PopScope does NOT intercept — so it must be disabled
        // mid-commit or it would unmount the screen and strand the write.
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: RepositoriesScope(
              repositories: repos,
              child: CollectionRefreshScope(
                revision: refresh,
                child: ImportReviewScreen(
                  sources: [
                    ImportSource(
                      kind: ImportSourceKind.genericJson,
                      adapterFactory: GenericJsonAdapter.new,
                    ),
                  ],
                  sharedBundle: bundleFor(danceProgramVenueArchive()),
                  onClose: () => closed++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        IconButton closeButton() => tester.widget<IconButton>(
          find.byKey(const ValueKey('import-close')),
        );
        // Enabled while reviewing.
        expect(closeButton().onPressed, isNotNull);

        // Arm the gate, then begin the commit: the first write blocks, so the
        // screen stays in its committing phase until we release the gate.
        final commitGate = Completer<void>();
        gate.arm(commitGate);
        await tester.tap(find.byKey(const ValueKey('import-commit-button')));
        await tester.pump();
        expect(find.byKey(const ValueKey('import-committing')), findsOneWidget);
        // Guarded: Close is disabled mid-commit, mirroring the PopScope.
        expect(closeButton().onPressed, isNull);
        expect(closed, 0);

        // Release the gate: the commit finishes, the data lands, the post-commit
        // onClose fires exactly once, and the live collection is refreshed —
        // nothing stranded.
        commitGate.complete();
        await tester.pumpAndSettle();
        expect(await repos.dances.listAll(), hasLength(1));
        expect(await repos.programs.listAll(), hasLength(1));
        expect(await repos.venues.listAll(), hasLength(1));
        expect(closed, 1);
        expect(refresh.value, greaterThan(0));
      },
    );
  });
}

/// A [SourceAdapter] that records the [ImportRequest] it was planned with, so a
/// test can assert the source URL was stashed on [ImportRequest.uri]. Produces
/// one trivial new dance so the review queue renders.
class _CapturingAdapter implements SourceAdapter {
  ImportRequest? lastRequest;

  @override
  ProvenanceSource get source => ProvenanceSource.json;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    lastRequest = request;
    return const [
      DiscoveredRecord(source: ProvenanceSource.json, externalId: 'c1'),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async => RawRecord(
    source: source,
    externalId: record.externalId,
    payload: 'captured',
    contentType: 'text/plain',
  );

  @override
  StructuredDraft parse(RawRecord raw) => StructuredDraft(
    dance: Dance(
      id: 'captured',
      title: 'Captured Dance',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
    raw: raw,
  );
}

/// A [SourceAdapter] that discovers two records but fails to fetch one — used
/// to exercise the review UI's non-blocking batch-error handling.
class _PartlyBrokenAdapter implements SourceAdapter {
  @override
  ProvenanceSource get source => ProvenanceSource.json;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async =>
      const [
        DiscoveredRecord(source: ProvenanceSource.json, externalId: 'ok'),
        DiscoveredRecord(source: ProvenanceSource.json, externalId: 'broken'),
      ];

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    if (record.externalId == 'broken') {
      throw fetchError(source, 'boom', externalId: 'broken');
    }
    return RawRecord(
      source: source,
      externalId: record.externalId,
      payload: 'ok',
      contentType: 'text/plain',
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) => StructuredDraft(
    dance: Dance(
      id: 'good',
      title: 'Good One',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
    raw: raw,
  );
}
