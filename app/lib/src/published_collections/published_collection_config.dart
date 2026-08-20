/// Static trust and transport policy for the signed published-collection feed.
///
/// This key is deliberately distinct from the update-manifest key. Rotating it
/// requires an app release containing the replacement public key before Analect
/// switches signing keys.
const String kPublishedCollectionManifestUrl =
    'https://analect.callerscompendium.com/collections/manifest.json';
const String kPublishedCollectionSignatureUrl =
    'https://analect.callerscompendium.com/collections/manifest.json.sig';
const String kPublishedCollectionPublicKey =
    'wT1TeOTv4opmfWstQXB8mFnLQEPgfQTKqR95ipYqaHk=';

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
