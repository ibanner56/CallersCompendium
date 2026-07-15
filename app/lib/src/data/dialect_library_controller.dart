import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../screens/settings_screen.dart' show kActiveDialectKey;

/// Persistence key for the JSON list of user-created custom [Dialect]s.
const String kCustomDialectsKey = 'custom_dialects';

/// Persistence key for the name of the active dialect (a shipped preset name or
/// a custom dialect name). Absent means the app default is active.
const String kActiveDialectRefKey = 'active_dialect_ref';

/// Owns the user's locally-saved custom dialects and which named dialect
/// (preset or custom) is currently active (`docs/design/ux.md` §6 — the
/// dialect manager).
///
/// Custom dialects are identified by their unique [Dialect.name]; the active
/// dialect is stored as that name and resolved against custom dialects first,
/// then the shipped [Dialect.presets], via [Dialect.resolveByName]. Backed by
/// the free-form [SettingsRepository]; every mutation persists immediately and
/// notifies listeners so the app re-renders live.
///
/// Mirrors the `CustomThemesController` pattern.
class DialectLibraryController extends ChangeNotifier {
  DialectLibraryController(this._settings);

  final SettingsRepository _settings;

  final List<Dialect> _customDialects = [];
  String? _activeName;

  /// Read-only view of the user's custom dialects, in insertion order.
  List<Dialect> get customDialects => List.unmodifiable(_customDialects);

  /// The shipped presets followed by the user's custom dialects — the full set
  /// of dialects the user can pick from.
  List<Dialect> get all =>
      List.unmodifiable([...Dialect.presets, ..._customDialects]);

  /// The active dialect's name, or `null` when nothing has been chosen.
  String? get activeName => _activeName;

  /// The resolved active [Dialect], falling back to the app default
  /// ([Dialect.larksRobins]) when the active name is unset or dangling.
  Dialect get active =>
      Dialect.resolveByName(_activeName, candidates: _customDialects) ??
      Dialect.larksRobins;

  /// Whether [name] belongs to a shipped, read-only preset.
  bool isPreset(String name) => Dialect.forName(name) != null;

  /// The custom dialect with [name], or `null` if there isn't one.
  Dialect? customByName(String name) {
    for (final d in _customDialects) {
      if (d.name == name) return d;
    }
    return null;
  }

  /// Loads persisted custom dialects + active name from storage. Safe to call
  /// once at startup; malformed entries are skipped rather than throwing.
  ///
  /// Back-compat: earlier builds stored only the active dialect as a full JSON
  /// blob under [kActiveDialectKey] (no library). When no library key exists
  /// yet, that blob is migrated in — as a custom dialect if it isn't a shipped
  /// preset — and made active, so a user's single custom dialect survives.
  Future<void> load() async {
    _customDialects.clear();
    final hasLibrary = await _settings.contains(kCustomDialectsKey);
    final raw = await _settings.get(kCustomDialectsKey);
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          final d = Dialect.fromJson(entry.cast<String, Object?>());
          if (_customByNameIndex(d.name) < 0) _customDialects.add(d);
        }
      }
    }

    final activeRaw = await _settings.get(kActiveDialectRefKey);
    _activeName = activeRaw is String ? activeRaw : null;

    if (!hasLibrary) {
      await _migrateLegacyActive();
    }
    notifyListeners();
  }

  /// Migrates a pre-library install: the active dialect was stored as a full
  /// JSON blob under [kActiveDialectKey]. If it names/matches a preset, just
  /// activate that; otherwise adopt it as a custom dialect and activate it.
  Future<void> _migrateLegacyActive() async {
    final legacy = await _settings.get(kActiveDialectKey);
    Dialect? dialect;
    if (legacy is Map) {
      dialect = Dialect.fromJson(legacy.cast<String, Object?>());
    } else if (legacy is String) {
      dialect = Dialect.forName(legacy);
    }
    if (dialect == null) return;

    final preset = Dialect.forName(dialect.name);
    final matchesPreset = preset != null && preset == dialect;
    if (!matchesPreset && Dialect.forName(dialect.name) == null) {
      _customDialects.add(dialect);
      await _persistDialects();
    }
    _activeName = dialect.name;
    await _persistActive();
  }

  /// Adds a new custom dialect, or replaces the one with the same name.
  Future<void> upsert(Dialect dialect) async {
    final index = _customByNameIndex(dialect.name);
    if (index >= 0) {
      _customDialects[index] = dialect;
    } else {
      _customDialects.add(dialect);
    }
    await _persistDialects();
    notifyListeners();
  }

  /// Creates a custom dialect seeded from [from] (defaults to a blank canonical
  /// dialect) under a unique name derived from [name], saves it without
  /// activating it, and returns it. Used by "new" / "duplicate from preset".
  Future<Dialect> duplicate({required String name, Dialect? from}) async {
    final seed = from ?? Dialect(name: name);
    final copy = seed.copyWith(name: _uniqueName(name));
    await upsert(copy);
    return copy;
  }

  /// Renames the custom dialect [oldName] to [newName] (uniquified). Presets
  /// cannot be renamed. Keeps the active pointer in sync. Returns the new name.
  Future<String?> rename(String oldName, String newName) async {
    final index = _customByNameIndex(oldName);
    if (index < 0) return null;
    final unique = oldName == newName ? newName : _uniqueName(newName);
    _customDialects[index] = _customDialects[index].copyWith(name: unique);
    await _persistDialects();
    if (_activeName == oldName) {
      _activeName = unique;
      await _persistActive();
    }
    notifyListeners();
    return unique;
  }

  /// Deletes the custom dialect [name]. If it was active, the active pointer
  /// falls back to the app default so the app is never stranded.
  Future<void> delete(String name) async {
    final index = _customByNameIndex(name);
    if (index < 0) return;
    _customDialects.removeAt(index);
    var changedActive = false;
    if (_activeName == name) {
      _activeName = Dialect.larksRobins.name;
      changedActive = true;
    }
    await _persistDialects();
    if (changedActive) await _persistActive();
    notifyListeners();
  }

  /// Sets the active dialect by [name] (a preset or custom name). Unknown names
  /// are ignored. Persists both the active-name ref and — for back-compat with
  /// readers of [kActiveDialectKey] — the resolved dialect's JSON blob.
  Future<void> setActive(String name) async {
    final resolved = Dialect.resolveByName(name, candidates: _customDialects);
    if (resolved == null || name == _activeName) return;
    _activeName = name;
    await _persistActive();
    notifyListeners();
  }

  int _customByNameIndex(String name) =>
      _customDialects.indexWhere((d) => d.name == name);

  Future<void> _persistDialects() => _settings.set(
    kCustomDialectsKey,
    _customDialects.map((d) => d.toJson()).toList(),
  );

  Future<void> _persistActive() async {
    await _settings.set(kActiveDialectRefKey, _activeName);
    // Keep the legacy full-blob key in sync so any reader that still resolves
    // the active dialect from [kActiveDialectKey] stays correct.
    await _settings.set(kActiveDialectKey, active.toJson());
  }

  /// Ensures a name doesn't collide with an existing preset or custom dialect,
  /// appending " 2", " 3", … until unique.
  String _uniqueName(String base) {
    final existing = {
      ...Dialect.presets.map((d) => d.name),
      ..._customDialects.map((d) => d.name),
    };
    if (!existing.contains(base)) return base;
    var n = 2;
    while (existing.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }
}
