import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/callersbox_online.dart';
import '../data/collection_refresh_scope.dart';
import '../data/contradb_online.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/program_ambiguous_review.dart';
import '../data/programs_refresh_scope.dart';
import '../data/plaintext_program_import.dart';
import '../data/program_import_online_resolver.dart';
import '../data/repositories_scope.dart';
import '../utils/undo_snack_bar.dart';
import 'import_review_screen.dart';

/// Builds a [Program] from a pasted, newline-separated list of dance titles
/// (epic #291, sub-issue #312).
///
/// One non-blank line becomes one program slot, in order. Each title is matched
/// case-insensitively against the local collection: an exact single match links
/// to that dance; an unmatched or ambiguous (multi-match) line becomes a
/// free-text note slot — the same note path announcements/breaks use — so
/// nothing is dropped and ordering is preserved.
///
/// The "Resolve unmatched online" action tries The Caller's Box first (#313),
/// then falls back to ContraDB (#943) for any title Caller's Box could not
/// resolve confidently. A title more than one source found several exact-title
/// hits for (and neither source ever resolved confidently) is offered to the
/// user via [ImportReviewScreen] rather than silently degrading to a note —
/// see [_resolveOnline].
///
/// Pushed as a route; pops with the created program's id on success (null if the
/// user backs out), mirroring [ProgramEditorScreen]. Commit shows an undo
/// SnackBar that hard-deletes the just-created program.
class PlaintextProgramImportScreen extends StatefulWidget {
  const PlaintextProgramImportScreen({
    super.key,
    this.callersBoxOnline,
    this.contraDbOnline,
  });

  /// Injectable Caller's Box search + import service seam. Tests supply a
  /// seam-backed instance so resolution never touches the network; defaults to a
  /// network-backed [CallersBoxOnline].
  final CallersBoxOnline? callersBoxOnline;

  /// Injectable ContraDB search + import service seam (issue #943), tried as
  /// the fallback source when Caller's Box does not resolve a title
  /// confidently. Tests supply a seam-backed instance; defaults to a
  /// network-backed [ContraDbOnline].
  final ContraDbOnline? contraDbOnline;

  @override
  State<PlaintextProgramImportScreen> createState() =>
      _PlaintextProgramImportScreenState();
}

