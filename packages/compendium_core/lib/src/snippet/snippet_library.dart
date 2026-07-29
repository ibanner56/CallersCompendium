import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/figure.dart';

/// Upper bound on the number of distinct entries a [WalkthroughSnippetLibrary]
/// may hold (#411). The library is personal and user-authored — a few dozen to a
/// few hundred figure signatures in practice — so this generous cap exists only
/// to bound a hostile/oversized import (memory / render-time DoS). Enforcement
/// is **soft**: [WalkthroughSnippetLibrary.fromJson] keeps the first
/// [kMaxSnippetLibraryEntries] entries (in sorted-key order, deterministically)
/// and drops the rest rather than throwing.
const int kMaxSnippetLibraryEntries = 2000;

const MapEquality<String, String> _mapEq = MapEquality<String, String>();

/// The user's personal, locally-authored **walkthrough snippet library** (#411):
/// a map of figure signature (see `figureSnippetSignature`) → the preferred
/// step-description text for that figure. Immutable value object; mutations
/// return a new instance.
///
/// The stored text is untrusted free text (it round-trips through backup /
/// share / import), so every entry is soft-clamped to
/// [kMaxWalkthroughSnippetLength] and blank entries are dropped. Rendering is
/// always via the dialect renderer's `renderFreeText` at display time — the
/// library never stores or emits markup.
@immutable
class WalkthroughSnippetLibrary {
  WalkthroughSnippetLibrary(Map<String, String> snippets)
    : _snippets = Map.unmodifiable(_normalize(snippets));

  /// An empty library (no snippets).
  static final WalkthroughSnippetLibrary empty = WalkthroughSnippetLibrary(
    const {},
  );

  final Map<String, String> _snippets;

  /// Read-only view of all snippets, keyed by figure signature.
  Map<String, String> get snippets => _snippets;

  /// Number of stored snippets.
  int get length => _snippets.length;

  bool get isEmpty => _snippets.isEmpty;
  bool get isNotEmpty => _snippets.isNotEmpty;

  /// The stored snippet for [signature], or `null` when there is none (or
  /// [signature] itself is `null`, e.g. a custom figure).
  String? resolve(String? signature) =>
      signature == null ? null : _snippets[signature];

  bool contains(String signature) => _snippets.containsKey(signature);

  /// Returns a copy with [signature] set to [text] (soft-clamped). A blank
  /// [text] REMOVES the entry. A new signature that would exceed
  /// [kMaxSnippetLibraryEntries] is ignored (the library is returned unchanged),
  /// so growth is bounded; updating an existing key is always allowed.
  WalkthroughSnippetLibrary withSnippet(String signature, String text) {
    final clamped = _clamp(text);
    final next = Map<String, String>.of(_snippets);
    if (clamped.trim().isEmpty) {
      next.remove(signature);
    } else {
      if (!next.containsKey(signature) &&
          next.length >= kMaxSnippetLibraryEntries) {
        return this;
      }
      next[signature] = clamped;
    }
    if (_mapEq.equals(next, _snippets)) return this;
    return WalkthroughSnippetLibrary(next);
  }

  /// Returns a copy without the entry for [signature].
  WalkthroughSnippetLibrary without(String signature) {
    if (!_snippets.containsKey(signature)) return this;
    final next = Map<String, String>.of(_snippets)..remove(signature);
    return WalkthroughSnippetLibrary(next);
  }

  /// Serializes to `{'snippets': {signature: text, …}}`.
  Map<String, Object?> toJson() => {
    'snippets': Map<String, String>.of(_snippets),
  };

  /// Reconstructs a library from [toJson] output. Tolerant: a missing/typewrong
  /// `snippets` section yields an empty library; non-string values are skipped;
  /// each value is soft-clamped and blank entries dropped; and no more than
  /// [kMaxSnippetLibraryEntries] entries are kept (first in sorted-key order).
  static WalkthroughSnippetLibrary fromJson(Map<String, Object?> json) {
    final raw = json['snippets'];
    if (raw is! Map) return empty;
    final collected = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! String) continue;
      final clamped = _clamp(value);
      if (clamped.trim().isEmpty) continue;
      collected[entry.key.toString()] = clamped;
    }
    if (collected.length <= kMaxSnippetLibraryEntries) {
      return WalkthroughSnippetLibrary(collected);
    }
    final keys = collected.keys.toList()..sort();
    final capped = <String, String>{
      for (final k in keys.take(kMaxSnippetLibraryEntries)) k: collected[k]!,
    };
    return WalkthroughSnippetLibrary(capped);
  }

  static Map<String, String> _normalize(Map<String, String> input) {
    final out = <String, String>{};
    for (final entry in input.entries) {
      final clamped = _clamp(entry.value);
      if (clamped.trim().isEmpty) continue;
      out[entry.key] = clamped;
    }
    return out;
  }

  static String _clamp(String text) =>
      text.length <= kMaxWalkthroughSnippetLength
      ? text
      : text.substring(0, kMaxWalkthroughSnippetLength);

  @override
  bool operator ==(Object other) =>
      other is WalkthroughSnippetLibrary &&
      _mapEq.equals(other._snippets, _snippets);

  @override
  int get hashCode => _mapEq.hash(_snippets);
}
