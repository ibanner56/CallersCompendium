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
/// start. An order the couples end in, in brackets after the name ("(231)"),
/// is kept in it too ("Proper (231)", or "(231)" with no start word), since
/// the stored formation does not otherwise say who ends where (the
/// maintainer's ruling on pre-release audit finding C-08). It is null when the
/// name states neither.
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
  final order = _coupleOrder.firstMatch(lower)?.group(0);
  return (
    shape: shape,
    qualifier: order == null
        ? qualifier
        : [?qualifier, order.replaceAll(_space, '')].join(' '),
  );
}

/// The order the couples end in, as a set name writes it: two to four digits
/// in brackets, `(231)` or `(2341)`.
final RegExp _coupleOrder = RegExp(r'\(\s*\d{2,4}\s*\)');

final RegExp _space = RegExp(r'\s+');

/// [qualifier] and [detail] joined into one formation detail (`; `, as the
/// Caller's Companion import joins details), or null when both are absent.
String? joinFormationDetail(String? qualifier, String? detail) {
  final parts = [?qualifier, ?detail].where((p) => p.isNotEmpty);
  return parts.isEmpty ? null : parts.join('; ');
}
