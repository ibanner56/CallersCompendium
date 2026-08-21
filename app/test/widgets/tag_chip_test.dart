import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/models/dance_list_entry.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/theme/wcag.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/tag_chip.dart';

import '../support/l10n_harness.dart';

/// User-chosen tag colours (issue #786).
///
/// Every guard here is falsified by *mutating out the guard* rather than by
/// reverting the feature: this is new behaviour, so the old code cannot
/// exercise it and would go red for an incidental reason. Each test records the
/// naive implementation it is meant to catch.
final _now = DateTime.utc(2026, 1, 1);

DanceListEntry _entryWithTag({int? color}) => DanceListEntry(
  dance: Dance(
    id: 'd1',
    title: 'Test Dance',
    form: DanceForm.contra,
    formation: const Formation(FormationShape.dupleImproper),
    level: DanceLevel.intermediate,
    rating: 3,
    createdAt: _now,
    updatedAt: _now,
  ),
  authorNames: const [],
  tagNames: const ['chestnut'],
  tags: [(id: 't1', name: 'chestnut', color: color)],
  listCustomFields: const [],
  callCounts: const DanceCallCounts(all: 0, performed: 0),
);

Future<void> _pumpChip(
  WidgetTester tester,
  Widget chip, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(body: Center(child: chip)),
    ),
  );
}

Future<void> _pumpTile(WidgetTester tester, DanceListEntry entry) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: DanceListTile(entry: entry, onTap: () {}),
      ),
    ),
  );
}

/// The colour actually painted behind the chip labelled [label].
Color? _chipBackground(WidgetTester tester, String label) {
  final chip = tester.widget<Chip>(
    find.ancestor(of: find.text(label), matching: find.byType(Chip)).first,
  );
  return chip.backgroundColor;
}

/// The colour the chip's label text actually renders with, after the theme's
/// [ChipThemeData] and the surrounding [DefaultTextStyle] have had their say.
Color _renderedLabelColor(WidgetTester tester, String label) {
  final text = tester.widget<Text>(find.text(label));
  final inherited = DefaultTextStyle.of(tester.element(find.text(label))).style;
  final effective = text.style == null
      ? inherited
      : inherited.merge(text.style);
  final color = effective.color;
  expect(
    color,
    isNotNull,
    reason: 'the label must resolve to a concrete colour to be checkable',
  );
  return color!;
}

void main() {
  group('a tag with no colour renders exactly as before', () {
    testWidgets('the chip has no background colour', (tester) async {
      // MUTATION CAUGHT: `Color(tag.color ?? 0xFF000000)` or any
      // always-set-backgroundColor implementation, which would tint every
      // existing tag in every existing collection. This is the compatibility
      // contract for `tags.color`'s null state.
      await _pumpChip(tester, const TagChip(name: 'chestnut', color: null));
      expect(_chipBackground(tester, 'chestnut'), isNull);
    });

    testWidgets('the label carries no colour override', (tester) async {
      // MUTATION CAUGHT: unconditionally applying readableForegroundOn to a
      // fallback colour, which would repaint uncoloured tags' text.
      await _pumpChip(tester, const TagChip(name: 'chestnut', color: null));
      expect(tester.widget<Text>(find.text('chestnut')).style, isNull);
    });

    testWidgets('the label icon carries no colour override', (tester) async {
      await _pumpChip(tester, const TagChip(name: 'chestnut', color: null));
      final icon = tester.widget<Icon>(find.byIcon(Icons.label_outline));
      expect(icon.color, isNull);
    });
  });

  group('colour is a redundant cue, never the only one', () {
    testWidgets('a coloured chip still shows its name and icon', (
      tester,
    ) async {
      // MUTATION CAUGHT: a "tidier" chip that drops the label icon, or swaps
      // the name for a bare swatch, once a colour is available — which would
      // make colour the sole carrier of the tag's identity.
      await _pumpChip(
        tester,
        const TagChip(name: 'chestnut', color: 0xFF2196F3),
      );
      expect(find.text('chestnut'), findsOneWidget);
      expect(find.byIcon(Icons.label_outline), findsOneWidget);
    });

    testWidgets('a coloured action chip still shows its name and icon', (
      tester,
    ) async {
      await _pumpChip(
        tester,
        TagChip(name: 'chestnut', color: 0xFF2196F3, onPressed: () {}),
      );
      expect(find.text('chestnut'), findsOneWidget);
      expect(find.byIcon(Icons.label_outline), findsOneWidget);
    });
  });

  group('the label stays legible on any hue', () {
    // MUTATION CAUGHT: hard-coding `colorScheme.onSurfaceVariant` (or leaving
    // the theme's chip label style to win, the hazard called out in
    // perform_card.dart for issue #367) instead of readableForegroundOn. Both
    // look fine on a mid-tone and fail outright on a light one.
    const adversarial = <String, int>{
      'near-white': 0xFFFFFFF0,
      'near-black': 0xFF010203,
      'saturated yellow': 0xFFFFEB3B,
      'saturated blue': 0xFF0D47A1,
      'mid-tone grey': 0xFF808080,
    };

    for (final theme in <String, ThemeData>{
      'light': AppTheme.light,
      'high contrast': AppTheme.highContrast,
    }.entries) {
      for (final colour in adversarial.entries) {
        testWidgets('${colour.key} clears WCAG AA in the ${theme.key} theme', (
          tester,
        ) async {
          await _pumpChip(
            tester,
            TagChip(name: 'chestnut', color: colour.value),
            theme: theme.value,
          );
          final background = _chipBackground(tester, 'chestnut');
          expect(background, Color(colour.value));
          final foreground = _renderedLabelColor(tester, 'chestnut');
          expect(
            Wcag.contrastRatio(foreground, background!),
            greaterThanOrEqualTo(Wcag.aaText),
            reason:
                '${colour.key} label must stay readable in the ${theme.key} '
                'theme',
          );
        });
      }
    }
  });

  group('the colour paints the tag chip and nothing else', () {
    testWidgets('the row and its other chips are untouched', (tester) async {
      // MUTATION CAUGHT: tinting the row's ListTile or the subtitle Wrap
      // instead of the chip — the over-reaching implementation ruled out for
      // this feature, since a tag colour is a colour for the tag alone.
      const tagColour = 0xFF2196F3;
      await _pumpTile(tester, _entryWithTag(color: tagColour));

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.tileColor, isNull);
      expect(tile.selectedTileColor, isNull);

      expect(_chipBackground(tester, 'chestnut'), const Color(tagColour));
      // The formation, level and rating chips sit in the same Wrap and must be
      // unaffected by their neighbour's colour.
      for (final sibling in ['Duple improper', 'Intermediate', '3']) {
        expect(
          _chipBackground(tester, sibling),
          isNull,
          reason: '"$sibling" is a different chip and keeps its own styling',
        );
      }
    });

    testWidgets('an uncoloured tag leaves the row exactly as it was', (
      tester,
    ) async {
      await _pumpTile(tester, _entryWithTag());
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.tileColor, isNull);
      expect(_chipBackground(tester, 'chestnut'), isNull);
    });
  });
}
