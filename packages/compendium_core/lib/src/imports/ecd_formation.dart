import '../model/formation.dart';

/// [formation], a contra shape an English Country Dance was given before the
/// ECD shapes existed, as the ECD shape it names (ADR-006 §12.1 F2, §9.2
/// point 3), or [formation] itself when it is an ECD shape already or has no
/// clear ECD counterpart.
///
/// - Duple proper is a duple minor; duple improper is a duple minor with the
///   improper flag set (proper is the flag's default, §9.2 point 2).
/// - A triplet is a three-couple set and a quadruplet a four-couple set,
///   which ECD stores as three- and four-couple longways (§9.2 point 6).
///
/// Every other shape is kept as it is, its description included: an
/// unclear mapping would change what the source states (R2). The mapping is
/// the implementer's reading of those answers; it is not itself one of them.
Formation ecdFormationFromContra(Formation formation) {
  final mapped = switch (formation.shape) {
    FormationShape.dupleProper => (FormationShape.dupleMinor, false),
    FormationShape.dupleImproper => (FormationShape.dupleMinor, true),
    FormationShape.triplet => (FormationShape.threeCoupleLongways, false),
    FormationShape.quadruplet => (FormationShape.fourCoupleLongways, false),
    _ => null,
  };
  if (mapped == null) return formation;
  return formation.copyWith(
    shape: mapped.$1,
    improper: formation.improper || mapped.$2,
  );
}
