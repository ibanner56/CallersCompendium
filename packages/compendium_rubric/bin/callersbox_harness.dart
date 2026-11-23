/// Command-line harness: run Caller's Box JSON through the compiler and report.
///
/// ```
/// fvm dart run bin/callersbox_harness.dart test/io/callersbox/*.json
/// fvm dart run bin/callersbox_harness.dart --quiet C:\corpus\dances
/// ```
///
/// A directory argument expands to the `.json` files directly inside it. The
/// point of the tool is the summary. Its headline is the **in-scope rate**:
/// how many dances compile out of the ones this compiler is actually aiming
/// at — everything that parsed, minus what a deferred figure blocked. The
/// all-attempted rate follows as a secondary number, and the unimplemented
/// moves the corpus names are listed after it. That list is the backlog, read
/// off real choreography rather than guessed at.
///
/// `--report <dir>` also writes a failure report into `<dir>`: every dance
/// that failed, re-run step by step (`lib/src/io/failure_report.dart`).
/// `failures.jsonl` has one record per dance, `summary.md` groups them by
/// cause, and `index.html` with `report.js` is a page to browse them in.
/// `--core-ids <file>` (one Caller's Box id per line, `#` comments) marks a
/// focus set, so each group also counts its dances from that set. Neither flag
/// changes the run's outcomes, rates or exit code.
///
/// Exit codes: `0` every attempted dance compiled, `1` some did not, `64` the
/// inputs could not be read. Note that the exit code tracks the *attempted*
/// set, so a corpus sweep will exit `1` as a matter of course.
library;

import 'dart:convert';
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
  final String? reportDir;
  final String? coreIdsPath;
  final paths = <String>[];
  try {
    (reportDir, coreIdsPath) = _options(args, paths);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    stderr.writeln(_usage);
    exit(_exitBadInput);
  }
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

  Set<String> coreIds = const {};
  if (coreIdsPath != null) {
    try {
      coreIds = {
        for (final line in File(coreIdsPath).readAsLinesSync())
          if (line.split('#').first.trim() case final id when id.isNotEmpty) id,
      };
    } on FileSystemException catch (error) {
      stderr.writeln('error: $coreIdsPath: unreadable: ${error.message}');
      exit(_exitBadInput);
    }
  }

  final runs = <DanceRun>[];
  final diagnoses = <FailureDiagnosis>[];
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
    if (reportDir == null) {
      runs.addAll(await runCallersBoxPayload(payload, label: file.path));
      continue;
    }
    for (final (run, diagnosis) in await diagnoseCallersBoxPayload(
      payload,
      label: file.path,
    )) {
      runs.add(run);
      if (diagnosis != null) diagnoses.add(diagnosis);
    }
  }

  if (!quiet) {
    for (final run in runs) {
      if (!verbose && run.outcome == DanceOutcome.compiled) continue;
      _writeRun(run, verbose: verbose);
    }
  }

  final report = CorpusReport(runs);
  _writeSummary(report);
  if (reportDir != null) {
    _writeFailureReport(reportDir, report, diagnoses, coreIds);
  }
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
    'in scope: ${report.compiled}/${report.inScope} '
    '(${_percent(report.inScopeRate)})',
  );
  stdout.writeln(
    '  dances the import structured fully, parsed, nothing deferred; '
    '${report.deferred} excluded as deferred',
  );
  stdout.writeln(
    'all attempted: ${report.compiled}/${report.attempted} '
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

/// Splits [args] into the input paths (added to [paths]) and the values of
/// `--report` and `--core-ids`.
(String?, String?) _options(List<String> args, List<String> paths) {
  String? report;
  String? coreIds;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--report' || arg == '--core-ids') {
      if (i + 1 >= args.length || args[i + 1].startsWith('-')) {
        throw FormatException('$arg needs a path');
      }
      if (arg == '--report') {
        report = args[++i];
      } else {
        coreIds = args[++i];
      }
    } else if (!arg.startsWith('-')) {
      paths.add(arg);
    }
  }
  if (coreIds != null && report == null) {
    throw const FormatException('--core-ids is only read with --report');
  }
  return (report, coreIds);
}

void _writeFailureReport(
  String dir,
  CorpusReport report,
  List<FailureDiagnosis> diagnoses,
  Set<String> coreIds,
) {
  final directory = Directory(dir);
  try {
    directory.createSync(recursive: true);
  } on FileSystemException catch (error) {
    // After the summary, so the run's own result is already printed; the
    // exit code stays the run's.
    stderr.writeln('error: --report $dir: ${error.message}');
    return;
  }
  String at(String name) => '${directory.path}${Platform.pathSeparator}$name';
  final headline =
      'in scope ${report.compiled}/${report.inScope} '
      '(${_percent(report.inScopeRate)}), '
      '${report.inScope - report.compiled} in-scope failures';
  File(at('failures.jsonl')).writeAsStringSync(
    diagnoses
        .map(
          (d) =>
              '${jsonEncode(d.toJson(core: coreIds.contains(d.run.sourceId)))}\n',
        )
        .join(),
  );
  File(at('summary.md')).writeAsStringSync(
    '$headline.\n\n${summarizeFailures(diagnoses, coreIds: coreIds)}',
  );
  File(at('report.js')).writeAsStringSync(
    failureReportScript(diagnoses, coreIds: coreIds, headline: headline),
  );
  File(at('index.html')).writeAsStringSync(
    '<!doctype html>\n<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1, '
    'viewport-fit=cover">\n$failureReportPage',
  );
  stdout.writeln('');
  stdout.writeln(
    'failure report: ${diagnoses.length} dances written to ${directory.path} '
    '(open index.html; summary.md groups them by cause)',
  );
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

const String _usage = '''
Usage: callersbox_harness [options] <file-or-directory>...

Imports Caller's Box JSON through compendium_core's adapter, compiles each
dance, and reports what compiled and which moves are still unimplemented.
A directory expands to the .json files directly inside it.

The headline is the in-scope rate: how many compiled out of the dances this
compiler is aiming at, which is everything that imported cleanly and parsed,
minus the ones a deferred figure blocked. The all-attempted rate follows it.

Options:
  -q, --quiet    summary only
  -v, --verbose  list every dance, with warnings
  --report <dir> also write a failure report to <dir>: failures.jsonl,
                 summary.md, and index.html (with report.js) to browse
  --core-ids <file>
                 with --report: Caller's Box ids of a focus set, one per
                 line, counted beside each cause
  -h, --help     this message

Exit codes:
  0  every attempted dance compiled
  1  some did not (expected on any real corpus sweep)
  64 the inputs could not be read
''';
