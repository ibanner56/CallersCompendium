import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/models/dance_list_entry.dart';
import 'package:compendium_app/src/theme/set_list_accents.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

import '../support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

DanceListEntry _entry({
  int? rating,
  DanceCallCounts callCounts = const DanceCallCounts(all: 0, performed: 0),
  Formation formation = const Formation(FormationShape.dupleImproper),
}) => DanceListEntry(
  dance: Dance(
    id: 'd1',
    title: 'Test Dance',
    form: DanceForm.ecd,
    formation: formation,
    rating: rating,
    createdAt: _now,
    updatedAt: _now,
  ),
  authorNames: const [],
  tagNames: const [],
  listCustomFields: const [],
  callCounts: callCounts,
);

Future<void> _pump(
  WidgetTester tester,
  DanceListEntry entry, {
  bool? requirePerformed,
}) async {
  Widget tile = DanceListTile(entry: entry, onTap: () {});
  if (requirePerformed != null) {
    tile = RequirePerformedForHistoryScope(
      notifier: ValueNotifier<bool>(requirePerformed),
      child: tile,
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: tile)));
}

void main() {
  testWidgets('rating indicator shows the value with a semantic label', (
    tester,
  ) async {
    await _pump(tester, _entry(rating: 4));

    final indicator = find.byKey(const ValueKey('rating-indicator'));
    expect(indicator, findsOneWidget);
    expect(
      find.descendant(of: indicator, matching: find.text('4')),
      findsOneWidget,
    );

    final label = tester.widget<Text>(
      find.descendant(of: indicator, matching: find.byType(Text)),
    );
    expect(label.semanticsLabel, 'Rating: 4 of 5 stars');
  });

  testWidgets('no rating indicator is shown for an unrated dance', (
    tester,
  ) async {
    await _pump(tester, _entry());
    expect(find.byKey(const ValueKey('rating-indicator')), findsNothing);
  });

  testWidgets('shows a form-type leading avatar with an icon + text label', (
    tester,
  ) async {
    await _pump(tester, _entry());

    // The avatar carries the form icon...
    final avatar = find.byType(CircleAvatar);
    expect(avatar, findsOneWidget);
    expect(
      find.descendant(of: avatar, matching: find.byIcon(Icons.groups_outlined)),
      findsOneWidget,
    );
    // ...and the meaning is not glyph-only: the form label is the tooltip.
    expect(
      find.ancestor(of: avatar, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: avatar, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, 'English (ECD)');
  });

  testWidgets('title uses the themed titleMedium style', (tester) async {
    await _pump(tester, _entry());
    final title = tester.widget<Text>(find.text('Test Dance'));
    final expected = Theme.of(
      tester.element(find.text('Test Dance')),
    ).textTheme.titleMedium;
    expect(title.style, expected);
  });

  group('called ×N chip', () {
    final chipKey = const ValueKey('called-count-d1');

    testWidgets('is hidden when the dance has never been called', (
      tester,
    ) async {
      await _pump(tester, _entry());
      expect(find.byKey(chipKey), findsNothing);
    });

    testWidgets('shows the all-occurrences count with plural semantics', (
      tester,
    ) async {
      await _pump(
        tester,
        _entry(callCounts: const DanceCallCounts(all: 3, performed: 1)),
      );
      final chip = find.byKey(chipKey);
      expect(chip, findsOneWidget);
      final label = tester.widget<Text>(
        find.descendant(of: chip, matching: find.byType(Text)),
      );
      expect(label.data, 'called ×3');
      expect(label.semanticsLabel, 'called 3 times');
    });

    testWidgets('uses the singular "1 time" semantic label', (tester) async {
      await _pump(
        tester,
        _entry(callCounts: const DanceCallCounts(all: 1, performed: 0)),
      );
      final label = tester.widget<Text>(
        find.descendant(of: find.byKey(chipKey), matching: find.byType(Text)),
      );
      expect(label.data, 'called ×1');
      expect(label.semanticsLabel, 'called 1 time');
    });

    testWidgets(
      'honors Require-mark-performed: shows the performed-only count',
      (tester) async {
        await _pump(
          tester,
          _entry(callCounts: const DanceCallCounts(all: 3, performed: 1)),
          requirePerformed: true,
        );
        final label = tester.widget<Text>(
          find.descendant(of: find.byKey(chipKey), matching: find.byType(Text)),
        );
        expect(label.data, 'called ×1');
        expect(label.semanticsLabel, 'called 1 time');
      },
    );

    testWidgets(
      'is hidden when performed count is zero and mark-performed is required',
      (tester) async {
        await _pump(
          tester,
          _entry(callCounts: const DanceCallCounts(all: 2, performed: 0)),
          requirePerformed: true,
        );
        expect(find.byKey(chipKey), findsNothing);
      },
    );

    testWidgets(
      'count updates live when the RequirePerformedForHistoryScope flips '
      '(no list reload)',
      (tester) async {
        final notifier = ValueNotifier<bool>(false);
        addTearDown(notifier.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequirePerformedForHistoryScope(
                notifier: notifier,
                child: DanceListTile(
                  entry: _entry(
                    callCounts: const DanceCallCounts(all: 3, performed: 1),
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

        // Default scope: all occurrences.
        Text label() => tester.widget<Text>(
          find.descendant(of: find.byKey(chipKey), matching: find.byType(Text)),
        );
        expect(label().data, 'called ×3');

        // Flip the setting on — the InheritedNotifier rebuilds the tile with
        // the performed-only tally, without any reload of the list.
        notifier.value = true;
        await tester.pump();
        expect(label().data, 'called ×1');

        // Flip back off — the tile returns to the all-occurrences tally.
        notifier.value = false;
        await tester.pump();
        expect(label().data, 'called ×3');
      },
    );
  });

  group('formation label colour (issue #367)', () {
    Chip formationChip(WidgetTester tester) {
      final chip = find.ancestor(
        of: find.text('Becket (CW)'),
        matching: find.byType(Chip),
      );
      return tester.widget<Chip>(chip);
    }

    testWidgets('no override ⇒ formation chip renders with no tint', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final controller = FormationColorsController(repos.settings);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormationColorsScope(
              controller: controller,
              child: DanceListTile(
                entry: _entry(
                  formation: const Formation(FormationShape.becketCw),
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      expect(formationChip(tester).backgroundColor, isNull);
    });

    testWidgets('an override tints the formation chip with a readable label', (
      tester,
    ) async {
      const yellow = Color(0xFFFFEB3B);
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final controller = FormationColorsController(repos.settings);
      await controller.load();
      await controller.setColor(FormationShape.becketCw, yellow);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormationColorsScope(
              controller: controller,
              child: DanceListTile(
                entry: _entry(
                  formation: const Formation(FormationShape.becketCw),
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(formationChip(tester).backgroundColor, yellow);
      // The label stays present (colour is never the only signal) and legible.
      final label = tester.widget<Text>(find.text('Becket (CW)'));
      expect(label.style?.color, readableForegroundOn(yellow));
    });
  });
}
