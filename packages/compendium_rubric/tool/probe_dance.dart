// Scratch probe: step-by-step trace of a dance record. Not part of the build.
import 'dart:io';

import 'package:compendium_rubric/compendium_rubric.dart';

String glyph(Facing f) => switch (f) {
  Facing.up => '^',
  Facing.down => 'v',
  Facing.acrossEast => '>',
  Facing.acrossWest => '<',
  _ => '?',
};

void render(Formation f) {
  for (var row = 0; row < f.rowCount; row++) {
    final cells = <String>[];
    for (var col = 0; col < kColumnCount; col++) {
      final id = f.dancerAt(Position(row, col));
      if (id == null) {
        cells.add('  .  ');
        continue;
      }
      final s = f.stateOf(id);
      cells.add(
        '${id.role == Role.lark ? 'L' : 'R'}'
        '${s.number == CoupleNumber.one ? 1 : 2}'
        '${String.fromCharCode(0x41 + id.coupleIndex)}'
        '${glyph(s.facing)}'
        '${s.waitingOut ? '*' : ' '}',
      );
    }
    print('  r$row  ${cells.join(' ')}');
  }
  final bands = handsFourBands(
    f,
  ).map((b) => '(${b.topRow},${b.bottomRow})').join(' ');
  print('  bands $bands   out=${waitingOutRows(f)}');
}

void main(List<String> args) {
  final dance =
      (parseDanceJson(File(args[0]).readAsStringSync())
              as Ok<Dance, DanceParseError>)
          .value;
  print('${dance.name}  (${dance.requiredHandsFour} hands four)');
  var state = dance.instantiate();
  final fold = FigureFold();
  print('\nstart');
  render(state);

  for (var i = 0; i < dance.figures.length; i++) {
    final fig = dance.figures[i];
    // Threaded exactly as the engine threads it (`FigureFold`): the distance
    // count, and any progression held until a couple reaches an end. Folding
    // by hand made the trace disagree with `compile` on both. The retries
    // (end effects, §10.7; an allemande's short waves, §8.5.8) are left to
    // `compile`, printed below.
    final r = fold.step(fig, state, index: i);
    print('\nop $i  $fig');
    switch (r) {
      case Ok(:final value):
        state = value;
        render(state);
      case Err(:final error):
        print('  REFUSED ${error.kind.name}: ${error.detail}');
        // `compile` may still go on: a refusal naming a pair waiting at an
        // end is retried with them traded (`docs/fundamentals.md` §10.7), and
        // one straight after an allemande from its short waves (§8.5.8),
        // which this step-through does not do.
        print('\ncompile: ${compile(dance)}');
        return;
    }
  }

  final result = compile(dance);
  print('\ncompile: $result');
}
