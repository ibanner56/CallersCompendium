import 'param_types.dart';

/// The discrete, pickable value vocabulary for a figure parameter, or `null`
/// when the parameter has no closed vocabulary (rotation/beats/text). Used to
/// offer optional param dropdowns on an Advanced "has figure" row.
///
/// `spec.choices`, when present, IS the domain — for every kind that has one.
/// A spec may narrow its kind's fixed vocabulary, or opt into the
/// [ParamVocab.unspecified] sentinel, and this facet must offer exactly what
/// [ParamSpec.validate] accepts and `FigureParamEditor` renders: the three are
/// consumers of one contract and must not disagree about a param's domain
/// (issue #726 / PR #736 taught the other two this same rule; this is the
/// third). Offering the fixed vocabulary instead lets a search row build a
/// filter for a value the param cannot hold — and silently drops a sentinel
/// the user needs to search for. A spec that omits `choices` keeps exactly the
/// kind's fixed vocabulary, i.e. today's behaviour.
List<String>? figureParamChoices(ParamSpec spec) {
  switch (spec.kind) {
    case ParamKind.dancerSet:
    case ParamKind.dancerPair:
      return spec.choices ?? ParamVocab.dancerSets;
    case ParamKind.handedness:
    case ParamKind.shoulder:
      return spec.choices ?? ParamVocab.sides;
    case ParamKind.spinDirection:
      return spec.choices ?? ParamVocab.spins;
    case ParamKind.fraction:
      return spec.choices ?? ParamVocab.fractions;
    case ParamKind.direction:
      return spec.choices ?? ParamVocab.directions;
    case ParamKind.choice:
      return spec.choices;
    case ParamKind.rotation:
    case ParamKind.places:
    case ParamKind.number:
    case ParamKind.beats:
    case ParamKind.text:
    case ParamKind.flag:
    // A list of dancers (ECD's `who`): searching by one is ADR-006's W7.
    case ParamKind.dancerList:
      return null;
  }
}

/// Whether [spec] admits the [ParamVocab.unspecified] sentinel, i.e. whether
/// "the source stated nothing here" is a representable state for this param.
bool paramAdmitsUnspecified(ParamSpec spec) =>
    spec.choices?.contains(ParamVocab.unspecified) ?? false;

/// The values a *user may pick* for a figure parameter: its [domain] minus the
/// [ParamVocab.unspecified] sentinel.
///
/// Deliberately distinct from the domain. The sentinel is a real, valid value —
/// [ParamSpec.validate] accepts it, [figureParamChoices] reports it, and the
/// renderer knows how to emit it — but it is meaningless as something a user
/// *chooses*: it means the SOURCE stated nothing, which is a fact about
/// provenance, not a choreographic value anyone sets on purpose. In search it
/// is worse than meaningless, because it sits next to "Any <param>", reads like
/// a synonym, and filters for the near-inverse set (issue #741).
///
/// So the sentinel is filtered out *here*, at the presentation edge, and never
/// in [figureParamChoices] or [ParamSpec.validate]: those two plus the editor
/// are the three consumers of one domain contract (issue #726 / PR #746) and
/// must not start disagreeing about what a param can hold.
///
/// **Do not collapse this into [figureParamChoices].** The two look like one
/// function split for no reason — the facet and the saved-search resolver call
/// them together and little else calls this one — but folding the filter into the domain function
/// silently reintroduces the exact defect PR #746 fixed: the facet would offer
/// LESS than the declared domain while [ParamSpec.validate] kept accepting what
/// it no longer offered, and the figure editor would lose the value it needs to
/// render "not stated" (see `FigureParamEditor._dropdown`, which reads the full
/// domain and filters separately for exactly that reason). The guard PR #751
/// merged asserts the domain side of that contract, so it would keep passing
/// while the presentation side rotted. One function answers "what may this
/// param hold?"; the other answers "what may a user pick?" — and #741 exists
/// because those had been treated as the same question.
List<String> figureParamSelectableChoices(List<String> domain) => [
  for (final choice in domain)
    if (choice != ParamVocab.unspecified) choice,
];
