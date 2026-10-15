import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
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
}
