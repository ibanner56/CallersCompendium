/// Reading The Caller's Box through `compendium_core`'s import adapter
/// (`docs/architecture.md` §9, `docs/implementation.md` §10).
///
/// This is the compiler's **second** input boundary. [parseDance] reads the
/// dance-record shape the app already stores; this file reads a foreign corpus
/// by handing it to core's [core.CallersBoxAdapter] and translating the
/// [core.Dance] that comes back. Nothing here re-implements a dialect: the
/// prose-to-figure work belongs upstream and stays there, and the only thing
/// this file owns is the translation between two structured models.
///
/// It lives in `lib/` rather than `tool/` because two callers need it — the
/// integration test in `test/io/`, and `bin/callersbox_harness.dart` — and a
/// library is the only placement that lets both import it as a package.
library;

import 'package:compendium_core/compendium_core.dart' as core;

import '../engine/compile_result.dart';
import '../engine/compiler.dart';
import '../engine/result.dart';
import '../ops/diagnostics.dart';
import 'dance_json.dart';

/// What became of one dance, from payload to verdict.
///
/// The three failing outcomes before [figureRefused] are all "the compiler
/// never ran", and they are kept apart because they blame different things:
/// [adapterFailed] blames the payload, [empty] and [unstructured] blame the
/// source's coverage of the dance, and [unsupported] blames this compiler.
/// Collapsing them would make a coverage number unreadable — a corpus that is
/// 30% unstructured and one that is 30% unsupported call for opposite work.
enum DanceOutcome {
  /// Ran, and landed where the dance claimed it would.
  compiled,

  /// Ran to the end, but the set landed somewhere else.
  mismatch,

  /// A figure refused to run.
  figureRefused,

  /// The compiler **threw**, which it is never supposed to do.
  ///
  /// Always a defect in this package, never a fact about the dance: a figure
  /// that cannot run is required to return an [OpError], so an exception
  /// escaping [compile] means an operation built a formation it should have
  /// refused to build. Caught here only so that one bad dance cannot end a
  /// corpus sweep, and kept as its own outcome so that catching it does not
  /// quietly bury it among the legitimate refusals.
  crashed,

  /// The record could not be read: a move this compiler does not implement, a
  /// progression tier it does not model, a non-contra form.
  unsupported,

  /// The adapter left at least one figure as free text.
  ///
  /// Never compiled, by standing rule: a `custom` figure has no semantics, so
  /// running the dance around it would produce a confident answer about
  /// choreography nobody described. *(User-ruled.)*
  unstructured,

  /// The adapter produced no figures at all.
  ///
  /// Usually a permission tier below `full`, where the source withholds the
  /// choreography. Distinct from [unstructured] because there is nothing to
  /// implement here — the dance was never in the payload.
  empty,

  /// The payload could not be read as a Caller's Box record at all.
  adapterFailed,
}

/// One dance's trip through the pipeline, with everything worth reporting.
class DanceRun {
  const DanceRun({
    required this.title,
    required this.outcome,
    required this.sourceId,
    required this.label,
    this.detail,
    this.warnings = const [],
    this.moves = const {},
    this.totalFigures = 0,
    this.customFigures = 0,
    this.assumedProgressionAt,
  });

  final String title;
  final DanceOutcome outcome;

  /// The source's own id (TCB's `ID`), when the payload carried one.
  final String? sourceId;

  /// Where the payload came from — a file path, or a caller-supplied name.
  final String label;

  /// Why, for the outcomes that have a reason: the parse error, the refusing
  /// figure, or the adapter's complaint.
  final String? detail;

  /// Import warnings and compile warnings, in that order.
  final List<Warning> warnings;

  /// The move ids the source named, before alias resolution.
  ///
  /// Deliberately the *source* vocabulary rather than the resolved one, because
  /// this is the set a coverage question is asked about: `see_saw` appearing in
  /// a corpus is a fact about the corpus, and that it resolves to `do_si_do`
  /// is a fact about this compiler.
  final Set<String> moves;

  final int totalFigures;
  final int customFigures;

  /// The figure this run assumed was the progression, when it assumed one.
  final int? assumedProgressionAt;

  bool get ran =>
      outcome == DanceOutcome.compiled || outcome == DanceOutcome.mismatch;

