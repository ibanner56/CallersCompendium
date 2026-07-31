import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/collection_refresh_scope.dart';
import '../data/import_diagnostic_labels.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/repositories_scope.dart';
import '../data/active_dialect_scope.dart';
import '../data/shorthand_mappings_scope.dart';
import '../data/venue_entity_mode_scope.dart';
import '../utils/undo_snack_bar.dart';
import 'dance_editor_screen.dart';
import 'import_shorthand_seed_screen.dart';

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

/// The adapter-agnostic in-app import experience (ROADMAP 6.3): pick or paste a
/// source payload, [ImportPipeline.plan] it non-destructively, review every
/// discovered record (with its parse quality, issues, and dedupe verdict),
/// resolve any ambiguous matches, commit, and offer an undo.
///
/// The screen takes a list of selectable [ImportSource]s so it is not tied to
/// any one source; this wires the generic [GenericJsonAdapter] ("Caller's
/// Compendium JSON", the default), the [CallersBoxAdapter] ("The Caller's Box"),
/// the [ContraDbHtmlAdapter] ("ContraDB"), and the byte-based
/// [CallersCompanionUsrAdapter] ("a Caller's Companion .USR file"). The `.USR`
/// source picks a binary file (bytes, not text) and — uniquely — commits and
/// undoes **programs** alongside dances via [CallersCompanionUsrImporter]; every
/// other source is dance-only text. The user picks the source explicitly (a
/// dropdown) so a bare id — which has no host to auto-detect — routes
/// unambiguously. A fresh adapter is built per plan because adapters may hold
/// per-discovery state.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.sources,
    this.picker,
    this.bytePicker,
    this.fetcher,
    this.onClose,
    this.sharedBundle,
  }) : assert(sources.length > 0, 'at least one import source is required');

  /// The selectable import sources; the first is selected by default.
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

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

enum _Phase { input, planning, review, committing }

/// The action the user chose (or that was defaulted) for one record.
enum _ActionKind { create, reimport, link, duplicate, skip }

/// One record's mutable review choice. Defaults are set from the verdict:
/// new → create, reimport → skip (keep-local; never a silent overwrite),
/// ambiguous → skip (never a silent create). See [_defaultChoice].
class _RowChoice {
  _RowChoice(this.kind, [this.linkTargetId]);

  _ActionKind kind;

  /// The candidate dance id to link/reimport onto (for link/reimport).
  String? linkTargetId;
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late final CompendiumRepositories _repos;
  bool _started = false;

  /// The currently selected import source (defaults to the first). Governs
  /// which adapter parses the payload and how URL-mode input is transformed.
  late ImportSource _selected = widget.sources.first;

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

  /// True when the selected source imports from a picked binary file rather than
  /// pasted/fetched text (governs the input UI and which plan path runs).
  bool get _isByteSource => _selected.bytePicker != null;

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

