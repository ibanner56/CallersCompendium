import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/collection_refresh_scope.dart';
import '../data/import_io.dart';
import '../data/repositories_scope.dart';

/// The adapter-agnostic in-app import experience (ROADMAP 6.3): pick or paste a
/// source payload, [ImportPipeline.plan] it non-destructively, review every
/// discovered record (with its parse quality, issues, and dedupe verdict),
/// resolve any ambiguous matches, commit, and offer an undo.
///
/// The screen takes a [SourceAdapter] factory so it is not tied to any one
/// source; this PR wires the single concrete [GenericJsonAdapter] ("Import from
/// Caller's Compendium JSON"). A fresh adapter is built per plan because
/// adapters may hold per-discovery state.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.adapterFactory,
    required this.sourceLabel,
    this.picker,
  });

  /// Builds a fresh [SourceAdapter] for each planning run.
  final SourceAdapter Function() adapterFactory;

  /// Human-readable name of the source, e.g. "Caller's Compendium JSON".
  final String sourceLabel;

  /// Test seam for choosing a file; defaults to [pickImportFile] (native
  /// open-file dialog). Widget tests inject canned text.
  final ImportPicker? picker;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

enum _Phase { input, planning, review, committing }

/// The action the user chose (or that was defaulted) for one record.
enum _ActionKind { create, reimport, link, duplicate, skip }

/// One record's mutable review choice. Defaults are set from the verdict:
/// new → create, reimport → reimport, ambiguous → skip (never a silent create).
class _RowChoice {
  _RowChoice(this.kind, [this.linkTargetId]);

  _ActionKind kind;

  /// The candidate dance id to link/reimport onto (for link/reimport).
  String? linkTargetId;
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late final CompendiumRepositories _repos;
  bool _started = false;

  final TextEditingController _pasteController = TextEditingController();
  bool _picking = false;

  _Phase _phase = _Phase.input;

  ImportBatchResult? _batch;
  List<_RowChoice> _choices = const [];

  /// Existing dance id → title, for showing candidate/reimport target names.
  Map<String, String> _titlesById = const {};

