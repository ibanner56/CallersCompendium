/// Test-only helpers for constructing figure fixtures that are checked against
/// the taxonomy.
///
/// This is a **separate entry point** from `compendium_core.dart` so that
/// nothing here is reachable from production code: importing
/// `package:compendium_core/compendium_core.dart` does not pull it in.
///
/// ## Why this exists
///
/// Test fixtures were never validated against the taxonomy. Rendering
/// *substitutes* rather than *validates*, so an invalid param renders literally
/// and the test still passes — which is how seven `meanwhile` fixtures silently
/// drifted when #697 split `orbit` into a first-class move, and stayed broken
/// for days until #745 (issue #747).
///
/// The `check_fixture_validity` ratchet closes that gap. It can validate a
/// fixture written entirely from literals by reading the source, but a fixture
/// built from variables — `Figure(move: id, params: {'who': who})` — only has
/// values at run time, so no source-reading check can reach it. [testFigure]
/// is the runtime half: it validates at construction, where the real values
/// exist.
///
/// ## Which one to use
///
/// * A fixture written from literals needs nothing — the ratchet reads and
///   validates it in place.
/// * A fixture built from variables must use [testFigure].
/// * A fixture that is **deliberately** invalid — testing how the app handles
///   untrusted or unknown input — must use [invalidTestFigure] and say why.
///
/// The ratchet enforces exactly this: every `Figure(` in the suites is either
/// literal-and-valid, routed through here, or carries an
/// `// invalid-fixture:` marker. Nothing can be silently omitted.
library;

import 'src/model/figure.dart';
import 'src/taxonomy/contra_taxonomy.dart';
import 'src/validation/validation.dart';

/// Builds a [Figure] and asserts it is valid under `contraTaxonomy`.
///
/// The signature mirrors [Figure]'s constructor exactly, so routing an existing
/// fixture through this is a rename and nothing else — no argument
/// reshuffling, and therefore no opportunity to change a fixture's meaning
/// while "just" satisfying the ratchet.
///
/// Throws [StateError] listing every error-severity issue when the figure is
/// invalid. Use this for any fixture whose move or params come from variables;
/// a fixture written entirely from literals is checked by the ratchet without
/// it.
///
/// Deliberately invalid fixtures must use [invalidTestFigure] instead — this
/// function has no bypass, because a bypass is what a drifted fixture would
/// reach for.
Figure testFigure({
  int schemaVersion = figureSchemaVersion,
  required String move,
  Map<String, Object?> params = const {},
  String? note,
  bool progression = false,
  CustomOrigin customOrigin = CustomOrigin.userEntered,
  bool assumedSubject = false,
  String? walkthroughOverride,
}) {
  final figure = Figure(
    schemaVersion: schemaVersion,
    move: move,
    params: params,
    note: note,
    progression: progression,
    customOrigin: customOrigin,
    assumedSubject: assumedSubject,
    walkthroughOverride: walkthroughOverride,
  );
  final issues = contraTaxonomy
      .validateFigure(figure)
      .where((i) => i.severity == ValidationSeverity.error)
      .toList();
  if (issues.isNotEmpty) {
    throw StateError(
      'invalid figure fixture: $move${params.isEmpty ? '' : ' $params'}\n'
      '${issues.map((i) => '  - [${i.code}] ${i.message}').join('\n')}\n'
      'If this fixture is invalid ON PURPOSE (testing untrusted or unknown '
      'input), use invalidTestFigure(..., reason: ...) and say why.',
    );
  }
  return figure;
}

/// Builds a [Figure] **without** validating it, for a fixture that is invalid
/// on purpose.
///
/// [reason] is required and must be substantive: it documents *why* this
/// fixture tests an error path, at the point of use where the next reader will
/// be. Several suites depend on invalid input — the renderer must surface an
/// unexpected dancer token via best-effort humanize rather than blanking it
/// (OWASP: never silently hide untrusted input), and the shorthand mapper must
/// drop a mapping whose value does not conform.
///
/// Throws [ArgumentError] if [reason] is too short to be meaningful, so this
/// cannot become a silent bypass of [testFigure].
Figure invalidTestFigure({
  int schemaVersion = figureSchemaVersion,
  required String move,
  Map<String, Object?> params = const {},
  String? note,
  bool progression = false,
  CustomOrigin customOrigin = CustomOrigin.userEntered,
  bool assumedSubject = false,
  String? walkthroughOverride,
  required String reason,
}) {
  if (reason.trim().length < minFixtureReasonLength) {
    throw ArgumentError.value(
      reason,
      'reason',
      'must be at least $minFixtureReasonLength characters explaining why '
          'this fixture is deliberately invalid',
    );
  }
  return Figure(
    schemaVersion: schemaVersion,
    move: move,
    params: params,
    note: note,
    progression: progression,
    customOrigin: customOrigin,
    assumedSubject: assumedSubject,
    walkthroughOverride: walkthroughOverride,
  );
}

/// Shortest `reason` accepted by [invalidTestFigure], and by the
/// `// invalid-fixture:` marker the ratchet reads. Long enough that a
/// placeholder like "n/a" or "test" cannot pass, short enough not to force
/// padding.
const int minFixtureReasonLength = 15;