  /// Whether the compiler was given a chance at all.
  ///
  /// A crash counts: the compiler was handed the dance and did not compile it,
  /// and excluding it would flatter the rate by hiding this package's own bugs.
  bool get attempted =>
      ran ||
      outcome == DanceOutcome.figureRefused ||
      outcome == DanceOutcome.crashed;

  @override
  String toString() =>
      '$title: ${outcome.name}${detail == null ? '' : ' ($detail)'}';
}

/// Aggregate figures over a set of runs.
///
/// Every rate here names its own denominator, because there is no single
/// honest one: a corpus is mostly dances this compiler was never given
/// ([DanceOutcome.empty], [DanceOutcome.unstructured]), and dividing by the
/// file count would report the source's coverage as though it were ours.
class CorpusReport {
  CorpusReport(List<DanceRun> runs) : runs = List.unmodifiable(runs);

  final List<DanceRun> runs;

  int get total => runs.length;

  int count(DanceOutcome outcome) =>
      runs.where((run) => run.outcome == outcome).length;

  /// Dances the compiler actually got to run against.
  int get attempted => runs.where((run) => run.attempted).length;

  int get compiled => count(DanceOutcome.compiled);

  /// Compiles as a fraction of the dances the compiler was handed. `0.0` when
  /// it was handed none — an empty corpus scores nothing, not everything.
  double get compileRate => attempted == 0 ? 0.0 : compiled / attempted;

  /// Every move id named anywhere in the corpus, including in dances that never
  /// compiled.
  Set<String> get movesSeen => {for (final run in runs) ...run.moves};

  /// Moves the corpus names that this compiler implements.
  Set<String> get movesCovered =>
      movesSeen.intersection(supportedMoves.toSet());

  /// Moves the corpus names that this compiler does not implement — the
  /// backlog, ordered by nothing but ready to be counted.
  Set<String> get movesMissing => movesSeen.difference(supportedMoves.toSet());

  /// Implemented moves this corpus never exercised — the blind spots in the
  /// sample rather than in the compiler.
  Set<String> get movesUnexercised =>
      supportedMoves.toSet().difference(movesSeen);

  /// Share of this compiler's vocabulary the corpus exercised.
  double get vocabularyCoverage => supportedMoves.isEmpty
      ? 0.0
      : movesCovered.length / supportedMoves.length;

  /// Share of the corpus's vocabulary this compiler implements.
  double get corpusCoverage =>
      movesSeen.isEmpty ? 0.0 : movesCovered.length / movesSeen.length;
}

/// Runs every dance in a Caller's Box [payload] through the whole pipeline.
///
/// [label] names the payload in the resulting [DanceRun]s — a file path, when
/// there is one. A payload holding several dances yields several runs; the
/// adapter accepts a bare record, a bare array, or a `{dances: [...]}` wrapper.
///
/// Never throws for a bad payload: an unreadable one becomes a single
/// [DanceOutcome.adapterFailed] run, so a caller folding over a corpus keeps
/// going.
Future<List<DanceRun>> runCallersBoxPayload(
  String payload, {
  String label = '<payload>',
}) async {
  final adapter = core.CallersBoxAdapter();
  final List<core.DiscoveredRecord> discovered;
  try {
    discovered = await adapter.discover(core.ImportRequest(payload: payload));
  } on Exception catch (error) {
    return [_adapterFailure(label, error)];
  }

  final runs = <DanceRun>[];
  for (final record in discovered) {
    try {
      final draft = adapter.parse(await adapter.fetch(record));
      runs.add(runCoreDance(draft, label: label));
    } on Exception catch (error) {
      runs.add(_adapterFailure(label, error, sourceId: record.externalId));
    }
  }
  return runs;
}

DanceRun _adapterFailure(String label, Object error, {String? sourceId}) =>
    DanceRun(
      title: label,
      outcome: DanceOutcome.adapterFailed,
      sourceId: sourceId,
      label: label,
      detail: '$error',
    );

