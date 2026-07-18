import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/plaintext_program_import.dart';
import '../data/repositories_scope.dart';

/// Builds a [Program] from a pasted, newline-separated list of dance titles
/// (epic #291, sub-issue #312).
///
/// One non-blank line becomes one program slot, in order. Each title is matched
/// case-insensitively against the local collection: an exact single match links
/// to that dance; an unmatched or ambiguous (multi-match) line becomes a
/// free-text note slot — the same note path announcements/breaks use — so
/// nothing is dropped and ordering is preserved.
///
/// The Caller's Box fallback (#313) and ContraDB import (#314) are intentionally
/// out of scope here.
///
/// Pushed as a route; pops with the created program's id on success (null if the
/// user backs out), mirroring [ProgramEditorScreen]. Commit shows an undo
/// SnackBar that hard-deletes the just-created program.
class PlaintextProgramImportScreen extends StatefulWidget {
  const PlaintextProgramImportScreen({super.key});

  @override
  State<PlaintextProgramImportScreen> createState() =>
      _PlaintextProgramImportScreenState();
}

class _PlaintextProgramImportScreenState
    extends State<PlaintextProgramImportScreen> {
  late final CompendiumRepositories _repos;
  bool _started = false;

  final _titleController = TextEditingController();
  final _pasteController = TextEditingController();

  /// Local `(id, title)` listing used for case-insensitive title resolution.
  List<({String id, String title})>? _collection;
  Object? _loadError;

  bool _committing = false;

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
      _titleController.addListener(_onInputChanged);
      _pasteController.addListener(_onInputChanged);
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

  void _onInputChanged() => setState(() {});

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

  bool get _canCommit =>
      !_committing &&
      _collection != null &&
      _titleController.text.trim().isNotEmpty &&
      _parsedLines.isNotEmpty;

  Future<void> _commit() async {
    if (!_canCommit) return;
    setState(() => _committing = true);
    final lines = _parsedLines;
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
    } catch (error) {
      if (!mounted) return;
      setState(() => _committing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('plaintext-import-error-snackbar'),
          content: Text('Could not import program: $error'),
        ),
      );
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final matched = lines
        .where((l) => l.resolution == PlaintextLineResolution.matched)
        .length;
    final notes = lines.length - matched;
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('plaintext-import-committed-snackbar'),
        content: Text(
          'Imported "${program.title}" — ${lines.length} '
          '${lines.length == 1 ? 'slot' : 'slots'} '
          '($matched linked, $notes ${notes == 1 ? 'note' : 'notes'}).',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _repos.programs.hardDelete([id]),
        ),
      ),
    );
    navigator.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from title list'),
        actions: [
          TextButton(
            key: const ValueKey('plaintext-import-commit'),
            onPressed: _canCommit ? _commit : null,
            child: const Text('Import'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Could not load your collection.'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                setState(() {
                  _collection = null;
                  _loadError = null;
                });
                _load();
              },
              child: const Text('Retry'),
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
              decoration: const InputDecoration(
                labelText: 'Program title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('plaintext-import-paste'),
              controller: _pasteController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Dance titles (one per line)',
                hintText:
                    'Paste one dance title per line.\n'
                    'Unrecognised lines are kept as notes.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
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
    if (_collection == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final lines = _parsedLines;
    if (lines.isEmpty) {
      return Center(
        key: const ValueKey('plaintext-import-empty-preview'),
        child: Text(
          'Paste a list of dance titles above to preview the program.',
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
          child: Text(
            '${lines.length} ${lines.length == 1 ? 'slot' : 'slots'}',
            style: Theme.of(context).textTheme.bodySmall,
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
    final scheme = Theme.of(context).colorScheme;
    final (
      IconData icon,
      Color color,
      String label,
    ) = switch (line.resolution) {
      PlaintextLineResolution.matched => (
        Icons.link,
        scheme.primary,
        'Linked to dance',
      ),
      PlaintextLineResolution.ambiguous => (
        Icons.help_outline,
        scheme.tertiary,
        'Multiple matches — added as note',
      ),
      PlaintextLineResolution.unmatched => (
        Icons.sticky_note_2_outlined,
        scheme.outline,
        'No match — added as note',
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
