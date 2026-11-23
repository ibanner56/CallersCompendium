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

  /// The adapter left at least one figure as free text, or structured one
  /// with less than the line said.
  ///
  /// Never compiled, by standing rule: a `custom` figure has no semantics, so
  /// running the dance around it would produce a confident answer about
  /// choreography nobody described. *(User-ruled.)* The same holds for a
  /// Caller's Box promenade that imports with no `where`: the line named a
  /// whole-set, counter-rotating, around-a-dancer or mixer promenade, and the
  /// import kept only the rotation. A line that does not import cleanly is the
  /// import pipeline's problem, not this compiler's. *(User-ruled
  /// 2026-11-22.)*
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
    this.blockedByDeferral = false,
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

  /// How many figures the source wrote, counted by `compendium_core` over
  /// its top-level lines: a `sequence` container counts once here, though it
  /// is danced as its children (see [dancedFigures]).
  final int totalFigures;
  final int customFigures;

  /// Whether this dance was stopped by something **deliberately deferred**
  /// rather than by a gap in the model.
  ///
  /// True for a move this compiler has not implemented, a vocabulary value it
  /// does not model, and a parameter value inside an implemented figure that is
  /// deferred with `unsupportedParam`. False for everything else, including an
  /// unmodelled progression tier — that is a property of the dance, not of a
  /// figure in it, and folding it in here would quietly widen what "deferred"
  /// means.
  final bool blockedByDeferral;

  /// The figure this run assumed was the progression, when it assumed one.
  ///
  /// Like every figure index this path reports (warnings, a refusal's
  /// "figure N", a parse error's `figures[N]`), it is a position in
  /// [dancedFigures], not in the source's lines: after a `sequence` the two
  /// differ, and this index can exceed [totalFigures].
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

  /// Whether this dance is inside the set the compiler is currently *aiming*
  /// at: it parsed with no figure left as free text, and nothing in it is
  /// deferred for later implementation. *(User-ruled scope.)*
  ///
  /// This is the honest denominator for a "how are we doing" number. It is not
  /// the honest denominator for "how much of the corpus can we read", which is
  /// what [CorpusReport.compileRate] answers — a deferral excluded here is
  /// still a dance nobody can compile today.
  ///
  /// **It is a slight over-estimate of the set, in the safe direction.** A
  /// dance that refuses at figure 2 for a genuine reason may still hold a
  /// deferred figure 5 that was never reached, and it counts as in scope. So
  /// the rate below is a floor, never a flattered number.
  bool get inScope =>
      !blockedByDeferral &&
      outcome != DanceOutcome.unstructured &&
      outcome != DanceOutcome.empty &&
      outcome != DanceOutcome.adapterFailed;

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

  /// Dances in the set this compiler is currently aiming at: parsed, no free
  /// text, nothing deferred. See [DanceRun.inScope].
  int get inScope => runs.where((run) => run.inScope).length;

  /// Dances excluded from [inScope] because something in them is deferred.
  int get deferred => runs.where((run) => run.blockedByDeferral).length;

  /// The headline rate: compiles as a fraction of the dances this compiler is
  /// currently *trying* to handle. *(User-ruled scope.)*
  double get inScopeRate => inScope == 0 ? 0.0 : compiled / inScope;

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
  final figures = dancedFigures(dance);
  final moves = {
    for (final figure in figures ?? const <core.Figure>[]) ..._movesIn(figure),
  };

  DanceRun finish(
    DanceOutcome outcome, {
    String? detail,
    List<Warning>? extra,
    int? assumedAt,
    bool deferred = false,
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
    blockedByDeferral: deferred,
    assumedProgressionAt: assumedAt,
  );

  if (figures == null) {
    // Not reachable from the Caller's Box adapter, which only ever builds a
    // decoded transcription; said rather than assumed, because the type allows
    // it and an empty list here would misreport the dance as `empty`.
    return finish(
      DanceOutcome.adapterFailed,
      detail: 'the transcription could not be decoded',
    );
  }
  if (figures.isEmpty) {
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

  final unreadPromenade = _promenadeWithNoWhere(figures);
  if (unreadPromenade != null) {
    // An import problem, so it is reported before the compiler is asked,
    // exactly as a free-text figure is (see [DanceOutcome.unstructured]).
    return finish(
      DanceOutcome.unstructured,
      detail:
          'figure ${unreadPromenade + 1} (promenade) imported with no where; '
          'in a Caller\'s Box record that is a whole-set, counter-rotating, '
          'around-a-dancer or mixer promenade the import could not name',
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
    deferred: attempt.deferred,
  );
}

/// The outcome of compiling one bridged reading of a dance.
typedef _Attempt = ({
  DanceOutcome outcome,
  String? detail,
  List<Warning> warnings,
  int? assumedAt,
  bool deferred,
});

_Attempt _attempt(BridgedDance bridged) {
  _Attempt done(
    DanceOutcome outcome, {
    String? detail,
    List<Warning>? extra,
    bool deferred = false,
  }) => (
    outcome: outcome,
    detail: detail,
    warnings: extra ?? bridged.warnings,
    assumedAt: bridged.assumedProgressionAt,
    deferred: deferred,
  );

  switch (parseDance(bridged.record)) {
    case Err(:final error):
      return done(
        DanceOutcome.unsupported,
        detail: '$error',
        deferred: error.deferred,
      );
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
          deferred: error.kind == ErrorKind.unsupportedParam,
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

  /// A position in [dancedFigures], as is every index in [record]'s figures.
  final int? assumedProgressionAt;
}

/// Translates a [core.Dance] into the dance-record shape [parseDance] reads.
///
/// The translation is deliberately thin — four fields, because those are the
/// four [parseDance] looks at. Its figures are [dancedFigures], so a `sequence`
/// arrives as its children (and a flagged sequence's flag on its last child).
/// Beyond that it does one thing the source did not: it may supply the
/// progression flag. See [assumedProgressionIndex].
///
/// Set [useNextNeighborsFallback] to place the progression by
/// [nextNeighborsProgressionIndex] instead. That is the retry
/// [runCoreDance] makes when the positional rule does not compile; it is not a
/// better rule, only a second guess, and it warns just as loudly.
BridgedDance bridgeCoreDance(
  core.Dance dance, {
  bool useNextNeighborsFallback = false,
}) {
  final figures = _requireDecoded(dance);
  final flagged = figures.any((figure) => figure.progression);
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
            '${assumedAt + 1} (${figures[assumedAt].move}) was assumed '
            'to be it'
            '${useNextNeighborsFallback ? ', because the positional rule did '
                      'not compile and this is where the first mention of the '
                      'next neighbours (nextNeighbors, N2) puts it' : ''}',
      ),
  ];

  return BridgedDance(
    record: {
      'title': dance.title,
      'form': dance.form.name,
      'formation': {'shape': dance.formation.shape.name},
      'progression': dance.progression.name,
      'figures': [
        for (var index = 0; index < figures.length; index++)
          {
            'move': figures[index].move,
            'params': _recordParams(figures[index].params),
            if (figures[index].progression || index == assumedAt)
              'progression': true,
          },
      ],
    },
    warnings: warnings,
    assumedProgressionAt: assumedAt,
  );
}

