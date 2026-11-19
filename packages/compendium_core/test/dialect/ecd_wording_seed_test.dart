import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/dialect/ecd_display.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// A dialect's wording for an ECD movement starts from the movement's own
/// template (ADR-006 §6.3), so it must save as it stands and read as the
/// movement does by default.
void main() {
  final taxonomy = shippedTaxonomies.forForm(DanceForm.ecd);
  final renderer = FigureRenderer(taxonomy);
  final ecdMoves = taxonomy.moves.keys.where(isEcdMove).toList();

  test('every ECD movement seeds a wording that saves', () {
    expect(ecdMoves, isNotEmpty);
    final failing = <String>[];
    for (final id in ecdMoves) {
      final seed = renderer.moveWordingTemplate(id)!;
      final check = checkWording(
        seed,
        renderer.moveWordingVocabulary(id, Dialect.larksRobins),
      );
      if (check.hasErrors) failing.add('$id: $seed (${check.error!.code})');
    }
    expect(failing, isEmpty);
  });

  // Each value of each parameter alone, and each pair of them: the seed
  // saved unedited reads as the default line, through switch groups, the
  // ECD slot words ("back to place"), the template's own choices (a run of
  // changes with no count, a forward and back with no direction, a hey with
  // no `who`) and its punctuation.
  test('a seed saved unedited reads as the default line', () {
    final mismatches = <String>[];
    var compared = 0;
    for (final id in ecdMoves) {
      final def = taxonomy.moves[id]!;
      final stored = checkWording(
        renderer.moveWordingTemplate(id)!,
        renderer.moveWordingVocabulary(id, Dialect.larksRobins),
      ).stored!;
      final dialect = Dialect.larksRobins.copyWith(moveWordings: {id: stored});
      final singles = <Map<String, Object?>>[
        for (final MapEntry(key: name, value: spec) in def.params.entries)
          for (final value in _sampleValues(spec)) {name: value},
      ];
      final cases = <Map<String, Object?>>[
        {},
        ...singles,
        for (var i = 0; i < singles.length; i++)
          for (var j = i + 1; j < singles.length; j++)
            if (singles[i].keys.first != singles[j].keys.first)
              {...singles[i], ...singles[j]},
      ];
      for (final params in cases) {
        final Figure figure;
        try {
          figure = testFigure(move: id, params: params);
        } on StateError {
          continue; // Not a figure the editor would save.
        }
        compared++;
        final custom = renderer.render(figure, dialect);
        final standard = renderer.render(figure, Dialect.larksRobins);
        if (custom != standard) {
          mismatches.add('$id $params: "$custom", not "$standard"');
        }
      }
    }
    expect(compared, greaterThan(1000));
    expect(mismatches, isEmpty);
  });

  test('a switch group becomes a condition', () {
    expect(
      renderer.moveWordingTemplate('ecd_box_the_gnat'),
      contains('[if balance then balance and]'),
    );
    expect(ecdTemplateAsWording('{who} {move}'), '{who} {move}');
    expect(
      ecdTemplateAsWording('{move} [{axis}] [{?balance}and balance]'),
      '{move} [{axis}] [if balance then and balance]',
    );
  });

  test('an ECD who that names nobody tests as empty', () {
    final condition = WordingTest('who', WordingTestOp.present);
    bool holds(Object? who) =>
        evaluateWordingCondition(condition, {'who': WordingSubject(null, who)});
    expect(holds(const ['twos']), isTrue);
    expect(holds(const [ParamVocab.unspecified]), isFalse);
    expect(holds(const <String>[]), isFalse);
  });
}

/// Values of [spec] to try: each choice, both sides of a switch, a number,
/// and one named dancer.
List<Object?> _sampleValues(ParamSpec spec) => switch (spec.kind) {
  ParamKind.flag => [true, false],
  ParamKind.number => [3],
  ParamKind.dancerList => [
    [_firstNamed(spec)],
  ],
  ParamKind.dancerSet || ParamKind.dancerPair => [_firstNamed(spec)],
  ParamKind.text || ParamKind.beats => const [],
  _ => [...?spec.choices],
};

String _firstNamed(ParamSpec spec) => (spec.choices ?? ParamVocab.dancerSets)
    .firstWhere((c) => c != ParamVocab.unspecified);