class _PlaintextProgramImportScreenState
    extends State<PlaintextProgramImportScreen> {
  late final CompendiumRepositories _repos;
  late final CallersBoxOnline _online;
  late final ContraDbOnline _contraDb;
  bool _started = false;

  final _titleController = TextEditingController();
  final _pasteController = TextEditingController();

  /// Local `(id, title)` listing used for case-insensitive title resolution.
  List<({String id, String title})>? _collection;
  Object? _loadError;

  bool _committing = false;

  /// Set once the "Resolve unmatched online" action has run for the current
  /// paste text: the resolved lines (some unmatched now linked via Caller's Box
  /// or ContraDB) that override the freshly-parsed lines for preview/commit.
  /// Cleared whenever the paste text changes, so edits re-parse from scratch.
  List<ParsedProgramLine>? _resolvedOverride;

  /// Whether an online resolution pass is currently running.
  bool _resolving = false;

  /// Memoized parse of the current paste text, so a single build (which reads
  /// [_parsedLines] from both [_canCommit] and the preview) reparses at most
  /// once. Invalidated when the paste text or the resolved [_collection]
  /// identity changes.
  List<ParsedProgramLine>? _parsedCache;
  String? _parsedCacheText;
  List<({String id, String title})>? _parsedCacheCollection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _online = widget.callersBoxOnline ?? CallersBoxOnline();
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      _titleController.addListener(_onTitleChanged);
      _pasteController.addListener(_onPasteChanged);
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final collection = await _repos.dances.listIdsAndTitles();
      if (!mounted) return;
      setState(() {
        _collection = collection;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _onTitleChanged() => setState(() {});

  /// Editing the pasted titles invalidates any prior online resolution: the
  /// lines must be re-parsed and re-resolved from the new text.
  void _onPasteChanged() => setState(() => _resolvedOverride = null);

  @override
  void dispose() {
    _titleController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  List<ParsedProgramLine> get _parsedLines {
    final collection = _collection;
    if (collection == null) return const [];
    final text = _pasteController.text;
    // Reuse the cached parse unless the paste text or the collection identity
    // changed. `identical` is enough: `_collection` is only ever swapped for a
    // fresh list by `_load`, never mutated in place.
    if (_parsedCache != null &&
        _parsedCacheText == text &&
        identical(_parsedCacheCollection, collection)) {
      return _parsedCache!;
    }
    final parsed = parsePlaintextProgram(text, collection: collection);
    _parsedCache = parsed;
    _parsedCacheText = text;
    _parsedCacheCollection = collection;
    return parsed;
  }

  /// The lines to preview and commit: the online-resolved override when present
  /// (produced by [_resolveOnline]), otherwise the freshly-parsed lines.
  List<ParsedProgramLine> get _effectiveLines =>
      _resolvedOverride ?? _parsedLines;

  /// Whether any line still lacks a resolution the online step could fill.
  bool get _hasUnresolved => _effectiveLines.any(
    (l) => l.resolution == PlaintextLineResolution.unmatched,
  );

  bool get _canCommit =>
      !_committing &&
      !_resolving &&
      _collection != null &&
      _titleController.text.trim().isNotEmpty &&
      _effectiveLines.isNotEmpty;

  Future<void> _resolveOnline() async {
    if (_resolving || _committing) return;
    final before = _effectiveLines;
    if (!before.any((l) => l.resolution == PlaintextLineResolution.unmatched)) {
      return;
    }
    setState(() => _resolving = true);
    List<ParsedProgramLine> resolved;
    try {
      resolved = await resolveUnmatchedOnline(
        before,
        service: _online,
        fallbacks: [_contraDb],
        repos: _repos,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          'Plaintext title-list online resolve failed: $error\n$stackTrace',
        );
      }
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('plaintext-import-resolve-error-snackbar'),
          content: Text(
            AppLocalizations.of(context).importPlaintextSearchError,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    // Issue #943: a title neither source resolved confidently, but at least
    // one found several exact-title hits, is offered to the user via
    // ImportReviewScreen rather than silently degrading straight to a note —
    // mirroring #823's batch-review ruling. Runs before the summary snackbar
    // so its counts reflect whatever the user actually resolved here.
    if (resolved.any((l) => l.onlineCandidates.isNotEmpty)) {
      resolved = await _reviewAmbiguousLines(resolved);
      if (!mounted) return;
    }

    final l10n = AppLocalizations.of(context);
    final linked = resolved.where((l) => l.importedOnline).length;
    // Any dances resolved online are now in the collection (their authors
    // too), so ask the live Collection view to reload (#340).
    if (linked > 0) CollectionRefreshScope.bump(context);
    final remaining = resolved
        .where((l) => l.resolution == PlaintextLineResolution.unmatched)
        .length;
    // Newly imported dances now live in the local collection. Refresh the cached
    // listing so a later paste edit (which clears the override and re-parses
    // against `_collection`) recognizes them as local matches instead of
    // re-searching/re-importing them online.
    if (linked > 0) {
      try {
        final collection = await _repos.dances.listIdsAndTitles();
        if (!mounted) return;
        _collection = collection;
      } on Exception {
        // A refresh failure is non-fatal: the resolved override already links
        // the imported dances for this session.
      }
    }
    setState(() {
      _resolvedOverride = resolved;
      _resolving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('plaintext-import-resolved-snackbar'),
        content: Text(
          linked == 0
              ? l10n.importPlaintextResolvedNone(remaining)
              : l10n.importPlaintextResolvedLinked(linked, remaining),
        ),
      ),
    );
  }

  /// Previews every ambiguous [lines] entry's online candidates and, if any
  /// previewed successfully, pushes [ImportReviewScreen] seeded with them
  /// (issue #943). Returns [lines] with any line the user picked a candidate
  /// for replaced by a fresh `matched` line linking that dance; every other
  /// line (including one whose candidates all failed to preview, or that the
  /// user left at skip) is returned unchanged, still `unmatched`.
  Future<List<ParsedProgramLine>> _reviewAmbiguousLines(
    List<ParsedProgramLine> lines,
  ) async {
    final seed = await buildProgramAmbiguousImport(
      lines,
      servicesBySource: {
        OnlineSource.callersBox: _online,
        OnlineSource.contraDb: _contraDb,
      },
      repos: _repos,
    );
    if (seed == null || !mounted) return lines;
    Map<int, String>? programResults;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportReviewScreen(
          sources: defaultImportSources(),
          programAmbiguousImport: seed,
          onProgramCommitted: (results) => programResults = results,
        ),
      ),
    );
    final results = programResults;
    if (results == null || results.isEmpty) return lines;
    return [
      for (var i = 0; i < lines.length; i++)
        if (results.containsKey(i))
          ParsedProgramLine(
            text: lines[i].text,
            resolution: PlaintextLineResolution.matched,
            danceId: results[i],
            matchCount: 1,
            importedOnline: true,
          )
        else
          lines[i],
    ];
  }

  Future<void> _commit() async {
    if (!_canCommit) return;
    setState(() => _committing = true);
    final lines = _effectiveLines;
    final now = DateTime.now().toUtc();
    final id = uuidV4();
    final program = Program(
      id: id,
      title: _titleController.text.trim(),
      slots: buildProgramSlots(lines, newSlotId: uuidV4),
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _repos.programs.create(program);
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          'Plaintext program import write failed: $error\n$stackTrace',
        );
      }
      setState(() => _committing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('plaintext-import-error-snackbar'),
          content: Text(AppLocalizations.of(context).importProgramCreateError),
        ),
      );
      return;
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final matched = lines
        .where((l) => l.resolution == PlaintextLineResolution.matched)
        .length;
    final notes = lines.length - matched;
    // The program itself is new, so every program view is stale — including on
    // a phone, where the Programs list had no refresh channel at all before
    // issue #768. Undo hard-deletes it again, so that broadcasts too.
    final programsRefresh = ProgramsRefreshScope.notifierOf(context);
    programsRefresh?.value++;
    showUndoSnackBar(
      messenger,
      key: const ValueKey('plaintext-import-committed-snackbar'),
      message: l10n.importProgramCommitted(
        program.title,
        lines.length,
        matched,
        notes,
      ),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        await _repos.programs.hardDelete([id]);
        programsRefresh?.value++;
      },
    );
    navigator.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.importTitleListTitle),
        actions: [
          TextButton(
            key: const ValueKey('plaintext-import-commit'),
            onPressed: _canCommit ? _commit : null,
            child: Text(l10n.importAction),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(l10n.importCollectionLoadError),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                setState(() {
                  _collection = null;
                  _loadError = null;
                });
                _load();
              },
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('plaintext-import-title'),
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.importProgramTitleLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('plaintext-import-paste'),
              controller: _pasteController,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: l10n.importTitleListDancesLabel,
                hintText: l10n.importTitleListDancesHint,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildPreview()),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final l10n = AppLocalizations.of(context);
    if (_collection == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final lines = _effectiveLines;
    if (lines.isEmpty) {
      return Center(
        key: const ValueKey('plaintext-import-empty-preview'),
        child: Text(
          l10n.importTitleListEmptyHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.importPlaintextSlotCount(lines.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_hasUnresolved)
                TextButton.icon(
                  key: const ValueKey('plaintext-import-resolve-online'),
                  onPressed: _resolving ? null : _resolveOnline,
                  icon: _resolving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore, size: 18),
                  label: Text(
                    _resolving
                        ? l10n.importResolving
                        : l10n.importResolveOnline,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            key: const ValueKey('plaintext-import-preview'),
            itemCount: lines.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _previewTile(lines[index], index),
          ),
        ),
      ],
    );
  }

  Widget _previewTile(ParsedProgramLine line, int index) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (
      IconData icon,
      Color color,
      String label,
    ) = switch (line.resolution) {
      PlaintextLineResolution.matched =>
        line.importedOnline
            ? (
                Icons.cloud_download_outlined,
                scheme.primary,
                l10n.importPlaintextImportedOnline,
              )
            : (Icons.link, scheme.primary, l10n.importPlaintextLinked),
      PlaintextLineResolution.ambiguous => (
        Icons.help_outline,
        scheme.tertiary,
        l10n.importPlaintextAmbiguous,
      ),
      PlaintextLineResolution.unmatched => (
        Icons.sticky_note_2_outlined,
        scheme.outline,
        l10n.importPlaintextUnmatched,
      ),
    };
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 12,
        child: Text(
          '${index + 1}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
      title: Text(line.text),
      subtitle: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
