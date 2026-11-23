/// What the program builder's **Suggested** sort looks for (#2343): one
/// weight per factor, the difficulty curve's shape and the venue window, as
/// Settings ▸ Experimental ▸ Suggestions edits them and the
/// `suggestion_settings` settings key stores them.
///
/// The stored shape is kept in this one module so it can change in one place:
///
/// ```json
/// {"version": 1,
///  "factors": {
///    "matrixVariety":    {"weight": "aLot"},
///    "formationBalance": {"weight": "aLittle"},
///    "difficultyCurve":  {"weight": "aLittle", "shape": "buildThenEase"},
///    "venueRecency":     {"weight": "aLot", "window": "3mo"}},
///  "preferences": []}
/// ```
///
/// Reading is lenient, field by field: a missing key, a missing factor or an
/// unknown token reads as that field's shipped default. Writing is
/// conservative: a factor this build does not know, a key inside a known
/// factor it does not know, an unknown top-level key, and every `preferences`
/// entry (reserved for saved-search preferences, #2325) are written back
/// exactly as they were read, so one device on an older build never drops
/// what a newer one stored. A value with a `version` this build does not know
/// reads as the defaults and is flagged ([SuggestionSettingsRead.isNewer]) so
/// the editor shows it read-only rather than overwriting it.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The `version` this build writes and fully reads.
const int suggestionSettingsVersion = 1;

/// How much a factor counts. The editor shows these as Off / A little / A lot
/// and never shows a number.
enum SuggestionWeight {
  off('off', 0),
  aLittle('aLittle', 1),
  aLot('aLot', 3);

  const SuggestionWeight(this.token, this.multiplier);

  /// The stored token.
  final String token;

  /// What a factor's effect is multiplied by in the score.
  final int multiplier;

  static SuggestionWeight? fromToken(Object? token) =>
      values.firstWhereOrNull((w) => w.token == token);
}

/// The difficulty curve's shape.
enum DifficultyCurveShape {
  /// Start easy, build to the hardest dances about two thirds of the way in,
  /// then ease off.
  buildThenEase('buildThenEase'),

  /// Keep close to the level of the dances already in the program.
  even('even'),

  /// No curve: the factor is skipped whatever its weight.
  off('off');

  const DifficultyCurveShape(this.token);

  final String token;

  static DifficultyCurveShape? fromToken(Object? token) =>
      values.firstWhereOrNull((s) => s.token == token);
}

/// How far back "called here recently" looks: calendar months, counted back
/// from today like the history filters' presets (docs/design/history-filters.md
/// Q2).
enum VenueRecencyWindow {
  oneMonth('1mo', 1),
  threeMonths('3mo', 3),
  sixMonths('6mo', 6);

  const VenueRecencyWindow(this.token, this.months);

  final String token;
  final int months;

  static VenueRecencyWindow? fromToken(Object? token) =>
      values.firstWhereOrNull((w) => w.token == token);
}

/// The factors, by their stored names.
enum SuggestionFactor {
  matrixVariety,
  formationBalance,
  difficultyCurve,
  venueRecency,
}

const _deepEquality = DeepCollectionEquality();

/// The settings, with what this build does not understand kept aside so it can
/// be written back unchanged.
@immutable
class SuggestionSettings {
  const SuggestionSettings({
    this.matrixVariety = SuggestionWeight.aLot,
    this.formationBalance = SuggestionWeight.aLittle,
    this.difficultyCurve = SuggestionWeight.aLittle,
    this.curveShape = DifficultyCurveShape.buildThenEase,
    this.venueRecency = SuggestionWeight.aLot,
    this.venueWindow = VenueRecencyWindow.threeMonths,
    this.preferences = const [],
    this.preserved = const {},
    this.preservedFactorKeys = const {},
    this.preservedFactors = const {},
  });

  /// The shipped defaults.
  static const SuggestionSettings defaults = SuggestionSettings();

  final SuggestionWeight matrixVariety;
  final SuggestionWeight formationBalance;
  final SuggestionWeight difficultyCurve;
  final DifficultyCurveShape curveShape;
  final SuggestionWeight venueRecency;
  final VenueRecencyWindow venueWindow;

  /// The stored `preferences` entries, verbatim. This build has no
  /// Prefer/Avoid rows (#2325 is not in it), so it neither reads nor scores
  /// them; it only keeps them.
  final List<Object?> preferences;

  /// Top-level keys other than `version`, `factors` and `preferences`, kept to
  /// be written back.
  final Map<String, Object?> preserved;

