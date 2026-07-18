import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Settings key recording that the one-time first-run collection seed has been
/// handled. Its mere *presence* (see [SettingsRepository.contains]) is the
/// idempotency latch — set once, on the first launch that runs [SeedService],
/// and never consulted for its value. This guarantees the seed is applied at
/// most once: a user who later deletes the seed dance is never re-seeded.
const String kInitialSeedCompletedKey = 'seed.initialCollection.completed';

/// Asset key (declared in `app/pubspec.yaml`) for the bundled first-run seed
/// archive — the canonical [CompendiumArchive] JSON for "The Baby Rose" by
/// David Kaynor, generated offline from its authoritative ContraDB source (see
/// `packages/compendium_core/test/seed/`).
const String kBabyRoseSeedAsset = 'assets/seed/baby_rose.json';

/// Loads a bundled asset's text by key. Defaults to [rootBundle]; overridden in
/// tests so no real asset bundle is required.
typedef SeedAssetLoader = Future<String> Function(String assetKey);

/// Seeds the collection with exactly one dance on a fresh, empty first launch,
/// so the app never opens to a completely empty collection.
///
/// Contract (ROADMAP: "first launch is never empty"):
/// - **Fresh install** (seed latch unset *and* collection empty): the bundled
///   seed archive is loaded and its single dance is inserted, then the latch is
///   set.
/// - **Already populated first run** (latch unset but collection non-empty —
///   e.g. an upgrade from a build without seeding): nothing is injected into
///   the user's data; the latch is set so this check never runs again.
/// - **Every later launch** (latch set): a no-op — including after the user
///   deletes the seed dance, so it is never re-added.
///
/// The seed asset is trusted, checked-in, offline-generated data; it is loaded
/// through the core's existing [decodeArchive] path (relying on its validation
/// and partial-failure tolerance) and applied with [ArchiveRestorer] in
/// [RestoreMode.merge] (an id-keyed upsert, safe on an empty database). Nothing
/// is fetched from the network. `compendium_core` stays Flutter-free (ADR-001):
/// the asset I/O and orchestration live here in the app; decode/restore are
/// core.
class SeedService {
  SeedService(this._repos, {SeedAssetLoader? assetLoader})
    : _assetLoader = assetLoader ?? rootBundle.loadString;

  final CompendiumRepositories _repos;
  final SeedAssetLoader _assetLoader;

  /// Applies the first-run seed if and only if this is a fresh, empty first
  /// launch. Idempotent across launches via [kInitialSeedCompletedKey].
  ///
  /// Throws if the (checked-in, build-verified) seed asset is missing or
  /// undecodable, so a build defect is loud; the latch is intentionally *not*
  /// set on that failure path, so a later launch with a fixed asset can retry.
  /// The caller ([main]) treats a seed failure as non-fatal to startup.
  Future<void> ensureSeeded() async {
    if (await _repos.settings.contains(kInitialSeedCompletedKey)) return;

    // `includeDeleted: true` so a soft-deleted-but-present collection (an
    // upgrade edge) still counts as "not empty" and is left untouched. A
    // lightweight existence probe (`LIMIT 1`) — we only need emptiness, not
    // the full id/title listing.
    if (await _repos.dances.hasAny(includeDeleted: true)) {
      await _repos.settings.set(kInitialSeedCompletedKey, true);
      return;
    }

    await _seedFromAsset();
    await _repos.settings.set(kInitialSeedCompletedKey, true);
  }

  Future<void> _seedFromAsset() async {
    final json = await _assetLoader(kBabyRoseSeedAsset);
    final read = decodeArchive(json);
    if (read.archive.dances.isEmpty) {
      throw StateError(
        'Seed asset "$kBabyRoseSeedAsset" contained no importable dance '
        '(errors: ${read.errors}).',
      );
    }
    final result = await ArchiveRestorer(
      _repos,
    ).restore(read.archive, mode: RestoreMode.merge);
    if (result.hasErrors) {
      throw StateError(
        'Failed to restore the first-run seed dance: ${result.errors}.',
      );
    }
  }
}
