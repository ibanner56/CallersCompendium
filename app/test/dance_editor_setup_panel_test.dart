import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dance_editor_setup.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// The setup panel (Credits, formation and music): when it starts folded,
/// what its summary says, that Save opens it to show an error inside, and
/// that its fields share rows only where they fit.
Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? danceId,
  Size size = const Size(1200, 2400),
}) async {
  await tester.binding.setSurfaceSize(size);
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
      // A fresh screen on each pump, so a second pump in a test starts over.
      home: DanceEditorScreen(key: UniqueKey(), danceId: danceId),
    ),
  );
  await tester.pumpAndSettle();
}

Future<CompendiumRepositories> _ecdDance() async {
  final repos = openTestRepositories();
  // ignore: unused_result
  await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Pat Shaw'));
  await repos.dances.create(
    Dance(
      id: 'd1',
      title: 'Hole in the Wall',
      form: DanceForm.ecd,
      authorIds: const ['c1'],
      formation: const Formation(FormationShape.dupleMinor, improper: true),
      meter: '3/2',
      musicalKey: 'D minor',
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return repos;
}

final _summary = find.byKey(const ValueKey('setup-summary'));
final _formation = find.byKey(const ValueKey('formation-field'));

void main() {
  testWidgets('an existing dance opens with the panel folded to a summary', (
    tester,
  ) async {
    await _pump(tester, await _ecdDance(), danceId: 'd1');
    expect(_formation, findsNothing);
    expect(
      tester.widget<Text>(_summary).data,
      'Pat Shaw · English (ECD) · Duple minor · Starts improper · 3/2 · D minor',
    );
    await openDanceEditorSetup(tester);
    expect(_formation, findsOneWidget);
    // Open, the summary gives way to the fields.
    expect(_summary, findsNothing);
  });

  testWidgets('a new dance opens the panel on a wide form, not on a phone', (
    tester,
  ) async {
    await _pump(tester, openTestRepositories());
    expect(_formation, findsOneWidget);
    expect(_summary, findsNothing);

    await _pump(tester, openTestRepositories(), size: const Size(390, 2400));
    expect(_formation, findsNothing);
    expect(_summary, findsOneWidget);
  });

  testWidgets('a folded panel leaves the focus order', (tester) async {
    await _pump(tester, await _ecdDance(), danceId: 'd1');
    final focusable = find.descendant(
      of: find.byKey(const ValueKey('setup-tile')),
      matching: find.byType(EditableText, skipOffstage: false),
      skipOffstage: false,
    );
    expect(focusable, findsWidgets);
    for (final element in focusable.evaluate()) {
      expect(Focus.of(element).canRequestFocus, isFalse);
    }
  });

  testWidgets('Save opens a folded panel to show the error inside it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(id: 'd1', title: 'Contra', createdAt: _now, updatedAt: _now),
    );
    await _pump(tester, repos, danceId: 'd1');
    await openDanceEditorSetup(tester);
    await tester.enterText(find.byKey(const ValueKey('phrase-field')), 'x*y');
    await tester.pumpAndSettle();
    // Fold it again, error unseen.
    await tester.tap(find.text('Credits, formation and music'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('phrase-field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('phrase-field')), findsOneWidget);
    final field = tester.state<FormFieldState<String>>(
      find.byKey(const ValueKey('phrase-field')),
    );
    expect(field.hasError, isTrue);
    expect((await repos.dances.getById('d1'))!.title, 'Contra');
  });

  testWidgets('type and formation share a row on a wide form, and stack on '
      'a phone', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDefaultDanceFormKey, 'ecd');
    final type = find.byKey(const ValueKey('form-field'));
    await _pump(tester, repos);
    expect(tester.getTopLeft(type).dy, tester.getTopLeft(_formation).dy);
    // An English dance's two credit lines share a row too.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('authors-credit-line'))).dy,
      tester
          .getTopLeft(find.byKey(const ValueKey('interpreters-credit-line')))
          .dy,
    );

    await _pump(tester, repos, size: const Size(390, 2400));
    await openDanceEditorSetup(tester);
    expect(
      tester.getTopLeft(_formation).dy,
      greaterThan(tester.getBottomLeft(type).dy),
    );
  });
}
