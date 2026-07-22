import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../export/share_sanitization.dart';

/// The six contact fields in their canonical display order (contact 1 before
/// contact 2, name → phone → email within each).
const List<VenueContactField> _orderedContactFields = [
  VenueContactField.contact1Name,
  VenueContactField.contact1Phone,
  VenueContactField.contact1Email,
  VenueContactField.contact2Name,
  VenueContactField.contact2Phone,
  VenueContactField.contact2Email,
];

/// A pre-export consent dialog that lets the user opt specific venue
/// contact-person PII fields into a shared program bundle **or** an exported
/// program PDF (issue #515).
///
/// Share/export is a privacy boundary: a venue's contact people are personal
/// details that are OMIT-BY-DEFAULT. This dialog lists only the contact fields
/// actually populated on the venue, each as an initially **unchecked**
/// (opt-in) checkbox, and returns the set the user affirmatively
/// checked. The same dialog serves every export flow, so its copy is worded
/// generically ("this export") rather than naming a single flow.
///
/// Result contract (consumed by the program export menu):
/// * `null` — the user cancelled **or** dismissed the dialog (tapped outside /
///   back). The caller MUST abort the export entirely; nothing is shared or
///   written. This dismiss==cancel behavior was an explicit product decision
///   (issue #515).
/// * a (possibly empty) set — the user pressed the confirm button. The caller
///   proceeds, including exactly the returned fields and clearing the rest; an
///   empty set means "export the venue with all six contact fields cleared".
class VenueContactShareDialog extends StatefulWidget {
  const VenueContactShareDialog({super.key, required this.fields});

  /// The populated contact fields offered as opt-in checkboxes, in display
  /// order. Never empty in practice — the caller only shows the dialog when at
  /// least one contact field is populated.
  final List<VenueContactField> fields;

  /// Shows the dialog for [venue]'s populated contact fields. Returns `null`
  /// when cancelled/dismissed (the caller aborts the share) or the
  /// affirmatively-checked set when confirmed.
  static Future<Set<VenueContactField>?> show(
    BuildContext context, {
    required Venue venue,
  }) {
    final populated = populatedVenueContactFields(venue);
    final fields = _orderedContactFields
        .where(populated.contains)
        .toList(growable: false);
    return showDialog<Set<VenueContactField>>(
      context: context,
      builder: (_) => VenueContactShareDialog(fields: fields),
    );
  }

  @override
  State<VenueContactShareDialog> createState() =>
      _VenueContactShareDialogState();
}

class _VenueContactShareDialogState extends State<VenueContactShareDialog> {
  final Set<VenueContactField> _checked = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('venue-contact-share-dialog'),
      title: Text(l10n.exportVenueContactTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.exportVenueContactBody),
            const SizedBox(height: 8),
            for (final field in widget.fields)
              CheckboxListTile(
                key: ValueKey('venue-contact-${field.name}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _checked.contains(field),
                onChanged: (selected) => setState(() {
                  if (selected ?? false) {
                    _checked.add(field);
                  } else {
                    _checked.remove(field);
                  }
                }),
                title: Text(_label(l10n, field)),
              ),
          ],
        ),
      ),
      actions: [
        // Cancel pops null (== dismiss) so the caller aborts the share.
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        // Confirm pops the checked set (possibly empty) so the caller proceeds.
        FilledButton(
          key: const ValueKey('venue-contact-share-confirm'),
          onPressed: () => Navigator.of(context).pop({..._checked}),
          child: Text(l10n.exportVenueContactConfirm),
        ),
      ],
    );
  }

  String _label(AppLocalizations l10n, VenueContactField field) =>
      switch (field) {
        VenueContactField.contact1Name => l10n.exportVenueContact1Name,
        VenueContactField.contact1Phone => l10n.exportVenueContact1Phone,
        VenueContactField.contact1Email => l10n.exportVenueContact1Email,
        VenueContactField.contact2Name => l10n.exportVenueContact2Name,
        VenueContactField.contact2Phone => l10n.exportVenueContact2Phone,
        VenueContactField.contact2Email => l10n.exportVenueContact2Email,
      };
}
