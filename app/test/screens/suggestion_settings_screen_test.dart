// Settings ▸ Experimental ▸ Suggestions and its editor (#2343), with Use in
// Perform's Swap this dance (#2348).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/suggestions_scope.dart';
import 'package:compendium_app/src/screens/settings/suggestion_settings_screen.dart';

import '../support/dropdown.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

class _Harness {
  _Harness(this.repos, this.enabled, this.settings, this.inPerformSwap);
  final CompendiumRepositories repos;
  final ValueNotifier<bool> enabled;
  final ValueNotifier<SuggestionSettingsRead> settings;
  final ValueNotifier<bool> inPerformSwap;
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget home, {
  bool enabled = false,
  SuggestionSettingsRead read = (
    settings: const SuggestionSettings(),
    isNewer: false,
  ),
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repos = openTestRepositories();
  final enabledNotifier = ValueNotifier<bool>(enabled);
  addTearDown(enabledNotifier.dispose);
  final settings = ValueNotifier<SuggestionSettingsRead>(read);
  addTearDown(settings.dispose);
  final inPerformSwap = ValueNotifier<bool>(false);
  addTearDown(inPerformSwap.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: SuggestionsEnabledScope(
          notifier: enabledNotifier,
          child: SuggestionsInPerformSwapScope(
            notifier: inPerformSwap,
            child: SuggestionSettingsScope(notifier: settings, child: child!),
          ),
        ),
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(repos, enabledNotifier, settings, inPerformSwap);
}

Finder _segment(SuggestionFactor factor, String label) => find.descendant(
  of: find.byKey(ValueKey('suggestion-weight-${factor.name}')),
  matching: find.text(label),
);

SuggestionWeight _selected(WidgetTester tester, SuggestionFactor factor) =>
    tester
        .widget<SegmentedButton<SuggestionWeight>>(
          find.byKey(ValueKey('suggestion-weight-${factor.name}')),
        )
        .selected
        .single;

Future<SuggestionSettingsRead> _stored(_Harness h) async =>
    readSuggestionSettings(await h.repos.settings.get(kSuggestionSettingsKey));

void main() {
  testWidgets('the Experimental toggle is off by default, and turning it on '
      'sets and saves suggestions_enabled', (tester) async {
    final h = await _pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: SuggestionsSection())),
    );
    // Off, the section starts collapsed, like the Glossary group above it.
    await tester.tap(find.text('Suggestions'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(
      const ValueKey('experimental-suggestions-enabled'),
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await h.repos.settings.get(kSuggestionsEnabledKey), isNull);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(h.enabled.value, isTrue);
    expect(await h.repos.settings.get(kSuggestionsEnabledKey), isTrue);

    await tester.tap(
      find.byKey(const ValueKey('experimental-suggestions-open')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SuggestionSettingsScreen), findsOneWidget);
  });

  testWidgets('Use in Perform\'s Swap this dance shows only while '
      'Suggestions is on, is off by default, and saves '
      'suggestions_in_perform_swap (#2348)', (tester) async {
    final h = await _pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: SuggestionsSection())),
    );
    await tester.tap(find.text('Suggestions'));
    await tester.pumpAndSettle();
    final swap = find.byKey(
      const ValueKey('experimental-suggestions-in-perform-swap'),
    );
    expect(swap, findsNothing, reason: 'Suggestions is off');

    await tester.tap(
      find.byKey(const ValueKey('experimental-suggestions-enabled')),
    );
    await tester.pumpAndSettle();
    expect(swap, findsOneWidget);
    expect(find.text("Use in Perform's Swap this dance"), findsOneWidget);
    expect(tester.widget<SwitchListTile>(swap).value, isFalse);
    expect(await h.repos.settings.get(kSuggestionsInPerformSwapKey), isNull);
    expect(
      tester.getSize(swap).height,
      greaterThanOrEqualTo(48),
      reason: 'a full-size row',
    );

    await tester.tap(swap);
    await tester.pumpAndSettle();
    expect(h.inPerformSwap.value, isTrue);
    expect(await h.repos.settings.get(kSuggestionsInPerformSwapKey), isTrue);

