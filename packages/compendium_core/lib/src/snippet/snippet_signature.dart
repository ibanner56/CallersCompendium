import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/figure.dart';
import '../taxonomy/param_types.dart';
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

  final salient =
      _salientParamNames(def.renderTemplate)
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

final RegExp _signaturePattern = RegExp(r'^([a-z0-9_]+)(?:\((.*)\))?$');

/// Produces a human-readable label for a snippet [signature] (#411) by
/// reconstructing a representative [Figure] and rendering it via [renderer]
/// under [dialect]. Used by the Settings snippet-library editor to show
/// "neighbors allemande left 1½" instead of the raw `allemande(hand=left,...)`.
///
/// Best-effort and never throws: an unparseable signature, an unknown move, or
/// an out-of-domain value falls back to returning the raw [signature] string, so
/// a library entry is always displayable even if the taxonomy has since changed.
String describeFigureSignature(
  String signature,
  Taxonomy taxonomy,
  FigureRenderer renderer,
  Dialect dialect,
) {
  final match = _signaturePattern.firstMatch(signature);
  if (match == null) return signature;
  final moveId = match.group(1)!;
  final def = taxonomy.resolve(moveId);
  if (def == null) return signature;

  final params = <String, Object?>{};
  final body = match.group(2);
  if (body != null && body.isNotEmpty) {
    for (final part in body.split(',')) {
      final eq = part.indexOf('=');
      if (eq <= 0) return signature;
      final key = part.substring(0, eq);
      final rawValue = part.substring(eq + 1);
      final spec = def.params[key];
      if (spec == null) return signature;
      final coerced = _coerceSignatureValue(spec, rawValue);
      if (coerced == null) return signature;
      params[key] = coerced;
    }
  }
  try {
    return renderer.render(Figure(move: moveId, params: params), dialect);
  } catch (_) {
    return signature;
  }
}

/// Coerces a signature's string token back to a typed param value using the
/// [spec]'s [ParamKind]. Returns `null` when the token can't be represented for
/// that kind (so the caller falls back to the raw signature).
Object? _coerceSignatureValue(ParamSpec spec, String token) {
  switch (spec.kind) {
    case ParamKind.rotation:
      return num.tryParse(token);
    case ParamKind.places:
    case ParamKind.beats:
      return int.tryParse(token);
    case ParamKind.flag:
      if (token == 'true') return true;
      if (token == 'false') return false;
      return null;
    default:
      return token;
  }
}
