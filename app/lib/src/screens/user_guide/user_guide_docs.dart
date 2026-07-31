import 'dart:convert' show LineSplitter;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;

import '../../app_metadata.dart';

/// Asset directory holding the bundled user guides (mirrored from `docs/user`
/// by `tools/ci/sync_user_docs.py`). Doc ids are paths relative to this dir.
const String _userDocsAssetDir = 'assets/docs/user';

/// The repo path the bundled guides are mirrored from. Link resolution happens
/// in this virtual space so a guide's relative links behave as they do in-repo.
const String _userDocsRepoDir = 'docs/user';

/// The guide the panel opens on: the documentation hub / table of contents.
const String kUserGuideHomeDoc = 'README.md';

/// Guides that intentionally are **not** bundled into the app — they exist in
/// the repo but aren't user-facing (mirrors `EXCLUDED_GUIDES` in
/// `tools/ci/sync_user_docs.py`; keep the two in sync). An in-app link to one
/// opens the repo copy on GitHub rather than showing a misleading
/// "isn't available yet" message.
const Set<String> kBundleExcludedGuides = {'style-guide.md'};

/// The base ref used when a guide links to a repo file that isn't bundled
/// (e.g. a design doc); such links open on GitHub rather than in the panel.
const String _repoBlobBase = '$kSourceRepoUrl/blob/main';

/// The online home of the user guides on GitHub. Used only as an explicit
/// fallback (on tap) if the bundled copy somehow can't be loaded.
const String kUserGuideOnlineUrl = '$_repoBlobBase/docs/user/README.md';

/// The outcome of resolving a link tapped inside the user guide.
sealed class GuideLink {
  const GuideLink();
}

/// A link to another bundled guide — navigate to it within the panel.
/// [fragment] is the target heading's anchor, if any; the doc view scrolls to
/// the matching heading once the guide is laid out.
class GuideInternalLink extends GuideLink {
  const GuideInternalLink(this.docId, {this.fragment});

  final String docId;
  final String? fragment;
}

/// A link to a guide that isn't bundled yet (a "coming soon" doc). The panel
/// surfaces this gracefully rather than navigating nowhere. [label] is a
/// human-friendly name derived from the target file.
class GuideMissingLink extends GuideLink {
  const GuideMissingLink(this.label);

  final String label;
}

/// A link that leaves the bundled guide set — an external `http(s)` URL, or a
/// repo file that isn't bundled (resolved to its GitHub URL). Opened in the
/// browser via `launchExternalUrl`.
class GuideExternalLink extends GuideLink {
  const GuideExternalLink(this.url);

  final String url;
}

/// Loads and resolves the offline user-guide docs bundled under
/// [`assets/docs/user`]($_userDocsAssetDir).
///
/// The available guides are **discovered** from the asset manifest (not
/// hard-coded), so a new `docs/user/*.md` guide is picked up automatically once
/// bundled. Link targets are resolved in the repo's `docs/` path space so the
/// guides' relative references (`./imports.md`, `../design/dialect.md`,
/// `./README.md#glossary`) behave as authored.
class UserGuideDocs {
  UserGuideDocs._(this._docIds, this._bundle);

  final Set<String> _docIds;
  final AssetBundle _bundle;

