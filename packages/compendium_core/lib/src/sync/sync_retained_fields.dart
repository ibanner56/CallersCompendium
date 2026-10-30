import '../privacy/data_classification.dart';
import '../privacy/settings_registry.dart';
import '../serialization/figure_codec.dart';
import 'sync_record_kind.dart';
import 'wire_mapping.dart';

/// The element key that identifies an item of each list container a body may
/// carry, so a field this build does not sync can be put back into the same
/// item when the record is shared again (spec §6.7). A list with no entry here
/// is positional: a field this build cannot place is refused instead.
const Map<String, String> syncRetainedListIdKeys = {
  'links': 'id',
  'slots': 'id',
  'customFields': 'fieldId',
  'sourceCitations': 'sourceId',
};

/// An inbound record body split by what this build does with each part.
///
/// [known] is what it syncs: every path classified `shareable` for the kind,
/// in its original shape. [retained] is everything else, kept verbatim so it
/// can be put back by [mergeRetainedFields] — null when there is nothing to
/// keep. [refusedPath] names the first part this build can neither apply nor
/// keep in place, and when it is set the whole record is refused as a newer
/// version's (spec §6.9).
///
/// A setting whose key this build does not sync is [wholeRecord]: there is
/// nothing to apply, and the body is kept as it came.
class SyncBodyPartition {
  const SyncBodyPartition._({
    required this.known,
    this.retained,
    this.refusedPath,
    this.wholeRecord = false,
  });

  final Map<String, Object?> known;
  final Map<String, Object?>? retained;
  final String? refusedPath;
  final bool wholeRecord;

  bool get isRefused => refusedPath != null;
}

/// Splits [body] of a [kind] record into the parts this build syncs and the
/// parts it keeps for a newer version of the app (spec §6.7).
///
/// A part is kept when it sits where it can be put back exactly: a key at the
/// top level, a key inside a nested object (`formation`, `provenance`), or a
/// key inside an item of a list keyed by [syncRetainedListIdKeys]. Anything a
/// newer build added inside a dance's figures or tunes is refused instead:
/// those lists are positional, and figure decoding would silently drop it.
///
/// A path this build knows but keeps private is kept like an unknown one — a
/// newer build may have reclassified it to travel — and is never written into
/// this device's own private field. Decided by Isaac (maintainer) in planning
/// this change; see spec §6.7.
SyncBodyPartition partitionInboundRecordBody(
  SyncRecordKind kind,
  Map<String, Object?> body, {
  String? settingsKey,
}) {
  if (kind == SyncRecordKind.setting) {
    return _partitionSetting(body, settingsKey);
  }
  final walk = _Walk(kind);
  final (known, retained) = walk.object(const [], body);
  return SyncBodyPartition._(
    known: known,
    retained: walk.refusedPath == null && retained.isNotEmpty ? retained : null,
    refusedPath: walk.refusedPath,
  );
}

/// Puts [retained] back into [body], the inverse of
/// [partitionInboundRecordBody]: for a body this build rebuilt from the same
/// known part, the result is the body the peer sent.
///
/// A part whose place no longer exists — a nested object now null, a list item
/// this device has since removed — is dropped with it.
Map<String, Object?> mergeRetainedFields(
  Map<String, Object?> body,
  Map<String, Object?> retained,
) => _merge(const [], body, retained);

/// [retained] without the parts this build now syncs, or null when nothing is
/// left — the same tree when nothing changed.
///
/// A kept part is only ever something the build that stored it did not sync.
/// After an upgrade that starts syncing it, the value belongs in the record
/// itself, and a kept copy put back over the projection would overwrite what
/// this device now holds — including the user's own edit — on every share.
/// `CompendiumSyncStorage.promoteRetainedSyncFields` moves such values into
/// the record at open; every body builder also prunes with this, so a part
/// that was not moved can never win over the record (spec §6.7).
Map<String, Object?>? pruneSyncedRetainedFields(
  SyncRecordKind kind,
  Map<String, Object?> retained, {
  String? settingsKey,
}) {
  final pruned = _prune(kind, const [], retained, settingsKey);
  return pruned.isEmpty ? null : pruned;
}

Map<String, Object?> _prune(
  SyncRecordKind kind,
  List<String> segments,
  Map<String, Object?> retained,
  String? settingsKey,
) {
  final out = <String, Object?>{};
  for (final entry in retained.entries) {
    final part = entry.value;
    if (part is! Map) continue;
    final childSegments = [...segments, entry.key];
    final path = childSegments.join('.');
    if (part.containsKey('v')) {
      final synced =
          isShareableWirePath(kind, path, settingsKey: settingsKey) ||
          hasShareableWireDescendant(kind, path);
      if (!synced) out[entry.key] = part;
    } else if (part['m'] case final Map<Object?, Object?> nested) {
      final kept = _prune(
        kind,
        childSegments,
        nested.cast<String, Object?>(),
        settingsKey,
      );
      if (kept.isNotEmpty) out[entry.key] = {'m': kept};
    } else if (part['l'] case final Map<Object?, Object?> byId) {
      final keptById = <String, Object?>{};
      for (final item in byId.entries) {
        final itemParts = item.value;
        if (itemParts is! Map) continue;
        final kept = _prune(
          kind,
          childSegments,
          itemParts.cast<String, Object?>(),
          settingsKey,
        );
        if (kept.isNotEmpty) keptById[item.key as String] = kept;
      }
      if (keptById.isNotEmpty) out[entry.key] = {'l': keptById};
    }
  }
  return out;
}

