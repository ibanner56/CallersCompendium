/// Why a Caller's Box dance failed, in enough detail to act on.
///
/// [runCoreDance] reports one line per failure: the refusing figure and its
/// message, or for a mismatch nothing beyond "ran, but the set landed
/// elsewhere". That is enough to count failures and not enough to fix one.
/// This file re-runs a failing dance step by step and records what a person
/// (or an agent) needs in order to see where it went wrong:
///
/// - the source's own figure lines, beside the figures the compiler read them
///   as, after the bridge's rewrites and progression flags;
/// - the set after every figure, up to the one that refused;
/// - for a mismatch, the expected and actual end states, which dancers are
///   off, and a coarse [MismatchClass];
/// - a **placement hint**: the other figures that would compile if they
///   carried the progression the run assumed.
///
/// It is diagnostics only. Nothing here feeds back into a [DanceRun]'s
/// outcome or the harness's rates: the placement hint in particular tries
/// placements to *explain* a failure, and the ruling that the scored retry
/// "is deliberately not a search" ([runCoreDance]) still holds for scoring.
///
/// Everything a diagnosis reports comes from re-running the same primary
/// bridge [runCoreDance] reports for a failure, through [FigureFold], so a
/// trace cannot disagree with the verdict it explains.
library;

import 'dart:convert';

import 'package:compendium_core/compendium_core.dart' as core;

import '../domain/couple_number.dart';
import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../domain/position.dart';
import '../engine/compile_result.dart';
import '../engine/compiler.dart';
import '../engine/figure_fold.dart';
import '../engine/result.dart';
import '../engine/success_criterion.dart';
import '../ops/transforms.dart';
import 'callersbox_source.dart';
import 'dance_json.dart';

/// The outcomes a diagnosis is made for: every one where the compiler was
/// given the dance, or could have been, and did not compile it.
const Set<DanceOutcome> diagnosedOutcomes = {
  DanceOutcome.mismatch,
  DanceOutcome.figureRefused,
  DanceOutcome.crashed,
  DanceOutcome.unsupported,
};

/// A coarse reading of how a mismatched dance missed.
///
/// The first three compare the actual end state against the success
/// criterion run a different number of times. They are the commonest
/// mismatches and each points somewhere specific: a progression that never
/// netted out, or one too many or too few.
enum MismatchClass {
  /// The set ended where it started: the progression did not net out.
  noNetProgression,

  /// The set ended one progression further on than the dance claims.
  oneProgressionTooMany,

  /// The set ended one progression short of what the dance claims (only
  /// possible for a double or longer progression).
  oneProgressionShort,

  /// Every dancer is in the expected place, but some carry the wrong couple
  /// number.
  numbersOnly,

  /// None of the above: some dancers ended somewhere else.
  elsewhere,
}

/// One step of a trace: the set after figure [index] (or the start, when
/// [index] is `null`).
class TraceStep {
  const TraceStep({
    required this.index,
    required this.grid,
    this.moved = const [],
  });

  final int? index;

  /// One string per row, cells separated by a space. A cell is a dancer label
  /// (`L1-A`) followed by a facing glyph (`^ v > < ~`), with `*` when that
  /// dancer is standing out; an empty cell is `.`.
  final List<String> grid;

  /// Labels of the dancers whose place changed in this step.
  final List<String> moved;

  Map<String, Object?> toJson() => {
    'index': index,
    'grid': grid,
    if (moved.isNotEmpty) 'moved': moved,
  };
}

/// Everything the report says about one failing dance.
class FailureDiagnosis {
  const FailureDiagnosis({
    required this.run,
    required this.signature,
    this.phrases = const [],
    this.figures = const [],
    this.trace = const [],
    this.failedAt,
    this.mismatchClass,
    this.expected,
    this.actual,
    this.offDancers = const [],
    this.placementHint,
    this.diagnosisError,
  });

  final DanceRun run;

  /// The failure with the dance-specific parts stripped (figure numbers,
  /// dancer labels, counts), so failures with the same cause group together.
  /// A mismatch's is `mismatch: ` and its [mismatchClass].
  final String signature;

  /// The source's phrases as written: `(name, lines)`.
  final List<(String, List<String>)> phrases;

  /// The figures as the compiler reads them, one line each
  /// (`move(param: value, ...)`), after the bridge's rewrites, with
  /// `[progression]` on every flagged figure, assumed or written.
  final List<String> figures;

