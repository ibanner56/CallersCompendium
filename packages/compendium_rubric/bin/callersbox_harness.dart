/// Command-line harness: run Caller's Box JSON through the compiler and report.
///
/// ```
/// fvm dart run bin/callersbox_harness.dart test/io/callersbox/*.json
/// fvm dart run bin/callersbox_harness.dart --quiet C:\corpus\dances
/// ```
///
/// A directory argument expands to the `.json` files directly inside it. The
/// point of the tool is the summary: which dances compile, and which moves the
/// corpus names that this compiler has not implemented. That second list is the
/// backlog, read off real choreography rather than guessed at.
///
/// Exit codes: `0` every attempted dance compiled, `1` some did not, `64` the
/// inputs could not be read.
library;

import 'dart:io';

import 'package:compendium_rubric/compendium_rubric.dart';

const int _exitAllCompiled = 0;
const int _exitSomeFailed = 1;
const int _exitBadInput = 64;

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }

  final quiet = args.contains('-q') || args.contains('--quiet');
  final verbose = args.contains('-v') || args.contains('--verbose');
  final paths = args.where((arg) => !arg.startsWith('-')).toList();
  if (paths.isEmpty) {
    stderr.writeln('error: no input files');
    stderr.writeln(_usage);
    exit(_exitBadInput);
  }

  final files = _expand(paths);
  if (files.isEmpty) {
    stderr.writeln('error: no .json files found in: ${paths.join(', ')}');
    exit(_exitBadInput);
  }

  final runs = <DanceRun>[];
  for (final file in files) {
    final String payload;
    try {
      // The Caller's Box serves its JSON with a byte-order mark; `jsonDecode`
      // reads one as content and fails on it.
      payload = file.readAsStringSync().replaceFirst('\uFEFF', '');
    } on FileSystemException catch (error) {
      stderr.writeln('${file.path}: unreadable: ${error.message}');
      continue;
    }
    runs.addAll(await runCallersBoxPayload(payload, label: file.path));
  }

  if (!quiet) {
    for (final run in runs) {
      if (!verbose && run.outcome == DanceOutcome.compiled) continue;
      _writeRun(run, verbose: verbose);
    }
  }

  final report = CorpusReport(runs);
  _writeSummary(report);
  exit(
    report.compiled == report.attempted ? _exitAllCompiled : _exitSomeFailed,
  );
}

/// Expands each argument to the files it names: a file is itself, a directory
/// is the `.json` files directly inside it.
List<File> _expand(List<String> paths) {
  final files = <File>[];
  for (final path in paths) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      files.addAll(
        directory.listSync().whereType<File>().where(
          (file) => file.path.toLowerCase().endsWith('.json'),
        ),
      );
      continue;
    }
    final file = File(path);
    if (file.existsSync()) {
      files.add(file);
      continue;
    }
    stderr.writeln('warning: no such file or directory: $path');
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void _writeRun(DanceRun run, {required bool verbose}) {
  final id = run.sourceId == null ? '' : ' [${run.sourceId}]';
  stdout.writeln('${run.outcome.name.toUpperCase()}$id ${run.title}');
  if (run.detail != null) stdout.writeln('  ${run.detail}');
  if (!verbose) return;
  for (final warning in run.warnings) {
    final at = warning.opIndex == null
        ? ''
        : ' (figure ${warning.opIndex! + 1})';
    stdout.writeln('  warning$at: ${warning.message}');
  }
}

void _writeSummary(CorpusReport report) {
  stdout.writeln('');
  stdout.writeln('${report.total} dances read');
  for (final outcome in DanceOutcome.values) {
    final count = report.count(outcome);
    if (count == 0) continue;
    stdout.writeln('  ${count.toString().padLeft(6)}  ${outcome.name}');
  }

  stdout.writeln('');
  stdout.writeln(
    'compiled ${report.compiled}/${report.attempted} attempted '
    '(${_percent(report.compileRate)})',
  );
  stdout.writeln(
    'vocabulary: ${report.movesCovered.length}/${supportedMoves.length} '
    'implemented moves exercised (${_percent(report.vocabularyCoverage)})',
  );
  stdout.writeln(
    'corpus: ${report.movesCovered.length}/${report.movesSeen.length} '
    'named moves implemented (${_percent(report.corpusCoverage)})',
  );

  if (report.movesMissing.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('named but not implemented:');
    for (final move in report.movesMissing.toList()..sort()) {
      stdout.writeln('  $move');
    }
  }
  if (report.movesUnexercised.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('implemented but unexercised here:');
    for (final move in report.movesUnexercised.toList()..sort()) {
      stdout.writeln('  $move');
    }
  }
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

const String _usage = '''
Usage: callersbox_harness [options] <file-or-directory>...

Imports Caller's Box JSON through compendium_core's adapter, compiles each
dance, and reports what compiled and which moves are still unimplemented.
A directory expands to the .json files directly inside it.

Options:
  -q, --quiet    summary only
  -v, --verbose  list every dance, with warnings
  -h, --help     this message

Exit codes:
  0  every attempted dance compiled
  1  some did not
  64 the inputs could not be read
''';
