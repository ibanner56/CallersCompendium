import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Copying a shipped move as a figure of the user's own (#1023, maintainer
/// decision 6): an independent definition, seeded from the move, that always
/// validates.
void main() {
  test('every shipped move and alias seeds a figure that validates, whose '
      'wording uses only its own slots', () {
    final ids = [...contraTaxonomy.moves.keys, ...contraTaxonomy.aliases.keys];
    final failures = <String>[];
    for (final id in ids) {
      final seed = userFigureSeedFromMove(contraTaxonomy, id)!;
      final errors = [
        for (final issue in validateUserFigure(seed))
          if (issue.severity == ValidationSeverity.error) issue.code,
      ];
      final unknown = userFigureTemplateSlots(
        seed.template,
      ).difference(seed.slots);
      if (errors.isNotEmpty || unknown.isNotEmpty) {
        failures.add('$id: errors $errors, unknown slots $unknown');
      }
      // Nothing the editor would stop to ask about before saving.
      if (seed.unusedParams.isNotEmpty) {
        failures.add('$id: unused ${seed.unusedParams}');
      }
      // Copied from the move it names, except an alias listed as a move
      // (`long_lines`), copied as itself, as it was while it was a move.
      final listed = contraTaxonomy.aliases[id]?.listedAsMove ?? false;
      if (seed.copiedFrom != (listed ? id : contraTaxonomy.resolve(id)!.id)) {
        failures.add('$id: copiedFrom ${seed.copiedFrom}');
      }
      // It reads back as it was written.
      if (decodeUserFigureDefinition(seed.toJson()) == null) {
        failures.add('$id: does not decode');
      }
    }
    expect(failures, isEmpty);
    expect(ids.length, greaterThan(50), reason: 'every move was checked');
  });

  test('a swing keeps the parameters its wording uses, their choices and '
      'defaults, and its beats', () {
    final seed = userFigureSeedFromMove(
      contraTaxonomy,
      'swing',
      choiceLabel: (key, value) => '$key:$value',
      random: Random(1),
    )!;
    expect(seed.params.map((p) => p.key), [
      'who',
      'prefix',
    ], reason: 'its wording, "{who} {prefix} {move}", never uses endFacing');
    expect(seed.defaultBeats, 8);
    expect(seed.copiedFrom, 'swing');
    final who = seed.param('who')!;
    expect(who.kind, ParamKind.dancerSet);
    expect(who.defaultValue, 'partners');
    final prefix = seed.param('prefix')!;
    expect(prefix.choices.map((c) => c.label), [
      'prefix:balance',
      'prefix:meltdown',
    ], reason: '"none", which the move words as nothing, is no value to pick');
    expect(
      prefix.defaultValue,
      isNull,
      reason: 'its default was "none": the copy says that by having no value',
    );
    expect(userFigureTemplateSlots(seed.template), contains('who'));
  });

  test('an unknown id seeds nothing', () {
    expect(userFigureSeedFromMove(contraTaxonomy, 'no_such_move'), isNull);
  });

  test('a choice\'s default follows its value to the new choice id', () {
    // Its default is not the first value, so taking the first would show.
    final taxonomy = Taxonomy(
      version: 1,
      form: DanceForm.contra,
      moves: [
        MoveDef(
          id: 'turn',
          displayName: 'turn',
          params: {
            'way': ParamSpec(
              ParamKind.choice,
              defaultValue: 'right',
              choices: ['left', 'right', 'around'],
            ),
          },
          renderTemplate: '{move} {way}',
        ),
      ],
    );
    final seed = userFigureSeedFromMove(
      taxonomy,
      'turn',
      choiceLabel: (key, value) => value,
    )!;
    final way = seed.param('way')!;
    expect(way.choiceLabel(way.defaultValue), 'right');
  });

  test('"none" is kept where it is a value of its own, not the default', () {
    // A slice with no return is a slice of its own.
    final slice = userFigureSeedFromMove(
      contraTaxonomy,
      'slice',
      choiceLabel: (key, value) => value,
    )!;
    final ret = slice.params.where((p) => p.key == 'return').firstOrNull;
    expect(ret, isNotNull);
    expect(ret!.choices.map((c) => c.label), contains('none'));
  });

  test('an alias starts from the values it pins', () {
    final seed = userFigureSeedFromMove(contraTaxonomy, 'pull_by_dancers')!;
    expect(seed.copiedFrom, 'pull_by');
    expect(seed.param('who')?.defaultValue, 'neighbors');
  });

  test('an ECD movement seeds no wording condition as words', () {
    final ecd = shippedTaxonomies.forForm(DanceForm.ecd);
    final shown = <String>[];
    for (final id in ecd.moves.keys.where((id) => id.startsWith('ecd_'))) {
      final template = userFigureSeedFromMove(ecd, id)!.template;
      if (template.contains('[if ')) shown.add('$id: $template');
    }
    expect(shown, isEmpty);
  });

  test('an ECD movement\'s list of dancers is seeded as a set, with no '
      'default (ADR-006 W5)', () {
    final ecd = shippedTaxonomies.forForm(DanceForm.ecd);
    final seed = userFigureSeedFromMove(ecd, 'ecd_set')!;
    final who = seed.params.firstWhere((p) => p.key == 'who');
    expect(who.kind, ParamKind.dancerSet);
    expect(who.defaultValue, isNull);
    for (final id in ecd.moves.keys.where((id) => id.startsWith('ecd_'))) {
      final kinds = userFigureSeedFromMove(ecd, id)!.params.map((p) => p.kind);
      expect(kinds, isNot(contains(ParamKind.dancerList)), reason: id);
    }
  });
  group('an English copy takes English\'s groups of dancers (#2294)', () {
    final ecd = shippedTaxonomies.forForm(DanceForm.ecd);

    test('a copy is for the form it was copied from', () {
      expect(userFigureSeedFromMove(ecd, 'ecd_set')!.form, 'ecd');
      expect(userFigureSeedFromMove(contraTaxonomy, 'swing')!.form, 'contra');
    });

    test('a shipped English movement starts no copy from "not stated"', () {
      // English words a group of dancers (`whom`) as `unspecified` until a
      // source names one. Offered as a default, that is a value a user never
      // picks, and one an older build cannot read.
      final seeded = <String>[];
      for (final id in ecd.moves.keys.where((id) => id.startsWith('ecd_'))) {
        for (final p in userFigureSeedFromMove(ecd, id)!.params) {
          if (p.kind != ParamKind.dancerSet) continue;
          seeded.add(id);
          expect(p.defaultValue, isNull, reason: '$id ${p.key}');
        }
      }
      // A control: some English movement's own group of dancers defaults to
      // "not stated", so the rule above has something to drop and the loop
      // is not vacuous. (An English movement's list of dancers, `who`, is
      // seeded as a set with no default, so it proves nothing here.)
      final defaultsToNotStated = [
        for (final id in ecd.moves.keys.where((id) => id.startsWith('ecd_')))
          for (final spec in ecd.resolve(id)!.params.values)
            if (spec.kind == ParamKind.dancerSet &&
                spec.defaultValue == ParamVocab.unspecified)
              id,
      ];
      expect(defaultsToNotStated, isNotEmpty);
      expect(seeded, isNotEmpty);
    });

    test('a group only English has is a valid default of an English copy', () {
      // Built, not shipped: no shipped English movement defaults to a named
      // group, so only this shows that the copy is checked as English's.
      final taxonomy = Taxonomy(
        version: 1,
        form: DanceForm.ecd,
        moves: [
          MoveDef(
            id: 'ecd_greet',
            displayName: 'greet',
            params: {
              'whom': ParamSpec(
                ParamKind.dancerSet,
                defaultValue: 'ends',
                choices: ecdSelectors,
              ),
            },
            renderTemplate: '{move} {whom}',
          ),
        ],
      );
      final seed = userFigureSeedFromMove(taxonomy, 'ecd_greet')!;
      expect(
        seed.param('whom'),
        isNotNull,
        reason: 'a default the copy\'s form refuses drops the whole parameter',
      );
      expect(seed.param('whom')!.defaultValue, 'ends');
      expect(
        validateUserFigure(
          seed,
        ).where((i) => i.severity == ValidationSeverity.error),
        isEmpty,
      );
    });
  });
}