/// [params] as the record carries them: a container's child figures become
/// figure records in their own right, as [parseDance] reads them.
Map<String, Object?> _recordParams(Map<String, Object?> params) => {
  for (final entry in params.entries)
    entry.key: entry.key == 'figures' && entry.value is List
        ? [
            for (final child in entry.value! as List)
              if (child is core.Figure)
                {
                  'move': child.move,
                  'params': _recordParams(child.params),
                  if (child.progression) 'progression': true,
                }
              else
                child,
          ]
        : entry.value,
};

/// The figure that stands for [figure] when the importer asks what move a line
/// is: a `modifier`'s main figure, its first child, which the later ones only
/// change the styling of; otherwise [figure] itself.
///
/// So "slice left while partner roll away" opens a Becket dance with a slice,
/// and is where it progresses *(user-ruled 2026-11-23: a modifier carrying the
/// progression carries it for its main figure)*.
core.Figure _mainFigure(core.Figure figure) =>
    figure.move == 'modifier' && figure.subFigures.isNotEmpty
    ? figure.subFigures.first
    : figure;

/// Which figure to treat as the progression when the source never said.
///
/// The Caller's Box has nowhere to record this. Its figure lines are prose, and
/// unlike ContraDB's markup — which the sibling adapter reads for an explicit
/// marker — there is no structural marker to carry across, so every dance
/// imported from it arrives with no figure flagged.
///
/// The rule is a rule rather than a search on purpose: it never tries a
/// placement to see what compiles. Outside Becket it is purely positional.
/// **The last figure progresses**, which is where contra choreography
/// overwhelmingly puts it — the dance ends standing with the next couple. In
/// Becket it reads only which move a figure is, never what it does to the set.
///
/// The exception is a **Becket dance**, whose dancers progress along the set
/// rather than through it, on the obvious move:
///
/// - One that **opens with a slide left** (or a slice left, which lands
///   exactly like one) progresses on it. A slide left at the top of the dance
///   *is* the progression: it hands the couple to the next one, and everything
///   after it is danced with the new neighbours. Reading the final figure there
///   would place the progression a full time through the dance away from where
///   it happens.
/// - Otherwise its **first diagonal chain or pass through along the set**
///   progresses (user-ruled 2026-11-23). Only a Becket dance with neither
///   falls back to the last figure.
///
/// Returns `null` only for a dance with no figures. *(User-ruled.)*
int? assumedProgressionIndex(core.Dance dance) {
  final figures = _requireDecoded(dance);
  if (figures.isEmpty) return null;

  final shape = dance.formation.shape;
  final isBecket =
      shape == core.FormationShape.becketCw ||
      shape == core.FormationShape.becketCcw;
  if (isBecket) {
    final opener = _mainFigure(figures.first);
    // `slide` defaults to `left` upstream, so an unparameterised slide is a
    // slide left and must be read as one.
    // A slice lands like a slide (user-ruled 2026-11-22), so a Becket dance
    // opening with a slice left progresses there too. Its direction is
    // carried under `slice` rather than `slide`, defaulting to `left` as well.
    final direction = switch (opener.move) {
      'slide_along_set' => opener.params['slide'] ?? 'left',
      // Only a straight return, which is one slide. A diagonal return (a
      // "Double slice") flagged is two progressions (user-ruled 2026-11-23),
      // and single-progression dances open with one too, so it is not
      // assumed here (agent's call).
      'slice' when (opener.params['return'] ?? 'straight') == 'straight' =>
        opener.params['slice'] ?? 'left',
      _ => null,
    };
    if (direction == 'left') return 0;

    // Otherwise a Becket dance progresses on its first move along the set:
    // a diagonal chain, which sends the chainers to the next hands four, or a
    // pass through along the set. (User-ruled 2026-11-23: Becket progressions
    // are usually the obvious move.) The couples may not stand together at an
    // end until a figure or two later; the compiler holds the progression
    // until they do (`OperationInvocation.applyHolding`).
    for (var index = 0; index < figures.length; index++) {
      if (_movesAlongTheSet(_mainFigure(figures[index]))) return index;
    }
  }

  return figures.length - 1;
}

