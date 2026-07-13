import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/facet_labels.dart';
import '../widgets/figure_table.dart';
import 'dance_editor_screen.dart';

/// Dance detail / card (`docs/design/ux.md` §2): header (title, authors,
/// formation, hook, tags, status banner, provenance line), a figure table
/// grouped by derived section with a canonical ⇄ dialect toggle, and the
/// calling notes / links / custom-field sections. The Edit action opens the
/// [DanceEditorScreen] (roadmap 3.3).
///
/// [onRestored] is called (if provided) when the user taps the Undo action
/// on the delete snackbar — allowing the caller (e.g. the Collection screen)
/// to reload its list so the restored dance reappears immediately.
class DanceDetailScreen extends StatefulWidget {
  const DanceDetailScreen({super.key, required this.danceId, this.onRestored});

  final String danceId;

  /// Optional callback invoked after a soft-delete is undone (restored).
  /// The Collection screen passes `() => _boot()` here so the list reloads.
  final VoidCallback? onRestored;

  @override
  State<DanceDetailScreen> createState() => _DanceDetailScreenState();
}

class _DanceDetailScreenState extends State<DanceDetailScreen> {
  late CompendiumRepositories _repos;
  Future<_DanceDetail?>? _future;

  /// When `false` the figure table renders in the user's active dialect;
  /// when `true` it renders canonical role/move tokens.  The toggle is hidden
  /// when the active dialect is already [Dialect.canonical] (toggling would
  /// be a no-op).
  bool _canonicalView = false;

  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only load once: didChangeDependencies also fires for unrelated ancestor
    // changes (Theme/MediaQuery/Localizations).
    if (_future == null) {
      _repos = RepositoriesScope.of(context);
      _future = _load();
    }
  }

  Future<_DanceDetail?> _load() async {
    final dance = await _repos.dances.getById(widget.danceId);
    if (dance == null) return null;

    final choreographers = await _repos.choreographers.listAll();
    final tags = await _repos.tags.listAll();
    final fieldDefs = await _repos.customFieldDefs.listAll();
    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};
    final defsById = {for (final d in fieldDefs) d.id: d};

    return _DanceDetail(
      dance: dance,
      authorNames: [
        for (final id in dance.authorIds)
          if (choreographerNames[id] != null) choreographerNames[id]!,
      ],
      tagNames: [
        for (final id in dance.tagIds)
          if (tagNames[id] != null) tagNames[id]!,
      ],
      customFields: [
        for (final value in dance.customFields)
          if (defsById[value.fieldId] case final def?)
            (label: def.label, value: _formatFieldValue(value.value)),
      ],
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DanceEditorScreen(danceId: widget.danceId),
      ),
    );
    if (mounted) _reload();
  }

  /// Duplicates the dance, appends " (copy)" to the copy's title (since
  /// [Dance.duplicate] preserves the original title verbatim), then navigates
  /// to the new copy's detail screen.
  Future<void> _duplicate() async {
    final now = DateTime.now().toUtc();
    final copy = await _repos.dances.duplicate(
      id: widget.danceId,
      newId: uuidV4(),
      now: now,
    );
    // Append " (copy)" so the duplicate is visually distinct in the list.
    await _repos.dances.update(
      copy.copyWith(title: '${copy.title} (copy)', updatedAt: now),
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DanceDetailScreen(danceId: copy.id),
      ),
    );
  }

  /// Soft-deletes the dance immediately and shows an "Undo" snackbar that
  /// calls [DanceRepository.restore] if tapped. Pops back to the list after
  /// deleting (before the snackbar appears, so the deleted dance is no longer
  /// visible in the collection). Pops with `true` so the caller can reload.
  /// [widget.onRestored] is called on undo so the Collection can re-display
  /// the dance without requiring user-initiated navigation.
  Future<void> _delete() async {
    final title = (await _future)?.dance.title ?? 'Dance';
    final now = DateTime.now().toUtc();
    await _repos.dances.softDelete(widget.danceId, at: now);
    if (!mounted) return;
    // Capture ScaffoldMessengerState before pop() so we don't read a
    // deactivating context after the route is removed from the tree.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('deleted-snackbar'),
        content: Text('"$title" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await _repos.dances.restore(
              widget.danceId,
              at: DateTime.now().toUtc(),
            );
            widget.onRestored?.call();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dance'),
        actions: [
          FutureBuilder<_DanceDetail?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.data == null) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('duplicate-dance'),
                    tooltip: 'Duplicate dance',
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: _duplicate,
                  ),
                  TextButton.icon(
                    key: const ValueKey('edit-dance'),
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  IconButton(
                    key: const ValueKey('delete-dance'),
                    tooltip: 'Delete dance',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _delete,
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<_DanceDetail?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data;
          if (detail == null) {
            return const Center(child: Text('Dance not found.'));
          }
          return _buildBody(detail);
        },
      ),
    );
  }

  Widget _buildBody(_DanceDetail detail) {
    final theme = Theme.of(context);
    final dance = detail.dance;
    final activeDialect = ActiveDialectScope.of(context);
    // When the active dialect is already canonical, _canonicalView is a no-op
    // (both sides of the toggle are identical).  In that case hide the toggle.
    final isCanonicalDialect = activeDialect == Dialect.canonical;
    final dialect = _canonicalView ? Dialect.canonical : activeDialect;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(dance.title, style: theme.textTheme.headlineSmall),
        if (detail.authorNames.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(detail.authorNames.join(', '), style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.grid_view, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(formationLabel(dance.formation))),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.repeat, size: 18),
            const SizedBox(width: 6),
            Text(progressionLabel(dance.progression)),
          ],
        ),
        if (dance.status != DanceStatus.active) ...[
          const SizedBox(height: 12),
          _StatusBanner(status: dance.status),
        ],
        if (dance.provenance != null) ...[
          const SizedBox(height: 8),
          _ProvenanceLine(provenance: dance.provenance!),
        ],
        if (dance.hook.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(dance.hook, style: theme.textTheme.bodyLarge),
        ],
        if (detail.tagNames.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final tag in detail.tagNames)
                Chip(
                  avatar: const Icon(Icons.label_outline, size: 16),
                  label: Text(tag),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Text('Figures', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (!isCanonicalDialect)
              _DialectToggle(
                canonical: _canonicalView,
                onChanged: (value) => setState(() => _canonicalView = value),
              ),
          ],
        ),
        FigureTable(
          figures: dance.figures,
          phraseStructure: dance.phraseStructure,
          renderer: _renderer,
          dialect: dialect,
        ),
        if (dance.callingNotes.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Calling notes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _renderer.renderFreeText(dance.callingNotes, dialect),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (dance.tunes.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Tunes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(dance.tunes.join(', ')),
        ],
        if (dance.links.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Links', style: theme.textTheme.titleMedium),
          for (final link in dance.links) _LinkRow(link: link),
        ],
        if (detail.customFields.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Custom fields', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final field in detail.customFields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${field.label}: ${field.value}'),
            ),
        ],
      ],
    );
  }
}

