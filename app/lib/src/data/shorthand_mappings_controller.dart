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

/// Persistence key for the user's shorthands for their own new figures
/// (#1023): tokens that insert a use of one of them with fixed arguments. See
/// [UserFigureShorthands].
const String kUserFigureShorthandsKey = userFigureShorthandsSettingKey;

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
/// It also owns the compound shorthands (#709) and the shorthands for the
/// user's new figures (#1023), each stored under its own key, so that one
/// place keeps every token unique across all three kinds.
///
/// Tokens are unique case-insensitively across the kinds; the controller
/// preserves the user's original casing for display and enforces uniqueness /
/// bounded length / non-empty on [upsert], [upsertCompound] and
/// [upsertUserFigure].
class ShorthandMappingsController extends ChangeNotifier {
  ShorthandMappingsController(this._settings, {Taxonomy? taxonomy})
    : _taxonomy = taxonomy ?? contraTaxonomy;

  final SettingsRepository _settings;
  final Taxonomy _taxonomy;

  List<ShorthandMapping> _mappings = const [];
  List<CompoundShorthand> _compound = const [];
  List<UserFigureShorthand> _userFigure = const [];

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

  /// The shorthands for the user's new figures, in display order.
  /// Unmodifiable.
  List<UserFigureShorthand> get userFigureShorthands =>
      List.unmodifiable(_userFigure);

  /// Every token a shorthand of any kind has, normalized: what a new
  /// shorthand, of any kind, cannot take.
  Set<String> get takenTokens => {
    for (final m in _mappings) m.normalizedToken,
    for (final c in _compound) c.normalizedToken,
    for (final u in _userFigure) u.normalizedToken,
  };

  /// The compound shorthands as a resolvable store, for free-text entry.
  CompoundShorthands get compoundStore => CompoundShorthands(_compound);

  /// The shorthands for the user's new figures as a resolvable store, for
  /// free-text entry.
  UserFigureShorthands get userFigureStore => UserFigureShorthands(_userFigure);

  /// Loads persisted mappings from storage. Safe to call once at startup;
  /// malformed payloads degrade to "no mappings" rather than throwing.
  Future<void> load() async {
    // Every key is read before any is applied, so a failed read leaves the
    // controller as it was.
    final stored = await _settings.get(kShorthandMappingsKey);
    final storedCompound = await _settings.get(kCompoundShorthandsKey);
    final storedUserFigure = await _settings.get(kUserFigureShorthandsKey);
    _mappings = ShorthandMappings.decode(
      stored,
      taxonomy: _taxonomy,
    ).mappings.toList();
    _compound = CompoundShorthands.decode(storedCompound).shorthands.toList();
    _userFigure = UserFigureShorthands.decode(
      storedUserFigure,
    ).shorthands.toList();
    notifyListeners();
  }

  /// Whether [token] already names a shorthand of any kind
  /// (case-insensitively), optionally ignoring the figure shorthand at
  /// [exceptIndex], the compound shorthand at [exceptCompoundIndex] or the
  /// shorthand for a new figure at [exceptUserFigureIndex] (used when editing
  /// a row in place).
  bool hasToken(
    String token, {
    int? exceptIndex,
    int? exceptCompoundIndex,
    int? exceptUserFigureIndex,
  }) {
    final normalized = normalizeShorthandToken(token);
    for (var i = 0; i < _mappings.length; i++) {
      if (i == exceptIndex) continue;
      if (_mappings[i].normalizedToken == normalized) return true;
    }
    for (var i = 0; i < _compound.length; i++) {
      if (i == exceptCompoundIndex) continue;
      if (_compound[i].normalizedToken == normalized) return true;
    }
    for (var i = 0; i < _userFigure.length; i++) {
      if (i == exceptUserFigureIndex) continue;
      if (_userFigure[i].normalizedToken == normalized) return true;
    }
    return false;
  }