  /// Discovers the bundled guides from the asset manifest. [bundle] defaults to
  /// [rootBundle]; tests can inject a bundle.
  static Future<UserGuideDocs> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final prefix = '$_userDocsAssetDir/';
    final ids = <String>{
      for (final key in manifest.listAssets())
        if (key.startsWith(prefix) && key.endsWith('.md'))
          key.substring(prefix.length),
    };
    return UserGuideDocs._(ids, b);
  }

  /// Builds an instance over a fixed set of doc ids for tests that exercise the
  /// pure link/image resolution logic without loading the asset manifest.
  @visibleForTesting
  factory UserGuideDocs.forTest(Set<String> docIds, [AssetBundle? bundle]) =>
      UserGuideDocs._(docIds, bundle ?? rootBundle);

  /// Whether any guides were bundled at all (false only if the bundle is
  /// missing entirely — the panel shows an empty state in that case).
  bool get isEmpty => _docIds.isEmpty;

  /// Whether [docId] is one of the bundled guides.
  bool has(String docId) => _docIds.contains(docId);

  /// The bundled guide ids, sorted for a stable order.
  List<String> get docIds => _docIds.toList()..sort();

  /// Reads the raw Markdown of a bundled guide.
  Future<String> read(String docId) =>
      _bundle.loadString('$_userDocsAssetDir/$docId');

  /// Classifies a link [href] tapped while viewing [fromDocId].
  GuideLink resolveLink(String fromDocId, String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) {
      return GuideInternalLink(fromDocId);
    }

    // Absolute URLs (http/https/mailto/…) leave the panel.
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return GuideExternalLink(trimmed);
    }

    final (path, fragment) = _splitFragment(trimmed);

    // A pure anchor (`#section`) stays on the current guide.
    if (path.isEmpty) {
      return GuideInternalLink(fromDocId, fragment: fragment);
    }

    final resolved = _resolveRepoPath(fromDocId, path);
    final userPrefix = '$_userDocsRepoDir/';
    if (resolved.startsWith(userPrefix) && resolved.endsWith('.md')) {
      final docId = resolved.substring(userPrefix.length);
      if (has(docId)) {
        return GuideInternalLink(docId, fragment: fragment);
      }
      if (kBundleExcludedGuides.contains(docId)) {
        // Deliberately unbundled (e.g. the contributor style guide): it exists
        // in the repo but isn't user-facing, so open the GitHub copy rather
        // than claim it's missing.
        return GuideExternalLink(_repoBlobUrl(resolved, fragment));
      }
      return GuideMissingLink(labelForDoc(docId));
    }

    // A repo file outside the bundled guides (e.g. a design doc): open on
    // GitHub so the link still works, but only when the user taps it.
    return GuideExternalLink(_repoBlobUrl(resolved, fragment));
  }

  /// Builds the GitHub blob URL for a repo-relative [repoPath] (+ optional
  /// [fragment]) — used for links that leave the bundled guide set.
  static String _repoBlobUrl(String repoPath, String? fragment) =>
      fragment == null
      ? '$_repoBlobBase/$repoPath'
      : '$_repoBlobBase/$repoPath#$fragment';

  /// Splits `path#fragment` into its path and (optional) fragment parts.
  static (String, String?) _splitFragment(String href) {
    final hash = href.indexOf('#');
    if (hash < 0) return (href, null);
    final fragment = href.substring(hash + 1);
    return (href.substring(0, hash), fragment.isEmpty ? null : fragment);
  }

  /// Resolves [target] (relative to the guide [fromDocId]) to a normalized repo
  /// path rooted at the repo root, e.g. `docs/user/imports.md` or
  /// `docs/design/wireframes/x.svg`.
  static String _resolveRepoPath(String fromDocId, String target) {
    final full = '$_userDocsRepoDir/$fromDocId';
    final baseDir = full.substring(0, full.lastIndexOf('/'));
    return _normalize('$baseDir/$target');
  }

  /// Normalizes a posix-style path, collapsing `.`/`..` segments.
  static String _normalize(String path) {
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty && segments.last != '..') {
          segments.removeLast();
        } else {
          segments.add(segment);
        }
      } else {
        segments.add(segment);
      }
    }
    return segments.join('/');
  }

  /// The guide's own title: the text of its first level-one (`# …`) heading.
  ///
  /// Guides are authored with exactly one H1 matching the guide's title (see
  /// `docs/user/style-guide.md`), so this is a better panel title than a name
  /// derived from the file name — "FAQ & troubleshooting" rather than "Faq".
  /// Returns `null` when [data] has no H1, so callers can fall back to
  /// [labelForDoc].
  static String? titleFromMarkdown(String data) {
    for (final line in const LineSplitter().convert(data)) {
      final match = _h1Pattern.firstMatch(line);
      if (match != null) {
        final title = match.group(1)!.trim();
        if (title.isNotEmpty) return title;
      }
    }
    return null;
  }

  /// Matches an ATX level-one heading (`# Title`), allowing the up-to-three
  /// leading spaces Markdown permits and an optional closing run of `#`.
  static final RegExp _h1Pattern = RegExp(r'^ {0,3}#\s+(.*?)\s*#*\s*$');

  /// Converts a heading's text to the anchor slug GitHub would generate for it,
  /// so a link like `./collection.md#group-by-category` resolves to the same
  /// heading in the app as it does on GitHub: lower-cased, punctuation dropped,
  /// spaces turned into hyphens.
  static String slugify(String heading) {
    final buffer = StringBuffer();
    for (final rune in heading.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (char == ' ') {
        buffer.write('-');
      } else if (char == '-' || char == '_' || _isAlphanumeric(rune)) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// Whether [rune] is a letter or digit for slug purposes. Deliberately
  /// includes non-ASCII letters (so a translated heading still slugs sensibly)
  /// by treating anything above the ASCII range that isn't punctuation-like as
  /// a letter, matching GitHub's Unicode-aware behaviour closely enough for
  /// the guides' headings.
  static bool _isAlphanumeric(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return true; // 0-9
    if (rune >= 0x61 && rune <= 0x7a) return true; // a-z (already lower-cased)
    if (rune < 0x80) return false;
    // Above ASCII: keep letters and combining marks, drop punctuation, symbols,
    // and separators (em dashes, curly quotes, arrows, …).
    return !_nonWordAboveAscii.hasMatch(String.fromCharCode(rune));
  }

  static final RegExp _nonWordAboveAscii = RegExp(
    r'[\p{P}\p{S}\p{Z}\p{C}]',
    unicode: true,
  );

  /// A human-friendly label for a guide file, e.g. `perform.md` → "Perform",
  /// `backup-portability.md` → "Backup portability". Used for "coming soon"
  /// messaging on not-yet-bundled guides, and as the panel title fallback when
  /// a guide has no H1 for [titleFromMarkdown] to read.
  static String labelForDoc(String docId) {
    final base = docId.split('/').last.replaceAll('.md', '');
    final words = base
        .split(RegExp(r'[-_]'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return base;
    // Sentence case: capitalise only the first word, keep the rest lower-case
    // (e.g. `backup-portability.md` → "Backup portability").
    final first = words.first;
    final head = first[0].toUpperCase() + first.substring(1);
    return [head, ...words.skip(1)].join(' ');
  }
}
