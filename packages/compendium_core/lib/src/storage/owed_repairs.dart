/// The one-time repairs still owed, given the completion markers a build
/// expects and the live ones a database holds.
///
/// [expected] is `CompendiumRepositories.oneTimeRepairMarkers`: each marker
/// key mapped to the `value_json` it must hold, or null when presence alone is
/// enough. [live] maps each of those keys the database holds as a live row
/// (`deleted_at IS NULL`) to its `value_json`. A tombstoned marker must be
/// left out of [live], as every sweep's own gate ignores it.
///
/// Returns the owed keys in [expected]'s order; empty when nothing is owed.
///
/// Pure, so the app's migration preflight can answer the question from a raw
/// `package:sqlite3` read before drift opens the file.
List<String> owedOneTimeRepairs({
  required Map<String, String?> expected,
  required Map<String, String> live,
}) => [
  for (final MapEntry(:key, value: want) in expected.entries)
    if (!live.containsKey(key) || (want != null && live[key] != want)) key,
];