/// Whether [figure] is a Becket progression move: a `chain` on either
/// diagonal, or a `pass_through` along the set. The direction is carried under
/// `where` upstream; `pass_through` defaults to `along` (as the compiler's
/// `PassThrough` does).
bool _movesAlongTheSet(core.Figure figure) => switch (figure.move) {
  'chain' => switch (figure.params['where']) {
    'leftDiagonal' || 'rightDiagonal' => true,
    _ => false,
  },
  'pass_through' => (figure.params['where'] ?? 'along') == 'along',
  _ => false,
};

/// The one alternative placement the *record itself* suggests, for when the
/// positional rule of [assumedProgressionIndex] does not compile.
///
/// A figure that reaches for `nextNeighbors` is naming the couple this hands
/// four has not met yet, so the progression must already have happened when it
/// is danced. The figure **immediately before the first such mention** is
/// therefore the latest point the progression can sit and still leave that
/// reach meaning what it says. *(User-ruled.)*
///
/// **Notes count as well as params** *(user-ruled 2026-11-23)*. Caller's Box
/// uses N2 for the rest of a dance after its progression, and the import keeps
/// some of those mentions only as the figure's note:
/// - a note that dances *with* the next neighbours ("[with N2]", which the
///   import writes `with nextNeighbors`) reaches for them, as a param does;
/// - a note that ends *facing* them ("face N2") says the progression is done by
///   the end of that figure, so the figure itself is the placement.
///
/// A dance that names the next neighbours and later names plain `neighbors`
/// again has left its minor set and come back, so its N2 is not a progression
/// marker; a note-only mention followed by such a figure is skipped. A mention
/// carried in a param keeps its earlier ruling and is never skipped.
///
/// This reads the figures' parameters and notes, not the compiled state: it is
/// the same kind of positional reasoning as [assumedProgressionIndex], with the
/// record supplying the landmark instead of the formation. Nothing here
/// inspects where dancers ended up, which the compiler forbids as a basis for
/// progression.
///
/// Returns `null` when no figure mentions the next neighbours, or when the
/// first mention reaches for them in the opening figure and so has nothing
/// before it.
int? nextNeighborsProgressionIndex(core.Dance dance) {
  final figures = _requireDecoded(dance);
  for (var index = 0; index < figures.length; index++) {
    final figure = figures[index];
    if (_namesNextNeighbors(figure)) return index == 0 ? null : index - 1;
    final reaches = _noteReaches(figure);
    final faces = _noteFaces(figure);
    if (!reaches && !faces) continue;
    if (figures.skip(index + 1).any(_namesNeighbors)) continue;
    if (reaches) return index == 0 ? null : index - 1;
    return index;
  }
  return null;
}

