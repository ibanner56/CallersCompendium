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
    // Build the inverse-pair lookup table from aliases that declare one.
    // Each alias with an inversePairId pins exactly ONE param on a two-valued
    // axis; the lookup maps (moveId, paramKey, oppositeValue) → counterpartId
    // in BOTH directions.
    final pairs = <String, _InversePairEntry>{};
    for (final alias in aliases) {
      final inversePairId = alias.inversePairId;
      if (inversePairId == null) continue;
      // Validate that the inversePairId resolves to a known move or alias —
      // a typo here would let resolvedMoveId rewrite persisted figures to a
      // non-existent id during the one-time migration, silently corrupting
      // user data with the done marker preventing a retry.
      if (!this.moves.containsKey(inversePairId) &&
          !this.aliases.containsKey(inversePairId)) {
        throw ArgumentError(
          'alias "${alias.id}" declares inversePairId "$inversePairId" '
          'which is neither a known move nor a known alias',
        );
      }
      if (alias.pinnedParams.length != 1) {
        throw ArgumentError(
          'alias "${alias.id}" declares an inversePairId but pins '
          '${alias.pinnedParams.length} params (expected exactly 1)',
        );
      }
      final paramKey = alias.pinnedParams.keys.single;
      final pinnedValue = alias.pinnedParams[paramKey];
      // Alias side: when the pinned param takes the OPPOSITE value, re-route
      // to the inverse pair id.
      pairs[alias.id] = _InversePairEntry(
        paramKey: paramKey,
        pinnedValue: pinnedValue,
        inversePairId: inversePairId,
      );
      // Target side: when the target move takes the ALIAS's pinned value,
      // re-route to the alias. A duplicate target would half-register the
      // second pair and silently break the "both directions" guarantee.
      if (pairs.containsKey(alias.targetMove)) {
        throw ArgumentError(
          'alias "${alias.id}" declares inversePairId targeting '
          '"${alias.targetMove}", but that target already has an '
          'inverse-pair entry from another alias',
        );
      }
      pairs[alias.targetMove] = _InversePairEntry(
        paramKey: paramKey,
        pinnedValue: pinnedValue,
        inversePairId: alias.id,
      );
    }
    _inversePairs = Map.unmodifiable(pairs);
  }

  final int version;
  final DanceForm form;
  final Map<String, MoveDef> moves;
  final Map<String, MoveAlias> aliases;

  /// Lookup table for inverse-pair re-routing, built from aliases with
  /// [MoveAlias.inversePairId]. Key: move id (alias OR target). Value: the
  /// param key, the alias's pinned value, and the counterpart id.
  late final Map<String, _InversePairEntry> _inversePairs;

  /// Neutral `beats` fallback surfaced by [effectiveParams] for an unknown
  /// move that carries no explicit count. Mirrors the custom/free-text move's
  /// default (a typical contra figure length): it keeps duration/phrase math
  /// sane without inventing a per-move value we can't know (issue #358).
  static const int _unknownMoveBeatsFallback = 8;

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
      // Unknown move: return a best-effort copy of the figure's own params
      // (never mutate [figure.params]). Preserve an authored `beats`; only
      // when it is absent fall back to a neutral default so downstream
      // duration/phrase math doesn't read 0 beats for a move we can't
      // recognize. We can't know the real per-move count, so a generic
      // default is the correct non-destructive choice.
      final effective = Map<String, Object?>.of(figure.params);
      effective.putIfAbsent('beats', () => _unknownMoveBeatsFallback);
      return effective;
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

  /// Returns the move id [figure] should carry given its effective params.
  ///
  /// For inverse-pair aliases (`box_the_gnat` ⇄ `swat_the_flea` on `hand`,
  /// `do_si_do` ⇄ `see_saw` on `shoulder`), the move id routes to the half
  /// whose pin matches the effective param value. Returns [figure.move]
  /// unchanged when no re-routing applies.
  ///
  /// Call when an authoring surface needs the effective move (the editor may
  /// route live; persistence also re-checks at write time) rather than on every
  /// read — `effectiveParams` is on the hot path and is deliberately untouched.
  /// Canonical keys are unaffected because both halves of a pair resolve to
  /// the same [MoveDef] id.
  String resolvedMoveId(Figure figure) {
    final pair = _inversePairs[figure.move];
    if (pair == null) return figure.move;
    final effective = effectiveParams(figure);
    final value = effective[pair.paramKey];
    // For the ALIAS side (e.g. swat_the_flea pins hand=left):
    //   If the effective value differs from the pin → re-route to inversePairId.
    // For the TARGET side (e.g. box_the_gnat, no pin):
    //   If the effective value EQUALS the alias's pin → re-route to the alias.
    final alias = aliases[figure.move];
    if (alias != null) {
      // Figure is on the alias side: re-route if the effective value differs
      // from the pinned value.
      return value != pair.pinnedValue ? pair.inversePairId : figure.move;
    }
    // Figure is on the target (MoveDef) side: re-route if the effective value
    // equals the alias's pinned value.
    return value == pair.pinnedValue ? pair.inversePairId : figure.move;
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

/// Internal descriptor for one half of an inverse-pair alias relationship.
@immutable
class _InversePairEntry {
  const _InversePairEntry({
    required this.paramKey,
    required this.pinnedValue,
    required this.inversePairId,
  });

  /// The param axis the pair pivots on (e.g. `'hand'`, `'shoulder'`).
  final String paramKey;

  /// The value the alias pins (e.g. `'left'`). For the target (MoveDef) side
  /// this is the value that triggers re-routing TO the alias; for the alias
  /// side this is the value that keeps the alias and a departure triggers
  /// re-routing to [inversePairId].
  final Object? pinnedValue;

  /// The counterpart id to re-route to when the effective param disagrees.
  final String inversePairId;
}