  /// The set at the start and after each figure that ran.
  final List<TraceStep> trace;

  /// The figure index that refused or threw, when one did.
  final int? failedAt;

  final MismatchClass? mismatchClass;
  final List<String>? expected;
  final List<String>? actual;

  /// For a mismatch: each dancer not where the criterion expected,
  /// as `label: expected -> actual`.
  final List<String> offDancers;

  /// For a run that assumed its progression: the other figures that compile
  /// when they carry it instead. `null` when not tried (the source flagged
  /// the progression, or the dance never parsed).
  final List<int>? placementHint;

  /// Set when re-running the dance for this diagnosis threw; everything but
  /// [run] and [signature] is then empty.
  final String? diagnosisError;

  Map<String, Object?> toJson({bool core = false}) => {
    'id': run.sourceId,
    'title': run.title,
    'outcome': run.outcome.name,
    'inScope': run.inScope,
    'deferred': run.blockedByDeferral,
    if (core) 'core': true,
    'detail': run.detail,
    'signature': signature,
    'assumedProgressionAt': run.assumedProgressionAt,
    'failedAt': failedAt,
    'phrases': [
      for (final (name, lines) in phrases) {'name': name, 'lines': lines},
    ],
    'figures': figures,
    'warnings': [
      for (final warning in run.warnings)
        {
          'at': warning.opIndex,
          'kind': warning.kind.name,
          'message': warning.message,
        },
    ],
    'trace': [for (final step in trace) step.toJson()],
    if (mismatchClass != null) 'mismatchClass': mismatchClass!.name,
    if (expected != null) 'expected': expected,
    if (actual != null) 'actual': actual,
    if (offDancers.isNotEmpty) 'offDancers': offDancers,
    if (placementHint != null) 'placementHint': placementHint,
    if (diagnosisError != null) 'diagnosisError': diagnosisError,
  };
}

/// Runs every dance in a Caller's Box [payload] like [runCallersBoxPayload],
/// and diagnoses each failure.
///
/// The second element is `null` for a run that needs no diagnosis (it
/// compiled, or never reached the compiler). Never throws for a bad payload.
Future<List<(DanceRun, FailureDiagnosis?)>> diagnoseCallersBoxPayload(
  String payload, {
  String label = '<payload>',
}) async {
  final adapter = core.CallersBoxAdapter();
  final List<core.DiscoveredRecord> discovered;
  try {
    discovered = await adapter.discover(core.ImportRequest(payload: payload));
  } on Exception {
    return [
      for (final run in await runCallersBoxPayload(payload, label: label))
        (run, null),
    ];
  }

  final results = <(DanceRun, FailureDiagnosis?)>[];
  for (final record in discovered) {
    final core.StructuredDraft draft;
    try {
      draft = adapter.parse(await adapter.fetch(record));
    } on Exception catch (error) {
      results.add((
        DanceRun(
          title: label,
          outcome: DanceOutcome.adapterFailed,
          sourceId: record.externalId,
          label: label,
          detail: '$error',
        ),
        null,
      ));
      continue;
    }
    final DanceRun run;
    try {
      run = runCoreDance(draft, label: label);
    } on Exception catch (error) {
      // As [runCallersBoxPayload] does, so the two agree on every run.
      results.add((
        DanceRun(
          title: label,
          outcome: DanceOutcome.adapterFailed,
          sourceId: record.externalId,
          label: label,
          detail: '$error',
        ),
        null,
      ));
      continue;
    }
    if (!diagnosedOutcomes.contains(run.outcome)) {
      results.add((run, null));
      continue;
    }
    FailureDiagnosis diagnosis;
    try {
      diagnosis = diagnoseFailure(draft, run);
    } catch (error) {
      // A diagnosis must never end the sweep or change its result: a dance
      // that crashed the compiler can crash a re-run of it too. Deliberately
      // unfiltered, for the reason [runCoreDance] gives for its own catch.
      diagnosis = FailureDiagnosis(
        run: run,
        signature: failureSignature(run),
        diagnosisError: '$error',
      );
    }
    results.add((run, diagnosis));
  }
  return results;
}