String _formatFieldValue(Object value) {
  if (value is bool) return value ? 'Yes' : 'No';
  return value.toString();
}

class _DialectToggle extends StatelessWidget {
  const _DialectToggle({required this.canonical, required this.onChanged});

  final bool canonical;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Show canonical terms',
      toggled: canonical,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Canonical'),
          Switch(
            key: const ValueKey('dialect-toggle'),
            value: canonical,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final DanceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (status) {
      DanceStatus.broken => (Icons.error_outline, theme.colorScheme.error),
      DanceStatus.deprecated => (
        Icons.warning_amber,
        theme.colorScheme.tertiary,
      ),
      DanceStatus.active => (
        Icons.check_circle_outline,
        theme.colorScheme.primary,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            danceStatusLabel(status),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvenanceLine extends StatelessWidget {
  const _ProvenanceLine({required this.provenance});

  final Provenance provenance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final license = provenance.license;
    final text = [
      'via ${_sourceLabel(provenance.source)}',
      if (license != null && license.isNotEmpty) license,
    ].join(' · ');
    return Row(
      children: [
        const Icon(Icons.source_outlined, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _sourceLabel(ProvenanceSource source) => switch (source) {
    ProvenanceSource.callersbox => "The Caller's Box",
    ProvenanceSource.contradb => 'ContraDB',
    ProvenanceSource.callersCompanion => "Caller's Companion",
    ProvenanceSource.manual => 'manual entry',
    ProvenanceSource.json => 'JSON import',
  };
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link});

  final DanceLink link;

  @override
  Widget build(BuildContext context) {
    final label = link.label?.trim();
    final display = (label != null && label.isNotEmpty)
        ? label
        : (link.url ?? link.targetDanceId ?? '');
    final icon = switch (link.kind) {
      LinkKind.source => Icons.article_outlined,
      LinkKind.video => Icons.play_circle_outline,
      LinkKind.relatedDance => Icons.link,
      LinkKind.other => Icons.open_in_new,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(display)),
        ],
      ),
    );
  }
}

typedef _CustomFieldDisplay = ({String label, String value});

class _DanceDetail {
  _DanceDetail({
    required this.dance,
    required this.authorNames,
    required this.tagNames,
    required this.customFields,
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;
  final List<_CustomFieldDisplay> customFields;
}
