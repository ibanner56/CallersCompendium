import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/callersbox_online.dart';
import '../data/contradb_online.dart';
import '../data/contradb_program_import.dart';
import '../data/contradb_program_search.dart';
import '../data/date_format_scope.dart';
import '../data/display_defaults.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/program_title_date.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../utils/undo_snack_bar.dart';

/// How the user is choosing which ContraDB program to import.
enum _ImportMode {
  /// Paste a `contradb.com/programs/N` URL or a bare id (the original flow).
  url,

  /// Search the public program index by name and pick a match (#342).
  search,
}

/// Builds a [Program] from a **ContraDB program (set list)** page
/// (epic #291, sub-issue #314).
///
/// The user pastes a `contradb.com/programs/N` URL (or a bare id). The page is
/// fetched once, parsed into ordered activities ([parseContraDbProgram]), and
/// previewed. On import each linked dance is resolved **identity-first** — the
/// specific ContraDB dance is scraped + imported via its `/dances/{id}`
/// ([ContraDbOnline]); a scrape failure falls back to The Caller's Box by title
/// (#313), and anything still unresolved becomes a verbatim note slot (#312).
/// Standalone note activities (announcements/waltz/break) are kept verbatim and
/// never searched. Slot order matches the program exactly.
///
/// Pushed as a route; pops with the created program's id on success (null if the
/// user backs out), mirroring [PlaintextProgramImportScreen]. Commit shows an
/// undo SnackBar that hard-deletes the just-created program.
class ContraDbProgramImportScreen extends StatefulWidget {
  const ContraDbProgramImportScreen({
    super.key,
    this.programFetcher,
    this.contraDbOnline,
    this.callersBoxOnline,
    this.programSearch,
    this.initialUrl,
  });

  /// Injectable fetcher for the program page HTML; tests supply a seam-backed
  /// fetcher so nothing touches the network. Defaults to [fetchImportUrl].
  final UrlFetcher? programFetcher;

  /// Injectable ContraDB identity import seam (per-dance scrape). Defaults to a
  /// network-backed [ContraDbOnline].
  final ContraDbOnline? contraDbOnline;

  /// Injectable Caller's Box fallback seam. Defaults to a network-backed
  /// [CallersBoxOnline].
  final CallersBoxOnline? callersBoxOnline;

  /// Injectable program-index search seam (fetch + parse + client-side filter).
  /// Defaults to a network-backed [ContraDbProgramSearch].
  final ContraDbProgramSearch? programSearch;

  /// A ContraDB program URL to pre-fill and fetch automatically on first frame
  /// (issue #343: the screen was opened by a URL shared from a browser via the
  /// OS share sheet / an `ACTION_SEND` intent). When non-null the URL field is
  /// seeded and [_fetchProgram] runs once, dropping the user straight onto the
  /// preview to review before committing. Null for the normal manual flow.
  ///
  /// The caller (`main.dart`) has already OWASP-validated this URL through
  /// `validateSharedContraDbProgramUrl`; it is a canonical
  /// `https://contradb.com/programs/N` string.
  final String? initialUrl;

  @override
  State<ContraDbProgramImportScreen> createState() =>
      _ContraDbProgramImportScreenState();
}

