import 'package:compendium_rubric/compendium_rubric.dart';

void show(String label, Formation f) {
  print('--- $label');
  for (final row in f.toRolesNotation()) {
    print('    $row');
  }
  print(
    '    out=${(waitingOutRows(f).toList()..sort())}  '
    'bands=${handsFourBands(f).map((b) => [b.topRow, b.bottomRow]).toList()}',
  );
}

void main() {
  final start = startingFormation(FormationType.dupleImproper, handsFour: 3);
  show('DI start, 3 h4', start);

  final passed = const PassThrough(dir: Direction.along).apply(start);
  switch (passed) {
    case Err(:final error):
      print('pass_through along REFUSED: $error');
    case Ok(:final value):
      show('after pass_through along', value);
  }
}
