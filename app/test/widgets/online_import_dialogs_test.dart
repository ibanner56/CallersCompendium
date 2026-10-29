import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_app/src/widgets/online_import_dialogs.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Pumps a trigger button, opens [showOnlineImportVariationDialog], and
/// returns the result future.
Future<Future<DedupeResolution?> Function()> _pumpVariationDialog(
  WidgetTester tester, {
  String existingTitle = 'Tangled Yarns',
  String existingId = 'dance-001',
}) async {
  DedupeResolution? result;
  var completed = false;
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            key: const ValueKey('open-dialog'),
            onPressed: () async {
              final l10n = AppLocalizations.of(ctx);
              result = await showOnlineImportVariationDialog(
                ctx,
                l10n,
                existingTitle: existingTitle,
                existingId: existingId,
              );
              completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  return () async {
    while (!completed) {
      await tester.pumpAndSettle();
    }
    return result;
  };
}

/// Pumps a trigger button, opens [showOnlineImportCrossSourceDuplicateDialog],
/// and returns the result future.
Future<Future<DedupeResolution?> Function()> _pumpCrossSourceDialog(
  WidgetTester tester, {
  String existingTitle = 'Tangled Yarns',
  String existingId = 'dance-002',
}) async {
  DedupeResolution? result;
  var completed = false;
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            key: const ValueKey('open-dialog'),
            onPressed: () async {
              final l10n = AppLocalizations.of(ctx);
              result = await showOnlineImportCrossSourceDuplicateDialog(
                ctx,
                l10n,
                existingTitle: existingTitle,
                existingId: existingId,
              );
              completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  return () async {
    while (!completed) {
      await tester.pumpAndSettle();
    }
    return result;
  };
}

/// Fake service: the first import returns [firstKind]; once a resolution is
/// supplied it returns `created`. Records every call so a test can see which
/// resolution (if any) was retried.
class _ConfirmingService implements OnlineSearchService {
  _ConfirmingService(this.firstKind);

  final OnlineImportKind firstKind;
  final resolutions = <DedupeResolution?>[];

  @override
  OnlineSource get source => OnlineSource.callersBox;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) =>
      throw UnimplementedError();

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) => throw UnimplementedError();

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
    List<String> defaultTagIds = const [],
  }) async {
    resolutions.add(ambiguousResolution);
    if (ambiguousResolution == null) {
      return OnlineImportResult(
        kind: firstKind,
        title: 'Existing Dance',
        danceId: 'existing',
      );
    }
    return const OnlineImportResult(
      kind: OnlineImportKind.created,
      title: 'Remote Dance',
      danceId: 'imported',
    );
  }
}