  Object? _planError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      final bundle = widget.sharedBundle;
      if (bundle != null) {
        // Share-target intake (issue #432): the bundle was already decoded and
        // validated Dart-side. Seed it and plan immediately so the user lands
        // on the review/consent list — skipping the manual input phase — with
        // nothing written until they confirm.
        _pasteController.text = bundle.json;
        _sourceUri = null;
        _plan();
      }
    }
  }

  @override
  void dispose() {
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
      _sourceUri = null;
      setState(() {});
    } on ImportFileTooLargeException catch (e) {
      // Untrusted input rejected before it was read into memory — tell the user
      // plainly (accessible SnackBar) and leave the input untouched.
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
    } on ImportFileTooLargeException catch (e) {
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
    } on UrlFetchException catch (e) {
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
    } on UrlFetchException catch (e) {
      if (!mounted) return;
      setState(() => _fetchError = importErrorMessage(l10n, e));
    } catch (e) {
      if (!mounted) return;
      // Never surface the raw error to the user (CWE-209); keep it for debug
      // logging only and show a generic, localized fetch-failure message.
      if (kDebugMode) {
        debugPrint('Import URL fetch failed: $e');
      }
      setState(() => _fetchError = l10n.importErrorUnreachable);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _plan() async {
    final payload = _pasteController.text;
    final bytes = _payloadBytes;
    if (_isByteSource) {
      if (bytes == null) return;
    } else if (payload.trim().isEmpty) {
      return;
    }
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
      final titles = {
        for (final e in await _repos.dances.listIdsAndTitles()) e.id: e.title,
      };
      if (!mounted) return;
      setState(() {
        _batch = batch;
        _titlesById = titles;
        _choices = [for (final plan in batch.records) _defaultChoice(plan)];
        _committed.clear();
        _phase = _Phase.review;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _planError = e;
        _phase = _Phase.review;
      });
    }
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
      case _ActionKind.skip:
        return null;
    }
  }

  /// Builds the batch actually committed plus its resolutions map; skipped rows
  /// are omitted so nothing is written for them.
  (ImportBatchResult, Map<int, DedupeResolution>, int) _buildCommitBatch() {
    final batch = _batch!;
    final acted = <ImportRecordPlan>[];
    final resolutions = <int, DedupeResolution>{};
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
      final (plan, resolution) = planned;
      final j = acted.length;
      acted.add(plan);
      if (resolution != null) resolutions[j] = resolution;
    }
    return (ImportBatchResult(records: acted), resolutions, skipped);
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
      // Refresh the live Collection so the committed dance appears immediately.
      CollectionRefreshScope.bump(context);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DanceEditorScreen(danceId: danceId),
        ),
      );
      if (!mounted) return;
      // Edits made in the editor also need to surface in the live Collection.
      CollectionRefreshScope.bump(context);
    } catch (e, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('Import commit-for-edit failed: $e\n$stackTrace');
      }
      setState(() => _phase = _Phase.review);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('import-edit-error'),
          content: Text(AppLocalizations.of(context).importReviewImportError),
        ),
      );
    }
  }

  Future<void> _commit() async {
    final (commitBatch, resolutions, skipped) = _buildCommitBatch();
    setState(() => _phase = _Phase.committing);
    final pipeline = ImportPipeline(_repos.dances, _repos.choreographers);
    // Commit/undo routing is gated on the concrete adapter type — NOT on
    // `_isByteSource` — so only Caller's Companion `.USR` persists/undoes
    // programs. A hypothetical future dance-only byte source would fall through
    // to the shared dance path and never touch programs.
    final adapter = _selected.adapterFactory();
    final sharedBundle = widget.sharedBundle;
    try {
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
          _repos.dances,
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
        CollectionRefreshScope.bump(context);
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
        // Refresh the live Collection so imported dances appear immediately.
        CollectionRefreshScope.bump(context);
        await _showResult(
          session: session,
          skipped: skipped,
          onUndo: () => pipeline.undo(session),
        );
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('Import commit failed: $e\n$stackTrace');
      }
      setState(() => _phase = _Phase.review);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('import-commit-error'),
          content: Text(AppLocalizations.of(context).importReviewImportError),
        ),
      );
    }
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
        // Bounds/duplicate backstop — never surface a raw error to the user
        // (this is an optional background step), but log it so an unexpected
        // failure is diagnosable.
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
    // Refresh the live Collection so the imported rows appear immediately.
    CollectionRefreshScope.bump(context);
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
    // Capture the refresh notifier now: the snackbar (and its Undo) outlives
    // this screen once we pop back to the shell, so the async Undo callback
    // can't read it from this (by then defunct) context.
    final refresh = CollectionRefreshScope.maybeOf(context);
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
        refresh?.value++;
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
  }) async {
    final l10n = AppLocalizations.of(context);
    var created = 0, reimported = 0, linked = 0, duplicated = 0;
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
              _summaryLine('Skipped', l10n.importReviewSummarySkipped(skipped)),
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
      // Undo reverted the DB; refresh again and stay for another attempt.
      CollectionRefreshScope.bump(context);
      setState(() => _phase = _Phase.review);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('import-undone-snackbar'),
          content: Text(l10n.importReviewUndone),
        ),
      );
    } else {
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
          _Phase.planning => const Center(
            key: ValueKey('import-planning'),
            child: CircularProgressIndicator(),
          ),
          _Phase.committing => const Center(
            key: ValueKey('import-committing'),
            child: CircularProgressIndicator(),
          ),
          _Phase.review => _buildReview(context),
        },
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasContent = _isByteSource
        ? _payloadBytes != null
        : _pasteController.text.trim().isNotEmpty;
    // While a file pick or URL fetch is in flight, lock every input so a
    // late-completing pick/fetch can't overwrite the payload or clobber
    // `_sourceUri` under the user, and so planning can't start on stale input.
    final busy = _picking || _fetching;
    final isUrlSource = _selected.urlBuilder != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.sources.length > 1) ...[
          Text(
            l10n.importReviewSourceLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          DropdownButton<ImportSource>(
            key: const ValueKey('import-source-select'),
            isExpanded: true,
            value: _selected,
            onChanged: busy
                ? null
                : (source) {
                    if (source == null) return;
                    setState(() {
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
                    });
                  },
            items: [
              for (final source in widget.sources)
                DropdownMenuItem<ImportSource>(
                  value: source,
                  child: Text(importSourceLabel(l10n, source.kind)),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (_isByteSource) ...[
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
    if (batch.records.isEmpty) {
      // A shared bundle can legitimately carry programs but no dances (e.g. a
      // program of only free-text/announcement slots). It passed intake (which
      // rejects only a bundle with neither dances nor programs), so the review
      // must still let the user consent to importing the programs — dead-ending
      // on "no dances" would regress the pre-#432 behavior that imported such
      // bundles. Only fall through here when there is nothing importable at all.
      final sharedBundle = widget.sharedBundle;
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
              for (var i = 0; i < batch.records.length; i++)
                _buildRow(context, i, batch.records[i]),
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
                      onPressed: importable == 0 ? null : _commit,
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

  /// Whether the shared bundle exceeds the soft entity cap (issue #432). Only
  /// ever true on the share-target path (a manual import has no [sharedBundle]).
  bool get _showSoftCapWarning {
    final bundle = widget.sharedBundle;
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
      widget.sharedBundle!.entityCount,
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
              // batch Undo.
              if (widget.sharedBundle == null) ...[
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
            _radioGroup(i, choice, [
              for (final c in verdict.candidates)
                _option(
                  i,
                  l10n.importReviewOptionLink(
                    _titlesById[c.danceId] ?? c.danceId,
                    (c.score * 100).round(),
                  ),
                  _ActionKind.link,
                  targetId: c.danceId,
                ),
              _option(
                i,
                l10n.importReviewOptionDuplicate,
                _ActionKind.duplicate,
              ),
              _option(i, l10n.importReviewOptionSkip, _ActionKind.skip),
            ]),
          ],
        );
    }
  }

  /// A stable identity string for the current selection, distinguishing link
  /// rows by their target id (a row may offer several link candidates).
  String _selectionValue(_RowChoice choice) => choice.kind == _ActionKind.link
      ? 'link:${choice.linkTargetId}'
      : choice.kind.name;

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
    final value = kind == _ActionKind.link ? 'link:$targetId' : kind.name;
    final keySuffix = kind == _ActionKind.link ? 'link-$targetId' : kind.name;
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
              onPressed: () => setState(() {
                _phase = _Phase.input;
                _batch = null;
                _planError = null;
              }),
              child: Text(l10n.importReviewTryAnother),
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
