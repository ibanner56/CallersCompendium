import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

/// Persistence key for the user's per-[FormationShape] color overrides
/// (issue #367). Stored as a JSON object mapping a shape's stable enum `.name`
/// to a packed ARGB int ([Color.toARGB32]). Only shapes the user explicitly
/// overrode are stored; every other shape falls back to the family palette.
const String kFormationColorOverridesKey = 'formation_color_overrides';

/// Resolves a persisted settings value into the per-shape color-override map
/// (issue #367).
///
/// Defensive by construction — this map is user/settings input that gets
/// serialized and reloaded, so a corrupt or hostile payload must never crash or
/// render an invisible label:
///
/// - A `null`, non-`Map`, or otherwise unexpected top-level value yields an
///   empty (mutable) map — the "no overrides" state, so every label falls back
///   to its family default.
/// - Only keys that exactly match a known [FormationShape] `.name` are kept;
///   unknown/removed shape keys are ignored gracefully (naturally bounding the
///   result to at most [FormationShape.values] entries).
/// - Each value is validated and normalized by [normalizeArgb], the shared
///   rule set (non-numeric, non-finite, fractional, negative and out-of-32-bit
///   values are rejected; whatever survives is forced fully opaque so a stored
///   zero-/low-alpha value can never make a highlight vanish). Tag colours
///   (issue #786) go through the same helper, so a hostile value is treated
///   identically wherever it entered from.
Map<FormationShape, Color> formationColorOverridesFromStored(Object? stored) {
  final result = <FormationShape, Color>{};
  if (stored is! Map) return result;
  final byName = {for (final s in FormationShape.values) s.name: s};
  stored.forEach((key, value) {
    if (result.length >= FormationShape.values.length) return;
    if (key is! String) return;
    final shape = byName[key];
    if (shape == null) return;
    final argb = normalizeArgb(value);
    if (argb == null) return;
    result[shape] = Color(argb);
  });
  return result;
}

/// Encodes the per-shape color-override map to a JSON-encodable object for
/// storage (issue #367): shape `.name` → packed ARGB int. Colors are stored
/// fully opaque so a round-trip is stable.
Map<String, int> encodeFormationColorOverrides(
  Map<FormationShape, Color> overrides,
) => {
  for (final entry in overrides.entries)
    entry.key.name: entry.value.toARGB32() | 0xFF000000,
};

/// Owns the user's per-[FormationShape] label-color overrides (issue #367) and
/// exposes them live to the widget tree.
///
/// Mirrors [CustomThemesController]: backed by the free-form
/// `SettingsRepository`, every mutation persists immediately and notifies
/// listeners so the formation labels re-tint live. Only shapes the user
/// explicitly set are stored; clearing a shape removes its override so the
/// label reverts to the family default.
class FormationColorsController extends ChangeNotifier {
  FormationColorsController(this._settings);

  final SettingsRepository _settings;

  final Map<FormationShape, Color> _overrides = {};

  /// Read-only view of the current overrides (only shapes the user set).
  Map<FormationShape, Color> get overrides => Map.unmodifiable(_overrides);

  /// The user's override color for [shape], or `null` when unset (the label
  /// should then fall back to its family default and render without a badge).
  Color? overrideFor(FormationShape shape) => _overrides[shape];

  /// Loads persisted overrides from storage. Safe to call once at startup;
  /// malformed payloads degrade to "no overrides" rather than throwing.
  Future<void> load() async {
    _overrides
      ..clear()
      ..addAll(
        formationColorOverridesFromStored(
          await _settings.get(kFormationColorOverridesKey),
        ),
      );
    notifyListeners();
  }

  /// Sets [shape]'s override to [color] (forced fully opaque), persists, and
  /// notifies.
  Future<void> setColor(FormationShape shape, Color color) async {
    _overrides[shape] = Color(color.toARGB32() | 0xFF000000);
    await _persist();
    notifyListeners();
  }

  /// Clears [shape]'s override (reverting it to the family default), persists,
  /// and notifies. No-op if the shape had no override.
  Future<void> clearColor(FormationShape shape) async {
    if (_overrides.remove(shape) == null) return;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() => _settings.set(
    kFormationColorOverridesKey,
    encodeFormationColorOverrides(_overrides),
  );
}