/// Whether [figure], or any figure inside it, names `nextNeighbors` in a param.
///
/// A container's children are danced in its slot, so a roll away with the next
/// neighbours inside a modifier reaches for them as surely as one on its own
/// line. *(Agent's call, 2026-11-23.)*
bool _namesNextNeighbors(core.Figure figure) =>
    figure.params.values.any(
      (value) => value == 'nextNeighbors' || value == 'nextNeighbor',
    ) ||
    figure.subFigures.any(_namesNextNeighbors);

/// Whether [figure], or any figure inside it, names plain `neighbors`.
bool _namesNeighbors(core.Figure figure) =>
    figure.params.values.any(
      (value) => value == 'neighbors' || value == 'neighbor',
    ) ||
    figure.subFigures.any(_namesNeighbors);

/// A note that dances with the next neighbours: "with N2", or the import's
/// `with nextNeighbors`, possibly with others named alongside ("with N2,
/// shadow"). Stops at a `;`, which separates a note's clauses.
final _withNextNeighbors = RegExp(r'\bwith\b[^;]*\b(N2|nextNeighbors?)\b');

/// A note that ends facing the next neighbours: "face N2".
final _faceNextNeighbors = RegExp(r'\bface\s+(N2|nextNeighbors?)\b');

bool _noteReaches(core.Figure figure) =>
    _withNextNeighbors.hasMatch(figure.note ?? '') ||
    figure.subFigures.any(_noteReaches);

bool _noteFaces(core.Figure figure) =>
    _faceNextNeighbors.hasMatch(figure.note ?? '') ||
    figure.subFigures.any(_noteFaces);

/// [dance]'s figures when its transcription decoded, or `null` when it did not.
///
/// `compendium_core` holds a transcription as a sealed [core.FigureSource]
/// rather than a bare list, so that an undecodable one cannot be read as an
/// empty dance by accident; this keeps that distinction instead of flattening
/// it.
List<core.Figure>? decodedFigures(core.Dance dance) =>
    switch (dance.figuresSource) {
      core.DecodedFigures(:final figures) => figures,
      core.UnreadableFigures() => null,
    };

