import 'package:compendium_core/compendium_core.dart';

import '../utils/safe_name.dart';
import 'share_sanitization.dart';

/// Builds a canonical, privacy-safe archive containing one dance and only its
/// referenced metadata.
String buildDanceShareBundle(
  Dance dance, {
  required Choreographer? Function(String id) choreographerFor,
  required Tag? Function(String id) tagFor,
  required PublishedSource? Function(String id) publishedSourceFor,
  required CustomFieldDef? Function(String id) customFieldFor,
  DateTime? now,
}) {
  final choreographers = <Choreographer>[];
  final seenAuthors = <String>{};
  for (final id in dance.authorIds) {
    if (!seenAuthors.add(id)) continue;
    final choreographer = choreographerFor(id);
    if (choreographer == null) {
      throw StateError('dance references missing choreographer "$id"');
    }
    choreographers.add(sanitizeChoreographerForShare(choreographer));
  }

  final tags = <Tag>[];
  final seenTags = <String>{};
  for (final id in dance.tagIds) {
    if (!seenTags.add(id)) continue;
    final tag = tagFor(id);
    if (tag == null) throw StateError('dance references missing tag "$id"');
    tags.add(tag);
  }

  final sources = <PublishedSource>[];
  final seenSources = <String>{};
  for (final citation in dance.sourceCitations) {
    if (!seenSources.add(citation.sourceId)) continue;
    final source = publishedSourceFor(citation.sourceId);
    if (source == null) {
      throw StateError(
        'dance references missing published source "${citation.sourceId}"',
      );
    }
    sources.add(source);
  }

  final customFields = <CustomFieldDef>[];
  final seenFields = <String>{};
  for (final value in dance.customFields) {
    if (!seenFields.add(value.fieldId)) continue;
    final field = customFieldFor(value.fieldId);
    if (field == null) {
      throw StateError(
        'dance references missing custom field "${value.fieldId}"',
      );
    }
    customFields.add(field);
  }

  return encodeArchive(
    CompendiumArchive(
      exportedAt: (now ?? DateTime.now()).toUtc(),
      dances: [dance],
      choreographers: choreographers,
      publishedSources: sources,
      customFields: customFields,
      tags: tags,
    ),
    mode: ArchiveSerializationMode.share,
  );
}

const String danceShareBundleExtension = 'ccshare';
const String danceShareJsonExtension = 'json';

/// Returns a safe filename for a dance archive.
String danceShareBundleFileName(
  String title, {
  String extension = danceShareBundleExtension,
}) {
  final sanitized = replaceUnsafeNameChars(title.trim());
  final base = sanitized.contains(RegExp(r'[A-Za-z0-9]')) ? sanitized : 'dance';
  return '$base.$extension';
}
