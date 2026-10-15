import '../model/figure.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Seeds `chain`'s implicit hand from its role (`who`), mirroring ContraDB's
/// own `chainChange` (`figure.js:256-263`), so a chain created or edited in the
/// editor stores the same explicit hand as one parsed from import text
/// (v28, #976). A no-op for any other move or an unrecognized `who`.
void seedChainHand(String moveId, Map<String, Object?> params) {
  if (moveId != 'chain') return;
  final who = params['who'];
  if (who is! String) return;
  final hand = chainHandForWho(who);
  if (hand != null) params['hand'] = hand;
}

/// Applies a change of the non-`beats` param [key] to [value] on a figure of
/// [move] whose params are [params], with every rule that change carries, and
/// returns the move the figure ends up as.
///
/// [params] is changed in place. The returned move differs from [move] only
/// when the change reroutes an inverse pair (`see_saw` ⇄ `do_si_do` on
/// `shoulder`, `swat_the_flea` ⇄ `box_the_gnat` on `hand`).
///
/// One function for the dance editor and for a user compound's expansion
/// (#709), so a parameter a compound fills in gets exactly the follow-on
/// changes the editor would have made. The rules, in order:
///
/// - **hey `length`** (#576): a full or half length drops a stale
///   `meetTarget`, which only applies to the partial lengths.
/// - **promenade `where`** (v30, #989): `in`, `out`, `up` or `down` leave no
///   rotation, so `direction` is reset to the `unspecified` sentinel. It is
///   written rather than removed, because the spec default is concrete.
/// - **a `balance` flag** shifts `beats` by +4 (on) or -4 (off) from the
///   current count, clamped to 0..64, including a manual override, and returns
///   before the rules below.
/// - **chain `who`** (#976) rewrites the role-implied `hand`.
/// - **inverse pairs** are rerouted by their pinned value.
/// - **beats** are reconciled with the move's canonical default (#262): a
///   change that shifts the default snaps `beats` to it, and one that leaves
///   it put never disturbs an existing count. A missing or non-int `beats` is
///   always seeded. A manual override ([beatsTouched]) is kept, unless
///   [aggressiveBeats] (#689) is on and the default actually moved.
String applyParamChange(
  Taxonomy taxonomy, {
  required String move,
  required Map<String, Object?> params,
  required String key,
  required Object? value,
  required bool beatsTouched,
  required bool aggressiveBeats,
}) {
  if (move == 'hey' && key == 'length') {
    final partial = value == 'lessThanHalf' || value == 'betweenHalfAndFull';
    if (!partial) params.remove('meetTarget');
  }
  if (move == 'promenade' && key == 'where') {
    const rotationless = {'in', 'out', 'up', 'down'};
    if (rotationless.contains(value)) {
      params['direction'] = ParamVocab.unspecified;
    }
  }
  final oldDefault = canonicalBeatsFor(taxonomy, move, params);
  if (key == 'balance' && value is bool && _isBalanceFlag(taxonomy, move)) {
    final wasOn = _effectiveBalance(taxonomy, move, params);
    params[key] = value;
    if (wasOn != value) {
      final current = params['beats'];
      final base = current is int ? current : oldDefault;
      if (base != null) {
        params['beats'] = (base + (value ? 4 : -4)).clamp(0, 64);
      }
    }
    return move;
  }
  params[key] = value;
  if (move == 'chain' && key == 'who') seedChainHand('chain', params);
  final resolved = taxonomy.resolvedMoveId(Figure(move: move, params: params));
  final newDefault = canonicalBeatsFor(taxonomy, resolved, params);
  if (newDefault == null) return resolved;
  if (beatsTouched) {
    if (aggressiveBeats && newDefault != oldDefault) {
      params['beats'] = newDefault;
    }
    return resolved;
  }
  final currentBeats = params['beats'];
  if (currentBeats is! int || newDefault != oldDefault) {
    params['beats'] = newDefault;
  }
  return resolved;
}

/// The canonical `beats` default of [move] for [params], ignoring any explicit
/// `beats` so the taxonomy re-derives it from the driver params. Null when
/// the move is unknown, has no `beats` param, or resolves to a non-int.
int? canonicalBeatsFor(
  Taxonomy taxonomy,
  String move,
  Map<String, Object?> params,
) {
  final def = taxonomy.resolve(move);
  if (def == null || !def.params.containsKey('beats')) return null;
  final probeParams = Map<String, Object?>.of(params)..remove('beats');
  final beats = taxonomy.effectiveParams(
    Figure(move: move, params: probeParams),
  )['beats'];
  return beats is int ? beats : null;
}

/// Whether [move] declares `balance` as a boolean flag, as opposed to swing's
/// `prefix` choice, which has its own 8→16 timing.
bool _isBalanceFlag(Taxonomy taxonomy, String move) =>
    taxonomy.resolve(move)?.params['balance']?.kind == ParamKind.flag;

/// The effective `balance` flag for [params], falling back to the spec
/// default.
bool _effectiveBalance(
  Taxonomy taxonomy,
  String move,
  Map<String, Object?> params,
) =>
    taxonomy.effectiveParams(
      Figure(move: move, params: Map<String, Object?>.of(params)),
    )['balance'] ==
    true;
