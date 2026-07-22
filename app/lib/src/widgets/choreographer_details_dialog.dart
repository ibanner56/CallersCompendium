import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A modal dialog for editing a [Choreographer]'s shared contact details.
///
/// This edits the **shared** author record: the same [Choreographer] row is
/// credited by every dance that lists this author, so a change here is visible
/// on all of those dances. The dialog copy makes that explicit.
///
/// Privacy: [Choreographer.email] and [Choreographer.location] are private
/// contact metadata. They live only in the user's local database and are never
/// shared or exported (see `Choreographer` doc + export regression tests).
///
/// Returns the updated [Choreographer] via [Navigator.pop] when the user saves,
/// or `null` when cancelled/dismissed. It performs no persistence itself — the
/// caller upserts the returned record so the dialog stays trivially testable.
class ChoreographerDetailsDialog extends StatefulWidget {
  const ChoreographerDetailsDialog({super.key, required this.choreographer});

  /// The author record to edit; fields prefill from it.
  final Choreographer choreographer;

  /// Opens the dialog for [choreographer], resolving to the edited record or
  /// `null` if the user cancels.
  static Future<Choreographer?> show(
    BuildContext context,
    Choreographer choreographer,
  ) => showDialog<Choreographer>(
    context: context,
    builder: (_) => ChoreographerDetailsDialog(choreographer: choreographer),
  );

  @override
  State<ChoreographerDetailsDialog> createState() =>
      _ChoreographerDetailsDialogState();
}

class _ChoreographerDetailsDialogState
    extends State<ChoreographerDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _websiteController;
  late final TextEditingController _notesController;
  late final TextEditingController _emailController;
  late final TextEditingController _locationController;
  late bool _deceased;

  @override
  void initState() {
    super.initState();
    final c = widget.choreographer;
    _nameController = TextEditingController(text: c.name);
    _websiteController = TextEditingController(text: c.website ?? '');
    _notesController = TextEditingController(text: c.notes ?? '');
    _emailController = TextEditingController(text: c.email ?? '');
    _locationController = TextEditingController(text: c.location ?? '');
    _deceased = c.deceased;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// Empty/whitespace text maps to `null` for optional fields.
  String? _trimmedOrNull(TextEditingController controller) {
    final trimmed = controller.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.choreographer;

    // Build a fresh record from the controllers (rather than copyWith) so that
    // clearing an optional field actually clears it: copyWith treats a null
    // website/notes as "keep existing", which would make website/notes
    // un-clearable from this dialog. The model normalizes email/location
    // (empty/whitespace -> null) itself; we pass website/notes trimmed-or-null
    // so they clear the same way. id/deceased carry over explicitly.
    final updated = Choreographer(
      id: existing.id,
      name: _nameController.text.trim(),
      website: _trimmedOrNull(_websiteController),
      notes: _trimmedOrNull(_notesController),
      email: _trimmedOrNull(_emailController),
      location: _trimmedOrNull(_locationController),
      deceased: _deceased,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.danceEditorChoreographerDetailsTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.danceEditorChoreographerDetailsIntro,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('choreographer-name-field'),
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorNameRequiredLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.danceEditorNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('choreographer-website-field'),
                controller: _websiteController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorWebsiteLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('choreographer-email-field'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorEmailPrivateLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('choreographer-location-field'),
                controller: _locationController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorLocationPrivateLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('choreographer-notes-field'),
                controller: _notesController,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorNotesLabel,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('choreographer-deceased-toggle'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.danceEditorDeceasedLabel),
                value: _deceased,
                onChanged: (value) => setState(() => _deceased = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('choreographer-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('choreographer-save'),
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
