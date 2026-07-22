import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// Focused coverage that the Layer 2 Collection & Dance keys resolve through
/// the wired delegates and produce the expected English text — including a
/// placeholder substitution and an ICU plural. Guards against a key being
/// referenced in code but missing from the ARB, and against the plural/
/// placeholder shapes drifting.
void main() {
  testWidgets('representative Collection & Dance keys render in English', (
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

    // Plain area-prefixed keys.
    expect(l10n.danceScreenTitle, 'Dance');
    expect(l10n.danceSectionFigures, 'Figures');
    expect(l10n.danceNotFound, 'Dance not found.');

    // Shared common key with a placeholder.
    expect(l10n.commonDeletedSnack('Chorus Jig'), '"Chorus Jig" deleted.');

    // ICU plural: singular vs. other.
    expect(l10n.danceFigureBeats(1), '1 beat');
    expect(l10n.danceFigureBeats(4), '4 beats');
    expect(l10n.danceHalfStatsFirstHalf(2), 'Called 2 times in the first half');
  });
}
