import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'custom_theme.dart';

/// Persistence key for the JSON list of saved [CustomTheme]s.
const String kCustomThemesKey = 'custom_themes';

/// Persistence key for the id of the active custom theme (absent/`null` means a
/// built-in [AppThemeSelection] is active instead).
const String kActiveCustomThemeKey = 'active_custom_theme';

/// Owns the user's locally-saved custom themes and which one (if any) is active
/// (`docs/design/ux-modernization.md` §4B).
///
/// Precedence is **custom-wins**: a custom theme is active iff [activeId] is
/// non-null. Selecting a built-in theme clears [activeId]; selecting/saving a
/// custom theme sets it. Backed by the free-form [SettingsRepository]; all
/// mutations persist immediately and notify listeners so the app re-themes
/// live.
class CustomThemesController extends ChangeNotifier {
  CustomThemesController(this._settings);

  final SettingsRepository _settings;

  final List<CustomTheme> _themes = [];
  String? _activeId;

  /// Read-only view of saved themes, in insertion order.
  List<CustomTheme> get themes => List.unmodifiable(_themes);

  /// The active custom theme's id, or `null` when a built-in theme is active.
  String? get activeId => _activeId;

  /// Whether a custom theme currently wins over the built-in selection.
  bool get hasActive => _activeId != null && active != null;

  /// The active custom theme, or `null` if none is active (or it was deleted).
  CustomTheme? get active {
    if (_activeId == null) return null;
    for (final t in _themes) {
      if (t.id == _activeId) return t;
    }
    return null;
  }

  CustomTheme? byId(String id) {
    for (final t in _themes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Loads persisted themes + active id from storage. Safe to call once at
  /// startup; malformed entries are skipped rather than throwing.
  Future<void> load() async {
    _themes.clear();
    final raw = await _settings.get(kCustomThemesKey);
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          try {
            _themes.add(CustomTheme.fromJson(entry.cast<String, Object?>()));
          } catch (_) {
            // diagnostics: silent — skips a corrupt entry rather than losing every theme
          }
        }
      }
    }
    final activeRaw = await _settings.get(kActiveCustomThemeKey);
    _activeId = activeRaw is String && byId(activeRaw) != null
        ? activeRaw
        : null;
    notifyListeners();
  }

  /// Adds a new custom theme (or replaces one with the same id), persists, and
  /// notifies. Does not change which theme is active.
  Future<void> upsert(CustomTheme theme) async {
    final index = _themes.indexWhere((t) => t.id == theme.id);
    if (index >= 0) {
      _themes[index] = theme;
    } else {
      _themes.add(theme);
    }
    await _persistThemes();
    notifyListeners();
  }

  /// Creates a new custom theme from a name, brightness, and role map (copied
  /// so later edits don't alias the caller's map) under a fresh id and a
  /// unique name, saves it, and returns it — without activating it. Used by
  /// the "duplicate" action and to seed a brand-new theme from a scheme.
  Future<CustomTheme> duplicate({
    required String name,
    required Brightness brightness,
    required Map<String, int> roles,
  }) async {
    final copy = CustomTheme(
      id: _newId(),
      name: _uniqueName(name),
      brightness: brightness,
      roles: Map<String, int>.from(roles),
    );
    await upsert(copy);
    return copy;
  }

  /// Deletes the theme with [id]; if it was active, reverts to the built-in
  /// selection by clearing [activeId].
  Future<void> delete(String id) async {
    _themes.removeWhere((t) => t.id == id);
    var changedActive = false;
    if (_activeId == id) {
      _activeId = null;
      changedActive = true;
    }
    await _persistThemes();
    if (changedActive) await _persistActive();
    notifyListeners();
  }

  /// Sets the active custom theme (or clears it with `null` to hand control
  /// back to the built-in [AppThemeSelection]).
  Future<void> setActive(String? id) async {
    final resolved = id != null && byId(id) != null ? id : null;
    if (resolved == _activeId) return;
    _activeId = resolved;
    await _persistActive();
    notifyListeners();
  }

  Future<void> _persistThemes() =>
      _settings.set(kCustomThemesKey, _themes.map((t) => t.toJson()).toList());

  Future<void> _persistActive() =>
      _settings.set(kActiveCustomThemeKey, _activeId);

  String _newId() => 'custom-${DateTime.now().microsecondsSinceEpoch}';

  /// Ensures a copied name doesn't collide with an existing one, appending
  /// " 2", " 3", … until it's unique (callers pass names like "X (copy)").
  String _uniqueName(String base) {
    final existing = _themes.map((t) => t.name).toSet();
    if (!existing.contains(base)) return base;
    var n = 2;
    while (existing.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }
}
