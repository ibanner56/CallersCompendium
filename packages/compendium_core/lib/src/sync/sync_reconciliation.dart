import '../storage/shareable_text.dart';
import 'sync_record_kind.dart';

/// The W7 kinds whose user-visible natural keys can collide across devices.
const Set<SyncRecordKind> syncNaturalKeyKinds = {
  SyncRecordKind.choreographer,
  SyncRecordKind.tag,
  SyncRecordKind.customFieldDef,
  SyncRecordKind.difficultyLevel,
};

/// Returns the normalized natural key represented by an archive-shaped body.
///
/// This deliberately does not include dances or programs: title dedupe and
/// slot ownership belong to W8.
String? syncNaturalKeyForBody(SyncRecordKind kind, Map<String, Object?> body) {
  final raw = switch (kind) {
    SyncRecordKind.choreographer || SyncRecordKind.tag => body['name'],
    SyncRecordKind.customFieldDef => body['key'],
    SyncRecordKind.difficultyLevel => body['label'],
    _ => null,
  };
  return raw is String ? normalizeShareableText(raw).toLowerCase() : null;
}

/// Returns the deterministic custom-field key for a losing definition.
///
/// The eight-hex form is preferred. If occupied, callers must retry with the
/// full UUID; no counter is used, so two devices cannot derive different keys.
String syncCustomFieldSuffix(
  String key,
  String losingId, {
  required bool full,
}) {
  final normalizedId = losingId.toLowerCase().replaceAll('-', '');
  final suffix = full
      ? normalizedId
      : normalizedId.substring(
          0,
          normalizedId.length < 8 ? normalizedId.length : 8,
        );
  return '${normalizeShareableText(key)}_$suffix';
}

Object? _rewriteNestedReference(
  Object? value, {
  required String key,
  required SyncRecordKind kind,
  required String Function(SyncRecordKind, String) resolve,
}) {
  if (value is! Map<Object?, Object?>) return value;
  final copy = _copyMap(value);
  if (copy == null) return value;
  final id = copy[key];
  if (id is String) copy[key] = resolve(kind, id);
  return copy;
}

/// Rewrites all W7-owned references in a dance body using [aliases].
///
/// The returned map is a deep copy. Unknown paths and non-string values are
/// left untouched so malformed records still reach the normal wire validator.
Map<String, Object?> rewriteSyncInboundReferences(
  Map<String, Object?> body,
  Map<SyncRecordKind, Map<String, String>> aliases,
) {
  final copy = _copyMap(body.cast<Object?, Object?>())!;
  String resolve(SyncRecordKind kind, String id) {
    final byId = aliases[kind];
    if (byId == null) return id;
    var current = id;
    final seen = <String>{id};
    while (byId[current] != null) {
      final next = byId[current]!;
      if (!seen.add(next)) break;
      current = next;
    }
    return current;
  }

  void rewriteList(String key, SyncRecordKind kind) {
    final values = copy[key];
    if (values is! List<Object?>) return;
    copy[key] = [
      for (final value in values)
        value is String ? resolve(kind, value) : value,
    ];
  }

  rewriteList('authorIds', SyncRecordKind.choreographer);
  rewriteList('tagIds', SyncRecordKind.tag);
  if (copy['difficultyLevelId'] case final String id) {
    copy['difficultyLevelId'] = resolve(SyncRecordKind.difficultyLevel, id);
  }
  if (copy['customFields'] case final List<Object?> values) {
    copy['customFields'] = [
      for (final value in values)
        _rewriteNestedReference(
          value,
          key: 'fieldId',
          kind: SyncRecordKind.customFieldDef,
          resolve: resolve,
        ),
    ];
  }
  if (copy['sourceCitations'] case final List<Object?> values) {
    copy['sourceCitations'] = [
      for (final value in values)
        _rewriteNestedReference(
          value,
          key: 'sourceId',
          kind: SyncRecordKind.publishedSource,
          resolve: resolve,
        ),
    ];
  }

  return copy;
}

Map<String, Object?>? _copyMap(Map<Object?, Object?> value) {
  final copy = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    copy[entry.key as String] = _copyValue(entry.value);
  }
  return copy;
}

Object? _copyValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    return _copyMap(value) ?? value;
  }
  if (value is List) return [for (final item in value) _copyValue(item)];
  return value;
}
