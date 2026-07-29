import 'package:meta/meta.dart';

/// Severity of a [ValidationIssue].
///
/// Per the domain-model design, structural invariants are hard errors
/// (thrown at construction), while musical/choreographic concerns such as
/// phrase overflow are warnings — real dances bend phrasing.
enum ValidationSeverity { error, warning }

/// A single finding produced by a validation pass.
@immutable
class ValidationIssue {
  const ValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.data = const <String, Object?>{},
  });

  final ValidationSeverity severity;

  /// Stable machine-readable identifier (e.g. `phrase_overflow`), suitable
  /// for filtering and for UI copy lookup.
  final String code;

  /// Human-readable description in canonical (dialect-free) vocabulary.
  ///
  /// This is an **internal/diagnostic** string (used by [toString], logging,
  /// and tests) — it is deliberately English and is **not** rendered directly
  /// in a localized UI. The presentation layer maps [code] (+ [data]) to a
  /// localized string instead (`app/lib/src/data/validation_issue_labels.dart`).
  final String message;

  /// Structured interpolation values for the presentation-layer localizer,
  /// keyed by name (e.g. `{'actual': 68, 'expected': 64}` for a phrase
  /// mismatch). Carries only the diagnostic's own typed values — never raw
  /// lower-layer text. Not part of identity ([==]/[hashCode]) since it is
  /// derived from the same construction that produces [message].
  final Map<String, Object?> data;

  @override
  bool operator ==(Object other) =>
      other is ValidationIssue &&
      other.severity == severity &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(severity, code, message);

  @override
  String toString() => '[$severity] $code: $message';
}
