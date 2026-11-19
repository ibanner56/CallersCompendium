import '../model/enums.dart';
import '../model/figure.dart';
import '../validation/validation.dart';

/// Whether [step], a step of a sequence, states its own timing: a `beats`
/// it stores, rather than one a taxonomy would fill in.
bool stepStatesTiming(Figure step) => step.params['beats'] is int;

/// The issue with the timing of [sequence], a `sequence` container in a dance
/// of [form], or null when there is none (ADR-006 §5.5).
///
/// An ECD sequence carries one span of bars, its own `beats`, and its steps
/// may carry no timing of their own ("A, B and C in bars 1–4"). When every
/// step states its timing, the steps must add up to the span; when only
/// some do, theirs must leave time for the rest. Either breach is a
/// `sequence_span_mismatch` warning, with the span and the steps' total in
/// its data: stored data is flagged, never rejected.
///
/// Contra keeps its own contract, where the editor holds a sequence's total
/// at the sum of its steps (`Figure.sequence`), so this returns null for any
/// form but [DanceForm.ecd], and for any figure that is not a sequence.
ValidationIssue? ecdSequenceSpanIssue(Figure sequence, DanceForm form) {
  if (form != DanceForm.ecd || !sequence.isSequence) return null;
  final steps = sequence.subFigures;
  if (steps.isEmpty) return null;
  final timed = steps.where(stepStatesTiming).toList();
  if (timed.isEmpty) return null;
  final total = timed.fold<int>(0, (sum, step) => sum + step.beats);
  final span = sequence.beats;
  final allTimed = timed.length == steps.length;
  if (allTimed ? total == span : total < span) return null;
  return ValidationIssue(
    severity: ValidationSeverity.warning,
    code: 'sequence_span_mismatch',
    message: allTimed
        ? 'the steps of a sequence total $total beats; its span is $span'
        : 'the timed steps of a sequence total $total beats, leaving none '
              'of its $span for the others',
    data: {'actual': total, 'expected': span, 'allTimed': allTimed},
  );
}
