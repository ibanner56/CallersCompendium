/// ContraDB dancer-set vocabulary, shared by the JSON adapter
/// (`contradb_adapter.dart`) and the rendered-HTML figure dialect
/// (`contradb_figure_dialect.dart`) so the two import paths structure the same
/// phrases to the same canonical tokens. Not exported from
/// `compendium_core.dart`.
library;

/// ContraDB dancer-set vocabulary (JSON API spellings, lowercase) → our
/// canonical tokens. Roles migrate from ContraDB gentlespoons/ladles to our
/// role1/role2 (`docs/research/contradb.md`).
const Map<String, String> contradbDancerVocab = {
  'everyone': 'everyone',
  'all': 'everyone',
  'gentlespoons': 'role1s',
  'gentlespoon': 'role1s',
  'gents': 'role1s',
  'larks': 'role1s',
  'ladles': 'role2s',
  'ladle': 'role2s',
  'ravens': 'role2s',
  'robins': 'role2s',
  'role1s': 'role1s',
  'role2s': 'role2s',
  'ones': 'ones',
  'twos': 'twos',
  'partners': 'partners',
  'partner': 'partners',
  'neighbors': 'neighbors',
  'neighbor': 'neighbors',
  'same roles': 'sameRoles',
  'first corners': 'firstCorners',
  'second corners': 'secondCorners',
  'shadows': 'shadows',
  'second shadows': 'secondShadows',
  'previous neighbors': 'prevNeighbors',
  'next neighbors': 'nextNeighbors',
  'third neighbors': 'thirdNeighbors',
  'fourth neighbors': 'fourthNeighbors',
  'centers': 'centers',
  'first gentlespoon': 'onesRole1',
  'first ladle': 'onesRole2',
  'second gentlespoon': 'twosRole1',
  'second ladle': 'twosRole2',
};

/// The [contradbDancerVocab] keys ContraDB's HTML template renders for a
/// dancer set that the HTML dialect would otherwise not read: the corner,
/// same-role, centre and single-dancer (`first gentlespoon`, …) subjects.
/// The other keys are API-only synonyms (`all`, `gents`, `larks`, …) or are
/// already spelled in the dialect's own ordinal-aware list.
const List<String> contradbRenderedOnlyDancerKeys = [
  'same roles',
  'first corners',
  'second corners',
  'centers',
  'first gentlespoon',
  'first ladle',
  'second gentlespoon',
  'second ladle',
];

/// The HTML dialect's subject entries for [contradbRenderedOnlyDancerKeys]:
/// each key run through [scrub] (the text the recognizers see has already been
/// through `scrubFigureText`, so `first gentlespoon` arrives as `first role1`)
/// paired with its canonical token, longest phrase (most words) first.
List<MapEntry<String, String>> contradbRenderedSubjectEntries(
  String Function(String) scrub,
) {
  final entries = <MapEntry<String, String>>[
    for (final key in contradbRenderedOnlyDancerKeys)
      MapEntry(scrub(key), contradbDancerVocab[key]!),
  ];
  // Stable: Dart's List.sort is not, so rank by (word count, original index).
  final order = <MapEntry<String, String>, int>{
    for (var i = 0; i < entries.length; i++) entries[i]: i,
  };
  entries.sort((a, b) {
    final byWords = b.key.split(' ').length.compareTo(a.key.split(' ').length);
    return byWords != 0 ? byWords : order[a]!.compareTo(order[b]!);
  });
  return entries;
}