/// The position in [figures] of the first `promenade` that states no `where`,
/// or `null` when every promenade states one.
///
/// **Caller's Box only.** The taxonomy's default `where` is `across`, and
/// another source may rely on it: ContraDB's `partners promenade on the left`
/// imports with a rotation and no `where`, and is a promenade across. Caller's
/// Box never does. It writes every promenade across as `… promenade across`,
/// which imports with `where: across`, and the lines that import with none are
/// the promenades its vocabulary cannot name: `around the major set`, the
/// counter-rotating rings (`inner ring cw, outer ring ccw`), `3/4 around
/// neighbor`, and the mixers' `P2 partner promenade counterclockwise`.
/// Compiling those as the default would dance a promenade across that the
/// source never called, so the run stops before it is bridged and is reported
/// as [DanceOutcome.unstructured]: the line did not import cleanly, which is
/// the import pipeline's problem rather than this compiler's. *(User-ruled
/// 2026-11-22; measured on the 24,107-file mirror.)*
///
/// A promenade inside a container counts, and the position is the container's:
/// it is danced in that slot, and compiling it as `across` there would be the
/// same guess.
int? _promenadeWithNoWhere(List<core.Figure> figures) {
  for (var index = 0; index < figures.length; index++) {
    if (_hasPromenadeWithNoWhere(figures[index])) return index;
  }
  return null;
}

// `compendium_core` has neither a legacy `dir` spelling nor an `unspecified`
// value for `promenade.where`, so absence is the only case.
bool _hasPromenadeWithNoWhere(core.Figure figure) =>
    (figure.move == 'promenade' && figure.params['where'] == null) ||
    figure.subFigures.any(_hasPromenadeWithNoWhere);

/// [figure]'s move and those of every figure inside it.
Iterable<String> _movesIn(core.Figure figure) => [
  figure.move,
  for (final child in figure.subFigures) ..._movesIn(child),
];

/// [dance]'s figures as the compiler dances them: [decodedFigures] with every
/// `sequence` container replaced by its children, or `null` when the
/// transcription did not decode.
///
/// `compendium_core` defines a sequence as figures "danced one after another
/// and shown on one line", and says ordinary sequence is still just the order
/// of a dance's figures: the container exists so a run can sit where one figure
/// must (one side of a `meanwhile`), not to change what is danced. Splicing the
/// children in place is therefore that definition read literally, and it
/// happens before anything positional reads the list, so the progression rules
/// below see the figures that are actually danced rather than the line they
/// were written on.
///
/// Only a top-level sequence is spliced. A sequence inside a `meanwhile` or
/// `modifier` stays inside it, and the parser builds those containers
/// (`docs/taxonomy.md`, "Containers"). A sequence with no readable children
/// (core's own constructor requires two, so only a malformed record gets here)
/// is left in place and refused by the parser, rather than silently
/// vanishing.
///
/// Every figure index reported downstream counts positions in this list, not
/// the source's lines.
///
/// A sequence the source flagged as the progression hands the flag to its
/// **last** child: the container's figure ends when its last child ends, which
/// is the same reading [assumedProgressionIndex] gives a dance whose final
/// figure is the progression. *(Agent's call, not yet ruled; the alternative
/// was refusing a flagged sequence, which no Caller's Box record can carry.)*
List<core.Figure>? dancedFigures(core.Dance dance) {
  final figures = decodedFigures(dance);
  if (figures == null) return null;
  return [
    for (final figure in figures)
      if (figure.isSequence && figure.subFigures.isNotEmpty)
        for (var i = 0; i < figure.subFigures.length; i++)
          figure.progression && i == figure.subFigures.length - 1
              ? figure.subFigures[i].copyWith(progression: true)
              : figure.subFigures[i]
      else
        figure,
  ];
}

List<core.Figure> _requireDecoded(core.Dance dance) =>
    dancedFigures(dance) ??
    (throw ArgumentError.value(
      dance.title,
      'dance',
      'has an undecodable transcription',
    ));
