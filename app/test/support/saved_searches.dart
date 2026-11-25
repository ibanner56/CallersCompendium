import 'package:compendium_core/compendium_core.dart';

/// Stores a readable saved search under each of [ids], named after its id.
/// An event rule or a template's slot rule can only start using a saved
/// search that is stored (#2529), so a test that writes one names a stored
/// search.
Future<void> storeSavedSearches(
  SettingsRepository settings,
  Iterable<String> ids,
) async {
  final searches = SavedSearchRepository(settings);
  for (final id in ids) {
    await searches.save(
      SavedSearch(
        id: id,
        name: id,
        spec: SavedSearchSpec.fromPanelState(
          CollectionPanelState(text: id),
          today: DateTime.utc(2026, 1, 1),
        ).value!,
      ),
    );
  }
}
