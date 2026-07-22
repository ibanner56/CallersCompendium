import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/widgets/program_status_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// Focused coverage that the Layer 3 Programs & Perform keys resolve through the
/// wired delegates and produce the expected English text — including the
/// app-side [ProgramStatus] label helper (ADR-001: core stays Flutter-free), an
/// ICU plural, and the two compound ICU messages that fold optional clauses via
/// `select` (the perform timing line and a figure's a11y label) so their shapes
/// can't silently drift. Guards against a key referenced in code but missing
/// from the ARB.
void main() {
  testWidgets('representative Programs & Perform keys render in English', (
    tester,
  ) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // App-side ProgramStatus label helper (core stays Flutter-free).
    expect(programStatusLabel(l10n, ProgramStatus.draft), 'Draft');
    expect(programStatusLabel(l10n, ProgramStatus.finalized), 'Finalized');
    expect(programStatusLabel(l10n, ProgramStatus.performed), 'Performed');

    // ICU plural: singular vs. other.
    expect(l10n.performAlternatesCount(1), '1 alternate');
    expect(l10n.performAlternatesCount(3), '3 alternates');

    // Plain placeholder message.
    expect(l10n.performSlotPosition(2, 8), 'Slot 2 of 8');

    // Unpluralised matrix label (kept byte-identical to the pre-l10n code).
    expect(
      l10n.programsMatrixSemanticLabel(2, 1),
      'Programming matrix: 2 dances by 1 moves',
    );

    // Compound perform timing line: optional planned / over / paused clauses
    // fold in via ICU select, with a nested plural on the planned minutes.
    expect(
      l10n.performTimingSemantic('12:34', '3:05', 'no', 0, 'no', 'no'),
      'Program time 12:34, slot time 3:05',
    );
    expect(
      l10n.performTimingSemantic('1:00', '0:30', 'yes', 1, 'no', 'no'),
      'Program time 1:00, slot time 0:30, planned 1 minute',
    );
    expect(
      l10n.performTimingSemantic('12:34', '9:00', 'yes', 8, 'yes', 'yes'),
      'Program time 12:34, slot time 9:00, planned 8 minutes, over planned, '
      'paused',
    );

    // Compound figure a11y label: import-gap text and note flow through
    // placeholders (the import-gap message itself stays owned by a later layer)
    // while progression and the beat count are localised inline.
    expect(
      l10n.performFigureSemantic(
        'partners swing',
        'no',
        '',
        'no',
        16,
        'no',
        '',
      ),
      'partners swing, 16 beats',
    );
    expect(
      l10n.performFigureSemantic('balance', 'no', '', 'yes', 8, 'yes', 'clap'),
      'balance, progression, 8 beats, note: clap',
    );
    expect(
      l10n.performFigureSemantic(
        'x',
        'yes',
        'Custom figure',
        'no',
        4,
        'no',
        '',
      ),
      'x, Custom figure, 4 beats',
    );
  });
}
