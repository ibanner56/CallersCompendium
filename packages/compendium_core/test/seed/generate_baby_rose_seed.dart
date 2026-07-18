// Regenerates the first-run seed dance asset,
// `app/assets/seed/baby_rose.json`, from the checked-in ContraDB source
// capture. See `baby_rose_seed_generator.dart` for the fidelity contract.
//
// Run from the package root (packages/compendium_core):
//
//     dart run test/seed/generate_baby_rose_seed.dart
//
// Reads the source HTML fixture and writes the canonical archive JSON asset,
// both resolved relative to the repository root. Offline only — no network.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'baby_rose_seed_generator.dart';

Future<void> main() async {
  // `dart run` sets the current directory to the package root
  // (packages/compendium_core); the repo root is two levels up.
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));
  final fixturePath = p.join(
    repoRoot,
    'tools',
    'seed',
    'fixtures',
    'contradb_dance_8.html',
  );
  final assetPath = p.join(repoRoot, 'app', 'assets', 'seed', 'baby_rose.json');

  final fixture = File(fixturePath);
  if (!fixture.existsSync()) {
    stderr.writeln('Missing source fixture: $fixturePath');
    exitCode = 1;
    return;
  }

  final json = await buildBabyRoseSeedArchiveJson(fixture.readAsStringSync());

  final asset = File(assetPath);
  asset.parent.createSync(recursive: true);
  // Trailing newline so the file is POSIX-friendly and diff-clean.
  asset.writeAsStringSync('$json\n');

  stdout.writeln('Wrote seed asset: $assetPath');
}
