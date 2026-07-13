import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../widgets/program_status_chip.dart';

/// Create or edit a program's metadata (`docs/design/ux.md` §4 header:
/// title / event date / venue / notes / status). Slot/dance building is 4.2
/// and CC-parity metadata (band/caller/level) is deliberately out of scope.
///
/// Works two ways:
/// - **Routed** (default): pushed with `Navigator.push<String>`; pops with the
///   saved program's id (or null if cancelled) so the caller can refresh.
/// - **Embedded** (split-pane): pass [onSaved]/[onDeleted]/[onNavigateTo]; the
///   screen invokes those callbacks instead of popping.
///
/// [programId] null ⇒ create a new program; otherwise edit that program.
class ProgramEditorScreen extends StatefulWidget {
  const ProgramEditorScreen({
    super.key,
    this.programId,
    this.onSaved,
    this.onDeleted,
    this.onNavigateTo,
  });

  final String? programId;

  /// Called after a successful save with the program's id (embedded mode).
  final void Function(String programId)? onSaved;

  /// Called after a successful soft-delete (embedded mode).
  final VoidCallback? onDeleted;

  /// Called after duplication with the new copy's id (embedded mode).
  final void Function(String programId)? onNavigateTo;

  bool get isNew => programId == null;
  bool get isEmbedded =>
      onSaved != null || onDeleted != null || onNavigateTo != null;

  @override
  State<ProgramEditorScreen> createState() => _ProgramEditorScreenState();
}

class _ProgramEditorScreenState extends State<ProgramEditorScreen> {
  late CompendiumRepositories _repos;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _venueController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loaded = false;
  Object? _loadError;

  /// The program being edited (null while creating). Non-editable fields
  /// (id, createdAt) are preserved from here on save.
  Program? _existing;
  DateTime? _eventDate;
  ProgramStatus _status = ProgramStatus.draft;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _repos = RepositoriesScope.of(context);
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.isNew) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final program = await _repos.programs.getById(widget.programId!);
      if (!mounted) return;
      if (program == null) {
        setState(() {
          _loadError = 'This program no longer exists.';
          _loaded = true;
        });
        return;
      }
      _titleController.text = program.title;
      _venueController.text = program.venue ?? '';
      _notesController.text = program.notes;
      setState(() {
        _existing = program;
        _eventDate = program.eventDate;
        _status = program.status;
        _loaded = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _venueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final initial = _eventDate?.toLocal() ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      // Store the calendar day as a UTC midnight so it round-trips through the
      // UTC-normalized storage layer without shifting across time zones.
      setState(
        () => _eventDate = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final venue = _venueController.text.trim();
    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();

    try {
      final String id;
      if (widget.isNew) {
        id = uuidV4();
        await _repos.programs.create(
          Program(
            id: id,
            title: title,
            eventDate: _eventDate,
            venue: venue.isEmpty ? null : venue,
            notes: notes,
            status: _status,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        id = _existing!.id;
        final updated = _existing!.copyWith(
          title: title,
          eventDate: _eventDate,
          clearEventDate: _eventDate == null,
          venue: venue.isEmpty ? null : venue,
          clearVenue: venue.isEmpty,
          notes: notes,
          status: _status,
          updatedAt: now,
        );
        await _repos.programs.update(updated);
        _existing = updated;
      }
      if (!mounted) return;
      setState(() => _saving = false);
      if (widget.isEmbedded) {
        widget.onSaved?.call(id);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"$title" saved.')));
      } else {
        Navigator.of(context).pop(id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the program.')),
      );
    }
  }

  Future<void> _duplicate() async {
    final source = _existing;
    if (source == null) return;
    final now = DateTime.now().toUtc();
    final copy = await _repos.programs.duplicate(
      id: source.id,
      newId: uuidV4(),
      newSlotId: uuidV4,
      now: now,
      newTitle: '${source.title} (copy)',
    );
    if (!mounted) return;
    if (widget.isEmbedded) {
      widget.onNavigateTo?.call(copy.id);
    } else {
      // Replace this route with the copy's editor so back returns to the list.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<String>(
          builder: (_) => ProgramEditorScreen(programId: copy.id),
        ),
      );
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Duplicated as "${copy.title}".')));
  }

  Future<void> _delete() async {
    final source = _existing;
    if (source == null) return;
    final title = source.title;
    await _repos.programs.softDelete(source.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"$title" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              _repos.programs.restore(source.id, at: DateTime.now().toUtc()),
        ),
      ),
    );
    if (widget.isEmbedded) {
      widget.onDeleted?.call();
    } else {
      Navigator.of(context).pop('deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New program' : 'Edit program'),
        actions: [
          if (!widget.isNew && _existing != null) ...[
            IconButton(
              key: const ValueKey('duplicate-program'),
              tooltip: 'Duplicate',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _duplicate,
            ),
            IconButton(
              key: const ValueKey('delete-program'),
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: _buildBody(),
      floatingActionButton: (_loaded && _loadError == null)
          ? FloatingActionButton.extended(
              key: const ValueKey('save-program'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading program'),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError is String
                ? _loadError! as String
                : 'Could not load the program.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final dateLabel = _eventDate == null
        ? 'No date set'
        : MaterialLocalizations.of(context).formatMediumDate(_eventDate!);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const ValueKey('program-title'),
            controller: _titleController,
            autofocus: widget.isNew,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Friday Night Contra',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'A title is required.'
                : null,
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Event date',
              border: OutlineInputBorder(),
            ),
            child: Row(
              children: [
                Expanded(child: Text(dateLabel)),
                TextButton.icon(
                  key: const ValueKey('pick-event-date'),
                  onPressed: _pickEventDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(_eventDate == null ? 'Set date' : 'Change'),
                ),
                if (_eventDate != null)
                  IconButton(
                    key: const ValueKey('clear-event-date'),
                    tooltip: 'Clear event date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _eventDate = null),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('program-venue'),
            controller: _venueController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Venue',
              hintText: 'e.g. Grange Hall',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('program-notes'),
            controller: _notesController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ProgramStatus>(
            key: const ValueKey('program-status'),
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final status in ProgramStatus.values)
                DropdownMenuItem(
                  value: status,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(programStatusPresentation(status).icon, size: 18),
                      const SizedBox(width: 8),
                      Text(programStatusPresentation(status).label),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
