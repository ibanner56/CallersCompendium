import 'package:compendium_app/src/editor/program_editor_draft_codec.dart';
import 'package:compendium_core/compendium_core.dart';

/// The stored new-program draft keys: each new-program editor writes under its
/// own key, and a draft from before that under the legacy shared one, so a
/// test that does not hold the editor reads them by prefix.
Future<List<String>> newProgramDraftKeys(CompendiumRepositories repos) async =>
    [
      for (final key in await repos.settings.keysWithPrefix(
        programEditorDraftKey(kLegacyNewProgramDraftId),
      ))
        if (isNewProgramEditorDraftKey(key)) key,
    ];

/// Whether any new-program draft is stored.
Future<bool> hasNewProgramDraft(CompendiumRepositories repos) async =>
    (await newProgramDraftKeys(repos)).isNotEmpty;

/// The one stored new-program draft's value, or `null` when there is none.
/// Fails when there are several, which a test that expects one would hide.
Future<Object?> newProgramDraft(CompendiumRepositories repos) async {
  final keys = await newProgramDraftKeys(repos);
  if (keys.isEmpty) return null;
  if (keys.length > 1) {
    throw StateError('expected one new-program draft, found $keys');
  }
  return repos.settings.get(keys.single);
}
