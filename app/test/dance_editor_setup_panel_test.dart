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

  testWidgets('a folded panel leaves the focus order, and an open one '
      'rejoins it', (tester) async {
    await _pump(tester, await _ecdDance(), danceId: 'd1');
    // Each field's own node, which the field creates below its EditableText;
    // `Focus.of` would find the wrapper above it instead.
    List<FocusNode> nodes() => tester
        .widgetList<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('setup-tile'), skipOffstage: false),
            matching: find.byType(EditableText, skipOffstage: false),
            skipOffstage: false,
          ),
        )
        // A dropdown's closed value is read-only text that never takes focus
        // itself (the dropdown does), so only the fields typed into count.
        .where((field) => !field.readOnly)
        .map((field) => field.focusNode)
        .toList();
    expect(nodes(), isNotEmpty);
    for (final node in nodes()) {
      expect(node.canRequestFocus, isFalse);
    }
    await openDanceEditorSetup(tester);
    for (final node in nodes()) {
      expect(node.canRequestFocus, isTrue);
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

  testWidgets('on a phone, Save scrolls the error in a folded panel onto the '
      'screen', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(id: 'd1', title: 'Contra', createdAt: _now, updatedAt: _now),
    );
    const size = Size(390, 844);
    await _pump(tester, repos, danceId: 'd1', size: size);
    await openDanceEditorSetup(tester);
    final phrase = find.byKey(const ValueKey('phrase-field'));
    await tester.ensureVisible(phrase);
    await tester.enterText(phrase, 'x*y');
    await tester.pumpAndSettle();
    final header = find.text('Credits, formation and music');
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(phrase, findsNothing);

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();
    final rect = tester.getRect(phrase);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(size.height));
  });

  group('Save after the list has let go of Title and the panel '
      '(pre-release audit finding GAPF-01)', () {
    final titleField = find.byKey(
      const ValueKey('title-field'),
      skipOffstage: false,
    );

    Future<void> scrollToEnd(WidgetTester tester) async {
      // A focused field would keep its list item alive.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final list = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      list.position.jumpTo(list.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(titleField, findsNothing, reason: 'the list let go of Title');
    }

    testWidgets('an empty Title shows its own message, not a failed save', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, size: const Size(390, 844));
      await scrollToEnd(tester);

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      expect(find.text('Title is required'), findsOneWidget);
      expect(find.textContaining("Couldn't save the dance"), findsNothing);
      expect(find.byType(DanceEditorScreen), findsOneWidget);
      expect((await tester.runAsync(repos.dances.listAll))!, isEmpty);
    });

    testWidgets('a phrase structure that does not read opens the panel at '
        'its message', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(id: 'd1', title: 'Contra', createdAt: _now, updatedAt: _now),
      );
      const size = Size(1200, 400);
      await _pump(tester, repos, danceId: 'd1', size: size);
      await openDanceEditorSetup(tester);
      final phrase = find.byKey(const ValueKey('phrase-field'));
      await tester.ensureVisible(phrase);
      await tester.enterText(phrase, 'not a phrase structure !!');
      await tester.pumpAndSettle();
      await scrollToEnd(tester);

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't save the dance"), findsNothing);
      final field = tester.widget<TextField>(
        find.descendant(of: phrase, matching: find.byType(TextField)),
      );
      expect(field.decoration?.errorText, isNotNull);
      final rect = tester.getRect(phrase);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
    });
  });

  testWidgets('a panel folded on a new dance stays folded after the list lets '
      'it go and builds it again', (tester) async {
    await _pump(tester, openTestRepositories(), size: const Size(1200, 400));
    await tester.tap(find.text('Credits, formation and music'));
    await tester.pumpAndSettle();
    expect(_summary, findsOneWidget);
    // A focused Title would keep its list item, the panel's, alive.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pumpAndSettle();
    // Gone from the lazy list, so it is built afresh on the way back.
    expect(
      find.byKey(const ValueKey('setup-tile'), skipOffstage: false),
      findsNothing,
    );
    list.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_summary, findsOneWidget);
    expect(_formation, findsNothing);
  });

  testWidgets('a field keeps its focus when a resize moves it between rows', (
    tester,
  ) async {
    await _pump(tester, openTestRepositories());
    final detail = find.byKey(const ValueKey('formation-detail-field'));
    await tester.tap(detail);
    await tester.pumpAndSettle();
    bool focused() => tester
        .widget<EditableText>(
          find.descendant(of: detail, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus;
    expect(focused(), isTrue);
    final wideTop = tester.getTopLeft(detail).dy;

    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(detail).dy, isNot(wideTop));
    expect(focused(), isTrue);
  });
}
