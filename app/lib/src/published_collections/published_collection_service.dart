import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../app_metadata.dart';
import '../update/semver.dart';
import '../update/update_signature.dart';
import 'published_collection_config.dart';
import 'published_collection_manifest.dart';

typedef PublishedCollectionBytesFetcher =
    Future<List<int>> Function(Uri uri, int maxBytes);

/// A user-visible failure while loading or verifying a published collection.
class PublishedCollectionFetchException implements Exception {
  const PublishedCollectionFetchException(this.code);

  final PublishedCollectionFetchFailure code;

  @override
  String toString() => 'PublishedCollectionFetchException: $code';
}

enum PublishedCollectionFetchFailure {
  unavailable,
  redirectRefused,
  responseTooLarge,
  malformed,
  unsupported,
  missingSignature,
  invalidSignature,
  digestMismatch,
  byteCountMismatch,
}

/// Fetches and authenticates the signed collection catalog, then verifies an
/// archive against the digest and exact byte count signed in that catalog.
class PublishedCollectionService {
  PublishedCollectionService({
    PublishedCollectionBytesFetcher? bytesFetcher,
    ManifestSignatureVerifier? signatureVerifier,
  }) : _bytesFetcher = bytesFetcher ?? _fetchBytes,
       _signatureVerifier = signatureVerifier ?? _verifyPublishedSignature;

  final PublishedCollectionBytesFetcher _bytesFetcher;
  final ManifestSignatureVerifier _signatureVerifier;

  Future<PublishedCollectionManifest> fetchCatalog() async {
    final manifestBytes = await _fetch(
      Uri.parse(kPublishedCollectionManifestUrl),
      kMaxPublishedCollectionManifestBytes,
    );
    final signatureBytes = await _fetch(
      Uri.parse(kPublishedCollectionSignatureUrl),
      kMaxPublishedCollectionSignatureBytes,
    );
    final signature = String.fromCharCodes(signatureBytes);
    if (signature.trim().isEmpty) {
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.missingSignature,
      );
    }
    final verified = await _signatureVerifier(manifestBytes, signature);
    if (!verified) {
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.invalidSignature,
      );
    }
    try {
      return PublishedCollectionManifest.parse(
        utf8.decode(manifestBytes),
        readerVersion: SemVer.tryParse(kAppVersion)!,
      );
    } on PublishedCollectionFormatException {
      // diagnostics: silent — map the typed parser failure to a safe UI error.
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.malformed,
      );
    } on FormatException {
      // diagnostics: silent — map malformed UTF-8 to a safe UI error.
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.malformed,
      );
    }
  }

  Future<List<int>> fetchArchive(PublishedCollectionEntry entry) async {
    if (!entry.isSupported) {
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.unsupported,
      );
    }
    final bytes = await _fetch(entry.archiveUrl, entry.archiveBytes);
    if (bytes.length != entry.archiveBytes) {
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.byteCountMismatch,
      );
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != entry.sha256) {
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.digestMismatch,
      );
    }
    try {
      utf8.decode(bytes);
    } on FormatException {
      // diagnostics: silent — map malformed UTF-8 to a safe UI error.
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.malformed,
      );
    }
    return bytes;
  }

  Future<List<int>> _fetch(Uri uri, int maxBytes) async {
    try {
      return await _bytesFetcher(
        uri,
        maxBytes,
      ).timeout(kPublishedCollectionFetchTimeout);
    } on PublishedCollectionFetchException {
      // diagnostics: silent — preserve the typed transport failure.
      rethrow;
    } on TimeoutException {
      // diagnostics: silent — map timeout to a safe UI error.
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.unavailable,
      );
    } on Object {
      // diagnostics: silent — map transport failures to a safe UI error.
      throw const PublishedCollectionFetchException(
        PublishedCollectionFetchFailure.unavailable,
      );
    }
  }
}

Future<bool> _verifyPublishedSignature(
  List<int> manifestBytes,
  String? signatureText,
) => verifyManifestSignatureWith(
  manifestBytes,
  signatureText,
  publicKeyBase64: kPublishedCollectionPublicKey,
);

Future<List<int>> _fetchBytes(Uri uri, int maxBytes) async {
  if (!isAllowedPublishedCollectionUri(uri)) {
    throw const PublishedCollectionFetchException(
      PublishedCollectionFetchFailure.redirectRefused,
    );
  }
  final client = http.Client();
  try {
    var current = uri;
    for (var redirects = 0; ; redirects++) {
      final request = http.Request('GET', current)..followRedirects = false;
      final response = await client.send(request);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const PublishedCollectionFetchException(
              PublishedCollectionFetchFailure.responseTooLarge,
            );
          }
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty) {
          throw const PublishedCollectionFetchException(
            PublishedCollectionFetchFailure.unavailable,
          );
        }
        return bytes;
      }
      if (!_isRedirect(response.statusCode)) {
        await response.stream.drain<void>();
        throw const PublishedCollectionFetchException(
          PublishedCollectionFetchFailure.unavailable,
        );
      }
      await response.stream.drain<void>();
      if (redirects >= kMaxPublishedCollectionRedirects) {
        throw const PublishedCollectionFetchException(
          PublishedCollectionFetchFailure.redirectRefused,
        );
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        throw const PublishedCollectionFetchException(
          PublishedCollectionFetchFailure.redirectRefused,
        );
      }
      final next = current.resolve(location);
      if (!isAllowedPublishedCollectionUri(next)) {
        throw const PublishedCollectionFetchException(
          PublishedCollectionFetchFailure.redirectRefused,
        );
      }
      current = next;
    }
  } finally {
    client.close();
  }
}

bool _isRedirect(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;
