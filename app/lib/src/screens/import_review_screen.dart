import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/callersbox_online.dart';
import '../data/import_diagnostic_labels.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/program_ambiguous_review.dart';
import '../data/repositories_scope.dart';
import '../data/active_dialect_scope.dart';
import '../data/shorthand_mappings_scope.dart';
import '../data/title_list_import.dart';
import '../data/venue_entity_mode_scope.dart';
import '../diagnostics/error_log.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/figure_diff_view.dart';
import 'dance_editor_screen.dart';
import 'import_shorthand_seed_screen.dart';
import 'published_collection_catalog_screen.dart';
import '../published_collections/published_collection_manifest.dart';
import '../published_collections/published_collection_service.dart';

/// Soft threshold (issue #432) on the number of entities in a **shared** bundle
/// (dances + choreographers + programs + venues, via
/// [compendiumArchiveEntityCount]). At or below this the review proceeds
/// silently; above it the review screen shows an advisory warning — but the
/// import can still be completed. It is deliberately a soft cap, not a block: a
/// user may legitimately share a large collection, and the real protection is
/// that nothing commits without the review/consent step.
const int kSharedBundleSoftCapEntities = 500;

/// A shared [CompendiumArchive] bundle that has already been decoded and
/// validated Dart-side by `ArchiveIntakeService` (size cap, UTF-8, well-formed
/// archive, schema-forward refusal) and is ready to be reviewed and — only on
/// the user's confirmation — committed through [CompendiumArchiveImporter].
///
/// Handed to [ImportReviewScreen] so the OS share target reuses the exact same
/// review/consent UI as the manual import flows (issue #432): nothing is written
/// until the user confirms on the review screen.
@immutable
class SharedBundleImport {
  const SharedBundleImport({
    required this.json,
    required this.archive,
    required this.entityCount,
  });

  /// The raw, validated archive JSON the dance side is planned from.
  final String json;

  /// The decoded archive; its programs and venues are committed alongside the
  /// dances by [CompendiumArchiveImporter] once the user confirms.
  final CompendiumArchive archive;

  /// Total entities the bundle would write, computed pre-render from the
  /// validated decode. Drives the soft-cap warning (see
  /// [kSharedBundleSoftCapEntities]).
  final int entityCount;
}

/// A verified published archive seeded directly into the review flow. The
/// archive bytes were authenticated by the catalog service; this class only
/// carries the decoded text and manifest-authoritative metadata to planning.
@immutable
class PublishedCollectionSeed {
  const PublishedCollectionSeed({required this.json, required this.metadata});

  final String json;
  final PublishedCollectionMetadata metadata;
}

/// The adapter-agnostic in-app import experience (ROADMAP 6.3): pick or paste a
/// source payload, [ImportPipeline.plan] it non-destructively, review every
/// discovered record (with its parse quality, issues, and dedupe verdict),
/// resolve any ambiguous matches, commit, and offer an undo.
///
/// The screen takes a list of selectable [ImportSource]s so it is not tied to
/// any one source; this wires a pasted list of dance titles ("a list of titles",
/// issue #823), the [CallersBoxAdapter] ("The Caller's Box", the source selected
/// on open), the [ContraDbHtmlAdapter] ("ContraDB"), the generic
/// [GenericJsonAdapter] ("Caller's Compendium JSON"), and the byte-based
/// [CallersCompanionUsrAdapter] ("a Caller's Companion .USR file"). The `.USR`
/// source picks a binary file (bytes, not text) and — uniquely — commits and
/// undoes **programs** alongside dances via [CallersCompanionUsrImporter]; every
/// other source is dance-only. The title-list source is the only one whose
/// payload is typed rather than picked or fetched, and the only one that plans
/// through [resolveTitleList] instead of an adapter — but it still commits
/// through the same review/consent step as everything else, so nothing it
/// resolves is written until the user confirms. The user picks the source
/// explicitly (a dropdown) so a bare id — which has no host to auto-detect —
/// routes unambiguously. A fresh adapter is built per plan because adapters may
/// hold per-discovery state.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.sources,
    this.picker,
    this.bytePicker,
    this.fetcher,
    this.onlineService,
    this.onClose,
    this.sharedBundle,
    this.publishedCollection,
    this.publishedCollectionService,
    this.onCommitStateChanged,
    this.programAmbiguousImport,
    this.onProgramCommitted,
  }) : assert(sources.length > 0, 'at least one import source is required'),
       assert(
         programAmbiguousImport == null || onProgramCommitted != null,
         'programAmbiguousImport requires onProgramCommitted — otherwise a '
         'committed candidate can never be linked back into its program slot',
       ),
       assert(
         programAmbiguousImport == null || sharedBundle == null,
         'programAmbiguousImport and sharedBundle are two different seeding '
         'paths and are never combined by any caller',
       ),
       assert(
         publishedCollection == null ||
             (sharedBundle == null && programAmbiguousImport == null),
         'publishedCollection is a standalone verified seed',
       );

  /// The selectable import sources. The screen opens on the one marked
  /// [ImportSource.preselected], falling back to the first when none is —
  /// order and default selection are deliberately separate (issue #823).
  final List<ImportSource> sources;

  /// Test seam for choosing a file; defaults to [pickImportFile] (native
  /// open-file dialog). Widget tests inject canned text.
  final ImportPicker? picker;

  /// Test seam for choosing a **binary** file (byte sources such as Caller's
  /// Companion `.USR`); overrides the selected [ImportSource.bytePicker] when
  /// provided. Widget tests inject canned bytes so no real picker plugin runs.
  final ImportBytePicker? bytePicker;

  /// Test seam for fetching a URL; defaults to [fetchImportUrl] (real HTTP
  /// GET). Widget tests inject canned text or a throwing fake so no real
  /// network call is made.
  final UrlFetcher? fetcher;

  /// Test seam for the online source a pasted title list is resolved against;
  /// defaults to a real [CallersBoxOnline]. Widget tests inject a fake so no
  /// real search or per-dance fetch is made.
  final OnlineSearchService? onlineService;

  /// Invoked to dismiss the screen when it is **embedded** (e.g. in the
  /// Collection blade's detail pane) rather than pushed as a route.
  ///
  /// When non-null the app bar shows a leading close button, and the
  /// post-commit auto-dismiss calls this instead of [Navigator.pop] — because
  /// an embedded screen has no route of its own to pop (popping would dismiss
  /// the whole shell). When null (the pushed / Settings case) the default back
  /// arrow and [Navigator.pop] behavior is preserved.
  final VoidCallback? onClose;

  /// A pre-validated shared bundle to review (issue #432). When non-null the
  /// screen skips the manual input phase: it seeds the bundle, plans it
  /// immediately, and lands the user on the review/consent list. On commit it
  /// routes through [CompendiumArchiveImporter] (dances + programs + venues) and
  /// offers a transient Undo snackbar. When null the screen behaves exactly as
  /// the manual import flows do.
  final SharedBundleImport? sharedBundle;

  /// Notifies an embedding shell while a commit is running so it cannot replace
  /// this screen before the result/undo handoff completes.
  final ValueChanged<bool>? onCommitStateChanged;

  /// A verified signed collection whose archive should open directly in review.
  final PublishedCollectionSeed? publishedCollection;

  /// When supplied, adds a signed published-collection choice to the source
  /// selector without adding it to [sources], so it cannot become the default
  /// manual import source.
  final PublishedCollectionService? publishedCollectionService;

  /// Program-import lines online resolution could not confidently resolve
  /// (issue #943), pre-previewed non-committingly. When non-null the screen
  /// seeds these as review rows — one per candidate, grouped under their
  /// pasted line — skipping the manual input phase entirely (mirrors
  /// [sharedBundle]'s seeding). Never combined with [sharedBundle] by any
  /// caller. Requires [onProgramCommitted].
  final ProgramAmbiguousImport? programAmbiguousImport;

  /// Invoked once, right before the screen dismisses, after a successful
  /// (non-undone) commit of a [programAmbiguousImport] seed. Keys are
  /// [ProgramAmbiguousLine.originalLineIndex]; a line absent from the map had
  /// no candidate committed (every candidate was left at skip, or none
  /// previewed) and stays a note. Never invoked when [programAmbiguousImport]
  /// is null.
  final void Function(Map<int, String> danceIdsByLineIndex)? onProgramCommitted;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

enum _Phase { input, planning, review, committing }

/// The action the user chose (or that was defaulted) for one record.
enum _ActionKind { create, reimport, link, duplicate, skip, variation }

/// One record's mutable review choice. Defaults are set from the verdict:
/// new → create, reimport → skip (keep-local; never a silent overwrite),
/// ambiguous → skip (never a silent create). See [_defaultChoice].
class _RowChoice {
  _RowChoice(this.kind, [this.linkTargetId]);

  _ActionKind kind;

  /// The candidate dance id to link/reimport/variation-link onto.
  String? linkTargetId;

  /// Whether choosing [_ActionKind.variation] should also create a symmetric
  /// `relatedDance` link back to [linkTargetId] (issue #686). Defaults to
  /// `true` to match [DedupeResolution.variation]'s own default, and only
  /// applies when [kind] is [_ActionKind.variation].
  bool linkBack = true;
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late final CompendiumRepositories _repos;
  bool _started = false;

  /// A picker-only sentinel. It is never planned: selecting it reveals the
  /// verified catalog, whose entry selection supplies real metadata and a source.
  static final ImportSource _publishedCatalogSource = ImportSource(
    kind: ImportSourceKind.publishedCollection,
    adapterFactory: () =>
        throw UnsupportedError('catalog option cannot import'),
  );

  /// The currently selected import source. Defaults to the source that marks
  /// itself [ImportSource.preselected], falling back to the first — order and
  /// default selection are deliberately separate (issue #823), so the dropdown
  /// can lead with the title list while the screen opens on The Caller's Box.
  ///
  /// The "at most one preselected" precondition is asserted in [initState]
  /// rather than the constructor, because the check is not a potentially-const
  /// expression and [ImportReviewScreen]'s constructor is `const`.
  late ImportSource _selected = widget.sources.firstWhere(
    (s) => s.preselected,
    orElse: () => widget.sources.first,
  );

  bool _showPublishedCatalog = false;
  PublishedCollectionEntry? _publishedEntry;
  Uint8List? _publishedArchiveBytes;

  List<ImportSource> get _sourcePickerSources => [
    ...widget.sources,
    if (widget.publishedCollectionService != null) _publishedCatalogSource,
  ];

  @override
  void initState() {
    super.initState();
    assert(
      // `preselected` names the one source the screen opens on. Two of them
      // would silently make the choice order-dependent again — the exact
      // coupling `preselected` exists to break (issue #823) — so fail fast
      // rather than let a custom or refactored list decide by position.
      widget.sources.where((s) => s.preselected).length <= 1,
      'at most one import source may be preselected',
    );
    _pasteController.addListener(_onPasteChanged);
  }