/// Translates one [core.StructuredDraft] into a record, compiles it, and
/// reports the verdict.
DanceRun runCoreDance(core.StructuredDraft draft, {String label = '<draft>'}) {
  final dance = draft.dance;
  final sourceId = draft.raw.externalId;
  final moves = {for (final figure in dance.figures) figure.move};

  DanceRun finish(
    DanceOutcome outcome, {
    String? detail,
    List<Warning>? extra,
    int? assumedAt,
  }) => DanceRun(
    title: dance.title,
    outcome: outcome,
    sourceId: sourceId,
    label: label,
    detail: detail,
    warnings: extra ?? const [],
    moves: moves,
    totalFigures: draft.quality.totalFigures,
    customFigures: draft.quality.customFigures,
    assumedProgressionAt: assumedAt,
  );

  if (dance.figures.isEmpty) {
    return finish(DanceOutcome.empty, detail: 'the source carried no figures');
  }
  if (draft.quality.customFigures > 0) {
    // Rejected before the compiler sees it, not after it fails: a `custom`
    // figure is text, and there is no reading of it that would make the dance
    // around it meaningful. *(User-ruled.)*
    return finish(
      DanceOutcome.unstructured,
      detail:
          '${draft.quality.customFigures} of ${draft.quality.totalFigures} '
          'figures stayed free text',
    );
  }

  // One compile with the positional assumption. If the assumption is the only
  // thing in the way, try the single alternative the record itself names.
  // *(User-ruled.)* The retry is deliberately not a search: exactly two
  // placements are ever tried, both chosen by reading the figures rather than
  // the formation, and a second failure is reported as the first one's.
  //
  // A crash is never retried. The compiler throwing is a defect here, and a
  // second placement that happens to land would bury it.
  var attempt = _attempt(bridgeCoreDance(dance));
  if (attempt.outcome != DanceOutcome.compiled &&
      attempt.outcome != DanceOutcome.crashed) {
    final fallback = bridgeCoreDance(dance, useNextNeighborsFallback: true);
    if (fallback.assumedProgressionAt != null &&
        fallback.assumedProgressionAt != attempt.assumedAt) {
      final retry = _attempt(fallback);
      if (retry.outcome == DanceOutcome.compiled) attempt = retry;
    }
  }
  return finish(
    attempt.outcome,
    detail: attempt.detail,
    extra: attempt.warnings,
    assumedAt: attempt.assumedAt,
  );
}

/// The outcome of compiling one bridged reading of a dance.
typedef _Attempt = ({
  DanceOutcome outcome,
  String? detail,
  List<Warning> warnings,
  int? assumedAt,
});

_Attempt _attempt(BridgedDance bridged) {
  _Attempt done(DanceOutcome outcome, {String? detail, List<Warning>? extra}) =>
      (
        outcome: outcome,
        detail: detail,
        warnings: extra ?? bridged.warnings,
        assumedAt: bridged.assumedProgressionAt,
      );

  switch (parseDance(bridged.record)) {
    case Err(:final error):
      return done(DanceOutcome.unsupported, detail: '$error');
    case Ok(:final value):
      final CompileResult result;
      try {
        result = compile(value);
      } catch (error) {
        // Deliberately unfiltered: what is being caught is "the compiler threw
        // at all", and narrowing the clause would let some other escaping type
        // end the sweep. The outcome keeps it loud.
        return done(DanceOutcome.crashed, detail: '$error');
      }
      final warnings = [...bridged.warnings, ...result.warnings];
      return switch (result) {
        Compiled() => done(DanceOutcome.compiled, extra: warnings),
        Mismatch() => done(
          DanceOutcome.mismatch,
          detail: 'ran, but the set landed elsewhere',
          extra: warnings,
        ),
        CompileError(:final opIndex, :final opName, :final error) => done(
          DanceOutcome.figureRefused,
          detail: opIndex == null
              ? '${error.kind.name}: ${error.message}'
              : 'figure ${opIndex + 1} ($opName) '
                    '${error.kind.name}: ${error.message}',
          extra: warnings,
        ),
      };
  }
}

/// A [core.Dance] rendered as a record this compiler can read, with whatever
/// the translation had to assume.
class BridgedDance {
  const BridgedDance({
    required this.record,
    this.warnings = const [],
    this.assumedProgressionAt,
  });

  final Map<String, Object?> record;
  final List<Warning> warnings;
  final int? assumedProgressionAt;
}