OnlinePreview _preview() {
  final dance = Dance(
    id: '',
    title: 'Remote Dance',
    authorIds: const [],
    tagIds: const [],
    tunes: const [],
    form: DanceForm.contra,
    formation: const Formation(FormationShape.dupleImproper),
    status: DanceStatus.active,
    figures: const [],
    customFields: const [],
    hook: '',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
  return OnlinePreview(
    result: OnlineSearchResultRow(
      source: OnlineSource.callersBox,
      id: 'remote',
      name: 'Remote Dance',
      author: '',
      formation: '',
    ),
    detail: DanceDetailData(
      dance: dance,
      authorNames: const [],
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

/// Pumps a button that runs [resolveAndImportOnline] against [service]; the
/// returned callback awaits the helper's result.
Future<Future<OnlineImportResult?> Function()> _pumpResolve(
  WidgetTester tester,
  _ConfirmingService service,
) async {
  OnlineImportResult? result;
  var completed = false;
  final repos = openTestRepositories();
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            key: const ValueKey('open-dialog'),
            onPressed: () async {
              result = await resolveAndImportOnline(
                ctx,
                service: service,
                repos: repos,
                preview: _preview(),
                l10n: AppLocalizations.of(ctx),
              );
              completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-dialog')));
  return () async {
    while (!completed) {
      await tester.pumpAndSettle();
    }
    return result;
  };
}

void main() {
  group('showOnlineImportVariationDialog (#797)', () {
    testWidgets('Cancel returns null', (tester) async {
      final getResult = await _pumpVariationDialog(tester);
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('online-import-variation-cancel')),
      );
      final result = await getResult();
      expect(result, isNull);
    });

    testWidgets('variation button returns DedupeResolution.variation', (
      tester,
    ) async {
      final getResult = await _pumpVariationDialog(
        tester,
        existingId: 'dance-xyz',
      );
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('online-import-variation-as-variation')),
      );
      final result = await getResult();
      expect(result?.kind, DedupeResolutionKind.variation);
      expect(result?.targetDanceId, 'dance-xyz');
    });

    testWidgets('same-dance button returns DedupeResolution.link', (
      tester,
    ) async {
      final getResult = await _pumpVariationDialog(
        tester,
        existingId: 'dance-abc',
      );
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('online-import-variation-same-dance')),
      );
      final result = await getResult();
      expect(result?.kind, DedupeResolutionKind.link);
      expect(result?.targetDanceId, 'dance-abc');
    });
  });

  group('showOnlineImportCrossSourceDuplicateDialog (#811)', () {
    testWidgets('Cancel returns null — nothing is written', (tester) async {
      // RED (naive regression): if the cross-source dialog were skipped and
      // the identical-figures case fell through to duplicate(), no dialog
      // would appear. This test ensures the dialog shows and Cancel returns
      // null (so the caller writes nothing).
      final getResult = await _pumpCrossSourceDialog(tester);
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-dialog'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-cancel'),
        ),
      );
      final result = await getResult();
      expect(result, isNull);
    });

    testWidgets(
      '"Same dance" returns DedupeResolution.link — no variation offered',
      (tester) async {
        // The dialog must NOT offer "Import as a variation" for identical-figure
        // cross-source imports: a variation of canonically identical figures
        // would be indistinguishable in its figures from the original — the
        // original problem wearing a button.
        final getResult = await _pumpCrossSourceDialog(
          tester,
          existingId: 'dance-def',
        );
        await tester.tap(find.byKey(const ValueKey('open-dialog')));
        await tester.pumpAndSettle();

        // Variation button must be absent.
        expect(
          find.byKey(const ValueKey('online-import-variation-as-variation')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(
            const ValueKey('online-import-cross-source-duplicate-same-dance'),
          ),
        );
        final result = await getResult();
        expect(result?.kind, DedupeResolutionKind.link);
        expect(result?.targetDanceId, 'dance-def');
      },
    );

    testWidgets('"Import a second copy" returns DedupeResolution.duplicate', (
      tester,
    ) async {
      // RED (naive regression): removing the "Import a second copy" button
      // leaves the user with no way to keep both sources, because Cancel
      // aborts the import entirely. This test confirms the button is present
      // and returns DedupeResolution.duplicate (which the pipeline commits as
      // a new dance via CommitAction.duplicate, creating the second copy).
      final getResult = await _pumpCrossSourceDialog(tester);
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();

      // Button must be present.
      expect(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-import-copy'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-import-copy'),
        ),
      );
      final result = await getResult();
      expect(result?.kind, DedupeResolutionKind.duplicate);
    });

    testWidgets('dialog title reads as expected', (tester) async {
      final getResult = await _pumpCrossSourceDialog(tester);
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();

      // The title is the localized cross-source key, not the variation one.
      expect(find.text('You already have this dance'), findsOneWidget);
      // The variation dialog title ("Variation of ...?") must not appear.
      expect(find.textContaining('Variation of'), findsNothing);

      // Dismiss to keep test clean.
      await tester.tap(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-cancel'),
        ),
      );
      await getResult();
    });

    // INTAKE-5: the dialog is also shown for a dance the user typed in, which
    // has no source, so its wording must not claim one.
    testWidgets('its body names no source', (tester) async {
      final getResult = await _pumpCrossSourceDialog(tester);
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your collection already has "Tangled Yarns". Both versions have '
          'the same sequence of moves.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('source'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-cancel'),
        ),
      );
      await getResult();
    });
  });

  group('resolveAndImportOnline', () {
    testWidgets('retries with the chosen resolution after needsConfirmation', (
      tester,
    ) async {
      final service = _ConfirmingService(OnlineImportKind.needsConfirmation);
      final getResult = await _pumpResolve(tester, service);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('online-import-variation-as-variation')),
      );
      final result = await getResult();

      expect(result?.kind, OnlineImportKind.created);
      expect(service.resolutions, hasLength(2));
      expect(service.resolutions[0], isNull);
      expect(service.resolutions[1]?.kind, DedupeResolutionKind.variation);
      expect(service.resolutions[1]?.targetDanceId, 'existing');
    });

    testWidgets(
      'retries with the chosen resolution after needsConfirmationIdentical',
      (tester) async {
        final service = _ConfirmingService(
          OnlineImportKind.needsConfirmationIdentical,
        );
        final getResult = await _pumpResolve(tester, service);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey('online-import-cross-source-duplicate-import-copy'),
          ),
        );
        final result = await getResult();

        expect(result?.kind, OnlineImportKind.created);
        expect(service.resolutions[1]?.kind, DedupeResolutionKind.duplicate);
      },
    );

    testWidgets(
      'returns null and writes nothing when the dialog is cancelled',
      (tester) async {
        final service = _ConfirmingService(OnlineImportKind.needsConfirmation);
        final getResult = await _pumpResolve(tester, service);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('online-import-variation-cancel')),
        );
        final result = await getResult();

        expect(result, isNull);
        // Only the probing import ran; no resolved retry was committed.
        expect(service.resolutions, [isNull]);
      },
    );

    testWidgets('returns the first result untouched when no confirmation is '
        'needed', (tester) async {
      final service = _ConfirmingService(OnlineImportKind.alreadyInCollection);
      final getResult = await _pumpResolve(tester, service);
      final result = await getResult();

      expect(result?.kind, OnlineImportKind.alreadyInCollection);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.resolutions, [isNull]);
    });
  });

  group('resolveAndImportOnline: possible matches (#1907)', () {
    // The real Caller's Box service and a real collection: `A-1 Reel
    // {variant}` by Chris Weiler arriving beside his `A1 Reel (Imp Var)`.
    Future<
      ({
        CompendiumRepositories repos,
        Future<OnlineImportResult?> Function() run,
      })
    >
    pump(WidgetTester tester, {bool deleteCandidate = false}) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'weiler', name: 'Chris Weiler'),
      );
      final stamp = DateTime.utc(2026);
      await repos.dances.create(
        Dance(
          id: 'impvar',
          title: 'A1 Reel (Imp Var)',
          authorIds: const ['weiler'],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      final service = CallersBoxOnline(
        jsonFetcher: (_) async => jsonEncode({
          'ID': '1606',
          'Name': 'A-1 Reel {variant}',
          'Authors': ['Chris Weiler'],
          'Permission': 'full',
          'phrases': [
            {
              'name': 'A1',
              'figures': ['(8) Long lines forward and back'],
            },
          ],
        }),
      );
      final preview = await service.loadPreview(
        repos,
        const OnlineSearchResultRow(
          source: OnlineSource.callersBox,
          id: '1606',
          name: '',
          author: '',
          formation: '',
        ),
      );
      if (deleteCandidate) {
        await repos.dances.softDelete('impvar', at: DateTime.utc(2026, 2));
      }
      OnlineImportResult? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                key: const ValueKey('open-dialog'),
                onPressed: () async {
                  result = await resolveAndImportOnline(
                    ctx,
                    service: service,
                    repos: repos,
                    preview: preview,
                    l10n: AppLocalizations.of(ctx),
                  );
                  completed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();
      return (
        repos: repos,
        run: () async {
          while (!completed) {
            await tester.pumpAndSettle();
          }
          return result;
        },
      );
    }

    testWidgets('"Import as a new dance" adds a dance and replaces nothing', (
      tester,
    ) async {
      final (:repos, :run) = await pump(tester);
      await tester.tap(
        find.byKey(const ValueKey('online-import-possible-match-new')),
      );
      final result = await run();

      expect(result?.kind, OnlineImportKind.created);
      expect(result?.danceId, isNot('impvar'));
      expect(await repos.dances.listAll(), hasLength(2));
      expect(
        (await repos.dances.getById('impvar'))!.title,
        'A1 Reel (Imp Var)',
      );
    });

    testWidgets('Cancel returns null and writes nothing', (tester) async {
      final (:repos, :run) = await pump(tester);
      await tester.tap(
        find.byKey(const ValueKey('online-import-possible-match-cancel')),
      );

      expect(await run(), isNull);
      expect(await repos.dances.listAll(), hasLength(1));
    });

    testWidgets('a candidate deleted since the preview leaves nothing to ask '
        'about, so the dance is simply added', (tester) async {
      final (:repos, :run) = await pump(tester, deleteCandidate: true);

      expect(
        find.byKey(const ValueKey('online-import-possible-match-dialog')),
        findsNothing,
      );
      final result = await run();
      expect(result?.kind, OnlineImportKind.created);
      expect(await repos.dances.listAll(), hasLength(1));
    });
  });

  group('resolveAndImportOnline: a figureless record', () {
    // The Caller's Box record for a dance whose permission is below `full`:
    // metadata only. Replacing a dance with it would erase its figures.
    final figurelessJson = jsonEncode({
      'ID': '1606',
      'Name': 'A-1 Reel {variant}',
      'Authors': ['Chris Weiler'],
      'Permission': 'limited',
      'FormationBase': 'Duple Minor - Improper',
      'Progression': 'Single',
    });

    Future<
      ({
        CompendiumRepositories repos,
        Future<OnlineImportResult?> Function() run,
      })
    >
    pump(
      WidgetTester tester, {
      required String existingTitle,
      Provenance? provenance,
      bool existingHasFigures = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'weiler', name: 'Chris Weiler'),
      );
      final stamp = DateTime.utc(2026);
      await repos.dances.create(
        Dance(
          id: 'mine',
          title: existingTitle,
          authorIds: const ['weiler'],
          figures: existingHasFigures
              ? [customFigure('Circle left once around')]
              : const [],
          provenance: provenance,
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      final service = CallersBoxOnline(
        jsonFetcher: (_) async => figurelessJson,
      );
      final preview = await service.loadPreview(
        repos,
        const OnlineSearchResultRow(
          source: OnlineSource.callersBox,
          id: '1606',
          name: '',
          author: '',
          formation: '',
        ),
      );
      OnlineImportResult? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                key: const ValueKey('open-dialog'),
                onPressed: () async {
                  result = await resolveAndImportOnline(
                    ctx,
                    service: service,
                    repos: repos,
                    preview: preview,
                    l10n: AppLocalizations.of(ctx),
                  );
                  completed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();
      return (
        repos: repos,
        run: () async {
          while (!completed) {
            await tester.pumpAndSettle();
          }
          return result;
        },
      );
    }

    Future<void> expectMineUntouched(CompendiumRepositories repos) async {
      final mine = (await repos.dances.getById('mine'))!;
      expect(mine.figuresSource, isA<DecodedFigures>());
      expect((mine.figuresSource as DecodedFigures).figures, hasLength(1));
    }

    testWidgets('under another title is added as a new dance without asking '
        'which dance to replace', (tester) async {
      final (:repos, :run) = await pump(
        tester,
        existingTitle: 'A1 Reel (Imp Var)',
      );

      expect(
        find.byKey(const ValueKey('online-import-possible-match-dialog')),
        findsNothing,
      );
      final result = await run();
      expect(result?.kind, OnlineImportKind.created);
      expect(result?.danceId, isNot('mine'));
      expect(await repos.dances.listAll(), hasLength(2));
      await expectMineUntouched(repos);
    });

    testWidgets('matching your dance with different figures cannot replace it, '
        'but can still be a variation', (tester) async {
      final (:repos, :run) = await pump(
        tester,
        existingTitle: 'A-1 Reel {variant}',
      );

      expect(
        find.byKey(const ValueKey('online-import-variation-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('online-import-variation-same-dance')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('online-import-variation-as-variation')),
      );
      final result = await run();

      expect(result?.kind, OnlineImportKind.created);
      expect(result?.danceId, isNot('mine'));
      expect(await repos.dances.listAll(), hasLength(2));
      await expectMineUntouched(repos);
    });

    testWidgets('identical to a copy from another source (both empty) cannot '
        'replace it either', (tester) async {
      final (:repos, :run) = await pump(
        tester,
        existingTitle: 'A-1 Reel {variant}',
        existingHasFigures: false,
        provenance: Provenance(
          source: ProvenanceSource.contradb,
          externalId: '77',
          importedAt: DateTime.utc(2026),
        ),
      );

      expect(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-dialog'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-same-dance'),
        ),
        findsNothing,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-import-copy'),
        ),
      );
      final result = await run();

      expect(result?.kind, OnlineImportKind.created);
      expect(await repos.dances.listAll(), hasLength(2));
    });
  });
}