/// Diagnoses [run], the verdict [runCoreDance] gave for [draft].
///
/// [bridged] defaults to the primary bridge of [draft], which is the one
/// [runCoreDance] reports for any failure (the fallback replaces it only when
/// the fallback compiles). Passing another reading is for tests.
FailureDiagnosis diagnoseFailure(
  core.StructuredDraft draft,
  DanceRun run, {
  BridgedDance? bridged,
}) {
  final dance = draft.dance;
  final phrases = sourcePhrases(draft.raw.payload);
  var signature = failureSignature(run);

  final reading = bridged ?? bridgeCoreDance(dance);
  // The figures as the compiler reads them, after the bridge's own rewrites
  // (a balanced long wave and a slide becomes `rory_o_more`) and its assumed
  // progression flags, not as the importer left them.
  final figures = [
    for (final figure in reading.record['figures']! as List)
      describeRecordFigure(figure as Map<String, Object?>),
  ];
  final parsed = parseDance(reading.record);
  if (parsed is! Ok<Dance, DanceParseError>) {
    // Never compiled, so there is no trace; the parse error names the figure
    // as `figures[N]` when one figure is to blame.
    final at = RegExp(r'figures\[(\d+)\]').firstMatch(run.detail ?? '');
    return FailureDiagnosis(
      run: run,
      signature: signature,
      phrases: phrases,
      figures: figures,
      failedAt: at == null ? null : int.parse(at.group(1)!),
    );
  }
  final compiled = parsed.value;

  final trace = <TraceStep>[];
  int? failedAt;
  var state = compiled.instantiate();
  trace.add(TraceStep(index: null, grid: renderGrid(state)));
  final fold = FigureFold();
  for (var index = 0; index < compiled.figures.length; index++) {
    final Result<Formation, Object> step;
    try {
      step = fold.step(compiled.figures[index], state, index: index);
    } catch (_) {
      failedAt = index;
      break;
    }
    if (step case Ok(:final value)) {
      trace.add(
        TraceStep(
          index: index,
          grid: renderGrid(value),
          moved: _moved(state, value),
        ),
      );
      state = value;
    } else {
      failedAt = index;
      break;
    }
  }

  MismatchClass? mismatchClass;
  List<String>? expected;
  List<String>? actual;
  var offDancers = const <String>[];
  if (run.outcome == DanceOutcome.mismatch) {
    final CompileResult result;
    try {
      result = compile(compiled);
    } catch (_) {
      return FailureDiagnosis(
        run: run,
        signature: signature,
        phrases: phrases,
        figures: figures,
        trace: trace,
        failedAt: failedAt,
      );
    }
    if (result is Mismatch) {
      mismatchClass = classifyMismatch(compiled, result);
      signature = 'mismatch: ${mismatchClass.name}';
      expected = renderGrid(result.expected);
      actual = renderGrid(result.actual);
      offDancers = _offDancers(
        normalizeWaveOffsets(result.actual),
        result.expected,
      );
    }
  }

  return FailureDiagnosis(
    run: run,
    signature: signature,
    phrases: phrases,
    figures: figures,
    trace: trace,
    failedAt: failedAt,
    mismatchClass: mismatchClass,
    expected: expected,
    actual: actual,
    offDancers: offDancers,
    placementHint: reading.assumedProgressionAt == null
        ? null
        : placementHint(reading),
  );
}

/// The figures, other than the one [bridged] assumed, that compile when the
/// progression flag is moved onto them alone.
///
/// Diagnostic only: see the library comment.
List<int> placementHint(BridgedDance bridged) {
  final count = (bridged.record['figures']! as List).length;
  final compiling = <int>[];
  for (var k = 0; k < count; k++) {
    if (k == bridged.assumedProgressionAt) continue;
    final parsed = parseDance(withProgressionAt(bridged, k).record);
    if (parsed is! Ok<Dance, DanceParseError>) continue;
    try {
      if (compile(parsed.value) is Compiled) compiling.add(k);
    } catch (_) {
      // A crash under a hypothetical placement says nothing about this dance.
    }
  }
  return compiling;
}

/// [bridged] with the progression flag on top-level figure [index] alone,
/// as though that were the figure assumed. Builds new maps throughout, so
/// [bridged] is left as it was.
BridgedDance withProgressionAt(BridgedDance bridged, int index) {
  final record = bridged.record;
  final figures = (record['figures']! as List).cast<Map<String, Object?>>();
  return BridgedDance(
    record: {
      ...record,
      'figures': [
        for (var i = 0; i < figures.length; i++)
          {
            for (final entry in figures[i].entries)
              if (entry.key != 'progression') entry.key: entry.value,
            if (i == index) 'progression': true,
          },
      ],
    },
    warnings: bridged.warnings,
    assumedProgressionAt: index,
  );
}

