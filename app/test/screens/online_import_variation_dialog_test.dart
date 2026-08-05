import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/screens/online_import_variation_dialog.dart';

import '../support/l10n_harness.dart';

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
}