  /// Set once the user picks a source from the dropdown themselves. After that
  /// the URL field stops auto-detecting/overriding the source (manual choice
  /// always wins) — so a deliberate selection is never silently reverted while
  /// the user edits a URL.
  bool _sourceManuallySelected = false;

  final TextEditingController _pasteController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  bool _picking = false;
  bool _fetching = false;

  /// The bytes of a picked binary payload for a byte source (Caller's Companion
  /// `.USR`), or `null` when none is chosen / the source is text-based. Byte
  /// sources plan/commit from these bytes instead of [_pasteController]'s text.
  Uint8List? _payloadBytes;

  /// A [SharedBundleImport] decoded from the current paste-field text when
  /// that text is a valid [CompendiumArchive] that carries programs.
  /// Maintained by [_onPasteChanged], which fires on every controller change
  /// (programmatic or user). Null when the text is absent, not an archive,
  /// or decodes to an archive with no programs.
  ///
  /// **Never write directly.** [_onPasteChanged] is the sole writer; it keeps
  /// this in sync with [_pasteController.text] automatically.
  SharedBundleImport? _cachedPickedBundle;

  /// The text value that produced [_cachedPickedBundle]. Used by
  /// [_onPasteChanged] to skip a re-decode when the text has not changed.
  String _lastDecodedText = '';

  /// Returns [_cachedPickedBundle], which is always in sync with the current
  /// paste-field text. Non-null only when the paste field holds a valid
  /// [CompendiumArchive] with programs.
  ///
  /// Manual-picker shared-bundle sites route through this accessor so they
  /// cannot diverge from each other.
  SharedBundleImport? get _effectivePickedBundle => _cachedPickedBundle;

  bool get _isPublishedImport =>
      _publishedEntry != null || widget.publishedCollection != null;

  bool get _isStandalonePublishedSeed => widget.publishedCollection != null;

  /// The shared-bundle archive represented by the current paste-field text.
  ///
  /// The immutable [widget.sharedBundle] is authoritative only while the text is
  /// still the JSON seeded by the share target. After "Try another" returns the
  /// user to the editable input and they change the text, routing must follow
  /// the listener-maintained live decode instead of silently committing the
  /// original shared bundle (issue #880).
  SharedBundleImport? get _effectiveSharedBundle {
    if (_isPublishedImport) return null;
    final sharedBundle = widget.sharedBundle;
    if (sharedBundle != null && _pasteController.text == sharedBundle.json) {
      return sharedBundle;
    }
    return _effectivePickedBundle;
  }

  /// Listener registered on [_pasteController] in [initState]. Re-decodes the
  /// paste-field text whenever it changes and updates [_cachedPickedBundle].
  ///
  /// A cheap pre-screen (`contains('"programs"')`) skips the full decode for
  /// text that cannot possibly be an archive with programs — title lists, plain
  /// JSON, and any bundle without programs. This screens out all text this app
  /// serialises that does not carry programs. It does not guarantee that every
  /// text that passes the screen is valid (a parse error leaves [bundle] null),
  /// and it does not handle JSON with escaped key characters (`\u0070rograms`),
  /// which no [CompendiumArchive] serialiser produces but a conforming JSON
  /// parser would accept. That edge is near-zero in practice and is not handled.
  void _onPasteChanged() {
    final text = _pasteController.text;
    if (text == _lastDecodedText) return;
    _lastDecodedText = text;
    SharedBundleImport? bundle;
    if (text.contains('"programs"')) {
      try {
        final result = decodeArchive(text);
        final hasRootError = result.errors.any(
          (e) => e.entityType == 'archive' && e.kind == ArchiveErrorKind.read,
        );
        if (!hasRootError && result.archive.programs.isNotEmpty) {
          bundle = SharedBundleImport(
            json: text,
            archive: result.archive,
            entityCount: compendiumArchiveEntityCount(result.archive),
          );
        }
      } catch (_) {
        // diagnostics: silent — not a decodable archive; leave bundle null,
        // the dance-only path handles it unchanged and GenericJsonAdapter will
        // report the error at plan time (which is logged there instead).
      }
    }
    // The listener fires synchronously inside TextEditingController.value =,
    // which is called before the onChanged callback at the TextField. That
    // callback calls setState(), which schedules a rebuild. Because the
    // listener fires first, _cachedPickedBundle is already current by the time
    // the rebuild reads it from the build-path sites (_buildReview,
    // _showSoftCapWarning, _buildSoftCapWarning, _buildRow). Do not call
    // setState here: the rebuild is already scheduled by onChanged, and calling
    // it a second time from the listener would double-schedule unnecessarily.
    // If the onChanged setState were ever removed, this listener would need its
    // own setState to trigger a rebuild for the build-path reads.
    _cachedPickedBundle = bundle;
  }

  /// True when the selected source imports from a picked binary file rather than
  /// pasted/fetched text (governs the input UI and which plan path runs).
  bool get _isByteSource => _selected.bytePicker != null;

  /// True when the selected source's payload is typed by the user rather than
  /// picked or fetched (the pasted title list, issue #823). Governs the input
  /// affordances and routes planning through [resolveTitleList] instead of an
  /// adapter.
  bool get _isPastedTextSource => _selected.pastedTextOnly;

  /// The resolved pasted title list awaiting review, or `null` for every other
  /// source. Carries the rows for titles that produced nothing importable, which
  /// have no place in [_batch] but must still be shown (issue #823).
  ///
  /// Changed **only** in lockstep with [_batch] — set by [_adoptBatch], cleared
  /// by [_resetToInput] — so it never describes a batch other than the one under
  /// review. Assigning it anywhere else reintroduces the leak raised in review of
  /// PR #842, where a resolution outlived its plan and another source's review
  /// rendered this one's already-owned / not-found groups and summary counts.
  TitleListResolution? _titleList;

  /// Row index → [ProgramAmbiguousLine.originalLineIndex], for a row seeded
  /// from [ImportReviewScreen.programAmbiguousImport]; empty list otherwise.
  /// Parallel to `_batch.records` — index `i` here describes `_batch!.records[i]`.
  /// Rows sharing the same line index are the candidates for one pasted
  /// program line, in the order [buildProgramAmbiguousImport] previewed them.
  List<int> _programLineOfRow = const [];

  /// Progress through the title-list online lookups as `(done, total)`, or
  /// `null` when no title-list resolution is running.
  (int, int)? _titleListProgress;

  /// Set when the user cancels an in-flight title-list resolution; read by the
  /// resolver between titles so the run stops without issuing further requests.
  /// Nothing is ever written during resolution, so a cancel simply discards the
  /// partial work.
  bool _titleListCancelled = false;

  /// User-presentable message from the last refused paste (a hard cap tripped),
  /// or `null`.
  String? _titleListError;

  /// The source URL the current payload was fetched from, stashed on
  /// [ImportRequest.uri] for provenance. Cleared whenever the payload is
  /// replaced by a file pick or a manual paste edit so it never goes stale;
  /// file/paste imports leave `uri == null`.
  String? _sourceUri;

  /// User-presentable message from the last failed URL fetch, or `null`.
  String? _fetchError;

  _Phase _phase = _Phase.input;

  ImportBatchResult? _batch;
  List<_RowChoice> _choices = const [];

  /// Indices of review rows already committed on their own via the per-row
  /// **Edit** action. These are excluded from the batch [_commit] (so they are
  /// never imported twice) and render as "Imported" instead of offering actions.
  final Set<int> _committed = <int>{};

  /// Existing dance id → title, for showing candidate/reimport target names.
  Map<String, String> _titlesById = const {};

  /// Row index → the figure-level diff (issue #686) between that row's
  /// confident candidate ([DedupeVerdict.hasConfidentMatch]) and the
  /// previewed draft, computed once per plan in [_plan]. Only populated for
  /// rows whose verdict has a confident match AND whose target dance could be
  /// loaded; a row with no entry here falls back to the pre-#686 plain
  /// ambiguous UI (either it has no confident match, or the target vanished
  /// out from under the review — conservatively treated the same as any
  /// other ambiguous candidate rather than guessed at).
  Map<int, FigureDiffResult> _confidentDiffs = const {};

  Object? _planError;

  Future<PublishedCollectionStatus> _publishedCollectionStatus(
    String collectionId,
    String version,
  ) async {
    final events = await (_publishedImportEvents ??= _repos.collectionImports
        .listAll());
    final matching = events
        .where(
          (event) =>
              event.collectionId == collectionId && event.version == version,
        )
        .map((event) => event.version)
        .toList();
    final held = await _repos.collectionImports.heldCount(
      collectionId,
      version: version,
    );
    return PublishedCollectionStatus(
      heldCount: held,
      importedVersion: matching.isEmpty
          ? null
          : matching.reduce(
              (a, b) => comparePublishedCollectionVersions(a, b) >= 0 ? a : b,
            ),
    );
  }

  Future<List<CollectionImportEvent>>? _publishedImportEvents;