  /// Adds [mapping] (when [index] is `null`) or replaces the mapping at [index].
  ///
  /// Rejects an empty/whitespace or over-long token, a token that collides
  /// case-insensitively with a DIFFERENT mapping, or a new mapping past
  /// [maxShorthandMappings] (which the next load would drop), by throwing
  /// [ArgumentError] — callers (the editor) validate first so this is a
  /// defensive backstop. Replacing a mapping in place is allowed at the cap.
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
    final adding = index == null || index < 0 || index >= _mappings.length;
    if (adding && _mappings.length >= maxShorthandMappings) {
      throw ArgumentError.value(mapping, 'mapping', 'would not be kept');
    }
    // Persist the trimmed token while keeping the user's original casing.
    final normalized = ShorthandMapping(token: token, figures: mapping.figures);
    final next = _mappings.toList();
    if (adding) {
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
    final adding = index == null || index < 0 || index >= _compound.length;
    if (!CompoundShorthands.keeps(normalized) ||
        (adding && _compound.length >= maxCompoundShorthands)) {
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

  /// Adds [shorthand] (when [index] is null) or replaces the shorthand for a
  /// new figure at [index]. Rejects, by throwing [ArgumentError], an empty or
  /// over-long token, one any other shorthand of any kind already has, or one
  /// the next load would drop; the editor validates first, so this is a
  /// backstop.
  Future<void> upsertUserFigure(
    UserFigureShorthand shorthand, {
    int? index,
  }) async {
    final token = shorthand.token.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) {
      throw ArgumentError.value(shorthand.token, 'token', 'invalid length');
    }
    if (hasToken(token, exceptUserFigureIndex: index)) {
      throw ArgumentError.value(
        shorthand.token,
        'token',
        'duplicates an existing shorthand (case-insensitive)',
      );
    }
    final normalized = UserFigureShorthand(
      token: token,
      figureId: shorthand.figureId,
      figureName: shorthand.figureName,
      args: shorthand.args,
      beats: shorthand.beats,
    );
    final adding = index == null || index < 0 || index >= _userFigure.length;
    if (!UserFigureShorthands.keeps(normalized) ||
        (adding && _userFigure.length >= maxUserFigureShorthands)) {
      throw ArgumentError.value(shorthand, 'shorthand', 'would not be kept');
    }
    final next = _userFigure.toList();
    if (adding) {
      next.add(normalized);
    } else {
      next[index] = normalized;
    }
    _userFigure = next;
    await _persistUserFigure();
    notifyListeners();
  }

  /// Removes the shorthand for a new figure at [index] (a no-op when out of
  /// range).
  Future<void> removeUserFigureAt(int index) async {
    if (index < 0 || index >= _userFigure.length) return;
    _userFigure = _userFigure.toList()..removeAt(index);
    await _persistUserFigure();
    notifyListeners();
  }

  /// Turns the compound shorthand at [compoundIndex] into [shorthand], one
  /// for a new figure, when an edit chose a new figure instead. Everything is
  /// checked before either key is written, so a refusal (by throwing
  /// [ArgumentError], as [upsertUserFigure]) leaves both kinds as they were.
  Future<void> replaceCompoundWithUserFigure(
    int compoundIndex,
    UserFigureShorthand shorthand,
  ) async {
    if (compoundIndex < 0 || compoundIndex >= _compound.length) {
      throw RangeError.index(compoundIndex, _compound, 'compoundIndex');
    }
    final normalized = _checkedUserFigure(
      shorthand,
      exceptCompoundIndex: compoundIndex,
    );
    final userFigure = [..._userFigure, normalized];
    final compound = _compound.toList()..removeAt(compoundIndex);
    // The new entry is written first: should the removal then fail, the
    // token is in both kinds, where the compound shorthand wins and the
    // other says so, rather than in neither. Each list is taken up only once
    // its key is written.
    await _settings.set(
      kUserFigureShorthandsKey,
      UserFigureShorthands(userFigure).toJson(),
    );
    _userFigure = userFigure;
    await _settings.set(
      kCompoundShorthandsKey,
      CompoundShorthands(compound).toJson(),
    );
    _compound = compound;
    notifyListeners();
  }

  /// Turns the shorthand for a new figure at [userFigureIndex] into
  /// [shorthand], a compound shorthand, when an edit chose a compound
  /// instead. Checked before either key is written, as
  /// [replaceCompoundWithUserFigure].
  Future<void> replaceUserFigureWithCompound(
    int userFigureIndex,
    CompoundShorthand shorthand,
  ) async {
    if (userFigureIndex < 0 || userFigureIndex >= _userFigure.length) {
      throw RangeError.index(userFigureIndex, _userFigure, 'userFigureIndex');
    }
    final normalized = _checkedCompound(
      shorthand,
      exceptUserFigureIndex: userFigureIndex,
    );
    final compound = [..._compound, normalized];
    final userFigure = _userFigure.toList()..removeAt(userFigureIndex);
    // The new entry first, as [replaceCompoundWithUserFigure] writes it.
    await _settings.set(
      kCompoundShorthandsKey,
      CompoundShorthands(compound).toJson(),
    );
    _compound = compound;
    await _settings.set(
      kUserFigureShorthandsKey,
      UserFigureShorthands(userFigure).toJson(),
    );
    _userFigure = userFigure;
    notifyListeners();
  }

  /// Turns each shorthand for the user's figure [id] into an ordinary
  /// shorthand for the figure [toFigure] returns for it (#1023, maintainer
  /// decision 5): what switching that figure to the shipped one of its name
  /// makes of its shorthands. Returns how many were turned.
  ///
  /// A shorthand [toFigure] returns null for, or that the ordinary
  /// shorthands have no room left for ([maxShorthandMappings]), stays as it
  /// is: once the figure is retired it shows that figure's name, as after a
  /// delete. So does one whose token an ordinary shorthand already has (two
  /// devices can each add one before they sync), which the next load would
  /// otherwise drop. Each turned keeps its token. The
  /// ordinary shorthands are written first: should the second write fail,
  /// a token is in both kinds, where the ordinary shorthand wins and the
  /// other says so, rather than in neither.
  Future<int> switchUserFigureShorthands(
    String id,
    Figure? Function(UserFigureShorthand shorthand) toFigure,
  ) async {
    final mappings = _mappings.toList();
    final kept = <UserFigureShorthand>[];
    var turned = 0;
    for (final shorthand in _userFigure) {
      final figure = shorthand.figureId == id ? toFigure(shorthand) : null;
      if (figure == null ||
          mappings.length >= maxShorthandMappings ||
          mappings.any((m) => m.normalizedToken == shorthand.normalizedToken)) {
        kept.add(shorthand);
        continue;
      }
      mappings.add(ShorthandMapping(token: shorthand.token, figures: [figure]));
      turned++;
    }
    if (turned == 0) return 0;
    await _settings.set(
      kShorthandMappingsKey,
      ShorthandMappings(mappings).toJson(),
    );
    _mappings = mappings;
    await _settings.set(
      kUserFigureShorthandsKey,
      UserFigureShorthands(kept).toJson(),
    );
    _userFigure = kept;
    notifyListeners();
    return turned;
  }

  /// [shorthand], trimmed, when a new one of its kind could be added (its
  /// token free but for the excepted entry, kept by the next load, and
  /// within the bound); throws [ArgumentError] otherwise.
  UserFigureShorthand _checkedUserFigure(
    UserFigureShorthand shorthand, {
    int? exceptCompoundIndex,
  }) {
    final token = shorthand.token.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) {
      throw ArgumentError.value(shorthand.token, 'token', 'invalid length');
    }
    if (hasToken(token, exceptCompoundIndex: exceptCompoundIndex)) {
      throw ArgumentError.value(shorthand.token, 'token', 'already taken');
    }
    final normalized = UserFigureShorthand(
      token: token,
      figureId: shorthand.figureId,
      figureName: shorthand.figureName,
      args: shorthand.args,
      beats: shorthand.beats,
    );
    if (!UserFigureShorthands.keeps(normalized) ||
        _userFigure.length >= maxUserFigureShorthands) {
      throw ArgumentError.value(shorthand, 'shorthand', 'would not be kept');
    }
    return normalized;
  }

