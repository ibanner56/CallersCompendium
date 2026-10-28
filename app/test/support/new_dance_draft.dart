import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_core/compendium_core.dart';

/// The stored new-dance draft keys: each new-dance editor writes under its
/// own key (AUTH-10), and a draft from before that under the legacy shared
/// one, so a test that does not hold the editor reads them by prefix.
Future<List<String>> newDanceDraftKeys(CompendiumRepositories repos) async => [
  for (final key in await repos.settings.keysWithPrefix(
    danceEditorDraftKey(kLegacyNewDanceDraftId),
  ))
    if (isNewDanceEditorDraftKey(key)) key,
];

/// Whether any new-dance draft is stored.
Future<bool> hasNewDanceDraft(CompendiumRepositories repos) async =>
    (await newDanceDraftKeys(repos)).isNotEmpty;

/// The one stored new-dance draft's value, or `null` when there is none.
/// Fails when there are several, which a test that expects one would hide.
Future<Object?> newDanceDraft(CompendiumRepositories repos) async {
  final keys = await newDanceDraftKeys(repos);
  if (keys.isEmpty) return null;
  if (keys.length > 1) {
    throw StateError('expected one new-dance draft, found $keys');
  }
  return repos.settings.get(keys.single);
}
