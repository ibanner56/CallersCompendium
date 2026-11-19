import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/dialect/ecd_display.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// A dialect's wording for an ECD movement starts from the movement's own
/// template (ADR-006 §6.3), so it must save as it stands and read as the
/// movement does by default.
void main() {
  final renderer = FigureRenderer(shippedTaxonomies.forForm(DanceForm.ecd));

  test('every ECD movement seeds a wording that saves', () {
    final failing = <String>[];
    for (final id in renderer.taxonomy.moves.keys.where(isEcdMove)) {
      final seed = renderer.moveWordingTemplate(id);
      if (seed == null) continue;
      final check = checkWording(
        seed,
        renderer.moveWordingVocabulary(id, Dialect.larksRobins),
      );
      if (check.hasErrors) failing.add('$id: $seed (${check.error!.code})');
    }
    expect(failing, isEmpty);
  });

  test('a switch group reads as the default line does', () {
    final seed = renderer.moveWordingTemplate('ecd_box_the_gnat')!;
    expect(seed, contains('[if balance then balance and]'));
    final stored = checkWording(
      seed,
      renderer.moveWordingVocabulary('ecd_box_the_gnat', Dialect.larksRobins),
    ).stored!;
    final dialect = Dialect(
      name: 'X',
      moveWordings: {'ecd_box_the_gnat': stored},
    );
    for (final balance in [true, false]) {
      final figure = testFigure(
        move: 'ecd_box_the_gnat',
        params: {'balance': balance},
      );
      expect(
        renderer.render(figure, dialect),
        renderer.render(figure, Dialect.larksRobins),
        reason: 'balance: $balance',
      );
    }
  });

  test('only switch groups change', () {
    expect(ecdTemplateAsWording('{who} {move}'), '{who} {move}');
    expect(
      ecdTemplateAsWording('{move} [{axis}] [{?balance}and balance]'),
      '{move} [{axis}] [if balance then and balance]',
    );
  });
}
