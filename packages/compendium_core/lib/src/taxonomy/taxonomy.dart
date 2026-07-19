import 'package:meta/meta.dart';

import '../model/enums.dart';
import '../model/figure.dart';
import '../validation/validation.dart';
import 'move_def.dart';

/// A versioned, per-form move taxonomy.
///
/// Taxonomy is data shipped with the app; adding moves/params is additive,
/// renames are migrations. Stored figures carry their own `schemaVersion`,
/// so old data always parses (validation may flag it, never reject it).
@immutable
class Taxonomy {
  Taxonomy({
    required this.version,
    required this.form,
    required List<MoveDef> moves,
    List<MoveAlias> aliases = const [],
  }) : moves = Map.unmodifiable({for (final m in moves) m.id: m}),
       aliases = Map.unmodifiable({for (final a in aliases) a.id: a}) {
    for (final alias in aliases) {
      final target = this.moves[alias.targetMove];
      if (target == null) {
        throw ArgumentError(
          'alias "${alias.id}" targets unknown move "${alias.targetMove}"',
        );
      }
      for (final key in alias.pinnedParams.keys) {
        if (!target.params.containsKey(key)) {
          throw ArgumentError(
            'alias "${alias.id}" pins unknown param "$key" of '
            '"${alias.targetMove}"',
          );
        }
      }
    }
  }

  final int version;
  final DanceForm form;
  final Map<String, MoveDef> moves;
  final Map<String, MoveAlias> aliases;

  /// Looks up a move id, resolving aliases to their canonical move.
  MoveDef? resolve(String moveId) {
    final direct = moves[moveId];
    if (direct != null) return direct;
    final alias = aliases[moveId];
    return alias == null ? null : moves[alias.targetMove];
  }

  /// Effective parameter values for [figure]: alias pins, then figure
  /// params, then spec defaults for anything still missing.
  ///
  /// For moves with a [MoveDef.paramBeats] table, `beats` is derived from the
  /// effective value of the driver parameter — unless the figure (or its
  /// alias) pins `beats` explicitly, in which case that pinned value wins. A
  /// driver value absent from the table leaves the flat spec default in place.
  ///
  /// For an **unknown move** (one not in this taxonomy, e.g. a figure authored
  /// in a newer app version or a since-removed move) this returns the figure's
  /// own params as-is instead of throwing — a best-effort result that lets the
  /// renderer, editor, and analysis paths degrade gracefully rather than crash.
  /// The move id and its params are never coerced or discarded here, so the
  /// figure round-trips losslessly and renders/edits normally again once the
  /// move is known (issue #358). Use [validateFigure] to detect the
  /// `unknown_move` condition; this method deliberately never fails.
  Map<String, Object?> effectiveParams(Figure figure) {
    final def = resolve(figure.move);
    if (def == null) {
      return Map<String, Object?>.of(figure.params);
    }
    final alias = aliases[figure.move];
    final effective = {
      for (final entry in def.params.entries)
        entry.key: figure.params.containsKey(entry.key)
            ? figure.params[entry.key]
            : (alias?.pinnedParams.containsKey(entry.key) ?? false)
            ? alias!.pinnedParams[entry.key]
            : entry.value.defaultValue,
    };
    final paramBeats = def.paramBeats;
    if (paramBeats != null &&
        !figure.params.containsKey('beats') &&
        !(alias?.pinnedParams.containsKey('beats') ?? false)) {
      final derived = paramBeats.byValue[effective[paramBeats.param]];
      if (derived != null) effective['beats'] = derived;
    }
    return effective;
  }

  /// Validates a figure against this taxonomy.
  ///
  /// Errors: unknown move, unknown param name, out-of-domain param value.
  /// Warnings: atypical beat count (per the move's `goodBeats`).
  List<ValidationIssue> validateFigure(Figure figure) {
    final issues = <ValidationIssue>[];
    final def = resolve(figure.move);
    if (def == null) {
      return [
        ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'unknown_move',
          message:
              'move "${figure.move}" is not in the '
              '${form.name} taxonomy (v$version)',
        ),
      ];
    }
    for (final entry in figure.params.entries) {
      final spec = def.params[entry.key];
      if (spec == null) {
        issues.add(
          ValidationIssue(
            severity: ValidationSeverity.error,
            code: 'unknown_param',
            message: '"${def.id}" has no parameter "${entry.key}"',
          ),
        );
      } else if (!spec.validate(entry.value)) {
        issues.add(
          ValidationIssue(
            severity: ValidationSeverity.error,
            code: 'invalid_param_value',
            message:
                '"${entry.value}" is not a valid value for '
                '"${def.id}.${entry.key}"',
          ),
        );
      }
    }
    final goodBeats = def.goodBeats;
    final beats = figure.params['beats'];
    if (goodBeats != null &&
        goodBeats.isNotEmpty &&
        beats is int &&
        !goodBeats.contains(beats)) {
      issues.add(
        ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'atypical_beats',
          message:
              '"${def.id}" is typically ${goodBeats.join('/')} beats, '
              'not $beats',
        ),
      );
    }
    return issues;
  }
}
