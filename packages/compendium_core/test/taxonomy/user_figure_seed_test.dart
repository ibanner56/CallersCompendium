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
      if (seed.copiedFrom != contraTaxonomy.resolve(id)!.id) {
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
}
