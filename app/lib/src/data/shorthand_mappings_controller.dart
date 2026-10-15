import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// Persistence key for the user's shorthand → figure(s) mappings (issue #420).
/// Stored as a JSON array of `{token, figures}` objects (see
/// [ShorthandMappings.encode]); absent/unset means no mappings (the shipped
/// default).
const String kShorthandMappingsKey = 'shorthand_mappings';

/// Persistence key for the user's compound shorthands (#709): tokens that
/// stand for one of their own compound figures with fixed arguments. See
/// [CompoundShorthands].
const String kCompoundShorthandsKey = compoundShorthandsSettingKey;

/// Owns the user's locally-saved shorthand → figure(s) mappings (issue #420)
/// and exposes them live to the widget tree.
///
/// Mirrors [FormationColorsController]/`DialectLibraryController`: backed by the
/// free-form [SettingsRepository], every mutation persists immediately and
/// notifies listeners so the free-text entry path picks up changes without a
/// relaunch. The persisted store is decoded defensively via
/// [ShorthandMappings.decode] (bounded, never-throw, taxonomy-validated) so a
/// corrupt or hostile payload degrades to "no mappings" rather than crashing;
/// structural `meanwhile` and `modifier` targets are validated against their
/// bounded alternating-child model.
///
/// It also owns the compound shorthands (#709), stored under their own key, so
/// that one place keeps every token unique across both kinds.
///
/// Tokens are unique case-insensitively across both kinds; the controller
/// preserves the user's original casing for display and enforces uniqueness /
/// bounded length / non-empty on [upsert] and [upsertCompound].
class ShorthandMappingsController extends ChangeNotifier {
  ShorthandMappingsController(this._settings, {Taxonomy? taxonomy})
    : _taxonomy = taxonomy ?? contraTaxonomy;

  final SettingsRepository _settings;
  final Taxonomy _taxonomy;

  List<ShorthandMapping> _mappings = const [];
  List<CompoundShorthand> _compound = const [];

  /// The current mappings, in display/insertion order. Unmodifiable.
  List<ShorthandMapping> get mappings => List.unmodifiable(_mappings);

  /// The current mappings wrapped as a resolvable [ShorthandMappings] store,
  /// suitable for passing to the free-text entry path.
  ShorthandMappings get store => ShorthandMappings(_mappings);

  /// Whether there are no mappings.
  bool get isEmpty => _mappings.isEmpty;

  /// The compound shorthands, in display order. Unmodifiable.
  List<CompoundShorthand> get compoundShorthands =>
      List.unmodifiable(_compound);

  /// The compound shorthands as a resolvable store, for free-text entry.
  CompoundShorthands get compoundStore => CompoundShorthands(_compound);

  /// Loads persisted mappings from storage. Safe to call once at startup;
  /// malformed payloads degrade to "no mappings" rather than throwing.
  Future<void> load() async {
    // Both keys are read before either is applied, so a failed read leaves
    // the controller as it was.
    final stored = await _settings.get(kShorthandMappingsKey);
    final storedCompound = await _settings.get(kCompoundShorthandsKey);
    _mappings = ShorthandMappings.decode(
      stored,
      taxonomy: _taxonomy,
    ).mappings.toList();
    _compound = CompoundShorthands.decode(storedCompound).shorthands.toList();
    notifyListeners();
  }

  /// Whether [token] already names a shorthand of either kind
  /// (case-insensitively), optionally ignoring the figure shorthand at
  /// [exceptIndex] or the compound shorthand at [exceptCompoundIndex] (used
  /// when editing a row in place).
  bool hasToken(String token, {int? exceptIndex, int? exceptCompoundIndex}) {
    final normalized = normalizeShorthandToken(token);
    for (var i = 0; i < _mappings.length; i++) {
      if (i == exceptIndex) continue;
      if (_mappings[i].normalizedToken == normalized) return true;
    }
    for (var i = 0; i < _compound.length; i++) {
      if (i == exceptCompoundIndex) continue;
      if (_compound[i].normalizedToken == normalized) return true;
    }
    return false;
  }