/// How [mismatch] missed, judged against [dance]'s own criterion.
MismatchClass classifyMismatch(Dance dance, Mismatch mismatch) {
  final actual = normalizeWaveOffsets(mismatch.actual);
  final input = dance.instantiate();
  final criterion = dance.success;
  if (actual == input) return MismatchClass.noNetProgression;
  if (criterion is ProgressionCriterion) {
    final count = criterion.count;
    if (actual == ProgressionCriterion(count: count + 1).expected(input)) {
      return MismatchClass.oneProgressionTooMany;
    }
    if (count > 1 &&
        actual == ProgressionCriterion(count: count - 1).expected(input)) {
      return MismatchClass.oneProgressionShort;
    }
  }
  final expected = mismatch.expected;
  final placesMatch = actual.dancers.keys.every(
    (id) => actual.stateOf(id).position == expected.stateOf(id).position,
  );
  return placesMatch ? MismatchClass.numbersOnly : MismatchClass.elsewhere;
}

/// [run]'s failure with its dance-specific parts stripped, so that two dances
/// failing for the same reason share a signature.
///
/// Strips the figure number, dancer labels (`L-B`, `R1-A`), the bare couple
/// letters the distance-set messages use ("B and C"), and every number.
String failureSignature(DanceRun run) {
  final detail = run.detail ?? run.outcome.name;
  return detail
      .replaceFirst(RegExp(r'^figure \d+ '), '')
      .replaceAll(RegExp(r'\b[LR][12]?-[A-Z]\b'), 'X')
      .replaceAll(RegExp(r'\b[A-Z] and [A-Z]\b'), 'X and X')
      .replaceAll(RegExp(r'figures\[\d+\]'), 'figures[#]')
      .replaceAll(RegExp(r'\d+(\.\d+)?'), '#');
}

/// The source's phrases from a Caller's Box [payload]: each phrase's name and
/// its figure lines, exactly as written. Empty when the payload carries none.
List<(String, List<String>)> sourcePhrases(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload.replaceFirst('﻿', ''));
  } on FormatException {
    return const [];
  }
  if (decoded is! Map) return const [];
  final phrases = decoded['phrases'];
  if (phrases is! List) return const [];
  return [
    for (final phrase in phrases)
      // Skipped exactly as the adapter skips them, so a malformed phrase
      // cannot fail the report of a dance the adapter read.
      if (phrase is Map && phrase['figures'] is List)
        (
          '${phrase['name'] ?? ''}',
          [for (final line in phrase['figures'] as List) '$line'],
        ),
  ];
}

/// One figure of a bridged record (`move`, `params`, `progression`) as one
/// line: `move(param: value, ...)`. A `progression` flag reads
/// `[progression]` whether the source wrote it or the bridge assumed it.
String describeRecordFigure(Map<String, Object?> figure) {
  final params = <String>[
    for (final entry
        in ((figure['params'] as Map?) ?? const {})
            .cast<String, Object?>()
            .entries)
      if (entry.key == 'figures' && entry.value is List)
        'figures: [${[for (final child in entry.value! as List) child is Map ? describeRecordFigure(child.cast<String, Object?>()) : '$child'].join('; ')}]'
      else
        '${entry.key}: ${entry.value}',
  ];
  return '${figure['move']}(${params.join(', ')})'
      '${figure['progression'] == true ? ' [progression]' : ''}';
}

/// [formation] as one string per row. See [TraceStep.grid].
List<String> renderGrid(Formation formation) => [
  for (var row = 0; row < formation.rowCount; row++)
    [
      for (var col = 0; col < kColumnCount; col++)
        switch (formation.dancerAt(Position(row, col))) {
          null => '.',
          final id => _cell(id, formation.stateOf(id)),
        },
    ].join(' '),
];

String _label(DancerId id, DancerState state) =>
    '${id.role.label}${state.number.label}-${id.coupleLetter}';

String _cell(DancerId id, DancerState state) =>
    '${_label(id, state)}${_glyph(state.facing)}'
    '${state.waitingOut ? '*' : ''}';

String _glyph(Facing facing) => switch (facing) {
  Facing.up => '^',
  Facing.down => 'v',
  Facing.acrossEast => '>',
  Facing.acrossWest => '<',
  Facing.flexible => '~',
};

