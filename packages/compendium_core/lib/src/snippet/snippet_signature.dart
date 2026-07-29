import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';

/// Version of the [figureSnippetSignature] normalization scheme (#411).
///
/// The signature is a stable key under which a user's global walkthrough-snippet
/// library stores per-figure step descriptions. Any change to how signatures are
/// derived changes those keys, so it is an explicit, versioned migration — bump
/// this and migrate stored keys, never change the rules silently.
const int kFigureSnippetSignatureVersion = 1;

/// Derives the **normalized figure signature** used as the global
/// walkthrough-snippet library key for [figure] (#411, owner-locked design).
///
/// Rule (deterministic, stable across dances):
/// `signature = moveId '(' sorted "name=value" of DISPLAY-SALIENT params ')'`.
///
/// - **Display-salient params** = exactly the params referenced by the move's
///   [MoveDef.renderTemplate] placeholders (e.g. `{who} {move} {hand} {turn}`),
///   MINUS the implicit `{move}` name and MINUS `beats` (duration, not reading).
///   This set is read from the taxonomy, so it is deterministic and versionable.
/// - **Values** come from [Taxonomy.effectiveParams] (taxonomy defaults folded
///   in), so an explicit `hand: right` and a defaulted `hand` collapse to the
///   same signature — the snippet reuses across dances regardless of whether the
///   param was stated. Values are normalized to canonical lowercase tokens with
///   a fixed numeric/bool form; keys are sorted; `null` values are omitted.
/// - So "allemande left ½" and "allemande right 1½" get DISTINCT signatures,
///   and `who` is part of the signature (a `{who}` placeholder), so
///   "swing your partner" and "swing your neighbor" are distinct — intended.
///
/// Returns `null` for a **custom / parse-gap** figure ([Figure.isCustom]) or an
/// **unknown move** (not in the taxonomy): those have no stable canonical
/// identity, so they never participate in the shared library (they may still
/// carry a per-dance [Figure.walkthroughOverride]).
String? figureSnippetSignature(Figure figure, Taxonomy taxonomy) {
  if (figure.isCustom) return null;
  final def = taxonomy.resolve(figure.move);
  if (def == null) return null;

  final salient = _salientParamNames(def.renderTemplate)
      .where((name) => name != 'beats' && def.params.containsKey(name))
      .toList()
    ..sort();
  if (salient.isEmpty) return def.id;

  final effective = taxonomy.effectiveParams(figure);
  final parts = <String>[];
  for (final name in salient) {
    final value = effective[name];
    if (value == null) continue;
    parts.add('$name=${_normalizeValue(value)}');
  }
  return parts.isEmpty ? def.id : '${def.id}(${parts.join(',')})';
}

final RegExp _placeholder = RegExp(r'\{(\w+)\}');

/// Extracts `{name}` placeholder names from a render template, excluding the
/// implicit `{move}` (the display name, not a stored param). Order-independent;
/// callers sort.
Iterable<String> _salientParamNames(String renderTemplate) => _placeholder
    .allMatches(renderTemplate)
    .map((m) => m.group(1)!)
    .where((name) => name != 'move');

/// Canonicalizes a param value to a stable string token for the signature:
/// integral numbers render without a trailing `.0`, other numbers trim trailing
/// zeros, bools render `true`/`false`, and strings (already canonical taxonomy
/// tokens) are lowercased.
String _normalizeValue(Object value) {
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is num) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    var s = value.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
  return value.toString().toLowerCase();
}
