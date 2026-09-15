import 'package:compendium_rubric/compendium_rubric.dart';

String arrow(Facing f) => switch (f) {
  Facing.up => '^',
  Facing.down => 'v',
  Facing.acrossEast => '>',
  Facing.acrossWest => '<',
  Facing.flexible => '?',
};

void show(String title, Formation f) {
  print('\n$title');
  print('          c0        c1     c2     c3        c4');
  for (var r = 0; r < f.rowCount; r++) {
    final cells = <String>[];
    for (var c = 0; c < kColumnCount; c++) {
      final id = f.dancerAt(Position(r, c));
      if (id == null) {
        cells.add('.'.padLeft(6));
      } else {
        final s = f.stateOf(id);
        cells.add(
          '${id.role.label}${s.number.label}-${id.coupleLetter} '
                  '${arrow(s.facing)}'
              .padLeft(9),
        );
      }
    }
    print('  r$r  ${cells.join(' ')}');
  }
}

void main() {
  show(
    'DUPLE IMPROPER (2 h4)',
    startingFormation(FormationType.dupleImproper, handsFour: 2),
  );
  show(
    'BECKET (2 h4)',
    startingFormation(FormationType.becketCw, handsFour: 2),
  );
}