/// Whether a setting [key] this build does not sync may still be kept whole
/// for a newer version. The two transport keys never may: they are never
/// adopted from a peer, and republishing one would repoint the store. A
/// withdrawn setting never gets here: it is dropped before apply instead
/// (`syncWithdrawnSettingKeys`).
bool isRetainableSettingKey(String key) {
  final egress = classifySettingsKey(key)?.egress;
  return egress != EgressClass.shareable &&
      egress != EgressClass.storeAddress &&
      egress != EgressClass.protocolIdentifier;
}

SyncBodyPartition _partitionSetting(
  Map<String, Object?> body,
  String? settingsKey,
) {
  final key = settingsKey;
  if (key == null) {
    return SyncBodyPartition._(known: body, refusedPath: 'value');
  }
  if (classifySettingsKey(key)?.egress == EgressClass.shareable) {
    final walk = _Walk(SyncRecordKind.setting, settingsKey: key);
    final (known, retained) = walk.object(const [], body);
    return SyncBodyPartition._(
      known: known,
      retained: walk.refusedPath == null && retained.isNotEmpty
          ? retained
          : null,
      refusedPath: walk.refusedPath,
    );
  }
  if (!isRetainableSettingKey(key)) {
    return SyncBodyPartition._(known: body, refusedPath: 'value');
  }
  return SyncBodyPartition._(known: const {}, wholeRecord: true);
}

class _Walk {
  _Walk(this.kind, {this.settingsKey});

  final SyncRecordKind kind;
  final String? settingsKey;
  String? refusedPath;

  (Map<String, Object?>, Map<String, Object?>) object(
    List<String> segments,
    Map<String, Object?> value,
  ) {
    final known = <String, Object?>{};
    final retained = <String, Object?>{};
    for (final entry in value.entries) {
      if (refusedPath != null) break;
      final key = entry.key;
      final childSegments = [...segments, key];
      final path = childSegments.join('.');
      final shareable = isShareableWirePath(
        kind,
        path,
        settingsKey: settingsKey,
      );
      final container = hasShareableWireDescendant(kind, path);
      if (!shareable && !container) {
        retained[key] = {'v': entry.value};
        continue;
      }
      if (!container) {
        known[key] = entry.value;
        _checkLeaf(path, entry.value);
        continue;
      }
      final child = entry.value;
      if (child is Map) {
        final (childKnown, childRetained) = object(
          childSegments,
          child.cast<String, Object?>(),
        );
        known[key] = childKnown;
        if (childRetained.isNotEmpty) retained[key] = {'m': childRetained};
      } else if (child is List) {
        final (childKnown, byId) = list(childSegments, child);
        known[key] = childKnown;
        if (byId.isNotEmpty) retained[key] = {'l': byId};
      } else {
        known[key] = child;
      }
    }
    return (known, retained);
  }

  (List<Object?>, Map<String, Object?>) list(
    List<String> segments,
    List<Object?> value,
  ) {
    final path = segments.join('.');
    final idKey = syncRetainedListIdKeys[path];
    final known = <Object?>[];
    final byId = <String, Object?>{};
    for (final item in value) {
      if (refusedPath != null) break;
      if (item is! Map) {
        known.add(item);
        continue;
      }
      final (itemKnown, itemRetained) = object(
        segments,
        item.cast<String, Object?>(),
      );
      known.add(itemKnown);
      if (itemRetained.isEmpty) continue;
      final id = idKey == null ? null : item[idKey];
      if (id is! String || byId.containsKey(id)) {
        // Nowhere stable to put it back: refuse rather than lose it.
        refusedPath ??= '$path.${itemRetained.keys.first}';
        break;
      }
      byId[id] = itemRetained;
    }
    return (known, byId);
  }

  void _checkLeaf(String path, Object? value) {
    if (kind != SyncRecordKind.dance) return;
    if (path == 'figures') {
      refusedPath ??= unsupportedFigurePath(value);
    } else if (path == 'tunes' && value is List) {
      if (value.any((tune) => tune is! String)) refusedPath ??= 'tunes';
    }
  }
}

Map<String, Object?> _merge(
  List<String> segments,
  Map<String, Object?> body,
  Map<String, Object?> retained,
) {
  final out = Map<String, Object?>.of(body);
  for (final entry in retained.entries) {
    final key = entry.key;
    final part = entry.value;
    if (part is! Map) continue;
    if (part.containsKey('v')) {
      out[key] = part['v'];
    } else if (part['m'] case final Map<Object?, Object?> nested) {
      final current = out[key];
      if (current is Map) {
        out[key] = _merge(
          [...segments, key],
          current.cast<String, Object?>(),
          nested.cast<String, Object?>(),
        );
      }
    } else if (part['l'] case final Map<Object?, Object?> byId) {
      final current = out[key];
      final path = [...segments, key];
      final idKey = syncRetainedListIdKeys[path.join('.')];
      if (current is List && idKey != null) {
        out[key] = [
          for (final item in current)
            if (item is Map &&
                item[idKey] is String &&
                byId[item[idKey]] is Map)
              _merge(
                path,
                item.cast<String, Object?>(),
                (byId[item[idKey]]! as Map).cast<String, Object?>(),
              )
            else
              item,
        ];
      }
    }
  }
  return out;
}
