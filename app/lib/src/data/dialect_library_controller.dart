import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../diagnostics/error_log.dart';

/// Persistence key for the JSON list of user-created custom [Dialect]s of
/// contra. Each other dance form has a key of its own
/// ([customDialectsKeyFor]).
const String kCustomDialectsKey = 'custom_dialects';

/// Legacy persistence key holding the full JSON blob of the active dialect.
/// Kept in sync for readers that still resolve the active dialect from it.
const String kActiveDialectKey = 'active_dialect';

/// Persistence key for the name of contra's active dialect (a shipped preset
/// name or a custom dialect name). Absent means the app default is active.
/// Each other dance form has a key of its own ([activeDialectRefKeyFor]).
const String kActiveDialectRefKey = 'active_dialect_ref';

/// Persistence key for English country dance's custom dialects
/// ([customDialectsKeyFor]).
const String kCustomDialectsEcdKey = 'custom_dialects_ecd';

/// Persistence key for square dance's custom dialects
/// ([customDialectsKeyFor]).
const String kCustomDialectsSquareKey = 'custom_dialects_square';

/// Persistence key for the name of English country dance's active dialect
/// ([activeDialectRefKeyFor]).
const String kActiveDialectRefEcdKey = 'active_dialect_ref_ecd';

/// Persistence key for the name of square dance's active dialect
/// ([activeDialectRefKeyFor]).
const String kActiveDialectRefSquareKey = 'active_dialect_ref_square';

/// The settings key holding [form]'s custom dialects.
///
/// Each dance form has its own dialects (ADR-006 §9.1, point 1), kept under
/// keys of its own (the maintainer's choice, 2026-11-19). Contra keeps the
/// key it has always had, so an older build on another device, which knows
/// only that one, still reads contra's dialects correctly and keeps the other
/// forms' keys whole without reading them (ADR-004). Every key is listed in
/// [dialectSettingKeys].
String customDialectsKeyFor(DanceForm form) => switch (form) {
  DanceForm.contra => kCustomDialectsKey,
  DanceForm.ecd => kCustomDialectsEcdKey,
  DanceForm.square => kCustomDialectsSquareKey,
};

/// The settings key holding the name of [form]'s active dialect. Contra keeps
/// [kActiveDialectRefKey]; see [customDialectsKeyFor].
String activeDialectRefKeyFor(DanceForm form) => switch (form) {
  DanceForm.contra => kActiveDialectRefKey,
  DanceForm.ecd => kActiveDialectRefEcdKey,
  DanceForm.square => kActiveDialectRefSquareKey,
};

/// The dance form whose custom dialects [key] holds, or `null` when it is not
/// one of the [customDialectsKeyFor] keys.
DanceForm? formOfCustomDialectsKey(String key) {
  for (final form in DanceForm.values) {
    if (customDialectsKeyFor(form) == key) return form;
  }
  return null;
}

/// Every settings key a dialect library writes, for every dance form, the
/// legacy [kActiveDialectKey] included.
final Set<String> dialectSettingKeys = {
  kActiveDialectKey,
  for (final form in DanceForm.values) ...{
    customDialectsKeyFor(form),
    activeDialectRefKeyFor(form),
  },
};

/// Owns one dance form's custom dialects and which named dialect (preset or
/// custom) is active for that form (`docs/design/ux.md` §6 — the dialect
/// manager). Each form has its own library ([form]); [DialectLibraries] holds
/// them all.
///
/// Custom dialects are identified by their unique [Dialect.name]; the active
/// dialect is stored as that name and resolved against custom dialects first,
/// then the shipped [Dialect.presets], via [Dialect.resolveByName]. Backed by
/// the free-form [SettingsRepository]; every mutation persists immediately and
/// notifies listeners so the app re-renders live.
///
/// Mirrors the `CustomThemesController` pattern.
class DialectLibraryController extends ChangeNotifier {
  DialectLibraryController(
    this._settings, {
    this._programs,
    this.form = DanceForm.contra,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final SettingsRepository _settings;

  /// The dance form whose dialects this library holds.
  final DanceForm form;

  String get _customKey => customDialectsKeyFor(form);
  String get _activeKey => activeDialectRefKeyFor(form);

  /// Only contra had a dialect before the library, and only contra keeps the
  /// legacy full-blob key [kActiveDialectKey] current.
  bool get _keepsLegacyBlob => form == DanceForm.contra;

  /// Where a rename is carried to the programs that name the dialect. `null`
  /// leaves programs untouched (a controller built without a program store).
  final ProgramRepository? _programs;
  final DateTime Function() _clock;

  final List<Dialect> _customDialects = [];
  String? _activeName;

  /// Whether a dialect of another dance form is named [name]. Set by
  /// [DialectLibraries]; a library on its own has no other forms. Names are
  /// unique only within one form, and a program names its dialect by name
  /// alone, so a rename is carried to programs only while no other form
  /// still answers to the old name.
  bool Function(String name)? _inOtherForm;

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
  ///
  /// Each dialect is read as the caller wrote it and keeps its name: the app
  /// does not overwrite a user's dialect (the maintainer's ruling of
  /// 2026-11-27, ADR-006 §9.1, point 7).
  ///
  /// Transactional: every read (including the legacy blob) finishes before any
  /// state changes, so a failing read leaves the previous library and active
  /// name untouched. Writes come only after the commit, for the first-run
  /// write-back; a failure there leaves the in-memory library complete and
  /// consistent.
  Future<void> load() async {
    final hasLibrary = await _settings.contains(_customKey);
    final raw = await _settings.get(_customKey);
    final activeRaw = await _settings.get(_activeKey);
    final legacy = hasLibrary || !_keepsLegacyBlob
        ? null
        : await _settings.get(kActiveDialectKey);

    final loaded = <Dialect>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          final d = Dialect.fromJson(entry.cast<String, Object?>());
          if (!loaded.any((existing) => existing.name == d.name)) {
            loaded.add(d);
          }
        }
      }
    }
    var activeName = activeRaw is String ? activeRaw : null;
    final migrated = hasLibrary ? null : _legacyActiveDialect(legacy);
    if (migrated != null) {
      if (Dialect.forName(migrated.name) == null) loaded.add(migrated);
      activeName = migrated.name;
    }