/// Translates a [core.Dance] into the dance-record shape [parseDance] reads.
///
/// The translation is deliberately thin — four fields, because those are the
/// four [parseDance] looks at — and it does exactly one thing the source did
/// not: it may supply the progression flag. See [assumedProgressionIndex].
///
/// Set [useNextNeighborsFallback] to place the progression by
/// [nextNeighborsProgressionIndex] instead. That is the retry
/// [runCoreDance] makes when the positional rule does not compile; it is not a
/// better rule, only a second guess, and it warns just as loudly.
BridgedDance bridgeCoreDance(
  core.Dance dance, {
  bool useNextNeighborsFallback = false,
}) {
  final flagged = dance.figures.any((figure) => figure.progression);
  final assumedAt = flagged
      ? null
      : (useNextNeighborsFallback
            ? nextNeighborsProgressionIndex(dance)
            : assumedProgressionIndex(dance));
  final warnings = <Warning>[
    if (assumedAt != null)
      Warning(
        WarningKind.assumedProgression,
        opIndex: assumedAt,
        detail:
            'the source flagged no figure as the progression, so figure '
            '${assumedAt + 1} (${dance.figures[assumedAt].move}) was assumed '
            'to be it'
            '${useNextNeighborsFallback ? ', because the positional rule did '
                      'not compile and this is the figure before the first '
                      'nextNeighbors reach' : ''}',
      ),
  ];

  return BridgedDance(
    record: {
      'title': dance.title,
      'form': dance.form.name,
      'formation': {'shape': dance.formation.shape.name},
      'progression': dance.progression.name,
      'figures': [
        for (var index = 0; index < dance.figures.length; index++)
          {
            'move': dance.figures[index].move,
            'params': dance.figures[index].params,
            if (dance.figures[index].progression || index == assumedAt)
              'progression': true,
          },
      ],
    },
    warnings: warnings,
    assumedProgressionAt: assumedAt,
  );
}

/// Which figure to treat as the progression when the source never said.
///
/// The Caller's Box has nowhere to record this. Its figure lines are prose, and
/// unlike ContraDB's markup — which the sibling adapter reads for an explicit
/// marker — there is no structural marker to carry across, so every dance
/// imported from it arrives with no figure flagged.
///
/// The rule is positional, not semantic, and it is a rule rather than a search
/// on purpose: nothing here looks at what the figures *do*. **The last figure
/// progresses**, which is where contra choreography overwhelmingly puts it —
/// the dance ends standing with the next couple.
///
/// The one exception is a **Becket dance that opens with a slide left**. Becket
/// dancers progress along the set rather than through it, and a slide left at
/// the top of the dance *is* that progression: it is the figure that hands the
/// couple to the next one, and everything after it is danced with the new
/// neighbours. Reading the final figure there would place the progression a
/// full time through the dance away from where it happens.
///
/// Returns `null` only for a dance with no figures. *(User-ruled.)*
int? assumedProgressionIndex(core.Dance dance) {
  if (dance.figures.isEmpty) return null;

  final shape = dance.formation.shape;
  final isBecket =
      shape == core.FormationShape.becketCw ||
      shape == core.FormationShape.becketCcw;
  if (isBecket) {
    final opener = dance.figures.first;
    // `slide` defaults to `left` upstream, so an unparameterised slide is a
    // slide left and must be read as one.
    final slide = opener.params['slide'] ?? 'left';
    if (opener.move == 'slide_along_set' && slide == 'left') return 0;
  }

  return dance.figures.length - 1;
}

/// The one alternative placement the *record itself* suggests, for when the
/// positional rule of [assumedProgressionIndex] does not compile.
///
/// A figure that reaches for `nextNeighbors` is naming the couple this hands
/// four has not met yet, so the progression must already have happened when it
/// is danced. The figure **immediately before the first such mention** is
/// therefore the latest point the progression can sit and still leave that
/// reach meaning what it says. *(User-ruled.)*
///
/// This reads the figures' parameters, not the compiled state: it is the same
/// kind of positional reasoning as [assumedProgressionIndex], with the record
/// supplying the landmark instead of the formation. Nothing here inspects where
/// dancers ended up, which the compiler forbids as a basis for progression.
///
/// Returns `null` when no figure mentions `nextNeighbors`, or when the first
/// mention is the opening figure and so has nothing before it.
int? nextNeighborsProgressionIndex(core.Dance dance) {
  for (var index = 0; index < dance.figures.length; index++) {
    final mentions = dance.figures[index].params.values.any(
      (value) => value == 'nextNeighbors' || value == 'nextNeighbor',
    );
    if (!mentions) continue;
    return index == 0 ? null : index - 1;
  }
  return null;
}
