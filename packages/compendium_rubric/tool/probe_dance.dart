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
  var progressions = 0;
  print('\nstart');
  render(state);

  for (var i = 0; i < dance.figures.length; i++) {
    final fig = dance.figures[i];
    // Threaded exactly as the engine threads it: the distance-named dancer
    // sets are anchored at the start of the dance, so a figure's reach depends
    // on how many progressions ran before it. Omitting this made the trace
    // disagree with `compile` on any dance that names a distance after
    // progressing.
    final r = fig.apply(state, progressions: progressions);
    print('\nop $i  $fig');
    switch (r) {
      case Ok(:final value):
        state = value;
        if (fig.progression) progressions++;
        render(state);
      case Err(:final error):
        print('  REFUSED ${error.kind.name}: ${error.detail}');
        return;
    }
  }

  final result = compile(dance);
  print('\ncompile: $result');
}
