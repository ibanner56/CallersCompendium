import 'package:meta/meta.dart';

import '../domain/formation.dart';
import '../ops/diagnostics.dart';

/// The outcome of compiling a dance (`docs/architecture.md` §4, §8.3, D8).
///
/// Sealed so callers must handle all three cases exhaustively. **[Mismatch] and
/// [CompileError] stay distinct**: "the dance ran and landed somewhere else" and
/// "the dance could not run" are different facts about the choreography, and
/// collapsing them would hide which one happened.
@immutable
sealed class CompileResult {
  const CompileResult({this.warnings = const []});

  /// Non-fatal diagnostics gathered during the compile.
  ///
  /// Present on every outcome: a warning never decides the outcome, so it must
  /// not be lost just because the dance also mismatched or errored.
  final List<Warning> warnings;

  /// Whether the dance compiled successfully.
  bool get isSuccess => this is Compiled;
}

/// Every operation ran and the final formation matched the success criterion.
final class Compiled extends CompileResult {
  const Compiled(this.finalFormation, {super.warnings});

  final Formation finalFormation;

  @override
  String toString() => 'Compiled($finalFormation)';
}

/// Every operation ran, but the final formation is not the expected one.
///
/// Both states are retained so a caller can diff them — the whole point of
/// keeping this separate from [CompileError].
final class Mismatch extends CompileResult {
  const Mismatch({
    required this.actual,
    required this.expected,
    super.warnings,
  });

  /// Where the operation list actually landed.
  final Formation actual;

  /// Where the success criterion says it should have landed, computed
  /// independently from the input formation (§3.4).
  final Formation expected;

  @override
  String toString() => 'Mismatch(actual: $actual, expected: $expected)';
}

/// A dance refused to compile, short-circuiting the fold (§3.3).
///
/// No `expected`/`actual` comparison is performed in this case, so there is no
/// final state to report.
///
/// Usually an operation refused, and [opIndex]/[opName] name it. They are
/// `null` for a refusal that no single figure owns — a dance that declares a
/// progression its figure list never performs is a fact about the list as a
/// whole — the same distinction [Warning.opIndex] draws.
final class CompileError extends CompileResult {
  const CompileError({
    required this.error,
    this.opIndex,
    this.opName,
    super.warnings,
  });

  /// Zero-based index of the offending operation, or `null` when the refusal
  /// is about the figure list as a whole.
  final int? opIndex;

  /// The offending operation's registry key, or `null` alongside [opIndex].
  final String? opName;

  final OpError error;

  /// The taxonomy error kind (D12).
  ErrorKind get kind => error.kind;

  @override
  String toString() => opIndex == null
      ? 'CompileError($error)'
      : 'CompileError(#$opIndex $opName: $error)';
}
