import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

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
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RepositoriesScope(
        repositories: repos,
        child: ImportReviewScreen(
          adapterFactory: adapterFactory ?? GenericJsonAdapter.new,
          sourceLabel: 'test JSON',
          picker: () async => payload,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    // The reimport option is offered and selected by default.
    expect(find.byKey(const ValueKey('import-row-0-reimport')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    expect(all.length, 1);
    expect(all.single.id, 'existing');
    expect(all.single.title, 'Refreshed Title');
  });

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