class _ContraDbProgramImportScreenState
    extends State<ContraDbProgramImportScreen> {
  late final CompendiumRepositories _repos;
  late final UrlFetcher _fetch;
  late final ContraDbOnline _contraDb;
  late final CallersBoxOnline _callersBox;
  late final ContraDbProgramSearch _search;
  bool _started = false;

  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  final _searchController = TextEditingController();

  /// Which entry method is active (paste a URL vs. search by name).
  _ImportMode _mode = _ImportMode.url;

  /// The full parsed program index (loaded lazily on first entering search
  /// mode); [_searchResults] is the current name-filtered view of it.
  List<ContraDbProgramIndexEntry> _allEntries = const [];
  List<ContraDbProgramIndexEntry> _searchResults = const [];
  bool _indexLoading = false;
  Object? _searchError;

  /// The most recently fetched + parsed program (null before the first fetch).
  ContraDbProgram? _program;

  /// Event date auto-detected from the fetched program title (issue #351),
  /// editable/clearable in the preview before commit. Null when nothing was
  /// detected or the user cleared it.
  DateTime? _eventDate;

  /// Whether [_eventDate]'s current value came from title auto-detection (drives
  /// the "detected from title" hint). Cleared once the user edits/clears it.
  bool _dateAutoDetected = false;

  bool _fetching = false;
  bool _committing = false;

  /// Whether the most recent fetch attempt failed (drives the error UI).
  bool _fetchFailed = false;

  /// A safe-to-show, localized detail for a fetch failure. Only ever the
  /// localized message for a curated [UrlFetchException] (scheme/redirect/size
  /// guards, etc.); it is null when the failure was an unexpected exception,
  /// whose raw text is logged (debug only) but never shown so no internals leak
  /// to the UI (CWE-209).
  String? _fetchErrorDetail;

  /// Index of the local collection used to mark which ContraDB programs have
  /// already been imported (issue #586). Loaded once from the program
  /// repository; `null` until loaded, in which case rows simply show no marker
  /// (the hint degrades to absent, never an error).
  ProgramImportMarkerIndex? _markerIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _fetch = widget.programFetcher ?? fetchImportUrl;
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
      _search = widget.programSearch ?? ContraDbProgramSearch();
      _titleController.addListener(() => setState(() {}));
      _loadMarkerIndex();

      // Opened from a shared URL (issue #343): pre-fill and fetch once, so the
      // user lands on the preview to review before committing. Deferred to the
      // first frame so the fetch's setState runs after the initial build.
      final initialUrl = widget.initialUrl;
      if (initialUrl != null && initialUrl.trim().isNotEmpty) {
        _urlController.text = initialUrl.trim();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fetchProgram();
        });
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _canFetch => !_fetching && !_committing;

  bool get _canCommit =>
      !_committing &&
      !_fetching &&
      _program != null &&
      _program!.activities.isNotEmpty &&
      _titleController.text.trim().isNotEmpty;

  Future<void> _fetchProgram() async {
    if (!_canFetch) return;
    setState(() {
      _fetching = true;
      _fetchFailed = false;
      _fetchErrorDetail = null;
    });
    try {
      final url = buildContraDbProgramUrl(_urlController.text);
      final html = await _fetch(url);
      final program = parseContraDbProgram(html);
      if (!mounted) return;
      final datePref = DateFormatScope.of(context);
      setState(() {
        _program = program;
        _fetching = false;
        // Pre-fill an empty title from the program page (editable).
        if (_titleController.text.trim().isEmpty && program.title.isNotEmpty) {
          _titleController.text = program.title;
        }
        // Best-effort, high-confidence event-date detection from the title
        // (#351). Only overwrites when nothing has been set/edited yet, so a
        // re-fetch never clobbers a date the user already picked.
        if (_eventDate == null) {
          final detected = detectEventDateFromTitle(
            _titleController.text,
            datePref,
          );
          if (detected != null) {
            _eventDate = detected;
            _dateAutoDetected = true;
          }
        }
      });
      if (program.activities.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const ValueKey('contradb-program-empty-snackbar'),
            content: Text(
              AppLocalizations.of(context).importContraDbEmptyProgram,
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      // Log the raw error for debugging/support (debug builds only, so nothing
      // leaks to release logs — CWE-532), but only surface a curated, localized
      // UrlFetchException message to the UI — never an arbitrary caught
      // exception, which could leak internals (CWE-209).
      if (kDebugMode) {
        debugPrint('ContraDB program fetch failed: $error\n$stackTrace');
      }
      // Mirrors the CWE-209 policy just above: UrlFetchException is log-safe
      // by construction (typed reason only, never raw prose), but any other
      // caught type here is exactly the "arbitrary caught exception" the
      // comment above refuses to surface to the UI, so it isn't logged
      // verbatim either — only its shape (issue #963).
      if (error is UrlFetchException) {
        logCaughtError(
          error,
          stackTrace,
          source: 'contradb_program_import_screen._fetchProgram',
        );
      } else {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'contradb_program_import_screen._fetchProgram',
        );
      }
      setState(() {
        _fetching = false;
        _fetchFailed = true;
        _fetchErrorDetail = error is UrlFetchException
            ? importErrorMessage(l10n, error)
            : null;
      });
    }
  }

  /// Switches entry mode. Entering search mode lazily loads the index once and
  /// clears any previously-fetched program so the results UI is reachable (a
  /// program fetched via the URL flow must not keep hiding the results list).
  void _onModeChanged(_ImportMode mode) {
    setState(() {
      _mode = mode;
      if (mode == _ImportMode.search) {
        _program = null;
        _fetchFailed = false;
        _fetchErrorDetail = null;
      }
    });
    if (mode == _ImportMode.search &&
        !_search.isLoaded &&
        !_indexLoading &&
        _searchError == null) {
      _loadIndex();
    }
  }

  Future<void> _loadMarkerIndex() async {
    try {
      final programs = await _repos.programs.listAll();
      if (!mounted) return;
      setState(() {
        _markerIndex = ProgramImportMarkerIndex(
          programs.map(
            (p) => ProgramImportMarkerEntry(
              title: p.title,
              source: p.provenance?.source,
              externalId: p.provenance?.externalId,
              importedAt: p.provenance?.importedAt,
            ),
          ),
        );
      });
    } catch (_) {
      // diagnostics: silent — the marker is a best-effort hint; if the
      // collection can't be read we simply show no markers rather than
      // surfacing an error.
    }
  }

  /// The already-imported marker for a ContraDB program [id]/[name], or a
  /// [ProgramImportMarker.none] when the index hasn't loaded yet.
  ProgramImportMarker _markerFor(String id, String name) =>
      _markerIndex?.markerFor(id, name) ?? ProgramImportMarker.none;

  Future<void> _loadIndex() async {
    setState(() {
      _indexLoading = true;
      _searchError = null;
    });
    try {
      final entries = await _search.loadIndex();
      if (!mounted) return;
      setState(() {
        _allEntries = entries;
        _indexLoading = false;
        _searchResults = filterProgramIndex(entries, _searchController.text);
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      logCaughtError(
        error,
        stackTrace,
        source: 'contradb_program_import_screen._loadIndex',
      );
      setState(() {
        _indexLoading = false;
        _searchError = error;
      });
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      // Editing the query returns to the results list even after a program was
      // picked + previewed, so the user can refine and choose a different one.
      _program = null;
      _fetchFailed = false;
      _fetchErrorDetail = null;
      _searchResults = filterProgramIndex(_allEntries, query);
    });
  }

  /// Picks a searched program: feeds its id into the existing URL fetch flow so
  /// the whole import pipeline (build URL → fetch → parse → resolve → commit) is
  /// reused unchanged.
  void _selectResult(ContraDbProgramIndexEntry entry) {
    _urlController.text = entry.id;
    _fetchProgram();
  }

  Future<void> _commit() async {
    if (!_canCommit) return;
    setState(() => _committing = true);
    final now = DateTime.now().toUtc();

    final List<ResolvedContraDbActivity> resolved;
    try {
      resolved = await resolveContraDbProgram(
        _program!,
        contraDb: _contraDb,
        callersBox: _callersBox,
        repos: _repos,
        now: now,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('ContraDB program resolve failed: $error\n$stackTrace');
      }
      logCaughtError(
        error,
        stackTrace,
        source: 'contradb_program_import_screen._commit.resolve',
      );
      setState(() => _committing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('contradb-program-resolve-error-snackbar'),
          content: Text(
            AppLocalizations.of(context).importContraDbResolveError,
          ),
        ),
      );
      return;
    }

    final id = uuidV4();
    final slots = buildContraDbProgramSlots(resolved, newSlotId: uuidV4);
    final caller = await _resolveCaller(_program!.contributor);
    // Capture ContraDB provenance so a later re-import of the same program can be
    // recognised (issue #586). The external id is the canonical numeric
    // /programs/N id derived defensively from the user's input; when it can't be
    // extracted, provenance is simply omitted (the program still imports, and
    // later detection degrades to a title-only "possibly imported" hint).
    final programId = contraDbProgramIdFromInput(_urlController.text);
    final program = Program(
      id: id,
      title: _titleController.text.trim(),
      eventDate: _eventDate,
      caller: caller,
      slots: slots,
      createdAt: now,
      updatedAt: now,
      provenance: programId == null
          ? null
          : Provenance(
              source: ProvenanceSource.contradb,
              externalId: programId,
              importedAt: now,
            ),
    );

    try {
      await _repos.programs.create(program);
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('ContraDB program import write failed: $error\n$stackTrace');
      }
      logCaughtError(
        error,
        stackTrace,
        source: 'contradb_program_import_screen._commit.write',
      );
      setState(() => _committing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('contradb-program-error-snackbar'),
          content: Text(AppLocalizations.of(context).importProgramCreateError),
        ),
      );
      return;
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final linked = resolved.where((a) => a.isLinked).length;
    final notes = slots.length - linked;
    // The program itself is new, and Undo hard-deletes it again. Neither needs
    // a broadcast: every program view watches `programs` directly (issue #768),
    // which is also what finally gave the phone Programs list a refresh path —
    // it had no channel at all before.
    showUndoSnackBar(
      messenger,
      key: const ValueKey('contradb-program-committed-snackbar'),
      message: l10n.importProgramCommitted(
        program.title,
        slots.length,
        linked,
        notes,
      ),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        await _repos.programs.hardDelete([id]);
      },
    );
    navigator.pop(id);
  }

  /// Maximum caller length accepted from a scraped contributor. Defense-in-depth
  /// on top of the core parser's own cap so an unexpectedly large value can
  /// never reach the stored program.
  static const int _kMaxCallerLength = 100;

  /// Resolves the imported program's caller with the ratified precedence
  /// (#350/#351): the ContraDB **contributor** when present → else the user's
  /// **default caller** (`kDefaultProgramCallerKey`, the same setting the manual
  /// new-program path prefills) → else null (blank).
  ///
  /// The contributor is untrusted scraped text: it is trimmed, collapsed, and
  /// length-bounded here (the core parser already sanitizes it too) and an
  /// empty/oversized value is ignored so we fall through to the default.
  Future<String?> _resolveCaller(String? contributor) async {
    final fromContributor = _sanitizeCaller(contributor);
    if (fromContributor != null) return fromContributor;
    try {
      final stored = await _repos.settings.get(kDefaultProgramCallerKey);
      final value = stored is String ? stored.trim() : '';
      if (value.isNotEmpty) return value;
    } catch (_) {
      // diagnostics: silent — unreadable/corrupt default; leave the caller
      // blank.
    }
    return null;
  }

  String? _sanitizeCaller(String? raw) {
    if (raw == null) return null;
    final cleaned = raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty || cleaned.length > _kMaxCallerLength) return null;
    return cleaned;
  }

  /// Opens the date picker to edit the (possibly auto-detected) event date. A
  /// manual pick clears the "detected from title" hint since it's now the
  /// user's own value. The range is wide enough to cover historical programs.
  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final stored = _eventDate;
    final initial = stored == null
        ? now
        : DateTime(stored.year, stored.month, stored.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        _eventDate = DateTime.utc(picked.year, picked.month, picked.day);
        _dateAutoDetected = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.importContraDbTitle),
        actions: [
          TextButton(
            key: const ValueKey('contradb-program-commit'),
            onPressed: _canCommit ? _commit : null,
            child: _committing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.importAction),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_ImportMode>(
                key: const ValueKey('contradb-program-mode'),
                segments: [
                  ButtonSegment(
                    value: _ImportMode.url,
                    icon: const Icon(Icons.link),
                    label: Text(l10n.importContraDbPasteUrl),
                  ),
                  ButtonSegment(
                    value: _ImportMode.search,
                    icon: const Icon(Icons.search),
                    label: Text(l10n.importContraDbSearchByName),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _canFetch
                    ? (selection) => _onModeChanged(selection.first)
                    : null,
              ),
              const SizedBox(height: 12),
              if (_mode == _ImportMode.url)
                ..._urlEntry()
              else
                ..._searchEntry(),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('contradb-program-title'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: l10n.importProgramTitleLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _urlEntry() {
    final l10n = AppLocalizations.of(context);
    return [
      TextField(
        key: const ValueKey('contradb-program-url'),
        controller: _urlController,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _fetchProgram(),
        decoration: InputDecoration(
          labelText: l10n.importContraDbUrlLabel,
          hintText: l10n.importContraDbUrlHint,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('contradb-program-fetch'),
        onPressed: _canFetch ? _fetchProgram : null,
        icon: _fetching
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_outlined),
        label: Text(
          _fetching ? l10n.importContraDbFetching : l10n.importContraDbFetch,
        ),
      ),
    ];
  }

  List<Widget> _searchEntry() {
    final l10n = AppLocalizations.of(context);
    return [
      TextField(
        key: const ValueKey('contradb-program-search-field'),
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          labelText: l10n.importContraDbSearchLabel,
          hintText: l10n.importContraDbSearchHint,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
        ),
      ),
    ];
  }

  /// Below the entry fields: the search results (search mode, before a program
  /// is fetched) or the fetched-program preview.
  Widget _buildBody() {
    if (_mode == _ImportMode.search && _program == null) {
      return _buildSearchResults();
    }
    return _buildPreview();
  }

  /// Builds the subtle two-tier "already imported?" badge for a ContraDB program
  /// row (issue #586), or `null` for [ProgramImportMarkerKind.none]. Colour is
  /// never the sole signal: each badge pairs an icon **and** a text label, and
  /// carries a tooltip + [Semantics] label (WCAG 1.4.1). The badge is a hint
  /// only and never blocks re-import.
  Widget? _buildMarkerBadge(ProgramImportMarker marker) {
    if (marker.isNone) return null;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final IconData icon;
    final Color color;
    final String label;
    final String tooltip;
    final String badgeKey;
    if (marker.isImported) {
      icon = Icons.check_circle;
      color = scheme.primary;
      label = l10n.importContraDbMarkerImported;
      final importedAt = marker.importedAt;
      tooltip = importedAt == null
          ? l10n.importContraDbMarkerImportedTooltipNoDate
          : l10n.importContraDbMarkerImportedTooltip(
              formatEventDate(
                importedAt,
                DateFormatScope.of(context),
                MaterialLocalizations.of(context),
                l10n,
              ),
            );
      badgeKey = 'contradb-program-marker-imported';
    } else {
      icon = Icons.help_outline;
      color = scheme.tertiary;
      label = l10n.importContraDbMarkerPossible;
      tooltip = l10n.importContraDbMarkerPossibleTooltip;
      badgeKey = 'contradb-program-marker-possible';
    }

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        excludeSemantics: true,
        child: Row(
          key: ValueKey(badgeKey),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final l10n = AppLocalizations.of(context);
    if (_indexLoading) {
      return const Center(
        key: ValueKey('contradb-program-search-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_searchError != null) {
      return Center(
        key: const ValueKey('contradb-program-search-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(l10n.importContraDbListError, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('contradb-program-search-retry'),
              onPressed: _loadIndex,
              child: Text(l10n.commonTryAgain),
            ),
          ],
        ),
      );
    }
    if (_searchController.text.trim().isEmpty) {
      return Center(
        key: const ValueKey('contradb-program-search-prompt'),
        child: Text(
          l10n.importContraDbSearchPrompt,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        key: const ValueKey('contradb-program-search-empty'),
        child: Text(l10n.importContraDbNoMatches),
      );
    }
    return ListView.separated(
      key: const ValueKey('contradb-program-search-results'),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _searchResults[index];
        final marker = _markerFor(entry.id, entry.name);
        final badge = _buildMarkerBadge(marker);
        return ListTile(
          dense: true,
          title: Text(entry.name),
          subtitle: badge == null
              ? Text('contradb.com/programs/${entry.id}') // i18n-ignore
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('contradb.com/programs/${entry.id}'), // i18n-ignore
                    const SizedBox(height: 4),
                    badge,
                  ],
                ),
          trailing: const Icon(Icons.download_outlined, size: 18),
          onTap: _canFetch ? () => _selectResult(entry) : null,
        );
      },
    );
  }

  Widget _buildPreview() {
    final l10n = AppLocalizations.of(context);
    if (_fetchFailed) {
      final detail = _fetchErrorDetail;
      return Center(
        key: const ValueKey('contradb-program-fetch-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(
              detail != null
                  ? l10n.importContraDbFetchError(detail)
                  : l10n.importContraDbFetchGenericError,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final program = _program;
    if (program == null) {
      return Center(
        key: const ValueKey('contradb-program-empty-preview'),
        child: Text(
          l10n.importContraDbPastePrompt,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }

    final activities = program.activities;
    if (activities.isEmpty) {
      return Center(child: Text(l10n.importContraDbEmptyProgram));
    }
    final danceCount = activities.where((a) => a.isDance).length;
    final noteCount = activities.length - danceCount;
    final marker = _markerFor(
      contraDbProgramIdFromInput(_urlController.text) ?? '',
      program.title,
    );
    final markerBadge = _buildMarkerBadge(marker);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (markerBadge != null)
          Padding(
            key: const ValueKey('contradb-program-preview-marker'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(alignment: Alignment.centerLeft, child: markerBadge),
          ),
        _buildEventDateRow(),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.importContraDbActivityCount(
              activities.length,
              danceCount,
              noteCount,
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.separated(
            key: const ValueKey('contradb-program-preview'),
            itemCount: activities.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _previewTile(activities[index], index),
          ),
        ),
      ],
    );
  }

  /// The editable event-date row shown above the activity preview. Displays the
  /// (possibly auto-detected) date with edit + clear controls, plus a
  /// transparent "detected from title" hint when the value came from #351's
  /// auto-detection so a wrong guess is obvious and cheap to correct.
  Widget _buildEventDateRow() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dateLabel = _eventDate == null
        ? l10n.importEventDateNone
        : formatEventDate(
            _eventDate!,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
            l10n,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.importEventDateLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dateLabel,
                  key: const ValueKey('contradb-program-event-date'),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('contradb-program-pick-date'),
                onPressed: _pickEventDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  _eventDate == null
                      ? l10n.importEventDateSet
                      : l10n.commonChange,
                ),
              ),
              if (_eventDate != null)
                IconButton(
                  key: const ValueKey('contradb-program-clear-date'),
                  tooltip: l10n.importEventDateClear,
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _eventDate = null;
                    _dateAutoDetected = false;
                  }),
                ),
            ],
          ),
        ),
        if (_dateAutoDetected && _eventDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              key: const ValueKey('contradb-program-date-detected-hint'),
              children: [
                Icon(Icons.auto_awesome, size: 14, color: scheme.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.importEventDateDetected,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _previewTile(ContraDbProgramActivity activity, int index) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (
      IconData icon,
      Color color,
      String primary,
      String? secondary,
    ) = activity.isDance
        ? (
            Icons.link,
            scheme.primary,
            activity.title ?? l10n.importContraDbDanceFallback,
            activity.text,
          )
        : (
            Icons.sticky_note_2_outlined,
            scheme.outline,
            activity.text ?? '',
            null,
          );
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 12,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          '${index + 1}',
          style: TextStyle(fontSize: 11, color: color),
        ),
      ),
      title: Text(primary),
      subtitle: secondary != null ? Text(secondary) : null,
      trailing: Icon(icon, size: 18, color: color),
    );
  }
}