  /// As [_checkedUserFigure], for a compound shorthand.
  CompoundShorthand _checkedCompound(
    CompoundShorthand shorthand, {
    int? exceptUserFigureIndex,
  }) {
    final token = shorthand.token.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) {
      throw ArgumentError.value(shorthand.token, 'token', 'invalid length');
    }
    if (hasToken(token, exceptUserFigureIndex: exceptUserFigureIndex)) {
      throw ArgumentError.value(shorthand.token, 'token', 'already taken');
    }
    final normalized = CompoundShorthand(
      token: token,
      compoundId: shorthand.compoundId,
      compoundName: shorthand.compoundName,
      args: shorthand.args,
    );
    if (!CompoundShorthands.keeps(normalized) ||
        _compound.length >= maxCompoundShorthands) {
      throw ArgumentError.value(shorthand, 'shorthand', 'would not be kept');
    }
    return normalized;
  }

  Future<void> _persistUserFigure() => _settings.set(
    kUserFigureShorthandsKey,
    UserFigureShorthands(_userFigure).toJson(),
  );

  Future<void> _persistCompound() => _settings.set(
    kCompoundShorthandsKey,
    CompoundShorthands(_compound).toJson(),
  );

  Future<void> _persist() => _settings.set(
    kShorthandMappingsKey,
    ShorthandMappings(_mappings).toJson(),
  );
}