    // Turning Suggestions off hides it, and leaves its own value alone.
    await tester.tap(
      find.byKey(const ValueKey('experimental-suggestions-enabled')),
    );
    await tester.pumpAndSettle();
    expect(swap, findsNothing);
    expect(h.inPerformSwap.value, isTrue);
  });

  testWidgets('the editor shows the shipped defaults, in words only', (
    tester,
  ) async {
    await _pump(tester, const SuggestionSettingsScreen());
    expect(
      _selected(tester, SuggestionFactor.matrixVariety),
      SuggestionWeight.aLot,
    );
    expect(
      _selected(tester, SuggestionFactor.formationBalance),
      SuggestionWeight.aLittle,
    );
    expect(
      _selected(tester, SuggestionFactor.difficultyCurve),
      SuggestionWeight.aLittle,
    );
    expect(
      _selected(tester, SuggestionFactor.venueRecency),
      SuggestionWeight.aLot,
    );
    // No weights as numbers anywhere.
    for (final digit in ['0', '1', '3', '0.5']) {
      expect(find.text(digit), findsNothing, reason: digit);
    }
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('suggestion-settings-reset')),
          )
          .onPressed,
      isNull,
      reason: 'nothing to reset',
    );
  });

  testWidgets('choosing Off for a factor saves it, and the other choices '
      'stay', (tester) async {
    final h = await _pump(tester, const SuggestionSettingsScreen());
    await tester.tap(_segment(SuggestionFactor.matrixVariety, 'Off'));
    await tester.pumpAndSettle();

    expect(
      _selected(tester, SuggestionFactor.matrixVariety),
      SuggestionWeight.off,
    );
    final stored = await _stored(h);
    expect(stored.settings.matrixVariety, SuggestionWeight.off);
    expect(stored.settings.venueRecency, SuggestionWeight.aLot);
    expect(h.settings.value.settings, stored.settings);
  });

  testWidgets('the curve shape and venue window save their choices', (
    tester,
  ) async {
    final h = await _pump(tester, const SuggestionSettingsScreen());
    await pickDropdownValue(
      tester,
      find.byKey(const ValueKey('suggestion-curve-shape')),
      DifficultyCurveShape.even,
    );
    await pickDropdownValue(
      tester,
      find.byKey(const ValueKey('suggestion-venue-window')),
      VenueRecencyWindow.sixMonths,
    );
    final stored = await _stored(h);
    expect(stored.settings.curveShape, DifficultyCurveShape.even);
    expect(stored.settings.venueWindow, VenueRecencyWindow.sixMonths);
  });

  testWidgets('Reset to defaults writes the shipped defaults and keeps what '
      'this build cannot read', (tester) async {
    final changed = readSuggestionSettings({
      'version': 1,
      'factors': {
        'matrixVariety': {'weight': 'off'},
        'difficultyCurve': {'weight': 'aLot', 'shape': 'even'},
        'futureFactor': {'weight': 'aLot'},
      },
      'preferences': [
        {'savedSearchId': 's1', 'mode': 'prefer'},
      ],
    });
    final h = await _pump(
      tester,
      const SuggestionSettingsScreen(),
      read: changed,
    );
    expect(
      _selected(tester, SuggestionFactor.matrixVariety),
      SuggestionWeight.off,
    );

    await tester.tap(find.byKey(const ValueKey('suggestion-settings-reset')));
    await tester.pumpAndSettle();

    expect(
      find.text('Suggestions look for the default things again.'),
      findsOneWidget,
    );
    expect(
      _selected(tester, SuggestionFactor.matrixVariety),
      SuggestionWeight.aLot,
    );
    final stored = await _stored(h);
    expect(stored.settings.hasDefaultChoices, isTrue);
    final json = stored.settings.toJson();
    expect((json['factors']! as Map).containsKey('futureFactor'), isTrue);
    expect(json['preferences'], [
      {'savedSearchId': 's1', 'mode': 'prefer'},
    ]);
  });

  testWidgets('Undo after Reset to defaults writes back the choices it '
      'replaced', (tester) async {
    // Reset acts at once (it can be undone, so it does not ask first); the
    // prompt it shows must carry an Undo that puts the caller's choices back.
    final changed = readSuggestionSettings({
      'version': 1,
      'factors': {
        'matrixVariety': {'weight': 'off'},
        'difficultyCurve': {'weight': 'aLot', 'shape': 'even'},
      },
    });
    final h = await _pump(
      tester,
      const SuggestionSettingsScreen(),
      read: changed,
    );

    await tester.tap(find.byKey(const ValueKey('suggestion-settings-reset')));
    await tester.pumpAndSettle();
    expect((await _stored(h)).settings.hasDefaultChoices, isTrue);

    final undo = find.byKey(const ValueKey('suggestion-settings-reset-undo'));
    expect(undo, findsOneWidget);
    await tester.tap(undo);
    await tester.pumpAndSettle();

    final want = changed.settings.toJson();
    expect(h.settings.value.settings.toJson(), want);
    expect((await _stored(h)).settings.toJson(), want);
    expect(
      _selected(tester, SuggestionFactor.matrixVariety),
      SuggestionWeight.off,
    );
  });

  testWidgets('Undo after Reset to defaults keeps a choice made since, and '
      'says it failed', (tester) async {
    final changed = readSuggestionSettings({
      'version': 1,
      'factors': {
        'matrixVariety': {'weight': 'off'},
      },
    });
    final h = await _pump(
      tester,
      const SuggestionSettingsScreen(),
      read: changed,
    );
    await tester.tap(find.byKey(const ValueKey('suggestion-settings-reset')));
    await tester.pumpAndSettle();

    // A choice made after the reset, here or synced in from another device.
    await tester.tap(_segment(SuggestionFactor.formationBalance, 'A lot'));
    await tester.pumpAndSettle();
    final since = h.settings.value.settings.toJson();

    await tester.tap(
      find.byKey(const ValueKey('suggestion-settings-reset-undo')),
    );
    await tester.pumpAndSettle();

    expect(h.settings.value.settings.toJson(), since);
    expect((await _stored(h)).settings.toJson(), since);
    expect(find.byKey(const ValueKey('undo-failed-snackbar')), findsOneWidget);
  });

  testWidgets("Undo after Reset to defaults keeps a peer's kept part that "
      'synced in meanwhile', (tester) async {
    final h = await _pump(
      tester,
      const SuggestionSettingsScreen(),
      read: readSuggestionSettings({
        'version': 1,
        'factors': {
          'matrixVariety': {'weight': 'off'},
        },
      }),
    );
    await tester.tap(find.byKey(const ValueKey('suggestion-settings-reset')));
    await tester.pumpAndSettle();

    // Another device's value arrives: the default choices, plus a part this
    // build does not read, which it must keep.
    h.settings.value = readSuggestionSettings({
      'version': 1,
      'factors': <String, Object?>{},
      'peerOnly': 'kept',
    });
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('suggestion-settings-reset-undo')),
    );
    await tester.pumpAndSettle();

    final stored = (await _stored(h)).settings;
    expect(stored.matrixVariety, SuggestionWeight.off);
    expect(stored.toJson()['peerOnly'], 'kept');
  });

  testWidgets('a value saved by a newer version is shown read-only and never '
      'overwritten', (tester) async {
    final h = await _pump(
      tester,
      const SuggestionSettingsScreen(),
      read: readSuggestionSettings({
        'version': 2,
        'factors': <String, Object?>{},
      }),
    );
    expect(
      find.byKey(const ValueKey('suggestion-settings-newer')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<SuggestionWeight>>(
            find.byKey(const ValueKey('suggestion-weight-matrixVariety')),
          )
          .onSelectionChanged,
      isNull,
    );
    await tester.tap(_segment(SuggestionFactor.matrixVariety, 'Off'));
    await tester.pumpAndSettle();
    expect(await h.repos.settings.get(kSuggestionSettingsKey), isNull);
    expect(h.settings.value.isNewer, isTrue);
  });
}
