import 'package:compendium_core/compendium_core.dart';

import 'display_defaults.dart';

/// The tag ids to add to dances imported on their own (issue #1476).
///
/// Reads [kDefaultImportTagIdsKey] and keeps only ids of tags that are live
/// right now, in the stored order. A deleted tag is dropped rather than failing
/// the import: a tombstoned id would attach a join row `DanceRepository` hides
/// (and that reappears if the tag is revived), and an erased id would fail the
/// dance's write on the foreign key.
///
/// Call it immediately before the commit, never earlier, so the window in which
/// a tag can be deleted underneath it stays as small as possible. Never throws:
/// an unreadable setting or tag list means "no default tags", because an import
/// must not fail over an optional convenience.
Future<List<String>> resolveDefaultImportTagIds(
  CompendiumRepositories repos,
) async {
  try {
    final configured = tryDecodeDefaultImportTagIds(
      await repos.settings.get(kDefaultImportTagIdsKey),
    );
    if (configured == null || configured.isEmpty) return const [];
    final live = {for (final tag in await repos.tags.listAll()) tag.id};
    return [
      for (final id in configured)
        if (live.contains(id)) id,
    ];
  } catch (_) {
    // diagnostics: silent — see the dartdoc; the import proceeds untagged.
    return const [];
  }
}
