import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/callersbox_online.dart';
import '../data/contradb_online.dart';
import '../data/contradb_program_import.dart';
import '../data/import_io.dart';
import '../data/repositories_scope.dart';

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
  bool _started = false;

  final _urlController = TextEditingController();
  final _titleController = TextEditingController();

  /// The most recently fetched + parsed program (null before the first fetch).
  ContraDbProgram? _program;

  bool _fetching = false;
  bool _committing = false;
  Object? _fetchError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _fetch = widget.programFetcher ?? fetchImportUrl;
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
      _titleController.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
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
      _fetchError = null;
    });
    try {
      final url = buildContraDbProgramUrl(_urlController.text);
      final html = await _fetch(url);
      final program = parseContraDbProgram(html);
      if (!mounted) return;
      setState(() {
        _program = program;
        _fetching = false;
        // Pre-fill an empty title from the program page (editable).
        if (_titleController.text.trim().isEmpty && program.title.isNotEmpty) {
          _titleController.text = program.title;
        }
      });
      if (program.activities.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: ValueKey('contradb-program-empty-snackbar'),
            content: Text('No dances or notes found on that program page.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _fetchError = error;
      });
    }
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
    } catch (error) {
      if (!mounted) return;
      setState(() => _committing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('contradb-program-resolve-error-snackbar'),
          content: Text('Could not import the ContraDB program: $error'),
        ),
      );
      return;
    }

    final id = uuidV4();
    final slots = buildContraDbProgramSlots(resolved, newSlotId: uuidV4);
    final program = Program(
      id: id,
      title: _titleController.text.trim(),
      slots: slots,
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
          key: const ValueKey('contradb-program-error-snackbar'),
          content: Text('Could not import program: $error'),
        ),
      );
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final linked = resolved.where((a) => a.isLinked).length;
    final notes = slots.length - linked;
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('contradb-program-committed-snackbar'),
        content: Text(
          'Imported "${program.title}" — ${slots.length} '
          '${slots.length == 1 ? 'slot' : 'slots'} '
          '($linked linked, $notes ${notes == 1 ? 'note' : 'notes'}).',
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
        title: const Text('Import from ContraDB'),
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
                : const Text('Import'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('contradb-program-url'),
                controller: _urlController,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _fetchProgram(),
                decoration: const InputDecoration(
                  labelText: 'ContraDB program URL',
                  hintText: 'e.g. https://contradb.com/programs/33',
                  border: OutlineInputBorder(),
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
                label: Text(_fetching ? 'Fetching…' : 'Fetch program'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('contradb-program-title'),
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Program title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildPreview()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_fetchError != null) {
      return Center(
        key: const ValueKey('contradb-program-fetch-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(
              'Could not fetch that program.\n$_fetchError',
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
          'Paste a ContraDB program URL above and tap "Fetch program".',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }

    final activities = program.activities;
    if (activities.isEmpty) {
      return const Center(
        child: Text('No dances or notes found on that program page.'),
      );
    }
    final danceCount = activities.where((a) => a.isDance).length;
    final noteCount = activities.length - danceCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${activities.length} ${activities.length == 1 ? 'activity' : 'activities'} '
            '($danceCount ${danceCount == 1 ? 'dance' : 'dances'}, '
            '$noteCount ${noteCount == 1 ? 'note' : 'notes'})',
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

  Widget _previewTile(ContraDbProgramActivity activity, int index) {
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
            activity.title ?? 'ContraDB dance',
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