  Future<void> _selectPublishedCollection(
    PublishedCollectionEntry entry,
    List<int> archiveBytes,
  ) async {
    final service = widget.publishedCollectionService;
    if (service == null) {
      throw StateError(
        'Published collection service is required for catalog imports',
      );
    }
    service.verifyArchiveBytes(entry, archiveBytes);
    final metadata = PublishedCollectionMetadata(
      collectionId: entry.id,
      collectionVersion: entry.version,
      archiveDigest: entry.sha256,
      permission: entry.permission.declaration,
      license: entry.license,
    );
    final seed = PublishedCollectionSeed(
      json: utf8.decode(archiveBytes),
      metadata: metadata,
    );
    final source = ImportSource(
      kind: ImportSourceKind.publishedCollection,
      adapterFactory: () => PublishedCollectionAdapter(seed.metadata),
      preselected: true,
    );
    setState(() {
      _showPublishedCatalog = false;
      _publishedEntry = entry;
      _publishedArchiveBytes = Uint8List.fromList(archiveBytes);
      _selected = source;
      _sourceManuallySelected = true;
      _payloadBytes = null;
      _sourceUri = null;
      _fetchError = null;
      _titleListError = null;
      _cachedPickedBundle = null;
      _lastDecodedText = seed.json;
      _pasteController.text = seed.json;
    });
    await _plan();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      final bundle = widget.sharedBundle;
      final published = widget.publishedCollection;
      if (published != null) {
        _lastDecodedText = published.json;
        _pasteController.text = published.json;
        _sourceUri = null;
        _plan();
      } else if (bundle != null) {
        // Share-target intake (issue #432): the bundle was already decoded and
        // validated Dart-side. Seed it and plan immediately so the user lands
        // on the review/consent list — skipping the manual input phase — with
        // nothing written until they confirm.
        //
        // Prime _lastDecodedText before the controller write so _onPasteChanged
        // short-circuits at the identity check and skips the redundant decode.
        // _cachedPickedBundle stays null, which is correct: while the text is
        // unchanged, _effectiveSharedBundle returns widget.sharedBundle without
        // consulting the cache. If the user edits after "Try another", the
        // listener decodes the new text and _effectiveSharedBundle follows it.
        _lastDecodedText = bundle.json;
        _pasteController.text = bundle.json;
        _sourceUri = null;
        _plan();
      } else if (widget.programAmbiguousImport != null) {
        // Program-import fallback ambiguity (issue #943): skip the manual
        // input phase entirely, mirroring the sharedBundle seeding above —
        // there is no adapter to run, only already-previewed candidates to
        // lay out for review.
        _adoptProgramAmbiguousSeed(widget.programAmbiguousImport!);
      }
    }
  }

  @override
  void dispose() {
    _pasteController.removeListener(_onPasteChanged);
    _pasteController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final picker = widget.picker ?? pickImportFile;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _picking = true);
    try {
      final text = await picker();
      if (!mounted || text == null) return;
      _pasteController.text = text;
      // A freshly picked file replaces any URL-sourced payload; drop stale
      // provenance so this import is recorded as file/paste (uri == null).
      // _onPasteChanged fires synchronously and updates _cachedPickedBundle.
      _sourceUri = null;
    } on ImportFileTooLargeException catch (e, stackTrace) {
      // Untrusted input rejected before it was read into memory — tell the user
      // plainly (accessible SnackBar) and leave the input untouched.
      logCaughtError(e, stackTrace, source: 'import_review_screen._chooseFile');
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('import-file-too-large'),
          content: Text(importFileTooLargeMessage(l10n, e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Picks the raw bytes of a binary payload for a byte source (Caller's
  /// Companion `.USR`). Uses the screen-level [ImportReviewScreen.bytePicker]
  /// test seam when provided, else the selected source's own
  /// [ImportSource.bytePicker].
  Future<void> _chooseUsrFile() async {
    final picker = widget.bytePicker ?? _selected.bytePicker;
    if (picker == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _picking = true);
    try {
      final bytes = await picker();
      if (!mounted || bytes == null) return;
      setState(() => _payloadBytes = bytes);
    } on ImportFileTooLargeException catch (e, stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'import_review_screen._chooseUsrFile',
      );
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('import-file-too-large'),
          content: Text(importFileTooLargeMessage(l10n, e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _fetchFromUrl() async {
    final fetcher = widget.fetcher ?? fetchImportUrl;
    final l10n = AppLocalizations.of(context);
    final input = _urlController.text.trim();
    // Rewrite the typed input into the URL actually fetched (e.g. build the
    // Caller's Box &format=JSON endpoint). A null builder fetches as typed.
    final String target;
    try {
      target = _selected.urlBuilder?.call(input) ?? input;
    } on UrlFetchException catch (e, stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'import_review_screen._fetchFromUrl.buildUrl',
      );
      setState(() => _fetchError = importErrorMessage(l10n, e));
      return;
    }
    setState(() {
      _fetching = true;
      _fetchError = null;
    });
    try {
      final body = await fetcher(target);
      if (!mounted) return;
      setState(() {
        _pasteController.text = body;
        // Provenance is the URL actually fetched (the resolved endpoint), not
        // the human URL/id the user typed.
        _sourceUri = target;
      });
    } on UrlFetchException catch (e, stackTrace) {
      if (!mounted) return;
      logCaughtError(
        e,
        stackTrace,
        source: 'import_review_screen._fetchFromUrl.fetch',
      );
      setState(() => _fetchError = importErrorMessage(l10n, e));
    } catch (e, stackTrace) {
      if (!mounted) return;
      // Never surface the raw error to the user (CWE-209); keep it for debug
      // logging only and show a generic, localized fetch-failure message.
      if (kDebugMode) {
        debugPrint('Import URL fetch failed: $e');
      }
      // Same CWE-209 caution as the debug-only print above: an arbitrary
      // fetch-transport error is not known log-safe, so only its shape is
      // recorded (issue #963).
      logCaughtErrorTypeOnly(
        e,
        stackTrace,
        source: 'import_review_screen._fetchFromUrl.fetch',
      );
      setState(() => _fetchError = l10n.importErrorUnreachable);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _plan() async {
    final publishedEntry = _publishedEntry;
    final publishedBytes = _publishedArchiveBytes;
    if (publishedEntry != null && publishedBytes != null) {
      widget.publishedCollectionService!.verifyArchiveBytes(
        publishedEntry,
        publishedBytes,
      );
    }
    final payload = publishedBytes == null
        ? _pasteController.text
        : utf8.decode(publishedBytes);
    final bytes = _payloadBytes;
    if (_isByteSource) {
      if (bytes == null) return;
    } else if (payload.trim().isEmpty) {
      return;
    }
    if (_isPastedTextSource) return _planTitleList(payload);
    setState(() {
      _phase = _Phase.planning;
      _planError = null;
    });
    try {
      final pipeline = ImportPipeline(_repos.dances, _repos.choreographers);
      final index = await pipeline.buildDedupeIndex();
      // Byte sources (Caller's Companion `.USR`) carry the raw file on
      // `options['bytes']`; text sources carry the pasted/fetched payload.
      final request = _isByteSource
          ? ImportRequest(options: {'bytes': bytes!})
          : ImportRequest(payload: payload, uri: _sourceUri);
      final batch = await pipeline.plan(
        _selected.adapterFactory(),
        request,
        index: index,
      );
      await _adoptBatch(batch);
    } catch (e, stackTrace) {
      if (!mounted) return;
      // `payload`/`bytes` here is the raw pasted/fetched/file content the user
      // supplied; a parse error from `pipeline.plan` (e.g. an adapter's own
      // ArchiveError) can echo fragments of it (see `docs/dev/localization.md`
      // on `ArchiveError(message:)` carrying internal diagnostics). It's
      // neither redacted by `CrashRedactor` (which only strips DB-known
      // content, emails/phones/paths) nor DB-derived, so only the error's
      // shape is recorded here, not its message (issue #963).
      logCaughtErrorTypeOnly(
        e,
        stackTrace,
        source: 'import_review_screen._plan',
      );
      setState(() {
        _planError = e;
        _phase = _Phase.review;
      });
    }
  }

  /// Plans a pasted list of dance titles (issue #823): each title is matched
  /// against the local collection and, failing that, looked up online and
  /// previewed — but **never committed**. The importable results become ordinary
  /// review rows with the usual dedupe verdicts and per-row actions; the titles
  /// that produced nothing importable are kept in [_titleList] and rendered as
  /// their own informative groups, so no pasted title silently vanishes.
  ///
  /// A hard cap trips before any network access and leaves the user on the input
  /// screen with the list intact.
  Future<void> _planTitleList(String payload) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _phase = _Phase.planning;
      _planError = null;
      _titleListError = null;
      _titleListCancelled = false;
      // Deliberately NOT (0, 0): how many titles need looking up isn't known
      // until the local-match stage has run, and a paste where everything is
      // already in the collection never looks up any. Staying null keeps the
      // generic spinner until the first real progress report arrives.
      _titleListProgress = null;
    });
    try {
      final resolution = await resolveTitleList(
        payload,
        service: widget.onlineService ?? CallersBoxOnline(),
        repos: _repos,
        onProgress: (done, total) {
          if (!mounted || total == 0) return;
          setState(() => _titleListProgress = (done, total));
        },
        isCancelled: () => _titleListCancelled || !mounted,
      );
      if (!mounted) return;
      await _adoptBatch(resolution.batch, titleList: resolution);
    } on TitleListTooLargeException catch (e, stackTrace) {
      if (!mounted) return;
      logCaughtError(
        e,
        stackTrace,
        source: 'import_review_screen._planTitleList',
      );
      setState(() {
        _resetToInput();
        _titleListError = titleListTooLargeMessage(l10n, e);
      });
    } on TitleListCancelled {
      // diagnostics: silent — user-initiated cancellation (the `isCancelled`
      // callback tripped), not a failure; nothing to log.
      if (!mounted) return;
      setState(_resetToInput);
    } catch (e, stackTrace) {
      if (!mounted) return;
      // Same pasted-content caution as `_plan` above: `payload` is raw pasted
      // text, so only the error's shape is recorded, not its message.
      logCaughtErrorTypeOnly(
        e,
        stackTrace,
        source: 'import_review_screen._planTitleList',
      );
      setState(() {
        _planError = e;
        _phase = _Phase.review;
        _titleListProgress = null;
      });
    }
  }

  /// Adopts a freshly planned [batch] into the review phase: default choices,
  /// the local title lookup for candidate names, and the issue #686 confident
  /// diffs. Shared by the adapter path and the title-list path so the two can
  /// never drift in how a planned record is presented.
  ///
  /// [titleList] is the pasted-title resolution that produced [batch], or null
  /// for every other source. It is assigned **here**, alongside `_batch`, rather
  /// than by the caller, so the invariant *"`_titleList` always describes the
  /// current `_batch`"* holds by construction: adopting any batch without one
  /// clears it. A `_titleList` that outlived its plan would render another
  /// source's review with this one's already-owned / not-found groups and
  /// summary counts (raised in review of PR #842).
  ///
  /// That leak is **latent today, not live**: `_titleList` only becomes non-null
  /// immediately before this method moves the screen to [_Phase.review], and
  /// there is no route from a *successful* review back to [_Phase.input] — the
  /// only returns are the cap refusal and the cancel (which clears it), plus the
  /// error screen's "try another", which is unreachable after a success. So no
  /// plan can currently start with a stale value. Coupling the two assignments
  /// is deliberate precisely because that argument is incidental: adding a
  /// back-to-input affordance to the grouped review — a plausible next change —
  /// would otherwise make the leak live, and nothing would have caught it.
  Future<void> _adoptBatch(
    ImportBatchResult batch, {
    TitleListResolution? titleList,
  }) async {
    final titles = batch.records.isEmpty
        // Nothing to review means nothing to name: `_titlesById` only labels
        // candidate/re-import targets on a row, so loading the collection's
        // titles for an empty batch is a read whose result is never read.
        ? const <String, String>{}
        : {
            for (final e in await _repos.dances.listIdsAndTitles())
              e.id: e.title,
          };
    final confidentDiffs = await _computeConfidentDiffs(batch);
    if (!mounted) return;
    setState(() {
      _batch = batch;
      // Set together with _batch, never separately — see this method's doc.
      _titleList = titleList;
      _titlesById = titles;
      _confidentDiffs = confidentDiffs;
      _choices = [for (final plan in batch.records) _defaultChoice(plan)];
      _committed.clear();
      _titleListProgress = null;
      _phase = _Phase.review;
    });
  }

  /// Seeds the review directly from a [ProgramAmbiguousImport] (issue #943):
  /// flattens every line's previewed candidates into one batch, in line order,
  /// via [_adoptBatch] — then forces every row's choice to skip regardless of
  /// its verdict's usual default. Unlike every other source, nothing here
  /// should ever auto-select: an ambiguous program line has no single
  /// "obvious" candidate by definition (that is precisely why it is
  /// ambiguous), so [_defaultChoice]'s isNew → create default would otherwise
  /// silently import the FIRST candidate of every line the instant the review
  /// opens.
  Future<void> _adoptProgramAmbiguousSeed(ProgramAmbiguousImport seed) async {
    final records = <ImportRecordPlan>[];
    final lineOfRow = <int>[];
    for (final line in seed.lines) {
      for (final plan in line.candidates) {
        records.add(plan);
        lineOfRow.add(line.originalLineIndex);
      }
    }
    await _adoptBatch(ImportBatchResult(records: records));
    if (!mounted) return;
    setState(() {
      _programLineOfRow = lineOfRow;
      for (final choice in _choices) {
        choice.kind = _ActionKind.skip;
      }
    });
  }

  /// Returns to the input step, discarding the planned batch and everything
  /// describing it.
  ///
  /// The counterpart to [_adoptBatch]: that method sets [_batch] and
  /// [_titleList] together, this one clears them together. **Every** path back
  /// to [_Phase.input] routes through here — both back-to-input buttons, the
  /// cap refusal, and the cancel — because clearing discipline spread across
  /// call sites is precisely what caused the leak raised in review of PR #842,
  /// and a manual exit that merely *looks* equivalent is how the same defect
  /// came back a second time. A fifth exit added later gets the invariant for
  /// free.
  ///
  /// Deliberately does not clear [_titleListError]: the cap refusal resets and
  /// *then* sets it, and the message belongs to the input step it returns to.
  ///
  /// Caller is responsible for being inside a [setState].
  void _resetToInput() {
    if (_isPublishedImport && widget.publishedCollectionService != null) {
      _showPublishedCatalog = true;
      _publishedEntry = null;
      _publishedArchiveBytes = null;
      _selected = widget.sources.firstWhere(
        (source) => source.preselected,
        orElse: () => widget.sources.first,
      );
      _cachedPickedBundle = null;
      _pasteController.clear();
    }
    _phase = _Phase.input;
    _batch = null;
    _titleList = null;
    _programLineOfRow = const [];
    _titleListProgress = null;
    _planError = null;
    // _cachedPickedBundle is maintained by _onPasteChanged and does not need
    // explicit clearing here; it stays valid as long as the paste text is
    // unchanged, and will update if the text is later modified.
  }

  /// Computes the issue #686 figure-level diff for every row whose verdict
  /// has a confident title+author match ([DedupeVerdict.hasConfidentMatch]),
  /// against that candidate's stored [Dance]. Rows with no confident match,
  /// or whose confident candidate's target dance can no longer be loaded
  /// (deleted mid-review), are simply absent from the result — [_buildActions]
  /// falls back to the plain (pre-#686) ambiguous UI for those.
  ///
  /// Reuses the app's own [contraTaxonomy] + a fresh [FigureRenderer] and the
  /// currently active [Dialect] — the comparison itself never depends on the
  /// dialect (see [diffFigures]'s doc comment); the dialect only shapes the
  /// display text of any lines actually rendered.
  Future<Map<int, FigureDiffResult>> _computeConfidentDiffs(
    ImportBatchResult batch,
  ) async {
    // Only ever touch [ActiveDialectScope] when at least one row actually has
    // a confident match to diff — a batch with none (the common case) never
    // requires it as an ancestor. Read it synchronously, before any `await`
    // below, so this never uses [context] across an async gap.
    final hasConfidentMatch = batch.records.any(
      (r) => r.verdict.hasConfidentMatch,
    );
    if (!hasConfidentMatch) return const {};
    final dialect = ActiveDialectScope.of(context);
    final renderer = FigureRenderer(contraTaxonomy);
    final diffs = <int, FigureDiffResult>{};
    for (var i = 0; i < batch.records.length; i++) {
      if (!mounted) return diffs;
      final verdict = batch.records[i].verdict;
      if (!verdict.hasConfidentMatch) continue;
      final candidate = verdict.candidates.firstWhere((c) => c.confident);
      final target = await _repos.dances.getById(candidate.danceId);
      if (target == null) continue;
      final draftDance = batch.records[i].draft.dance;
      diffs[i] = diffFigures(
        oldFigures: target.figures,
        oldStructure: target.phraseStructure,
        newFigures: draftDance.figures,
        newStructure: draftDance.phraseStructure,
        taxonomy: contraTaxonomy,
        renderer: renderer,
        dialect: dialect,
      );
    }
    return diffs;
  }

  _RowChoice _defaultChoice(ImportRecordPlan plan) {
    switch (plan.verdict.kind) {
      case DedupeKind.isNew:
        return _RowChoice(_ActionKind.create);
      case DedupeKind.reimport:
        // Default to keep-local (skip) so a re-import never silently overwrites
        // local edits (issue #446). The target id is retained so the user can
        // deliberately choose "Re-import onto …" to overwrite.
        return _RowChoice(_ActionKind.skip, plan.verdict.targetDanceId);
      case DedupeKind.ambiguous:
        return _RowChoice(_ActionKind.skip);
    }
  }

  /// Builds the committed [ImportRecordPlan] for row [i] from its chosen
  /// resolution, together with the [DedupeResolution] the core pipeline needs
  /// (only for the ambiguous link/duplicate choices; `null` otherwise). Returns
  /// `null` for a skipped row, which is never written. The core pipeline honours
  /// resolutions only for ambiguous verdicts, so create/reimport/link/duplicate
  /// are expressed directly. Shared by [_buildCommitBatch] (batch import) and
  /// [_editRow] (single-row edit) so the two paths can never drift.
  (ImportRecordPlan, DedupeResolution?)? _planForRow(int i) {
    final record = _batch!.records[i];
    final draft = record.draft;
    final choice = _choices[i];
    switch (choice.kind) {
      case _ActionKind.create:
        return (
          ImportRecordPlan(draft: draft, verdict: DedupeVerdict.isNew()),
          null,
        );
      case _ActionKind.reimport:
        return (
          ImportRecordPlan(
            draft: draft,
            verdict: DedupeVerdict.reimport(choice.linkTargetId!),
          ),
          null,
        );
      case _ActionKind.link:
        return (
          ImportRecordPlan(
            draft: draft,
            verdict: DedupeVerdict.ambiguous(record.verdict.candidates),
          ),
          DedupeResolution.link(choice.linkTargetId!),
        );
      case _ActionKind.duplicate:
        return (
          ImportRecordPlan(
            draft: draft,
            verdict: DedupeVerdict.ambiguous(const []),
          ),
          DedupeResolution.duplicate(),
        );
      case _ActionKind.variation:
        return (
          ImportRecordPlan(
            draft: draft,
            verdict: DedupeVerdict.ambiguous(record.verdict.candidates),
          ),
          DedupeResolution.variation(
            choice.linkTargetId!,
            linkBack: choice.linkBack,
          ),
        );
      case _ActionKind.skip:
        return null;
    }
  }

  /// Builds the batch actually committed plus its resolutions map; skipped
  /// rows are omitted so nothing is written for them. Also returns, in acted
  /// order, which original row index produced each acted entry — needed by
  /// [_commit] to map a [ImportReviewScreen.programAmbiguousImport] seed's
  /// committed ids back to its line indices (issue #943).
  ///
  /// Within one program-ambiguity line ([_programLineOfRow]), only the FIRST
  /// non-skip row is honoured — including one already committed via the
  /// per-row Edit action. A user who set more than one candidate to a
  /// non-skip action would otherwise import the same pasted line twice, which
  /// [ProgramAmbiguousLine]'s own doc comment says can never happen. This is a
  /// backstop, not a UI affordance: the candidate rows have no mutual-exclusion
  /// control of their own, and every one is an ordinary review row.
  (ImportBatchResult, Map<int, DedupeResolution>, int, List<int>)
  _buildCommitBatch() {
    final batch = _batch!;
    final acted = <ImportRecordPlan>[];
    final actedRowIndices = <int>[];
    final resolutions = <int, DedupeResolution>{};
    // Seed with lines whose candidate already committed via per-row Edit, so
    // a different candidate for the same line can never ALSO import here.
    final decidedProgramLines = <int>{
      for (var i = 0; i < batch.records.length; i++)
        if (_committed.contains(i) && i < _programLineOfRow.length)
          _programLineOfRow[i],
    };
    var skipped = 0;
    for (var i = 0; i < batch.records.length; i++) {
      // Rows already committed via the per-row Edit action are excluded so the
      // batch import never writes them twice.
      if (_committed.contains(i)) continue;
      final planned = _planForRow(i);
      if (planned == null) {
        skipped++;
        continue;
      }
      if (i < _programLineOfRow.length &&
          !decidedProgramLines.add(_programLineOfRow[i])) {
        // Another candidate for this line already committed to a non-skip
        // choice (or committed on its own via Edit); this one no-ops.
        skipped++;
        continue;
      }
      final (plan, resolution) = planned;
      final j = acted.length;
      acted.add(plan);
      actedRowIndices.add(i);
      if (resolution != null) resolutions[j] = resolution;
    }
    return (
      ImportBatchResult(records: acted),
      resolutions,
      skipped,
      actedRowIndices,
    );
  }

  /// Commits just row [i] on its own (honouring its chosen resolution) and then
  /// opens the freshly committed dance in the [DanceEditorScreen] — the
  /// one-click "import + edit" affordance (issue #266). The row is marked
  /// committed so the batch [_commit] never writes it again, and the live
  /// Collection is refreshed both after the commit and after the editor returns.
  Future<void> _editRow(int i) async {
    final planned = _planForRow(i);
    // Edit is disabled for skipped rows, so there is nothing to commit.
    if (planned == null) return;
    final (plan, resolution) = planned;

    widget.onCommitStateChanged?.call(true);
    setState(() => _phase = _Phase.committing);
    // Edit is a single-dance affordance, so it always uses the adapter-agnostic
    // dance commit path — even for the Caller's Companion `.USR` byte source,
    // whose programs remain the batch Import button's responsibility.
    final pipeline = ImportPipeline(_repos.dances, _repos.choreographers);
    try {
      final session = await pipeline.commit(
        ImportBatchResult(records: [plan]),
        now: DateTime.now().toUtc(),
        newId: uuidV4,
        resolutions: resolution == null
            ? const <int, DedupeResolution>{}
            : {0: resolution},
      );
      if (!mounted) return;
      final committed = session.records
          .where((r) => r.succeeded && r.action != CommitAction.skip)
          .toList();
      final danceId = committed.isEmpty ? null : committed.first.danceId;
      if (danceId == null) {
        setState(() => _phase = _Phase.review);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const ValueKey('import-edit-error'),
            content: Text(AppLocalizations.of(context).importReviewEditError),
          ),
        );
        return;
      }
      setState(() {
        _phase = _Phase.review;
        _committed.add(i);
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DanceEditorScreen(danceId: danceId),
        ),
      );
      if (!mounted) return;
    } catch (e, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('Import commit-for-edit failed: $e\n$stackTrace');
      }
      logCaughtError(e, stackTrace, source: 'import_review_screen._editRow');
      setState(() => _phase = _Phase.review);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('import-edit-error'),
          content: Text(AppLocalizations.of(context).importReviewImportError),
        ),
      );
    } finally {
      widget.onCommitStateChanged?.call(false);
    }
  }

  Future<void> _commit() async {
    final (commitBatch, resolutions, skipped, actedRowIndices) =
        _buildCommitBatch();
    widget.onCommitStateChanged?.call(true);
    setState(() => _phase = _Phase.committing);
    final pipeline = ImportPipeline(_repos.dances, _repos.choreographers);
    // Commit/undo routing is gated on the concrete adapter type — NOT on
    // `_isByteSource` — so only Caller's Companion `.USR` persists/undoes
    // programs. A hypothetical future dance-only byte source would fall through
    // to the shared dance path and never touch programs.
    final sharedBundle = _effectiveSharedBundle;
    try {
      final publishedEntry = _publishedEntry;
      final publishedBytes = _publishedArchiveBytes;
      if (publishedEntry != null && publishedBytes != null) {
        widget.publishedCollectionService!.verifyArchiveBytes(
          publishedEntry,
          publishedBytes,
        );
      }
      final adapter = _selected.adapterFactory();
      if (sharedBundle != null) {
        // Share target (issue #432): commit dances + programs + venues through
        // the archive importer, then offer a transient Undo that reverts exactly
        // this batch. Routed first and gated on the pre-validated bundle, never
        // on the adapter type.
        await _commitSharedBundle(
          pipeline,
          sharedBundle,
          commitBatch,
          resolutions,
        );
      } else if (adapter is CallersCompanionUsrAdapter) {
        final importer = CallersCompanionUsrImporter(
          pipeline,
          _repos.programs,
          _repos.venues,
        );
        final archive = readCcUsrArchive(_payloadBytes!);
        final result = await importer.commit(
          commitBatch,
          archive,
          now: DateTime.now().toUtc(),
          venueEntityMode: VenueEntityModeScope.of(context),
          newId: uuidV4,
          newSlotId: uuidV4,
          resolutions: resolutions,
        );
        if (!mounted) return;
        setState(() => _phase = _Phase.review);
        await _showResult(
          session: result.danceSession,
          skipped: skipped,
          onUndo: () => importer.undo(result),
          ccResult: result,
        );
        if (!mounted) return;
        // Opt-in, previewed step (#562): offer to seed figure shorthands from
        // the file's InsertCall call buttons. Runs after the result dialog so
        // it never blocks the dance/program import; declining seeds nothing.
        await _maybeSeedShorthands(archive);
      } else if (adapter is PublishedCollectionAdapter) {
        final metadata = adapter.metadata;
        final importer = PublishedCollectionImporter(pipeline);
        final result = await importer.commit(
          commitBatch,
          metadata: metadata,
          now: DateTime.now().toUtc(),
          newId: uuidV4,
          resolutions: resolutions,
        );
        try {
          await _repos.collectionImports.record(result.event);
        } catch (_) {
          // diagnostics: silent — the outer commit handler presents a safe
          // localized error after compensating the imported batch.
          // The event is part of the published import's all-or-nothing
          // contract. Remove the just-committed dances before surfacing the
          // failure so an event-less import cannot remain.
          await pipeline.undo(result.session);
          rethrow;
        }
        _publishedImportEvents = null;
        if (!mounted) return;
        setState(() => _phase = _Phase.review);
        await _showResult(
          session: result.session,
          skipped: skipped,
          onUndo: () => pipeline.undo(result.session),
        );
      } else {
        final session = await pipeline.commit(
          commitBatch,
          now: DateTime.now().toUtc(),
          newId: uuidV4,
          resolutions: resolutions,
        );
        if (!mounted) return;
        // Leave the progress phase before showing the (awaited) result dialog so
        // no indeterminate spinner animates behind it.
        setState(() => _phase = _Phase.review);
        await _showResult(
          session: session,
          skipped: skipped,
          onUndo: () => pipeline.undo(session),
          programResults: _programCommitResults(session, actedRowIndices),
        );
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('Import commit failed: $e\n$stackTrace');
      }
      logCaughtError(e, stackTrace, source: 'import_review_screen._commit');
      setState(() => _phase = _Phase.review);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('import-commit-error'),
          content: Text(AppLocalizations.of(context).importReviewImportError),
        ),
      );
    } finally {
      widget.onCommitStateChanged?.call(false);
    }
  }

  /// Maps a just-committed [session]'s successful records back to
  /// [ProgramAmbiguousLine.originalLineIndex] (issue #943), for
  /// [ImportReviewScreen.onProgramCommitted]. `null` when this review was not
  /// seeded from a [ImportReviewScreen.programAmbiguousImport] — distinct from
  /// an empty map, which would mean a program seed where nothing committed.
  Map<int, String>? _programCommitResults(
    ImportSession session,
    List<int> actedRowIndices,
  ) {
    if (_programLineOfRow.isEmpty) return null;
    final results = <int, String>{};
    for (var j = 0; j < session.records.length; j++) {
      final record = session.records[j];
      if (!record.succeeded || record.danceId == null) continue;
      final rowIndex = actedRowIndices[j];
      if (rowIndex >= _programLineOfRow.length) continue;
      results[_programLineOfRow[rowIndex]] = record.danceId!;
    }
    return results;
  }

  /// Opt-in, previewed shorthand seeding from a Caller's Companion file's
  /// `InsertCall` call buttons (issue #562).
  ///
  /// Builds the parseable shorthand candidates from [archive], splits them
  /// against the user's existing shorthands (conflicts are surfaced, never
  /// overwritten), and — only when there is something to offer — pushes the
  /// preview step. The user picks which to seed (and, for buttons with a
  /// distinct alternate call, primary vs. alternate); each accepted candidate is
  /// `upsert`ed. Declining seeds nothing, and because conflicts are skipped a
  /// re-import of the same file adds no duplicates.
  Future<void> _maybeSeedShorthands(CcUsrArchive archive) async {
    final controller = ShorthandMappingsScope.maybeOf(context);
    if (controller == null) return;

    final candidates = buildInsertCallShorthandCandidates(
      archive.insertCalls,
      taxonomy: contraTaxonomy,
    );
    if (candidates.isEmpty) return;

    final existing = {for (final m in controller.mappings) m.normalizedToken};
    final partition = partitionInsertCallCandidates(candidates, existing);
    // Nothing addable: every candidate already exists. Surfacing a screen with
    // only skipped rows would be noise, so stay silent (the tokens are already
    // defined — re-import idempotency needs no user action).
    if (partition.seedable.isEmpty) return;

    final dialect = ActiveDialectScope.of(context);
    final chosen = await Navigator.of(context).push<List<ShorthandMapping>>(
      MaterialPageRoute(
        builder: (_) => ImportShorthandSeedScreen(
          seedable: partition.seedable,
          conflicting: partition.conflicting,
          dialect: dialect,
        ),
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    var seeded = 0;
    for (final mapping in chosen) {
      // Defensive: another shorthand with this token could have appeared while
      // the step was open. upsert throws on a duplicate; skip rather than abort
      // the batch so one late collision can't drop the rest.
      if (controller.hasToken(mapping.token)) continue;
      try {
        await controller.upsert(mapping);
        seeded++;
      } catch (e, stackTrace) {
        // diagnostics: silent — bounds/duplicate backstop; never surface a raw
        // error to the user (this is an optional background step, and the
        // token/mapping content is unvalidated pasted import content, so it
        // isn't logged either — see `_plan`'s `logCaughtErrorTypeOnly` note
        // above for why raw pasted content isn't recorded). Debug-only print
        // remains for local diagnosis.
        if (kDebugMode) {
          debugPrint('Shorthand seed upsert failed: $e\n$stackTrace');
        }
      }
    }
    if (!mounted || seeded == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('shorthand-seed-complete'),
        content: Text(
          AppLocalizations.of(context).importShorthandSeedComplete(seeded),
        ),
      ),
    );
  }

  /// Commits a validated shared [bundle] (issue #432): dances + their author
  /// choreographers + programs + venues, via [CompendiumArchiveImporter] — the
  /// same commit engine the receive-side share path has always used — then hands
  /// off to a transient Undo snackbar. Any failure propagates to [_commit]'s
  /// catch (which surfaces the generic commit-error snackbar and writes nothing
  /// further), keeping intake fail-closed on malformed/hostile input.
  Future<void> _commitSharedBundle(
    ImportPipeline pipeline,
    SharedBundleImport bundle,
    ImportBatchResult commitBatch,
    Map<int, DedupeResolution> resolutions,
  ) async {
    final importer = CompendiumArchiveImporter(
      pipeline,
      _repos.programs,
      _repos.venues,
    );
    final result = await importer.commit(
      commitBatch,
      bundle.archive,
      now: DateTime.now().toUtc(),
      newId: uuidV4,
      newSlotId: uuidV4,
      resolutions: resolutions,
    );
    if (!mounted) return;
    setState(() => _phase = _Phase.review);
    await _showSharedBundleUndo(result: result, importer: importer);
  }

  /// Shows the transient post-commit Undo for a shared bundle and returns the
  /// user to where they were. The Undo reverts **exactly** this import (the ids
  /// the commit returned) via [CompendiumArchiveImporter.undo]; once the
  /// snackbar auto-dismisses (see [kUndoSnackBarDuration]) the action is gone —
  /// session-transient, never persisted (issue #432 / reusing #463's helper).
  Future<void> _showSharedBundleUndo({
    required CompendiumArchiveImportResult result,
    required CompendiumArchiveImporter importer,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    final importedDances = result.danceSession.records
        .where((r) => r.succeeded && r.action != CommitAction.skip)
        .length;
    final importedCount = importedDances + result.programs.length;

    showUndoSnackBar(
      messenger,
      key: const ValueKey('shared-import-undo-snackbar'),
      message: l10n.sharedImportComplete(importedCount),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: accessibleNavigation,
      onUndo: () async {
        // Idempotent: a repeated tap (or a tap after another undo) is a no-op.
        if (result.isUndone) return;
        await importer.undo(result);
      },
    );

    // Return to where the user was; the transient snackbar rides the app-level
    // ScaffoldMessenger, so it stays visible after this route is gone.
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showResult({
    required ImportSession session,
    required int skipped,
    required Future<void> Function() onUndo,
    CcUsrImportResult? ccResult,
    Map<int, String>? programResults,
  }) async {
    final l10n = AppLocalizations.of(context);
    var created = 0, reimported = 0, linked = 0, duplicated = 0, varied = 0;
    final errors = <ImportError>[];
    for (final r in session.records) {
      if (!r.succeeded) {
        if (r.error != null) errors.add(r.error!);
        continue;
      }
      switch (r.action) {
        case CommitAction.create:
          created++;
        case CommitAction.reimport:
          reimported++;
        case CommitAction.link:
          linked++;
        case CommitAction.duplicate:
          duplicated++;
        case CommitAction.variation:
          varied++;
        case CommitAction.skip:
          break;
      }
    }
    // Program outcomes only exist for a Caller's Companion `.USR` import; a
    // text import leaves [ccResult] null and the dialog stays dance-only.
    final programs = ccResult?.programs ?? const [];
    final programNames = [
      for (final p in programs)
        (p.title.trim().isEmpty
            ? l10n.importReviewUntitledProgram
            : p.title.trim()),
    ];
    final programIssues = ccResult?.programIssues ?? const [];
    var undone = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('import-result-dialog'),
        title: Text(l10n.importReviewComplete),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryLine('Created', l10n.importReviewSummaryCreated(created)),
              _summaryLine(
                'Re-imported',
                l10n.importReviewSummaryReimported(reimported),
              ),
              _summaryLine('Linked', l10n.importReviewSummaryLinked(linked)),
              _summaryLine(
                'Duplicated',
                l10n.importReviewSummaryDuplicated(duplicated),
              ),
              _summaryLine(
                'Variation',
                l10n.importReviewSummaryVariation(varied),
              ),
              _summaryLine('Skipped', l10n.importReviewSummarySkipped(skipped)),
              // A pasted title list's non-importable answers would otherwise be
              // lost with the review screen when it auto-dismisses after a
              // commit — and "which of these do I already have?" is worth
              // keeping (issue #823). Null for every other source.
              if (_titleList != null) ...[
                const SizedBox(height: 8),
                _summaryLine(
                  'AlreadyOwned',
                  l10n.importReviewSummaryAlreadyOwned(
                    _titleList!.countIn(TitleListGroup.alreadyInCollection),
                  ),
                ),
                _summaryLine(
                  'NotFound',
                  l10n.importReviewSummaryNotFound(
                    _titleList!.countIn(TitleListGroup.notFound),
                  ),
                ),
              ],
              if (ccResult != null) ...[
                const SizedBox(height: 8),
                _summaryLine(
                  'Programs',
                  l10n.importReviewSummaryPrograms(programs.length),
                ),
                if (ccResult.updatedProgramCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.importReviewProgramsUpdated(
                        ccResult.updatedProgramCount,
                      ),
                      key: const ValueKey('import-programs-updated'),
                    ),
                  ),
                if (programNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      key: const ValueKey('import-program-names'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final name in programNames) Text('• $name'),
                      ],
                    ),
                  ),
                if (programIssues.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.importReviewProgramNotes(programIssues.length),
                    key: const ValueKey('import-program-notes'),
                    style: Theme.of(dialogContext).textTheme.labelLarge,
                  ),
                  for (final issue in programIssues)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• ${importIssueMessage(l10n, issue)}'),
                    ),
                ],
              ],
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.importReviewRecordsFailed(errors.length),
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• ${importRecordErrorMessage(l10n, e)}'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('import-undo-button'),
            onPressed: () async {
              await onUndo();
              undone = true;
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(
              ccResult != null
                  ? l10n.importReviewUndoWithPrograms
                  : l10n.commonUndo,
            ),
          ),
          FilledButton(
            key: const ValueKey('import-done-button'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonDone),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (undone) {
      // Undo reverted the DB; refresh again and stay for another attempt. An
      // archive undo removes imported programs as well as dances; the program
      // views pick that up from their own streams (issue #768).
      setState(() => _phase = _Phase.review);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('import-undone-snackbar'),
          content: Text(l10n.importReviewUndone),
        ),
      );
    } else {
      // Program-import fallback ambiguity (issue #943): report which lines
      // resolved before dismissing, so the caller can link those dances into
      // program slots. Never fired on an undone commit — nothing was kept.
      if (programResults != null) {
        widget.onProgramCommitted?.call(programResults);
      }
      // Embedded (onClose provided): dismiss via the shell — it has no route to
      // pop. Pushed (onClose null): pop this screen's route as before.
      final onClose = widget.onClose;
      if (onClose != null) {
        onClose();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Widget _summaryLine(String keyLabel, String text) =>
      Text(text, key: ValueKey('import-summary-$keyLabel'));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Block a user-initiated back/dismiss while a commit is in flight: leaving
    // mid-commit would let the write finish with the screen unmounted, stranding
    // freshly-imported data without the transient Undo (issue #432). The
    // imperative pop the post-commit flow performs is unaffected by PopScope.
    return PopScope(
      canPop: _phase != _Phase.committing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.importDances),
          key: const ValueKey('import-review-appbar'),
          leading: widget.onClose == null
              ? null
              : IconButton(
                  key: const ValueKey('import-close'),
                  tooltip: l10n.importReviewClose,
                  icon: const Icon(Icons.close),
                  // Disabled mid-commit to mirror the PopScope guard: the
                  // embedded Close invokes [widget.onClose] directly (not a
                  // route pop), which PopScope does not intercept, so a tap
                  // during [_Phase.committing] would unmount the screen while
                  // the write is in flight and strand the imported data without
                  // its Undo/refresh (issue #432).
                  onPressed: _phase == _Phase.committing
                      ? null
                      : widget.onClose,
                ),
        ),
        body: switch (_phase) {
          _Phase.input => _buildInput(context),
          _Phase.planning => _buildPlanning(context),
          _Phase.committing => const Center(
            key: ValueKey('import-committing'),
            child: CircularProgressIndicator(),
          ),
          _Phase.review => _buildReview(context),
        },
      ),
    );
  }

  /// The planning spinner. A pasted title list additionally shows how far
  /// through the batch it is and a Cancel, because it makes one online lookup
  /// per unmatched title — a bare indeterminate spinner would leave a long list
  /// looking hung with no way out. Nothing has been written at this point, so
  /// cancelling simply discards the partial work.
  ///
  /// A paste with **nothing to look up** — every title already in the collection
  /// or rejected by the per-line bounds — falls back to the generic spinner. It
  /// has no batch to report and nothing to cancel, so "Searching 0 of 0…" beside
  /// a Cancel button would be both meaningless and untrue.
  Widget _buildPlanning(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = _titleListProgress;
    if (progress == null) {
      return const Center(
        key: ValueKey('import-planning'),
        child: CircularProgressIndicator(),
      );
    }
    final (done, total) = progress;
    return Center(
      key: const ValueKey('import-planning'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: done / total),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.importReviewTitleListProgress(done, total),
              key: const ValueKey('import-titles-progress'),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            key: const ValueKey('import-titles-cancel'),
            onPressed: _titleListCancelled
                ? null
                : () => setState(() => _titleListCancelled = true),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasContent =
        !_showPublishedCatalog &&
        (_isByteSource
            ? _payloadBytes != null
            : _pasteController.text.trim().isNotEmpty);
    // While a file pick or URL fetch is in flight, lock every input so a
    // late-completing pick/fetch can't overwrite the payload or clobber
    // `_sourceUri` under the user, and so planning can't start on stale input.
    final busy = _picking || _fetching;
    final isUrlSource = _selected.urlBuilder != null;
    final titlePreflight = _isPastedTextSource
        ? preflightTitleList(_pasteController.text)
        : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_sourcePickerSources.length > 1 && !_isPublishedImport) ...[
          Text(
            l10n.importReviewSourceLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          DropdownButton<ImportSource>(
            key: const ValueKey('import-source-select'),
            isExpanded: true,
            value: _showPublishedCatalog ? _publishedCatalogSource : _selected,
            onChanged: busy
                ? null
                : (source) {
                    if (source == null) return;
                    if (source == _publishedCatalogSource) {
                      setState(() {
                        _showPublishedCatalog = true;
                        _publishedEntry = null;
                        _publishedArchiveBytes = null;
                      });
                      return;
                    }
                    setState(() {
                      _showPublishedCatalog = false;
                      _publishedEntry = null;
                      _publishedArchiveBytes = null;
                      _selected = source;
                      // A deliberate pick disables URL auto-detection so it is
                      // never silently reverted as the user edits the URL.
                      _sourceManuallySelected = true;
                      // Selecting a new source drops any stale fetch error and
                      // URL provenance: the fetched-from URL belonged to the
                      // previous source/adapter, so carrying it onto the next
                      // plan would misattribute provenance. The payload is left
                      // for the user (they may re-fetch or paste); it plans as
                      // a paste (uri == null) until a fresh fetch sets it.
                      _fetchError = null;
                      _sourceUri = null;
                      // Binary payloads belong to a specific byte source; drop
                      // them when switching so a `.USR` can't plan through a
                      // text adapter (or vice versa).
                      _payloadBytes = null;
                      // A cap refusal belongs to the title-list source; it must
                      // not linger over a different source's input.
                      _titleListError = null;
                    });
                  },
            items: [
              for (final source in _sourcePickerSources)
                DropdownMenuItem<ImportSource>(
                  value: source,
                  child: Text(
                    source == _publishedCatalogSource
                        ? l10n.publishedCollectionsTitle
                        : importSourceLabel(l10n, source.kind),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (_showPublishedCatalog) ...[
          PublishedCollectionCatalog(
            key: const ValueKey('inline-published-collection-catalog'),
            service: widget.publishedCollectionService,
            statusLoader: _publishedCollectionStatus,
            onImport: _selectPublishedCollection,
          ),
          const SizedBox(height: 16),
        ],
        if (_showPublishedCatalog) ...[
          const SizedBox.shrink(),
        ] else if (_isPublishedImport) ...[
          Text(
            l10n.importReviewDancesFromSource(
              importSourceLabel(l10n, _selected.kind),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(l10n.importReviewGenericSubtitle),
        ] else if (_isByteSource) ...[
          Text(
            l10n.importReviewFromSource(
              importSourceLabel(l10n, _selected.kind),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(l10n.importReviewUsrSubtitle),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('import-choose-usr-file'),
            onPressed: busy ? null : _chooseUsrFile,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(l10n.importReviewChooseUsr),
          ),
          if (_payloadBytes != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                key: const ValueKey('import-usr-chosen'),
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(l10n.importReviewFileReady(_payloadBytes!.length)),
                ],
              ),
            ),
        ] else if (_isPastedTextSource) ...[
          Text(
            l10n.importReviewDancesFromSource(
              importSourceLabel(l10n, _selected.kind),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(l10n.importReviewTitleListSubtitle),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('import-titles-field'),
            controller: _pasteController,
            minLines: 6,
            maxLines: 14,
            enabled: !busy,
            onChanged: (_) {
              // A fresh edit invalidates any prior cap refusal, and the live
              // count below has to keep up with what is actually in the box.
              _sourceUri = null;
              setState(() => _titleListError = null);
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.importReviewPasteTitles,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.importReviewTitleListCount(titlePreflight!.distinctTitleCount),
            key: const ValueKey('import-titles-count'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (titlePreflight.duplicateLines > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.importReviewTitleListDuplicates(
                  titlePreflight.duplicateLines,
                ),
                key: const ValueKey('import-titles-duplicates'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_titleListError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Row(
                  key: const ValueKey('import-titles-error'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _titleListError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ] else ...[
          Text(
            l10n.importReviewDancesFromSource(
              importSourceLabel(l10n, _selected.kind),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(l10n.importReviewGenericSubtitle),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('import-choose-file'),
            onPressed: busy ? null : _chooseFile,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(l10n.importReviewChooseFile),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('import-url-field'),
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enabled: !busy,
                  onChanged: (value) {
                    final detected = _sourceManuallySelected
                        ? null
                        : detectSourceForUrl(value, widget.sources);
                    final clearError = _fetchError != null;
                    if (detected != null && detected != _selected) {
                      // Auto-flip the source selector to match the pasted URL's
                      // host (manual selection would have short-circuited above).
                      setState(() {
                        _selected = detected;
                        _fetchError = null;
                        _sourceUri = null;
                      });
                    } else if (clearError) {
                      setState(() => _fetchError = null);
                    }
                  },
                  onSubmitted: (_) => busy ? null : _fetchFromUrl(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: isUrlSource
                        ? l10n.importReviewUrlLabel
                        : l10n.importReviewUrlLabelGeneric,
                    hintText: isUrlSource
                        ? l10n.importReviewUrlHint
                        : l10n.importReviewUrlHintGeneric,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('import-fetch-url'),
                onPressed: busy ? null : _fetchFromUrl,
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(l10n.importReviewFetch),
              ),
            ],
          ),
          if (_fetchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                key: const ValueKey('import-url-error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _fetchError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('import-paste-field'),
            controller: _pasteController,
            minLines: 4,
            maxLines: 10,
            enabled: !busy,
            onChanged: (_) {
              // Editing the payload by hand drops any URL provenance so the
              // import is recorded as a paste (uri == null).
              _sourceUri = null;
              setState(() {});
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.importReviewPasteJson,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('import-continue'),
          onPressed: (hasContent && !busy) ? _plan : null,
          icon: const Icon(Icons.playlist_add_check),
          label: Text(l10n.importReviewReviewButton),
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final batch = _batch;
    if (_planError != null) {
      return _buildMessage(
        context,
        icon: Icons.error_outline,
        title: l10n.importReviewCouldNotRead,
        detail: '$_planError',
      );
    }
    if (batch == null) return const SizedBox.shrink();

    final unreadable = batch.errors;
    final titleList = _titleList;
    if (batch.records.isEmpty) {
      // A pasted title list with nothing importable is not a dead end (issue
      // #823): the whole point of listing every pasted title is that "you
      // already have these six, and these two couldn't be found" is a useful
      // answer in itself. Fall through to the grouped review instead of the
      // generic "no dances" message.
      if (titleList != null && titleList.rows.isNotEmpty) {
        return _buildTitleListOnlyReview(context, titleList);
      }
      // A shared bundle can legitimately carry programs but no dances (e.g. a
      // program of only free-text/announcement slots). It passed intake (which
      // rejects only a bundle with neither dances nor programs), so the review
      // must still let the user consent to importing the programs — dead-ending
      // on "no dances" would regress the pre-#432 behavior that imported such
      // bundles. Also applies to a manually picked .ccshare (issue #852).
      // Only fall through here when there is nothing importable at all.
      final sharedBundle = _effectiveSharedBundle;
      if (unreadable.isEmpty &&
          sharedBundle != null &&
          sharedBundle.archive.programs.isNotEmpty) {
        return _buildSharedProgramsOnlyReview(
          context,
          sharedBundle.archive.programs.length,
        );
      }
      return _buildMessage(
        context,
        icon: unreadable.isEmpty ? Icons.inbox_outlined : Icons.error_outline,
        title: unreadable.isEmpty
            ? l10n.importReviewNoDancesTitle
            : l10n.importReviewCouldNotRead,
        detail: unreadable.isEmpty
            ? l10n.importReviewNoDancesBody
            : unreadable
                  .map((e) => importRecordErrorMessage(l10n, e))
                  .join('\n'),
      );
    }

    final importable = [
      for (var i = 0; i < _choices.length; i++)
        if (!_committed.contains(i) && _choices[i].kind != _ActionKind.skip) i,
    ].length;
    // A shared bundle (share-target or manual pick, issue #852/#869) commits
    // programs regardless of how dance rows are dispositioned, so the button
    // gate must account for programs — not just the dance count. Mirrors the
    // identical check at the top of this method that routes zero-dance archives
    // to _buildSharedProgramsOnlyReview.
    final effectiveBundle = _effectiveSharedBundle;
    final programCount = effectiveBundle?.archive.programs.length ?? 0;
    final hasPrograms = programCount > 0;
    // How many *distinct* existing local dances a commit would overwrite (issue
    // #446): the unique re-import target ids across rows the user has set to
    // "Re-import onto …", excluding rows already committed on their own via
    // Edit. Counting unique targets (not rows) is deliberate — planning reuses
    // one DedupeIndex, so several incoming records that share a provenance key
    // can all target the same local dance; only that one dance is overwritten.
    // Surfaced as a warning before commit so an overwrite is always a
    // deliberate choice, never silent.
    final overwriteTargets = <String>{
      for (var i = 0; i < _choices.length; i++)
        if (!_committed.contains(i) &&
            _choices[i].kind == _ActionKind.reimport &&
            _choices[i].linkTargetId != null)
          _choices[i].linkTargetId!,
    };
    final overwriteCount = overwriteTargets.length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('import-review-list'),
            padding: const EdgeInsets.all(12),
            children: [
              if (_showSoftCapWarning) _buildSoftCapWarning(context),
              if (unreadable.isNotEmpty) _buildBatchErrors(context, unreadable),
              if (titleList != null) _buildTitleListSummary(context, titleList),
              for (var i = 0; i < batch.records.length; i++) ...[
                if (_isFirstRowOfProgramLine(i))
                  _buildProgramLineHeading(context, i),
                _buildRow(context, i, batch.records[i]),
              ],
              if (titleList != null)
                ..._buildTitleListGroups(context, titleList),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (overwriteCount > 0) ...[
                  _buildOverwriteWarning(context, overwriteCount),
                  const SizedBox(height: 8),
                ],
                if (hasPrograms) ...[
                  Text(
                    l10n.importReviewWillImportPrograms(programCount),
                    key: const ValueKey('import-programs-label'),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.importReviewWillImport(
                          importable,
                          batch.records.length,
                        ),
                        key: const ValueKey('import-count-label'),
                      ),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('import-commit-button'),
                      onPressed: (importable == 0 && !hasPrograms)
                          ? null
                          : _commit,
                      icon: const Icon(Icons.download_done),
                      label: Text(l10n.importAction),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The review body for a pasted title list that produced **nothing**
  /// importable — every title was either already in the collection or could not
  /// be found (issue #823).
  ///
  /// Deliberately not the generic "no dances found" dead end: that answer
  /// ("which of these do I already have?") is worth showing on its own, and a
  /// caller who pasted twelve titles and got none needs to see which six she
  /// owns and which two the app couldn't find, because those need completely
  /// different follow-up.
  ///
  /// It carries a Back affordance for the same reason the generic dead end does:
  /// there is no Import button on this screen, so without one the only way on is
  /// to close the whole import and start again — losing the answer she just
  /// asked for. Returning here resets the same state the generic message's
  /// button does.
  Widget _buildTitleListOnlyReview(
    BuildContext context,
    TitleListResolution titleList,
  ) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: const ValueKey('import-review-list'),
      padding: const EdgeInsets.all(12),
      children: [
        _buildTitleListSummary(context, titleList),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.importReviewTitleListNothingToImport,
            key: const ValueKey('import-titles-nothing-to-import'),
          ),
        ),
        ..._buildTitleListGroups(context, titleList),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('import-back-to-input'),
              onPressed: () => setState(_resetToInput),
              icon: const Icon(Icons.arrow_back),
              label: Text(l10n.commonBack),
            ),
          ),
        ),
      ],
    );
  }

  /// The banner heading the title-list review: how many titles were pasted and
  /// how they split across the three groups, so the shape of the answer is
  /// legible before scrolling.
  Widget _buildTitleListSummary(
    BuildContext context,
    TitleListResolution titleList,
  ) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final owned = titleList.countIn(TitleListGroup.alreadyInCollection);
    final notFound = titleList.countIn(TitleListGroup.notFound);
    final toImport = titleList.countIn(TitleListGroup.toImport);
    final parts = <String>[
      l10n.importReviewTitleListToImport(toImport),
      l10n.importReviewTitleListOwned(owned),
      l10n.importReviewTitleListNotFound(notFound),
    ];
    return Container(
      key: const ValueKey('import-titles-summary'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.importReviewTitleListPasted(titleList.rows.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(parts.join(' · ')),
          if (titleList.duplicateLines > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.importReviewTitleListDuplicates(titleList.duplicateLines),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  /// The two non-actionable groups, in the order a caller reads them: the
  /// dances she already owns, then the ones nothing could be found for. Both are
  /// omitted when empty. Each row states *why* it is here, because "already had
  /// it" and "couldn't find it" need completely different follow-up (issue
  /// #823).
  List<Widget> _buildTitleListGroups(
    BuildContext context,
    TitleListResolution titleList,
  ) {
    final l10n = AppLocalizations.of(context);
    final owned = titleList.rowsIn(TitleListGroup.alreadyInCollection).toList();
    final notFound = titleList.rowsIn(TitleListGroup.notFound).toList();
    return [
      if (owned.isNotEmpty)
        _buildTitleListGroup(
          context,
          key: 'owned',
          icon: Icons.library_add_check_outlined,
          heading: l10n.importReviewTitleListOwned(owned.length),
          rows: owned,
          detail: (row) => switch (row.localMatchCount) {
            1 =>
              row.localAuthors.isEmpty
                  ? l10n.importReviewTitleListOwnedUnknownAuthor
                  : l10n.importReviewTitleListOwnedBy(
                      row.localAuthors.join(', '),
                    ),
            _ => l10n.importReviewTitleListOwnedMany(row.localMatchCount),
          },
        ),
      if (notFound.isNotEmpty)
        _buildTitleListGroup(
          context,
          key: 'not-found',
          icon: Icons.search_off_outlined,
          heading: l10n.importReviewTitleListNotFound(notFound.length),
          rows: notFound,
          detail: (row) => titleListNotFoundReasonMessage(l10n, row.reason!),
        ),
    ];
  }

  Widget _buildTitleListGroup(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String heading,
    required List<TitleListRow> rows,
    required String Function(TitleListRow) detail,
  }) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('import-titles-group-$key'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(heading, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  key: ValueKey('import-titles-$key-${row.title}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.title, style: theme.textTheme.bodyLarge),
                    Text(
                      detail(row),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Whether the shared bundle exceeds the soft entity cap (issue #432). True
  /// on the OS share-target path ([widget.sharedBundle]) and also when the
  /// current paste-field text decodes to a bundle with programs
  /// ([_effectivePickedBundle], issue #852). The banner tracks the current
  /// paste-field text via [_onPasteChanged], so it updates whenever the text
  /// changes.
  bool get _showSoftCapWarning {
    final bundle = _effectiveSharedBundle;
    return bundle != null && bundle.entityCount > kSharedBundleSoftCapEntities;
  }

  /// An accessible advisory banner shown when a **shared** bundle carries more
  /// than [kSharedBundleSoftCapEntities] entities (issue #432). It is a soft
  /// warning, not a block: the Import button stays enabled and the user can
  /// still proceed. Distinct from the overwrite warning (which uses the error
  /// palette) — this uses the tertiary palette so "unusually large" reads as
  /// caution, not error.
  Widget _buildSoftCapWarning(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final message = l10n.sharedImportSoftCapWarning(
      _effectiveSharedBundle!.entityCount,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.importReviewWarningPrefix(message),
      child: Container(
        key: const ValueKey('import-soft-cap-warning'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The review body for a shared bundle that carries **programs but no dances**
  /// (issue #432). Such a bundle is valid (intake only rejects one with neither),
  /// and the pre-#432 auto-commit path imported it — so the consent screen must
  /// still offer an Import (routing through the same [_commit] → archive-importer
  /// path, which commits the programs and any venues from an empty dance batch),
  /// rather than dead-ending on the generic "no dances" message. Shows the
  /// soft-cap warning if applicable and honors the same transient Undo.
  Widget _buildSharedProgramsOnlyReview(
    BuildContext context,
    int programCount,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('import-review-list'),
            padding: const EdgeInsets.all(12),
            children: [
              if (_showSoftCapWarning) _buildSoftCapWarning(context),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.event_note_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.sharedImportProgramsOnly(programCount),
                      key: const ValueKey('import-count-label'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('import-commit-button'),
                onPressed: _commit,
                icon: const Icon(Icons.download_done),
                label: Text(l10n.importAction),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// An accessible pre-commit warning banner stating how many existing local
  /// dances a commit will overwrite (issue #446). Meaning is carried by an icon
  /// and text (not color alone), and a merged [Semantics] `label` announces the
  /// count to screen readers as a warning.
  Widget _buildOverwriteWarning(BuildContext context, int count) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final message = l10n.importReviewOverwriteWarning(count);
    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.importReviewWarningPrefix(message),
      child: Container(
        key: const ValueKey('import-overwrite-warning'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatchErrors(BuildContext context, List<ImportError> errors) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('import-batch-errors'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.importReviewBatchErrors(errors.length),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final e in errors)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${importRecordErrorMessage(l10n, e)}'),
              ),
          ],
        ),
      ),
    );
  }

  /// Whether row [i] is the first row of a program-ambiguity line (issue
  /// #943) — the point at which [_buildProgramLineHeading] should render.
  bool _isFirstRowOfProgramLine(int i) {
    if (i >= _programLineOfRow.length) return false;
    return i == 0 || _programLineOfRow[i - 1] != _programLineOfRow[i];
  }

  /// The heading introducing one program-ambiguity line's candidate rows
  /// (issue #943): the pasted line text, so the user can see which line these
  /// candidates are for before choosing one (or leaving them all skipped,
  /// keeping the line a note).
  Widget _buildProgramLineHeading(BuildContext context, int i) {
    final l10n = AppLocalizations.of(context);
    final lineIndex = _programLineOfRow[i];
    final lineText = widget.programAmbiguousImport!.lines
        .firstWhere((l) => l.originalLineIndex == lineIndex)
        .lineText;
    return Padding(
      key: ValueKey('import-program-line-$lineIndex'),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.help_outline, size: 18),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.importReviewProgramAmbiguousLine(lineText),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, int i, ImportRecordPlan plan) {
    final l10n = AppLocalizations.of(context);
    final draft = plan.draft;
    final quality = draft.quality;
    return Card(
      key: ValueKey('import-row-$i'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.dance.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _qualityChip(context, quality),
              ],
            ),
            for (final issue in draft.issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      issue.severity == ImportIssueSeverity.warning
                          ? Icons.warning_amber_outlined
                          : Icons.info_outline,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(importIssueMessage(l10n, issue))),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (_committed.contains(i))
              Row(
                key: ValueKey('import-row-$i-imported'),
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l10n.importReviewImported)),
                ],
              )
            else ...[
              _buildActions(context, i, plan.verdict),
              // The per-row Edit commits that one dance immediately (issue
              // #266). It is suppressed for a shared bundle (issue #432) so a
              // shared file can never write before the single batch Import
              // consent, and so every imported row is covered by the transient
              // batch Undo. Also suppressed for a manually picked .ccshare with
              // programs (_effectiveSharedBundle, issue #852/#880) for the same
              // reason, and for a program-ambiguity candidate (issue #943):
              // [_showResult] only reports [ImportReviewScreen.onProgramCommitted]
              // from the batch commit path, so an Edit-committed candidate would
              // create a dance the program screen never learns about and can
              // never link into its slot.
              if (_effectiveSharedBundle == null &&
                  i >= _programLineOfRow.length) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: ValueKey('import-row-$i-edit'),
                    onPressed: _choices[i].kind == _ActionKind.skip
                        ? null
                        : () => _editRow(i),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l10n.commonEdit),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _qualityChip(BuildContext context, ParseQuality quality) {
    final l10n = AppLocalizations.of(context);
    final label = quality.isFullyCustom
        ? l10n.importReviewCustom
        : l10n.importReviewStructured(
            quality.structuredFigures,
            quality.totalFigures,
          );
    return Chip(
      key: const ValueKey('import-quality-chip'),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  /// Builds the "Variation?" inline-diff block for row [i]'s confident
  /// candidate whose figures genuinely differ (issue #686): a heading naming
  /// [targetTitle], the [FigureDiffView] itself, and the "also link back as
  /// a related dance" checkbox (only meaningful when the row's choice ends up
  /// being [_ActionKind.variation], but shown alongside it so the choice is
  /// visible/adjustable before committing to that option).
  Widget _buildVariationBlock(
    BuildContext context,
    int i,
    FigureDiffResult diff,
    String targetTitle,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final choice = _choices[i];
    return Card(
      key: ValueKey('import-row-$i-variation'),
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.importReviewVariationTitle(targetTitle),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              l10n.importReviewVariationBody(targetTitle),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            FigureDiffView(result: diff),
            CheckboxListTile(
              key: ValueKey('import-row-$i-variation-linkback'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: choice.linkBack,
              title: Text(l10n.importReviewOptionLinkBack(targetTitle)),
              onChanged: (value) =>
                  setState(() => choice.linkBack = value ?? true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, int i, DedupeVerdict verdict) {
    final l10n = AppLocalizations.of(context);
    final choice = _choices[i];
    switch (verdict.kind) {
      case DedupeKind.isNew:
        return _radioGroup(i, choice, [
          _option(i, l10n.importReviewOptionNewDance, _ActionKind.create),
          _option(i, l10n.importReviewOptionSkip, _ActionKind.skip),
        ]);
      case DedupeKind.reimport:
        final title =
            '${_titlesById[verdict.targetDanceId] ?? verdict.targetDanceId}';
        return _radioGroup(i, choice, [
          _option(
            i,
            l10n.importReviewOptionReimport(title),
            _ActionKind.reimport,
            targetId: verdict.targetDanceId,
          ),
          _option(i, l10n.importReviewOptionDuplicate, _ActionKind.duplicate),
          _option(i, l10n.importReviewOptionSkip, _ActionKind.skip),
        ]);
      case DedupeKind.ambiguous:
        final confidentDiff = _confidentDiffs[i];
        final options = <_Option>[];
        Widget? variationBlock;
        for (final c in verdict.candidates) {
          final title = _titlesById[c.danceId] ?? c.danceId;
          // A confident candidate (issue #685) whose figures genuinely
          // differ (issue #686) gets the richer "Variation?" treatment
          // instead of the plain link row: an inline diff plus a choice
          // between importing as a distinct variation or treating it as the
          // same dance. A confident candidate whose figures are IDENTICAL
          // falls through to the plain link row below unchanged — that's
          // #685 territory (a true duplicate), not #686's.
          if (c.confident &&
              confidentDiff != null &&
              !confidentDiff.identical) {
            variationBlock = _buildVariationBlock(
              context,
              i,
              confidentDiff,
              title,
            );
            options.add(
              _option(
                i,
                l10n.importReviewOptionVariation(title),
                _ActionKind.variation,
                targetId: c.danceId,
              ),
            );
            options.add(
              _option(
                i,
                l10n.importReviewOptionSameDance(title),
                _ActionKind.link,
                targetId: c.danceId,
              ),
            );
            continue;
          }
          options.add(
            _option(
              i,
              l10n.importReviewOptionLink(title, (c.score * 100).round()),
              _ActionKind.link,
              targetId: c.danceId,
            ),
          );
        }
        options.add(
          _option(i, l10n.importReviewOptionDuplicate, _ActionKind.duplicate),
        );
        options.add(_option(i, l10n.importReviewOptionSkip, _ActionKind.skip));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.importReviewPossibleMatch,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            ?variationBlock,
            _radioGroup(i, choice, options),
          ],
        );
    }
  }

  /// A stable identity string for the current selection, distinguishing link
  /// and variation rows by their target id (a row may offer several link
  /// candidates, or a link and a variation option for the same candidate).
  String _selectionValue(_RowChoice choice) => switch (choice.kind) {
    _ActionKind.link => 'link:${choice.linkTargetId}',
    _ActionKind.variation => 'variation:${choice.linkTargetId}',
    _ => choice.kind.name,
  };

  Widget _radioGroup(int i, _RowChoice choice, List<_Option> options) {
    return RadioGroup<String>(
      groupValue: _selectionValue(choice),
      onChanged: (value) {
        if (value == null) return;
        final option = options.firstWhere((o) => o.value == value);
        setState(() {
          choice.kind = option.kind;
          choice.linkTargetId = option.targetId;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in options)
            RadioListTile<String>(
              key: ValueKey('import-row-$i-${o.keySuffix}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: o.value,
              title: Text(o.label),
            ),
        ],
      ),
    );
  }

  _Option _option(int i, String label, _ActionKind kind, {String? targetId}) {
    final value = switch (kind) {
      _ActionKind.link => 'link:$targetId',
      _ActionKind.variation => 'variation:$targetId',
      _ => kind.name,
    };
    final keySuffix = switch (kind) {
      _ActionKind.link => 'link-$targetId',
      _ActionKind.variation => 'variation-$targetId',
      _ => kind.name,
    };
    return _Option(
      value: value,
      keySuffix: keySuffix,
      label: label,
      kind: kind,
      targetId: targetId,
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const ValueKey('import-message'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const ValueKey('import-back-to-input'),
              onPressed: _isStandalonePublishedSeed
                  ? (widget.onClose ?? () => Navigator.of(context).pop())
                  : () => setState(_resetToInput),
              child: Text(
                _isStandalonePublishedSeed
                    ? l10n.commonBack
                    : l10n.importReviewTryAnother,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable action in a row's [RadioGroup]. [value] is the group's stable
/// identity string (link options carry their target id so multiple link
/// candidates stay distinct); [kind]/[targetId] are applied to the row's choice
/// when selected.
class _Option {
  const _Option({
    required this.value,
    required this.keySuffix,
    required this.label,
    required this.kind,
    this.targetId,
  });

  final String value;
  final String keySuffix;
  final String label;
  final _ActionKind kind;
  final String? targetId;
}
