import 'dart:ui' show CheckedState;

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/batch_screen_harness.dart';
import '../support/test_repositories.dart';

Dance _dance(String id, String title, {List<String> tagIds = const []}) =>
    Dance(
      id: id,
      title: title,
      tagIds: tagIds,
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      status: DanceStatus.active,
      figures: const [],
      customFields: const [],
      hook: '',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Bouncy: Apple, Cherry. Other: Banana, Date.
Future<void> _seed(WidgetTester tester) async {
  final repos = openTestRepositories();
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 't1', name: 'Bouncy'));
  await repos.dances.create(_dance('a', 'Apple', tagIds: const ['t1']));
  await repos.dances.create(_dance('b', 'Banana'));
  await repos.dances.create(_dance('c', 'Cherry', tagIds: const ['t1']));
  await repos.dances.create(_dance('d', 'Date'));
  await pumpBatchScreen(tester, repos);
  await tester.tap(find.byKey(const ValueKey('collection-group-by')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bouncy').last);
  await tester.pumpAndSettle();
}

Future<void> _longPress(WidgetTester tester, String title) async {
  await tester.longPress(find.text(title));
  await tester.pumpAndSettle();
}

final _tagBox = find.byKey(const ValueKey('group-checkbox-tag'));
final _otherBox = find.byKey(const ValueKey('group-checkbox-other'));

bool? _value(WidgetTester tester, Finder box) =>
    tester.widget<Checkbox>(box).value;

void main() {
  testWidgets('entering selection keeps the sections and adds checkboxes', (
    tester,
  ) async {
    await _seed(tester);
    expect(_tagBox, findsNothing, reason: 'no checkbox outside selection');

    await _longPress(tester, 'Banana');

    expect(find.byKey(const ValueKey('group-header-tag')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-header-other')), findsOneWidget);
    expect(_value(tester, _tagBox), isFalse);
    expect(_value(tester, _otherBox), isNull, reason: '1 of 2 is mixed');
    // Rows keep their grouped order, so the pressed row did not jump.
    final y = [
      for (final t in ['Apple', 'Cherry', 'Banana', 'Date'])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(y, orderedEquals([...y]..sort()));
  });

  testWidgets('a header checkbox selects only its section, then clears it', (
    tester,
  ) async {
    await _seed(tester);
    await _longPress(tester, 'Banana');

    await tester.tap(_tagBox);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    expect(_value(tester, _tagBox), isTrue);
    expect(_value(tester, _otherBox), isNull);

    await tester.tap(_tagBox);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget, reason: 'Banana stays');
    expect(_value(tester, _tagBox), isFalse);
  });

  testWidgets('a mixed header selects the rest of its section', (tester) async {
    await _seed(tester);
    await _longPress(tester, 'Banana');
    await tester.tap(_otherBox);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(_value(tester, _otherBox), isTrue);
  });

  testWidgets('a header never clears selections the list does not show', (
    tester,
  ) async {
    await _seed(tester);
    await _longPress(tester, 'Banana');
    // Search hides Banana (and Date); Cherry is the only shown row.
    await tester.enterText(
      find.byKey(const ValueKey('collection-search-field')),
      'Cherry',
    );
    await tester.pumpAndSettle();
    await tester.tap(_tagBox);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.textContaining('1 not shown'), findsOneWidget);

    await tester.tap(_tagBox);
    await tester.pumpAndSettle();
    expect(
      find.text('1 selected'),
      findsOneWidget,
      reason: 'hidden Banana survives clearing the section',
    );
  });

  testWidgets('a screen reader reaches the checkbox with state and action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _seed(tester);
    await _longPress(tester, 'Banana');

    final node = tester.getSemantics(
      find.bySemanticsLabel('Other, 2 dances, 1 selected'),
    );
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isChecked, CheckedState.mixed);

    await tester.tap(find.bySemanticsLabel('Other, 2 dances, 1 selected'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Other, 2 dances, 2 selected'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
