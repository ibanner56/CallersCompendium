// The dance editor at the narrowest phone width with the largest text the
// app is tested at (pre-release audit finding B-12): nothing in it may
// overflow, for a contra dance or a square, with a figure list whose beats
// do not fill the phrase structure (so the beat warning shows).
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/screen_size.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Future<void> _pumpEditor(WidgetTester tester, Dance dance) async {
  final repos = openTestRepositories();
  await repos.dances.create(dance);
  // Tall enough that the whole editor, figure list included, is laid out
  // without scrolling; only the width is a small phone's.
  await setScreenSize(tester, const Size(320, 6000));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final shorthands = ShorthandMappingsController(repos.settings);
  addTearDown(shorthands.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ShorthandMappingsScope(
              controller: shorthands,
              child: child!,
            ),
          ),
        ),
      ),
      home: DanceEditorScreen(danceId: dance.id),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every layout overflow reported while [body] runs.
Future<List<String>> _overflows(Future<void> Function() body) async {
  final reported = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      final where = details.informationCollector?.call().join('\n') ?? '';
      reported.add('$text\n${where.split('\n').take(12).join('\n')}');
    } else {
      previous?.call(details);
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reported;
}

void main() {
  for (final (form, figure) in [
    (
      DanceForm.contra,
      Figure(move: 'swing', params: const {'who': 'partners'}),
    ),
    (
      DanceForm.square,
      Figure(
        move: 'sq_swing',
        params: const {'who': 'everyone', 'whom': 'corners'},
      ),
    ),
  ]) {
    testWidgets('a ${form.name} dance with a beat warning does not overflow '
        'at 320 dp with 2x text', (tester) async {
      final dance = Dance(
        id: 'd1',
        title: 'Narrow',
        form: form,
        figures: [figure],
        createdAt: _now,
        updatedAt: _now,
      );
      final overflows = await _overflows(() => _pumpEditor(tester, dance));
      // The warning the figures' beats raise is on screen, so the row that
      // overflowed is laid out.
      expect(
        find.byKey(const ValueKey('figure-beats-warning')),
        findsOneWidget,
      );
      expect(overflows, isEmpty, reason: overflows.join('\n\n'));
    });
  }
}
