/// Which **Keep** items start on when a caller swaps a dance from Perform's
/// **Adjust program** sheet (#2346), as Settings ▸ Program ▸ Perform mode ▸
/// **Swap a dance** edits them and the `perform_swap_defaults` settings key
/// stores them.
///
/// The stored shape is kept in this one module so it can change in one place:
///
/// ```json
/// {"version": 1,
///  "keep": {"formation": true, "levelOrEasier": true,
///           "sameType": true, "notInProgram": true}}
/// ```
///
/// Reading is lenient: a missing key, a missing item or a value that is not a
/// `bool` reads as on, the shipped default. Writing is conservative: an item
/// this build does not know inside `keep`, and an unknown top-level key, are
/// written back exactly as they were read, so one device on an older build
/// never drops what a newer one stored. A value with a `version` this build
/// does not know reads as the defaults and is flagged
/// ([PerformSwapDefaultsRead.isNewer]) so the settings editor shows it
/// read-only rather than overwriting it.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The `version` this build writes and fully reads.
const int performSwapDefaultsVersion = 1;

/// The seeded **Keep** items whose starting state the defaults choose, by
/// their stored names. Figures to keep always start off and are not here.
enum PerformSwapKeepItem { formation, levelOrEasier, sameType, notInProgram }

const _deepEquality = DeepCollectionEquality();

/// The defaults, with what this build does not understand kept aside so it
/// can be written back unchanged.
@immutable
class PerformSwapDefaults {
  const PerformSwapDefaults({
    this.formation = true,
    this.levelOrEasier = true,
    this.sameType = true,
    this.notInProgram = true,
    this.preserved = const {},
    this.preservedKeep = const {},
  });

  /// The shipped defaults: every item on.
  static const PerformSwapDefaults defaults = PerformSwapDefaults();

  /// **Same formation**.
  final bool formation;

  /// **This level or easier**.
  final bool levelOrEasier;

  /// **Same type** (offered only in a program that mixes types).
  final bool sameType;

  /// **Not already in tonight's program**.
  final bool notInProgram;

  /// Top-level keys other than `version` and `keep`, kept to be written back.
  final Map<String, Object?> preserved;

  /// Items inside `keep` this build does not know, kept to be written back.
  final Map<String, Object?> preservedKeep;

  bool isOn(PerformSwapKeepItem item) => switch (item) {
    PerformSwapKeepItem.formation => formation,
    PerformSwapKeepItem.levelOrEasier => levelOrEasier,
    PerformSwapKeepItem.sameType => sameType,
    PerformSwapKeepItem.notInProgram => notInProgram,
  };

  /// These defaults with [item] set to [on].
  PerformSwapDefaults withItem(PerformSwapKeepItem item, bool on) =>
      PerformSwapDefaults(
        formation: item == PerformSwapKeepItem.formation ? on : formation,
        levelOrEasier: item == PerformSwapKeepItem.levelOrEasier
            ? on
            : levelOrEasier,
        sameType: item == PerformSwapKeepItem.sameType ? on : sameType,
        notInProgram: item == PerformSwapKeepItem.notInProgram
            ? on
            : notInProgram,
        preserved: preserved,
        preservedKeep: preservedKeep,
      );

  /// The stored JSON object.
  Map<String, Object?> toJson() => {
    ...preserved,
    'version': performSwapDefaultsVersion,
    'keep': {
      ...preservedKeep,
      for (final item in PerformSwapKeepItem.values) item.name: isOn(item),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is PerformSwapDefaults &&
      _deepEquality.equals(other.toJson(), toJson());

  @override
  int get hashCode => _deepEquality.hash(toJson());
}

/// A stored value as read: the defaults to use, and whether the value came
/// from a newer build ([isNewer]), in which case [defaults] are the shipped
/// ones and the stored value must not be overwritten by an edit.
typedef PerformSwapDefaultsRead = ({
  PerformSwapDefaults defaults,
  bool isNewer,
});

/// Reads a stored `perform_swap_defaults` value: a JSON object, or a string
/// holding one. Never throws. Absent, malformed or wrong-typed reads as the
/// shipped defaults (writable); a `version` above [performSwapDefaultsVersion]
/// reads as the shipped defaults with `isNewer`.
PerformSwapDefaultsRead readPerformSwapDefaults(Object? stored) {
  const fallback = (defaults: PerformSwapDefaults.defaults, isNewer: false);
  final map = _asMap(stored);
  if (map == null) return fallback;
  final version = map['version'];
  if (version is int && version > performSwapDefaultsVersion) {
    return (defaults: PerformSwapDefaults.defaults, isNewer: true);
  }
  if (version != performSwapDefaultsVersion) return fallback;
  final preserved = <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries)
      if (key is String && key != 'version' && key != 'keep') key: value,
  };
  final rawKeep = map['keep'];
  final keep = rawKeep is Map
      ? {
          for (final MapEntry(:key, :value) in rawKeep.entries)
            if (key is String) key: value,
        }
      : const <String, Object?>{};
  final known = {for (final item in PerformSwapKeepItem.values) item.name};
  bool on(PerformSwapKeepItem item) =>
      keep[item.name] is bool ? keep[item.name]! as bool : true;
  return (
    defaults: PerformSwapDefaults(
      formation: on(PerformSwapKeepItem.formation),
      levelOrEasier: on(PerformSwapKeepItem.levelOrEasier),
      sameType: on(PerformSwapKeepItem.sameType),
      notInProgram: on(PerformSwapKeepItem.notInProgram),
      preserved: Map.unmodifiable(preserved),
      preservedKeep: Map.unmodifiable({
        for (final MapEntry(:key, :value) in keep.entries)
          if (!known.contains(key)) key: value,
      }),
    ),
    isNewer: false,
  );
}

/// Whether [stored] is a value a backup may restore: a JSON object with an
/// integer `version` of at least 1 whose `keep` (when present) is an object.
/// A version-1 value must also hold a `bool` for each item this build reads;
/// a newer one is accepted as it stands, since this build keeps it without
/// reading it.
bool isValidStoredPerformSwapDefaults(Object? stored) {
  final map = _asMap(stored);
  if (map == null) return false;
  final version = map['version'];
  if (version is! int || version < 1) return false;
  final keep = map['keep'];
  if (keep != null && keep is! Map) return false;
  if (version > performSwapDefaultsVersion || keep is! Map) return true;
  return PerformSwapKeepItem.values.every((item) {
    final value = keep[item.name];
    return value == null || value is bool;
  });
}

Map<Object?, Object?>? _asMap(Object? stored) {
  Object? value = stored;
  if (value is String) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  return value is Map ? value : null;
}