String _place(DancerState state) =>
    'row ${state.position.row} col ${state.position.col} '
    '#${state.number == CoupleNumber.one ? 1 : 2}';

List<String> _moved(Formation before, Formation after) => [
  for (final id in after.dancers.keys)
    if (before.stateOf(id).position != after.stateOf(id).position)
      _label(id, after.stateOf(id)),
];

List<String> _offDancers(Formation actual, Formation expected) => [
  for (final id in actual.dancers.keys)
    if (actual.stateOf(id).position != expected.stateOf(id).position ||
        actual.stateOf(id).number != expected.stateOf(id).number)
      '$id: expected ${_place(expected.stateOf(id))}, '
          'actual ${_place(actual.stateOf(id))}',
];

/// A Markdown summary of [diagnoses]: failures grouped by [FailureDiagnosis.signature],
/// with the mismatch classes and placement hints counted.
///
/// [coreIds] marks the dances of a focus set (Hudson's Seattle core set, in
/// practice) so each group carries its count beside the total. In-scope and
/// deferred failures are listed separately, because only the first count
/// against the headline rate.
String summarizeFailures(
  List<FailureDiagnosis> diagnoses, {
  Set<String> coreIds = const {},
  int examples = 5,
}) {
  bool isCore(FailureDiagnosis d) => coreIds.contains(d.run.sourceId);
  final buffer = StringBuffer()
    ..writeln('# Rubric failure summary')
    ..writeln();
  final inScope = diagnoses.where((d) => d.run.inScope).toList();
  final deferred = diagnoses.where((d) => !d.run.inScope).toList();
  final withCore = coreIds.isNotEmpty;

  buffer
    ..writeln(
      '${inScope.length} in-scope failures'
      '${withCore ? ' (${inScope.where(isCore).length} core)' : ''}; '
      '${deferred.length} more blocked by a deferral.',
    )
    ..writeln();

  final hinted = inScope.where((d) => d.placementHint?.isNotEmpty ?? false);
  final tried = inScope.where((d) => d.placementHint != null);
  final assumed = inScope.where((d) => d.run.assumedProgressionAt != null);
  buffer
    ..writeln('## Progression placement')
    ..writeln()
    ..writeln(
      '${hinted.length} of ${tried.length} in-scope failures that parsed with '
      'an assumed progression compile when the flag is moved to another figure'
      '${withCore ? ' (${hinted.where(isCore).length} core)' : ''}. '
      '${assumed.length - tried.length} more assumed one but never parsed, so '
      'were not tried. Diagnostic only: the scored run never tries other '
      'placements. By the earliest figure that compiles:',
    )
    ..writeln();
  final byPlace = <String, int>{};
  for (final d in hinted) {
    final earliest = d.placementHint!.first;
    final place = earliest == 0
        ? 'the first figure'
        : earliest == d.figures.length - 1
        ? 'the last figure'
        : 'a middle figure';
    byPlace[place] = (byPlace[place] ?? 0) + 1;
  }
  for (final entry
      in byPlace.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    buffer.writeln('- ${entry.value} on ${entry.key}');
  }
  buffer.writeln();

  void table(String heading, List<FailureDiagnosis> group) {
    final bySignature = <String, List<FailureDiagnosis>>{};
    for (final d in group) {
      (bySignature[d.signature] ??= []).add(d);
    }
    final rows = bySignature.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    buffer
      ..writeln('## $heading')
      ..writeln()
      ..writeln(
        withCore
            ? '| Dances | Core | Placement fixes | Cause | Examples |'
            : '| Dances | Placement fixes | Cause | Examples |',
      )
      ..writeln(
        withCore
            ? '| ---: | ---: | ---: | --- | --- |'
            : '| ---: | ---: | --- | --- |',
      );
    for (final row in rows) {
      final fixes = row.value
          .where((d) => d.placementHint?.isNotEmpty ?? false)
          .length;
      final ids = [
        for (final d in row.value.take(examples)) d.run.sourceId ?? d.run.label,
      ].join(', ');
      final cause = row.key.replaceAll('|', r'\|');
      buffer.writeln(
        withCore
            ? '| ${row.value.length} | ${row.value.where(isCore).length} | $fixes | $cause | $ids |'
            : '| ${row.value.length} | $fixes | $cause | $ids |',
      );
    }
    buffer.writeln();
  }

  table('In-scope failures by cause', inScope);
  table('Deferred failures by cause', deferred);
  return buffer.toString();
}
