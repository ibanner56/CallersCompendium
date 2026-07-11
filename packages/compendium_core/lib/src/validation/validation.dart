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
  });

  final ValidationSeverity severity;

  /// Stable machine-readable identifier (e.g. `phrase_overflow`), suitable
  /// for filtering and for UI copy lookup.
  final String code;

  /// Human-readable description in canonical (dialect-free) vocabulary.
  final String message;

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
