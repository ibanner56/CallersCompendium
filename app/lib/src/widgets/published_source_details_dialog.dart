import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

/// A modal dialog for editing a [PublishedSource]'s shared bibliographic
/// details.
///
/// This edits the **shared** source record: the same [PublishedSource] row is
/// cited by every dance that references it, so a change here is visible on all
/// of those dances. The dialog copy makes that explicit (mirrors the
/// [ChoreographerDetailsDialog] pattern).
///
/// Returns the updated [PublishedSource] via [Navigator.pop] when the user
/// saves, or `null` when cancelled/dismissed. It performs no persistence
/// itself — the caller upserts the returned record so the dialog stays
/// trivially testable.
class PublishedSourceDetailsDialog extends StatefulWidget {
  const PublishedSourceDetailsDialog({super.key, required this.source});

  /// The source record to edit; fields prefill from it.
  final PublishedSource source;

  /// Opens the dialog for [source], resolving to the edited record or `null`
  /// if the user cancels.
  static Future<PublishedSource?> show(
    BuildContext context,
    PublishedSource source,
  ) => showDialog<PublishedSource>(
    context: context,
    builder: (_) => PublishedSourceDetailsDialog(source: source),
  );

  @override
  State<PublishedSourceDetailsDialog> createState() =>
      _PublishedSourceDetailsDialogState();
}

class _PublishedSourceDetailsDialogState
    extends State<PublishedSourceDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final TextEditingController _yearController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _titleController = TextEditingController(text: s.title);
    _authorController = TextEditingController(text: s.author ?? '');
    _yearController = TextEditingController(text: s.year?.toString() ?? '');
    _urlController = TextEditingController(text: s.url ?? '');
    _notesController = TextEditingController(text: s.notes ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _yearController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Empty/whitespace text maps to `null` for optional fields.
  String? _trimmedOrNull(TextEditingController controller) {
    final trimmed = controller.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.source;

    // Build a fresh record from the controllers (rather than copyWith) so that
    // clearing an optional field actually clears it: copyWith treats a null
    // author/year/url/notes as "keep existing", which would make those fields
    // un-clearable from this dialog. The model normalizes author/url/notes
    // (empty/whitespace -> null) itself; year is parsed to an int or null.
    // id carries over explicitly.
    final yearText = _yearController.text.trim();
    final updated = PublishedSource(
      id: existing.id,
      title: _titleController.text.trim(),
      author: _trimmedOrNull(_authorController),
      year: yearText.isEmpty ? null : int.parse(yearText),
      url: _trimmedOrNull(_urlController),
      notes: _trimmedOrNull(_notesController),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Source details'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These details are shared across every dance that cites this '
                'source. Editing them here updates the source everywhere it '
                'is referenced.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('source-title-field'),
                controller: _titleController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('source-author-field'),
                controller: _authorController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Author / editor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('source-year-field'),
                controller: _yearController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Year',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final parsed = int.tryParse(text);
                  if (parsed == null) return 'Enter a whole number';
                  if (parsed <= 0) return 'Enter a positive year';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('source-url-field'),
                controller: _urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('source-notes-field'),
                controller: _notesController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('source-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('source-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
