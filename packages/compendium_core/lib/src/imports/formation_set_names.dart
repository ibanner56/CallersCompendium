import '../model/formation.dart';

/// A formation name that states a set shape (triplet, triple minor,
/// quadruplet), with the start word it carries, if any.
typedef FormationSetName = ({FormationShape shape, String? qualifier});

/// Reads the set shape out of an already-lowercased formation name such as
/// "Proper Triplet (231)" or "Improper Quadruplet (2341)", or returns null
/// when [lower] names no such shape.
///
/// Importers must try this **before** their `proper` / `improper` /
/// `indecent` checks: those words also qualify set shapes, so testing them
/// first reads "Proper Triplet" as a duple proper. Within this function
/// `triplet` is tested before `triple minor`, and a bare "triple" is left to
/// the caller.
///
/// The start word ("Proper", "Improper", "Indecent") is returned as
/// [FormationSetName.qualifier] for the caller to keep as the formation's
/// detail, the way the Caller's Companion `.USR` path keeps a triple minor's
/// start. It is null when the name states none.
FormationSetName? classifyFormationSetName(String lower) {
  final FormationShape shape;
  if (lower.contains('quadruplet')) {
    shape = FormationShape.quadruplet;
  } else if (lower.contains('triplet')) {
    shape = FormationShape.triplet;
  } else if (lower.contains('triple minor')) {
    // Only the phrase: a bare "triple" (e.g. a progression remark) keeps its
    // place in each mapper, after the start words.
    shape = FormationShape.tripleMinor;
  } else {
    return null;
  }
  final String? qualifier;
  if (lower.contains('indecent')) {
    qualifier = 'Indecent';
  } else if (lower.contains('improper')) {
    qualifier = 'Improper';
  } else if (lower.contains('proper')) {
    qualifier = 'Proper';
  } else {
    qualifier = null;
  }
  return (shape: shape, qualifier: qualifier);
}

/// [qualifier] and [detail] joined into one formation detail (`; `, as the
/// Caller's Companion import joins details), or null when both are absent.
String? joinFormationDetail(String? qualifier, String? detail) {
  final parts = [?qualifier, ?detail].where((p) => p.isNotEmpty);
  return parts.isEmpty ? null : parts.join('; ');
}