    _customDialects
      ..clear()
      ..addAll(loaded);
    _activeName = activeName;

    if (!hasLibrary) {
      // Persist the migrated state, and mark the library as initialized so the
      // one-time migration doesn't re-run (and re-write settings) on every
      // future startup.
      if (migrated != null) await _persistActive();
      await _persistDialects();
    }
    notifyListeners();
  }

  /// Decodes a pre-library install's active dialect, stored as a full JSON blob
  /// under [kActiveDialectKey] (or a preset name). If it names/matches a preset
  /// the caller just activates it; otherwise it is adopted as a custom dialect.
  /// Pure: [load] reads the blob and applies the result.
  Dialect? _legacyActiveDialect(Object? legacy) {
    if (legacy is Map) return Dialect.fromJson(legacy.cast<String, Object?>());
    if (legacy is String) return Dialect.forName(legacy);
    return null;
  }

  /// Adds a new custom dialect, or replaces the one with the same name. A
  /// custom dialect may not take a shipped preset's name (that would create a
  /// duplicate name in [all] and shadow the preset); callers should uniquify
  /// first (see [duplicate]/[rename]).
  Future<void> upsert(Dialect dialect) async {
    if (Dialect.forName(dialect.name) != null) {
      throw ArgumentError.value(
        dialect.name,
        'dialect.name',
        'cannot reuse a shipped preset name for a custom dialect',
      );
    }
    final index = _customByNameIndex(dialect.name);
    if (index >= 0) {
      _customDialects[index] = dialect;
    } else {
      _customDialects.add(dialect);
    }
    await _persistDialects();
    notifyListeners();
  }

  /// Saves [edited] over the custom dialect that has its name, and reports
  /// whether it did. `false` means no custom dialect has that name any more,
  /// so nothing is written.
  ///
  /// The save for an editor opened on an existing dialect, which keeps the name
  /// it opened with. [upsert] cannot serve there: it adds the dialect when the
  /// name is not found, so a dialect renamed elsewhere while its editor was
  /// open would gain a second copy under its old name, and one deleted
  /// meanwhile would come back. A dialect is identified by its name alone, so a
  /// name deleted and then taken by a new dialect cannot be told apart from the
  /// original here; the edit lands on that one.
  Future<bool> updateTerms(Dialect edited) async {
    final index = _customByNameIndex(edited.name);
    if (index < 0) return false;
    _customDialects[index] = edited;
    await _persistDialects();
    notifyListeners();
    return true;
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
  /// cannot be renamed. Keeps the active pointer in sync, and carries the new
  /// name to every program that names the dialect, trashed ones included (a
  /// program stores only the name). Delete still leaves programs unpinned.
  /// Returns the new name.
  ///
  /// The library is saved before the programs are touched: a failure in
  /// between leaves programs on the old name, which already reads as
  /// "unavailable" (`resolveProgramDialect`), rather than on a name that was
  /// never saved.
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
    if (unique != oldName && !(_inOtherForm?.call(oldName) ?? false)) {
      await _programs?.renameDialect(
        oldName: oldName,
        newName: unique,
        updatedAt: _clock(),
      );
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

  /// Puts [dialect] back at [index] (clamped): Undo of [delete]. When
  /// [wasActive] and the active pointer is still on the fallback [delete] set,
  /// it is made active again; a dialect the user chose since stays chosen.
  /// (Choosing that fallback dialect itself in between cannot be told apart
  /// from not choosing, so Undo then makes the restored one active.)
  /// Programs name their dialect, and [delete] leaves them unpinned, so they
  /// find it again by name.
  ///
  /// Throws [ArgumentError] when a dialect of that name exists again (a new
  /// one took the name meanwhile), rather than shadow or replace it.
  Future<void> restoreDeleted(
    Dialect dialect, {
    required int index,
    required bool wasActive,
  }) async {
    if (isPreset(dialect.name) || customByName(dialect.name) != null) {
      throw ArgumentError.value(
        dialect.name,
        'dialect.name',
        'a dialect of this name exists again',
      );
    }
    _customDialects.insert(index.clamp(0, _customDialects.length), dialect);
    final reactivate = wasActive && _activeName == Dialect.larksRobins.name;
    if (reactivate) _activeName = dialect.name;
    await _persistDialects();
    if (reactivate) await _persistActive();
    notifyListeners();
  }

  /// Drops every dialect's name and wording for the user's figure [id], once
  /// it is deleted (#1023, plan C9): nothing else would ever read them. One
  /// write for the library when any dialect held them, and then the active
  /// dialect's copy too when it is a custom dialect.
  Future<void> forgetUserFigure(String id) async {
    var changed = false;
    for (var i = 0; i < _customDialects.length; i++) {
      final kept = dialectWithoutUserFigure(_customDialects[i], id);
      if (!identical(kept, _customDialects[i])) {
        _customDialects[i] = kept;
        changed = true;
      }
    }
    if (!changed) return;
    await _persistDialects();
    if (customByName(_activeName ?? '') != null) await _persistActive();
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
    _customKey,
    _customDialects.map((d) => d.toJson()).toList(),
  );

  Future<void> _persistActive() async {
    await _settings.set(_activeKey, _activeName);
    // Keep the legacy full-blob key in sync so any reader that still resolves
    // contra's active dialect from [kActiveDialectKey] stays correct.
    if (_keepsLegacyBlob) {
      await _settings.set(kActiveDialectKey, active.toJson());
    }
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

/// One [DialectLibraryController] for each dance form (ADR-006 §9.1, point 1),
/// and the dialect each form is shown in.
///
/// Notifies whenever any form's library does.
class DialectLibraries extends ChangeNotifier {
  DialectLibraries(
    SettingsRepository settings, {
    ProgramRepository? programs,
    DateTime Function()? clock,
  }) : _byForm = {
         for (final form in DanceForm.values)
           form: DialectLibraryController(
             settings,
             programs: programs,
             form: form,
             clock: clock,
           ),
       },
       _borrowed = const {} {
    _join();
  }

  /// [contra]'s library with an empty library of every other form beside
  /// it, on the same settings and programs, for tests and previews that need
  /// only contra's. [contra] stays its creator's to dispose.
  @visibleForTesting
  DialectLibraries.withContra(DialectLibraryController contra)
    : _byForm = {
        for (final form in DanceForm.values)
          form: form == DanceForm.contra
              ? contra
              : DialectLibraryController(
                  contra._settings,
                  programs: contra._programs,
                  form: form,
                  clock: contra._clock,
                ),
      },
      _borrowed = {DanceForm.contra} {
    _join();
  }

  /// Listens to every form's library and lets each see the others' names.
  void _join() {
    for (final library in _byForm.values) {
      library._inOtherForm = (name) => _byForm.values.any(
        (other) =>
            !identical(other, library) &&
            other.customDialects.any((d) => d.name == name),
      );
      library.addListener(notifyListeners);
    }
  }

  final Map<DanceForm, DialectLibraryController> _byForm;

  /// The forms whose library someone else disposes ([withContra]).
  final Set<DanceForm> _borrowed;

  /// [form]'s library.
  DialectLibraryController forForm(DanceForm form) => _byForm[form]!;

  /// Contra's library.
  DialectLibraryController get contra => forForm(DanceForm.contra);

  /// Every form's dialects, presets and custom, each once: what search
  /// enriches from, so a dance is found by any form's words.
  List<Dialect> get all =>
      List.unmodifiable({for (final library in _byForm.values) ...library.all});

  /// Every form's custom dialects, in form order.
  List<Dialect> get allCustomDialects => List.unmodifiable([
    for (final library in _byForm.values) ...library.customDialects,
  ]);

  /// The active dialect of every form.
  DialectsByForm get active => DialectsByForm({
    for (final entry in _byForm.entries) entry.key: entry.value.active,
  });

  /// Loads every form's library. Each loads on its own, so one that fails
  /// leaves the others loaded; the first failure is rethrown once all have
  /// been tried.
  Future<void> load() async {
    Object? firstError;
    StackTrace? firstStack;
    // The first failure is rethrown below, for the caller to log; any later
    // one is logged here, so none goes unseen.
    void failed(Object error, StackTrace stack) {
      if (firstError == null) {
        firstError = error;
        firstStack = stack;
      } else {
        logCaughtError(error, stack, source: 'dialect_libraries.load');
      }
    }

    for (final library in _byForm.values) {
      try {
        await library.load();
      } catch (error, stack) {
        failed(error, stack); // diagnostics: silent — rethrown or logged.
      }
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStack!);
    }
  }

  /// Drops the user's figure [id] from every form's dialects
  /// ([DialectLibraryController.forgetUserFigure]).
  Future<void> forgetUserFigure(String id) async {
    for (final library in _byForm.values) {
      await library.forgetUserFigure(id);
    }
  }

  @override
  void dispose() {
    for (final MapEntry(key: form, value: library) in _byForm.entries) {
      library.removeListener(notifyListeners);
      if (!_borrowed.contains(form)) library.dispose();
    }
    super.dispose();
  }
}
