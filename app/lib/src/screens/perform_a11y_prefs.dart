import 'package:compendium_core/compendium_core.dart';

import 'perform_card.dart' show kPerformDefaultScale, kPerformMinScale;
import 'settings/settings_keys.dart';

/// The in-Perform accessibility preferences persisted across sessions
/// (issue #449): the manual text scale, the dark-stage high-contrast theme,
/// and whether figures render canonical role/move tokens.
///
/// This is a plain value object with no Flutter or platform dependencies so the
/// load/validate/save logic in [PerformA11yPrefsStore] stays unit-testable
/// without a real device.
class PerformA11yPrefs {
  const PerformA11yPrefs({
    required this.textScale,
    required this.stageMode,
    required this.canonicalView,
  });

  /// The defaults applied on first run or when a stored value is absent or
  /// invalid. Match the historical in-view defaults so existing behaviour is
  /// unchanged: a large default scale, stage mode on, canonical view off.
  static const PerformA11yPrefs defaults = PerformA11yPrefs(
    textScale: kPerformDefaultScale,
    stageMode: true,
    canonicalView: false,
  );

  final double textScale;
  final bool stageMode;
  final bool canonicalView;

  @override
  bool operator ==(Object other) =>
      other is PerformA11yPrefs &&
      other.textScale == textScale &&
      other.stageMode == stageMode &&
      other.canonicalView == canonicalView;

  @override
  int get hashCode => Object.hash(textScale, stageMode, canonicalView);
}

/// Loads and persists the Perform accessibility preferences via the app's
/// existing [SettingsRepository] key/value store (issue #449). Values are held
/// in the same JSON settings table as every other app preference, so no new
/// persistence mechanism or dependency is introduced.
///
/// [load] is defensive by design (OWASP input validation): the settings store
/// is a mutable local database that can also be seeded from imported/shared
/// data, so a stored value may be absent, of the wrong type, or out of range.
/// Any value that fails validation falls back to [PerformA11yPrefs.defaults]
/// rather than crashing or applying a hostile value — an absurd text scale, a
/// non-finite number, or a non-bool toggle can never reach the UI.
class PerformA11yPrefsStore {
  PerformA11yPrefsStore(this._settings);

  final SettingsRepository _settings;

  /// Reads all three prefs, coercing/validating each and substituting the
  /// default for any absent or invalid entry. Never throws for missing keys.
  Future<PerformA11yPrefs> load() async {
    final textScale = _readTextScale(await _settings.get(kPerformTextScaleKey));
    final stageMode = _readBool(
      await _settings.get(kPerformStageModeKey),
      PerformA11yPrefs.defaults.stageMode,
    );
    final canonicalView = _readBool(
      await _settings.get(kPerformCanonicalViewKey),
      PerformA11yPrefs.defaults.canonicalView,
    );
    return PerformA11yPrefs(
      textScale: textScale,
      stageMode: stageMode,
      canonicalView: canonicalView,
    );
  }

  Future<void> saveTextScale(double value) =>
      _settings.set(kPerformTextScaleKey, value);

  Future<void> saveStageMode(bool value) =>
      _settings.set(kPerformStageModeKey, value);

  Future<void> saveCanonicalView(bool value) =>
      _settings.set(kPerformCanonicalViewKey, value);

  /// Accepts a stored text scale only when it is a finite number at or above
  /// the enforced minimum; anything else (null, non-number, NaN/Infinity, or
  /// below the floor) yields the default. There is no upper clamp: the in-view
  /// A+ control is intentionally unbounded, so a large but finite manual size
  /// is a legitimate low-vision preference.
  double _readTextScale(Object? raw) {
    if (raw is num) {
      final value = raw.toDouble();
      if (value.isFinite && value >= kPerformMinScale) return value;
    }
    return PerformA11yPrefs.defaults.textScale;
  }

  bool _readBool(Object? raw, bool fallback) => raw is bool ? raw : fallback;
}