  /// Keys inside a known factor's object other than the ones this build
  /// reads, by factor name, kept to be written back.
  final Map<String, Map<String, Object?>> preservedFactorKeys;

  /// Factors this build does not know, by name, kept to be written back.
  final Map<String, Object?> preservedFactors;

  SuggestionWeight weightOf(SuggestionFactor factor) => switch (factor) {
    SuggestionFactor.matrixVariety => matrixVariety,
    SuggestionFactor.formationBalance => formationBalance,
    SuggestionFactor.difficultyCurve => difficultyCurve,
    SuggestionFactor.venueRecency => venueRecency,
  };

  /// These settings with [factor] at [weight].
  SuggestionSettings withWeight(
    SuggestionFactor factor,
    SuggestionWeight weight,
  ) => copyWith(
    matrixVariety: factor == SuggestionFactor.matrixVariety ? weight : null,
    formationBalance: factor == SuggestionFactor.formationBalance
        ? weight
        : null,
    difficultyCurve: factor == SuggestionFactor.difficultyCurve ? weight : null,
    venueRecency: factor == SuggestionFactor.venueRecency ? weight : null,
  );

  SuggestionSettings copyWith({
    SuggestionWeight? matrixVariety,
    SuggestionWeight? formationBalance,
    SuggestionWeight? difficultyCurve,
    DifficultyCurveShape? curveShape,
    SuggestionWeight? venueRecency,
    VenueRecencyWindow? venueWindow,
  }) => SuggestionSettings(
    matrixVariety: matrixVariety ?? this.matrixVariety,
    formationBalance: formationBalance ?? this.formationBalance,
    difficultyCurve: difficultyCurve ?? this.difficultyCurve,
    curveShape: curveShape ?? this.curveShape,
    venueRecency: venueRecency ?? this.venueRecency,
    venueWindow: venueWindow ?? this.venueWindow,
    preferences: preferences,
    preserved: preserved,
    preservedFactorKeys: preservedFactorKeys,
    preservedFactors: preservedFactors,
  );

  /// Whether every factor, the curve shape and the window are the shipped
  /// defaults. Kept entries do not count: Reset to defaults keeps them too.
  bool get hasDefaultChoices =>
      matrixVariety == defaults.matrixVariety &&
      formationBalance == defaults.formationBalance &&
      difficultyCurve == defaults.difficultyCurve &&
      curveShape == defaults.curveShape &&
      venueRecency == defaults.venueRecency &&
      venueWindow == defaults.venueWindow;

  /// The shipped choices, keeping what this build does not understand (an
  /// unknown factor, a preference), as **Reset to defaults** writes them.
  SuggestionSettings resetChoices() => SuggestionSettings(
    preferences: preferences,
    preserved: preserved,
    preservedFactorKeys: preservedFactorKeys,
    preservedFactors: preservedFactors,
  );