  Object? _planError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
    }
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final picker = widget.picker ?? pickImportFile;
    setState(() => _picking = true);
    try {
      final text = await picker();
      if (!mounted || text == null) return;
      _pasteController.text = text;
      setState(() {});
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _plan() async {
    final payload = _pasteController.text;
    if (payload.trim().isEmpty) return;
    setState(() {
      _phase = _Phase.planning;
      _planError = null;
    });
    try {
      final pipeline = ImportPipeline(_repos.dances, _repos.choreographers);
      final index = await pipeline.buildDedupeIndex();
      final batch = await pipeline.plan(
        widget.adapterFactory(),
        ImportRequest(payload: payload),
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
        return _RowChoice(_ActionKind.reimport, plan.verdict.targetDanceId);
      case DedupeKind.ambiguous:
        return _RowChoice(_ActionKind.skip);
    }
  }

  /// Builds the batch actually committed plus its resolutions map. Each acted
  /// row is reconstructed with the exact verdict/resolution that yields the
  /// chosen [CommitAction] (the core pipeline honours resolutions only for
  /// ambiguous verdicts, so create/reimport/link/duplicate are expressed
  /// directly); skipped rows are omitted so nothing is written for them.
  (ImportBatchResult, Map<int, DedupeResolution>, int) _buildCommitBatch() {
    final batch = _batch!;
    final acted = <ImportRecordPlan>[];
    final resolutions = <int, DedupeResolution>{};
    var skipped = 0;
    for (var i = 0; i < batch.records.length; i++) {
      final draft = batch.records[i].draft;
      final choice = _choices[i];
      final j = acted.length;
      switch (choice.kind) {
        case _ActionKind.create:
          acted.add(
            ImportRecordPlan(draft: draft, verdict: DedupeVerdict.isNew()),
          );
        case _ActionKind.reimport:
          acted.add(
            ImportRecordPlan(
              draft: draft,
              verdict: DedupeVerdict.reimport(choice.linkTargetId!),
            ),
          );
        case _ActionKind.link:
          acted.add(
            ImportRecordPlan(
              draft: draft,
              verdict: DedupeVerdict.ambiguous(
                batch.records[i].verdict.candidates,
              ),
            ),
          );
          resolutions[j] = DedupeResolution.link(choice.linkTargetId!);
        case _ActionKind.duplicate:
          acted.add(
            ImportRecordPlan(
              draft: draft,
              verdict: DedupeVerdict.ambiguous(const []),
            ),
          );
          resolutions[j] = DedupeResolution.duplicate();
        case _ActionKind.skip:
          skipped++;
      }
    }
    return (ImportBatchResult(records: acted), resolutions, skipped);
  }

  Future<void> _commit() async {
    final (commitBatch, resolutions, skipped) = _buildCommitBatch();
    setState(() => _phase = _Phase.committing);
    final pipeline = ImportPipeline(_repos.dances, _repos.choreographers);
    try {
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
      await _showResult(pipeline, session, skipped);
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.review);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('import-commit-error'),
          content: Text("Couldn't import: $e"),
        ),
      );
    }
  }

  Future<void> _showResult(
    ImportPipeline pipeline,
    ImportSession session,
    int skipped,
  ) async {
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
    var undone = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('import-result-dialog'),
        title: const Text('Import complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryLine('Created', created),
            _summaryLine('Re-imported', reimported),
            _summaryLine('Linked', linked),
            _summaryLine('Duplicated', duplicated),
            _summaryLine('Skipped', skipped),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${errors.length} record(s) failed to import:',
                style: Theme.of(dialogContext).textTheme.labelLarge,
              ),
              for (final e in errors)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• ${e.message}'),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('import-undo-button'),
            onPressed: () async {
              await pipeline.undo(session);
              undone = true;
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Undo'),
          ),
          FilledButton(
            key: const ValueKey('import-done-button'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
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
        const SnackBar(
          key: ValueKey('import-undone-snackbar'),
          content: Text('Import undone.'),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _summaryLine(String label, int count) =>
      Text('$label: $count', key: ValueKey('import-summary-$label'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import dances'),
        key: const ValueKey('import-review-appbar'),
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
    );
  }

  Widget _buildInput(BuildContext context) {
    final hasContent = _pasteController.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Import dances from ${widget.sourceLabel}.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose a file or paste its contents. Nothing is added to your '
          'collection until you review and confirm.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('import-choose-file'),
          onPressed: _picking ? null : _chooseFile,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose file…'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('import-paste-field'),
          controller: _pasteController,
          minLines: 4,
          maxLines: 10,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Or paste JSON',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('import-continue'),
          onPressed: hasContent ? _plan : null,
          icon: const Icon(Icons.playlist_add_check),
          label: const Text('Review import'),
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final batch = _batch;
    if (_planError != null) {
      return _buildMessage(
        context,
        icon: Icons.error_outline,
        title: "Couldn't read the import",
        detail: '$_planError',
      );
    }
    if (batch == null) return const SizedBox.shrink();

    final unreadable = batch.errors;
    if (batch.records.isEmpty) {
      return _buildMessage(
        context,
        icon: unreadable.isEmpty ? Icons.inbox_outlined : Icons.error_outline,
        title: unreadable.isEmpty
            ? 'No dances found'
            : "Couldn't read the import",
        detail: unreadable.isEmpty
            ? 'The file did not contain any dances to import.'
            : unreadable.map((e) => e.message).join('\n'),
      );
    }

    final importable = _choices.where((c) => c.kind != _ActionKind.skip).length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('import-review-list'),
            padding: const EdgeInsets.all(12),
            children: [
              if (unreadable.isNotEmpty) _buildBatchErrors(context, unreadable),
              for (var i = 0; i < batch.records.length; i++)
                _buildRow(context, i, batch.records[i]),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$importable of ${batch.records.length} will be imported',
                    key: const ValueKey('import-count-label'),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('import-commit-button'),
                  onPressed: importable == 0 ? null : _commit,
                  icon: const Icon(Icons.download_done),
                  label: const Text('Import'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBatchErrors(BuildContext context, List<ImportError> errors) {
    return Card(
      key: const ValueKey('import-batch-errors'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${errors.length} record(s) couldn't be read (the rest can still "
              'be imported):',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final e in errors)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${e.message}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, int i, ImportRecordPlan plan) {
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
                    Expanded(child: Text(issue.message)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            _buildActions(context, i, plan.verdict),
          ],
        ),
      ),
    );
  }

  Widget _qualityChip(BuildContext context, ParseQuality quality) {
    final label = quality.isFullyCustom
        ? 'Custom'
        : '${quality.structuredFigures}/${quality.totalFigures} structured';
    return Chip(
      key: const ValueKey('import-quality-chip'),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildActions(BuildContext context, int i, DedupeVerdict verdict) {
    final choice = _choices[i];
    switch (verdict.kind) {
      case DedupeKind.isNew:
        return _radioGroup(i, choice, [
          _option(i, 'New dance', _ActionKind.create),
          _option(i, 'Skip', _ActionKind.skip),
        ]);
      case DedupeKind.reimport:
        final title =
            _titlesById[verdict.targetDanceId] ?? verdict.targetDanceId;
        return _radioGroup(i, choice, [
          _option(
            i,
            'Re-import onto "$title"',
            _ActionKind.reimport,
            targetId: verdict.targetDanceId,
          ),
          _option(
            i,
            'Import as a new (duplicate) dance',
            _ActionKind.duplicate,
          ),
          _option(i, 'Skip', _ActionKind.skip),
        ]);
      case DedupeKind.ambiguous:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Possible match — choose how to import:',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            _radioGroup(i, choice, [
              for (final c in verdict.candidates)
                _option(
                  i,
                  'Link to "${_titlesById[c.danceId] ?? c.danceId}" '
                  '(${(c.score * 100).round()}% match)',
                  _ActionKind.link,
                  targetId: c.danceId,
                ),
              _option(
                i,
                'Import as a new (duplicate) dance',
                _ActionKind.duplicate,
              ),
              _option(i, 'Skip', _ActionKind.skip),
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
              child: const Text('Try another file'),
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
