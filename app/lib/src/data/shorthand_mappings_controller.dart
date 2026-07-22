import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// Persistence key for the user's shorthand → figure(s) mappings (issue #420).
/// Stored as a JSON array of `{token, figures}` objects (see
/// [ShorthandMappings.encode]); absent/unset means no mappings (the shipped
/// default).
const String kShorthandMappingsKey = 'shorthand_mappings';

/// Owns the user's locally-saved shorthand → figure(s) mappings (issue #420)
/// and exposes them live to the widget tree.
///
/// Mirrors [FormationColorsController]/`DialectLibraryController`: backed by the
/// free-form [SettingsRepository], every mutation persists immediately and
/// notifies listeners so the free-text entry path picks up changes without a
/// relaunch. The persisted store is decoded defensively via
/// [ShorthandMappings.decode] (bounded, never-throw, taxonomy-validated) so a
/// corrupt or hostile payload degrades to "no mappings" rather than crashing.
///
/// Tokens are unique case-insensitively; the controller preserves the user's
/// original casing for display and enforces uniqueness / bounded length /
/// non-empty on [upsert].
class ShorthandMappingsController extends ChangeNotifier {
  ShorthandMappingsController(this._settings, {Taxonomy? taxonomy})
    : _taxonomy = taxonomy ?? contraTaxonomy;

  final SettingsRepository _settings;
  final Taxonomy _taxonomy;

  List<ShorthandMapping> _mappings = const [];

  /// The current mappings, in display/insertion order. Unmodifiable.
  List<ShorthandMapping> get mappings => List.unmodifiable(_mappings);

  /// The current mappings wrapped as a resolvable [ShorthandMappings] store,
  /// suitable for passing to the free-text entry path.
  ShorthandMappings get store => ShorthandMappings(_mappings);

  /// Whether there are no mappings.
  bool get isEmpty => _mappings.isEmpty;

  /// Loads persisted mappings from storage. Safe to call once at startup;
  /// malformed payloads degrade to "no mappings" rather than throwing.
  Future<void> load() async {
    final stored = await _settings.get(kShorthandMappingsKey);
    _mappings = ShorthandMappings.decode(
      stored,
      taxonomy: _taxonomy,
    ).mappings.toList();
    notifyListeners();
  }

  /// Whether [token] already names a mapping (case-insensitively), optionally
  /// ignoring the mapping at [exceptIndex] (used when editing a row in place).
  bool hasToken(String token, {int? exceptIndex}) {
    final normalized = normalizeShorthandToken(token);
    for (var i = 0; i < _mappings.length; i++) {
      if (i == exceptIndex) continue;
      if (_mappings[i].normalizedToken == normalized) return true;
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

  Future<void> _persist() => _settings.set(
    kShorthandMappingsKey,
    ShorthandMappings(_mappings).toJson(),
  );
}