  /// Adds [mapping] (when [index] is `null`) or replaces the mapping at [index].
  ///
  /// Rejects an empty/whitespace or over-long token, or a token that collides
  /// case-insensitively with a DIFFERENT mapping, by throwing [ArgumentError]
  /// — callers (the editor) validate first so this is a defensive backstop.
  Future<void> upsert(ShorthandMapping mapping, {int? index}) async {
    final token = mapping.token.trim();
    if (token.isEmpty) {
      throw ArgumentError.value(mapping.token, 'token', 'must be non-empty');
    }
    if (token.length > maxShorthandTokenLength) {
      throw ArgumentError.value(
        mapping.token,
        'token',
        'must be at most $maxShorthandTokenLength characters',
      );
    }
    if (hasToken(token, exceptIndex: index)) {
      throw ArgumentError.value(
        mapping.token,
        'token',
        'duplicates an existing shorthand (case-insensitive)',
      );
    }
    // Mirror the decode invariant (shorthand_mappings.dart): a mapping must
    // expand to a non-empty, bounded list of figures. An empty expansion would
    // make resolve() return `[]`, which the free-text entry path treats as a
    // shorthand HIT that inserts nothing — so guard the in-app mutation path
    // just as strictly as the persisted-payload decode path.
    if (mapping.figures.isEmpty) {
      throw ArgumentError.value(
        mapping.figures,
        'figures',
        'must expand to at least one figure',
      );
    }
    if (mapping.figures.length > maxShorthandTargetFigures) {
      throw ArgumentError.value(
        mapping.figures,
        'figures',
        'must expand to at most $maxShorthandTargetFigures figures',
      );
    }
    // Persist the trimmed token while keeping the user's original casing.
    final normalized = ShorthandMapping(token: token, figures: mapping.figures);
    final next = _mappings.toList();
    if (index == null || index < 0 || index >= next.length) {
      next.add(normalized);
    } else {
      next[index] = normalized;
    }
    _mappings = next;
    await _persist();
    notifyListeners();
  }

  /// Removes the mapping at [index] (a no-op for an out-of-range index).
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _mappings.length) return;
    final next = _mappings.toList()..removeAt(index);
    _mappings = next;
    await _persist();
    notifyListeners();
  }

  /// Adds [shorthand] (when [index] is null) or replaces the compound
  /// shorthand at [index]. Rejects, by throwing [ArgumentError], an empty or
  /// over-long token or one any other shorthand of either kind already has;
  /// the editor validates first, so this is a backstop.
  Future<void> upsertCompound(CompoundShorthand shorthand, {int? index}) async {
    final token = shorthand.token.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) {
      throw ArgumentError.value(shorthand.token, 'token', 'invalid length');
    }
    if (hasToken(token, exceptCompoundIndex: index)) {
      throw ArgumentError.value(
        shorthand.token,
        'token',
        'duplicates an existing shorthand (case-insensitive)',
      );
    }
    final normalized = CompoundShorthand(
      token: token,
      compoundId: shorthand.compoundId,
      compoundName: shorthand.compoundName,
      args: shorthand.args,
    );
    // Mirror the decode invariant, as [upsert] does: a shorthand the next
    // load would drop must not be saved as if it were kept.
    if (!CompoundShorthands.keeps(normalized)) {
      throw ArgumentError.value(shorthand, 'shorthand', 'would not be kept');
    }
    final next = _compound.toList();
    if (index == null || index < 0 || index >= next.length) {
      next.add(normalized);
    } else {
      next[index] = normalized;
    }
    _compound = next;
    await _persistCompound();
    notifyListeners();
  }

  /// Removes the compound shorthand at [index] (a no-op when out of range).
  Future<void> removeCompoundAt(int index) async {
    if (index < 0 || index >= _compound.length) return;
    _compound = _compound.toList()..removeAt(index);
    await _persistCompound();
    notifyListeners();
  }

  Future<void> _persistCompound() => _settings.set(
    kCompoundShorthandsKey,
    CompoundShorthands(_compound).toJson(),
  );

  Future<void> _persist() => _settings.set(
    kShorthandMappingsKey,
    ShorthandMappings(_mappings).toJson(),
  );
}
