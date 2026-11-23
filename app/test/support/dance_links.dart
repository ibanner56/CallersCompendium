import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/export/dance_code.dart';
import 'package:compendium_core/compendium_core.dart';

/// Dance links for tests of the receiving side (#2335): one that opens, and
/// one of each kind the issue says must be refused.

/// The title of the dance [goodDanceLink] carries.
const String danceLinkTitle = 'Code Contra';

/// A one-dance archive, as a shared dance file carries it.
String danceLinkBundleJson({int? schemaVersion, bool withDance = true}) {
  final json =
      jsonDecode(
            encodeArchive(
              CompendiumArchive(
                exportedAt: DateTime.utc(2026, 11, 22),
                dances: [
                  if (withDance)
                    Dance(
                      id: 'code-d1',
                      title: danceLinkTitle,
                      createdAt: DateTime.utc(2026, 1, 1),
                      updatedAt: DateTime.utc(2026, 1, 1),
                    ),
                ],
              ),
            ),
          )
          as Map<String, Object?>;
  if (schemaVersion != null) json['schemaVersion'] = schemaVersion;
  return jsonEncode(json);
}

List<int> _deflate(List<int> bytes) =>
    ZLibCodec(raw: true, level: 9).encode(bytes);

String _linkFor(List<int> deflated) =>
    '$danceLinkPrefix${base64Url.encode(deflated).replaceAll('=', '')}';

/// A link that opens, carrying [danceLinkTitle].
String goodDanceLink() => encodeDanceLink(danceLinkBundleJson());

/// A link whose archive is from a schema newer than this build's.
String newerSchemaDanceLink() => encodeDanceLink(
  danceLinkBundleJson(schemaVersion: archiveSchemaVersion + 1),
);

/// A well-formed link to an archive with no dances or programs.
String emptyArchiveDanceLink() =>
    encodeDanceLink(danceLinkBundleJson(withDance: false));

/// One character past [kMaxDanceLinkLength].
String overLengthDanceLink() =>
    '$danceLinkPrefix${'A' * (kMaxDanceLinkLength + 1 - danceLinkPrefix.length)}';

/// A good link, but of a format version this build does not read.
String unknownVersionDanceLink() =>
    goodDanceLink().replaceFirst(danceLinkPrefix, 'ccdance://2/');

/// A good link's compressed payload cut in half, as a code read only in part
/// would give.
String truncatedDanceLink() {
  final deflated = _deflate(utf8.encode(danceLinkBundleJson()));
  return _linkFor(deflated.sublist(0, deflated.length ~/ 2));
}

/// A short link that inflates past [kMaxDanceInflatedBytes].
String inflateBombDanceLink() {
  final json = '{"a":"${'x' * (kMaxDanceInflatedBytes + 1)}"}';
  final link = _linkFor(_deflate(utf8.encode(json)));
  assert(link.length < kMaxDanceLinkLength);
  return link;
}
