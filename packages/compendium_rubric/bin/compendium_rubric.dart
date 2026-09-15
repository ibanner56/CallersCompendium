/// Command-line entry point: compile a dance record and report the outcome.
///
/// ```
/// fvm dart run bin/compendium_rubric.dart test/golden/the_baby_rose.json
/// cat dance.json | fvm dart run bin/compendium_rubric.dart
/// ```
///
/// Exit codes are distinct per outcome so the tool composes in a script:
/// `0` compiled, `1` mismatched, `2` a figure refused to run, `64` the input
/// could not be read. The three dance-level outcomes stay separate for the same
/// reason [CompileResult] keeps them separate — "landed elsewhere" and "could
/// not run" are different facts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:compendium_rubric/compendium_rubric.dart';

const int _exitCompiled = 0;
const int _exitMismatch = 1;
const int _exitFigureRefused = 2;
const int _exitBadInput = 64;

void main(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }

  final paths = args.where((arg) => arg != '-').toList();
  if (paths.length > 1) {
    stderr.writeln('error: expected at most one input file');
    stderr.writeln(_usage);
    exit(_exitBadInput);
  }

  final String source;
  final String label;
  if (paths.isEmpty) {
    source = _readStdin();
    label = '<stdin>';
  } else {
    final file = File(paths.single);
    if (!file.existsSync()) {
      stderr.writeln('error: no such file: ${paths.single}');
      exit(_exitBadInput);
    }
    source = file.readAsStringSync();
    label = paths.single;
  }

  switch (parseDanceJson(source)) {
    case Err(:final error):
      stderr.writeln('$label: $error');
      exit(_exitBadInput);
    case Ok(:final value):
      exit(_report(value, label));
  }
}

String _readStdin() {
  final buffer = StringBuffer();
  String? line;
  while ((line = stdin.readLineSync(encoding: utf8)) != null) {
    buffer.writeln(line);
  }
  return buffer.toString();
}

/// Prints the compile outcome and returns the process exit code.
int _report(Dance dance, String label) {
  final title = dance.name.isEmpty ? label : dance.name;
  stdout.writeln(title);
  stdout.writeln(
    '  ${dance.formation.label} - ${dance.figures.length} figures - '
    '${dance.requiredHandsFour} hands four - ${dance.success.name}',
  );

  final result = compile(dance);
  for (final warning in result.warnings) {
    stdout.writeln('  warning: $warning');
  }

  switch (result) {
    case Compiled(:final finalFormation):
      stdout.writeln('  COMPILED');
      _writeMatrix('final', finalFormation);
      return _exitCompiled;

    case Mismatch(:final actual, :final expected):
      // Both states are printed because the useful information is the
      // difference between them, not either one alone.
      stdout.writeln('  MISMATCH - the dance ran but landed elsewhere');
      _writeMatrix('actual', actual);
      _writeMatrix('expected', expected);
      return _exitMismatch;

    case CompileError(:final opIndex, :final opName, :final error):
      final at = opIndex == null
          ? 'in the figure list'
          : 'at figure ${opIndex + 1} ($opName)';
      stdout.writeln('  ERROR $at: ${error.kind.name}');
      stdout.writeln('    ${error.message}');
      return _exitFigureRefused;
  }
}

void _writeMatrix(String heading, Formation formation) {
  stdout.writeln('  $heading:');
  for (final row in formation.toRolesNotation()) {
    stdout.writeln('    $row');
  }
}

const String _usage = '''
Usage: compendium_rubric [<dance.json>]

Compiles a dance record and checks the result against the progression it
claims. Reads stdin when no file is given.

Exit codes:
  0  compiled
  1  mismatch - every figure ran, but the set landed elsewhere
  2  a figure refused to run
  64 the input could not be read
''';
