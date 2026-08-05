import 'param_types.dart';

/// The dancer-set tokens offerable for a figure param, given whether the
/// enclosing dance is a mixer and what the param currently holds.
///
/// When [mixer] is `true`, every token in [domain] is offered: a mixer dance
/// can meaningfully use any partner-series token.
///
/// When [mixer] is `false`, the five mixer partner-series tokens
/// ([ParamVocab.mixerPartnerSeries]) are suppressed — **unless** [currentValue]
/// is one of them, in which case that token is retained at its original
/// position.
///
/// ## Why retention matters
///
/// `FigureParamEditor._dropdown` reconciles the displayed selection with the
/// model: if `value` is absent from `selectable`, it falls back to the spec
/// default and then **writes that fallback into the draft** via
/// `addPostFrameCallback`. Without retention, merely opening the editor on a
/// non-mixer dance whose figure stores `nextPartners` would silently rewrite
/// the value to (e.g.) `role1s` — destroying transcribed choreography with no
/// undo and no indication (issue #732, also the class of defects #724/#726
/// exist to prevent). Retaining `currentValue` keeps `selectable.contains(value)`
/// true, so `current == value`, the write-back condition `current != value`
/// never holds, and the stored value is preserved.
///
/// The token is still shown and selectable on the figure that already holds it;
/// it simply is not offered on other figures in the same non-mixer dance.
List<String> offerableDancerSets(
  List<String> domain, {
  required bool mixer,
  Object? currentValue,
}) {
  if (mixer) return domain;
  return [
    for (final token in domain)
      if (!ParamVocab.mixerPartnerSeries.contains(token) ||
          token == currentValue)
        token,
  ];
}