  /// The stored JSON object.
  Map<String, Object?> toJson() {
    Map<String, Object?> factor(
      SuggestionFactor which,
      Map<String, Object?> known,
    ) => {...?preservedFactorKeys[which.name], ...known};
    return {
      ...preserved,
      'version': suggestionSettingsVersion,
      'factors': {
        ...preservedFactors,
        SuggestionFactor.matrixVariety.name: factor(
          SuggestionFactor.matrixVariety,
          {'weight': matrixVariety.token},
        ),
        SuggestionFactor.formationBalance.name: factor(
          SuggestionFactor.formationBalance,
          {'weight': formationBalance.token},
        ),
        SuggestionFactor.difficultyCurve.name: factor(
          SuggestionFactor.difficultyCurve,
          {'weight': difficultyCurve.token, 'shape': curveShape.token},
        ),
        SuggestionFactor.venueRecency.name: factor(
          SuggestionFactor.venueRecency,
          {'weight': venueRecency.token, 'window': venueWindow.token},
        ),
      },
      'preferences': preferences,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SuggestionSettings &&
      _deepEquality.equals(other.toJson(), toJson());

  @override
  int get hashCode => _deepEquality.hash(toJson());
}

/// A stored value as read: the settings to use, and whether the value came
/// from a newer build ([isNewer]), in which case [settings] are the defaults
/// and the stored value must not be overwritten by an edit.
typedef SuggestionSettingsRead = ({SuggestionSettings settings, bool isNewer});

/// Reads a stored `suggestion_settings` value: a JSON object, or a string
/// holding one. Never throws. Absent, malformed or wrong-typed reads as the
/// defaults (writable); a `version` above [suggestionSettingsVersion] reads as
/// the defaults with `isNewer`.
SuggestionSettingsRead readSuggestionSettings(Object? stored) {
  const fallback = (settings: SuggestionSettings.defaults, isNewer: false);
  final map = _asMap(stored);
  if (map == null) return fallback;
  final version = map['version'];
  if (version is int && version > suggestionSettingsVersion) {
    return (settings: SuggestionSettings.defaults, isNewer: true);
  }
  if (version != suggestionSettingsVersion) return fallback;

  final preserved = <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries)
      if (key is String &&
          key != 'version' &&
          key != 'factors' &&
          key != 'preferences')
        key: value,
  };
  final rawFactors = map['factors'];
  final factors = rawFactors is Map
      ? {
          for (final MapEntry(:key, :value) in rawFactors.entries)
            if (key is String) key: value,
        }
      : const <String, Object?>{};
  final known = {for (final f in SuggestionFactor.values) f.name};
  final preservedFactors = <String, Object?>{
    for (final MapEntry(:key, :value) in factors.entries)
      if (!known.contains(key)) key: value,
  };
  final preservedFactorKeys = <String, Map<String, Object?>>{};
  Map<String, Object?> factorMap(SuggestionFactor factor, Set<String> reads) {
    final raw = factors[factor.name];
    if (raw is! Map) return const {};
    final entries = {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String) key: value,
    };
    final extra = {
      for (final MapEntry(:key, :value) in entries.entries)
        if (!reads.contains(key)) key: value,
    };
    if (extra.isNotEmpty) preservedFactorKeys[factor.name] = extra;
    return entries;
  }

  const d = SuggestionSettings.defaults;
  final variety = factorMap(SuggestionFactor.matrixVariety, {'weight'});
  final formation = factorMap(SuggestionFactor.formationBalance, {'weight'});
  final curve = factorMap(SuggestionFactor.difficultyCurve, {
    'weight',
    'shape',
  });
  final venue = factorMap(SuggestionFactor.venueRecency, {'weight', 'window'});
  final rawPreferences = map['preferences'];
  return (
    settings: SuggestionSettings(
      matrixVariety:
          SuggestionWeight.fromToken(variety['weight']) ?? d.matrixVariety,
      formationBalance:
          SuggestionWeight.fromToken(formation['weight']) ?? d.formationBalance,
      difficultyCurve:
          SuggestionWeight.fromToken(curve['weight']) ?? d.difficultyCurve,
      curveShape:
          DifficultyCurveShape.fromToken(curve['shape']) ?? d.curveShape,
      venueRecency:
          SuggestionWeight.fromToken(venue['weight']) ?? d.venueRecency,
      venueWindow:
          VenueRecencyWindow.fromToken(venue['window']) ?? d.venueWindow,
      preferences: rawPreferences is List
          ? List<Object?>.unmodifiable(rawPreferences)
          : const [],
      preserved: Map.unmodifiable(preserved),
      preservedFactorKeys: Map.unmodifiable(preservedFactorKeys),
      preservedFactors: Map.unmodifiable(preservedFactors),
    ),
    isNewer: false,
  );
}

/// Whether [stored] is a value a backup may restore: a JSON object with an
/// integer `version` of at least 1 whose `factors` (when present) is an object
/// and whose `preferences` (when present) is a list. A version-1 value must
/// also use only known tokens for the fields this build reads; a newer one is
/// accepted as it stands, since this build keeps it without reading it.
bool isValidStoredSuggestionSettings(Object? stored) {
  final map = _asMap(stored);
  if (map == null) return false;
  final version = map['version'];
  if (version is! int || version < 1) return false;
  final factors = map['factors'];
  if (factors != null && factors is! Map) return false;
  final preferences = map['preferences'];
  if (preferences != null && preferences is! List) return false;
  if (version > suggestionSettingsVersion || factors is! Map) return true;
  bool field(SuggestionFactor factor, String key, bool Function(Object?) ok) {
    final raw = factors[factor.name];
    if (raw == null) return true;
    if (raw is! Map) return false;
    final value = raw[key];
    return value == null || ok(value);
  }

  bool weight(SuggestionFactor f) =>
      field(f, 'weight', (v) => SuggestionWeight.fromToken(v) != null);
  return SuggestionFactor.values.every(weight) &&
      field(
        SuggestionFactor.difficultyCurve,
        'shape',
        (v) => DifficultyCurveShape.fromToken(v) != null,
      ) &&
      field(
        SuggestionFactor.venueRecency,
        'window',
        (v) => VenueRecencyWindow.fromToken(v) != null,
      );
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
