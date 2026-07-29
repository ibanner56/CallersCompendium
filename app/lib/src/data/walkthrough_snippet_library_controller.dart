import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// Persistence key for the JSON blob of the user's personal walkthrough snippet
/// library (#411). A settings key-value blob — like `custom_dialects` — so it
/// needs no schema-versioned table and no `kCompendiumSchemaVersion` bump.
const String kWalkthroughSnippetsKey = 'walkthrough_snippets';

/// Owns the user's personal [WalkthroughSnippetLibrary] — per-figure step
/// descriptions keyed by figure signature — and persists it to the free-form
/// [SettingsRepository]. Mirrors [DialectLibraryController]: every mutation
/// saves immediately and notifies listeners so the editor re-renders live.
///
/// The library is local, user-authored data. All entries are untrusted free
/// text and are soft-clamped by [WalkthroughSnippetLibrary]; rendering to the
/// active dialect happens at display time via `renderFreeText` (no markup).
class WalkthroughSnippetLibraryController extends ChangeNotifier {
  WalkthroughSnippetLibraryController(this._settings);

  final SettingsRepository _settings;

  WalkthroughSnippetLibrary _library = WalkthroughSnippetLibrary.empty;

  /// The current snippet library.
  WalkthroughSnippetLibrary get library => _library;

  /// The snippet stored for [signature], or `null` when there is none.
  String? resolve(String? signature) => _library.resolve(signature);

  /// Loads the persisted library. Safe to call once at startup; malformed data
  /// decodes to an empty (or partial) library rather than throwing.
  Future<void> load() async {
    final raw = await _settings.get(kWalkthroughSnippetsKey);
    if (raw is Map) {
      _library = WalkthroughSnippetLibrary.fromJson(
        raw.cast<String, Object?>(),
      );
    } else {
      _library = WalkthroughSnippetLibrary.empty;
    }
    notifyListeners();
  }

  /// Sets the global default snippet for [signature] to [text] (a blank [text]
  /// removes it). Persists and notifies. No-op when nothing changes.
  Future<void> setSnippet(String signature, String text) async {
    final next = _library.withSnippet(signature, text);
    if (next == _library) return;
    _library = next;
    await _persist();
    notifyListeners();
  }

  /// Removes the global default snippet for [signature]. Persists and notifies.
  Future<void> removeSnippet(String signature) async {
    final next = _library.without(signature);
    if (next == _library) return;
    _library = next;
    await _persist();
    notifyListeners();
  }

  /// Replaces the whole library (used by backup restore). Persists and notifies.
  Future<void> replaceAll(WalkthroughSnippetLibrary library) async {
    if (library == _library) return;
    _library = library;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() =>
      _settings.set(kWalkthroughSnippetsKey, _library.toJson());
}
