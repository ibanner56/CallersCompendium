/// Static trust and transport policy for the signed published-collection feed.
///
/// The keys are deliberately distinct from the update-manifest keys: a
/// compromise of collection publishing must never become a way to sign app
/// installers.
const String kPublishedCollectionManifestUrl =
    'https://analect.callerscompendium.com/collections/manifest.json';
const String kPublishedCollectionSignatureUrl =
    'https://analect.callerscompendium.com/collections/manifest.json.sig';

/// The Ed25519 public keys (standard base64) the collection catalog's detached
/// signature is accepted under. A catalog verifies if **any** key in this set
/// verifies it; an empty list trusts nothing.
///
/// The list is a **set**, not a history: at most a *current* key (the one
/// Compendium Analect signs with today, via its `ANALECT_SIGNING_KEY_B64`
/// secret) and a *next* key (generated offline and pinned ahead of time so
/// installs already trust it when Analect switches to it). Pinning only one key
/// cannot rotate without stranding one cohort of installs: a release that pins
/// only the replacement rejects the live catalog until Analect switches, and
/// after the switch every older install rejects it. Removing a key does not
/// revoke it for installs that already shipped with it. The full procedure is
/// `docs/dev/releasing.md` → "Published-collection key rotation" (#2161).
const List<String> kPublishedCollectionPublicKeys = [
  // Current: the key Compendium Analect signs the catalog with today.
  'wT1TeOTv4opmfWstQXB8mFnLQEPgfQTKqR95ipYqaHk=',
  // Next: pinned by the maintainer ahead of the next rotation (not yet set).
];

/// Signed collections have no product/entity cap. This is only a high
/// defense-in-depth ceiling for an unbounded hostile response. It is intentionally
/// far above the current 600–800 dance publication target.
const int kMaxPublishedCollectionArchiveBytes = 1024 * 1024 * 1024;
const int kMaxPublishedCollectionManifestBytes = 256 * 1024;
const int kMaxPublishedCollectionSignatureBytes = 4 * 1024;
const int kMaxPublishedCollectionRedirects = 5;
const Duration kPublishedCollectionFetchTimeout = Duration(seconds: 60);

const Set<String> kPublishedCollectionAllowedHosts = {
  'analect.callerscompendium.com',
};

bool isAllowedPublishedCollectionUri(Uri uri) {
  if (!uri.isScheme('https') ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  return kPublishedCollectionAllowedHosts.contains(uri.host.toLowerCase());
}
