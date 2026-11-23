import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../export/share_file.dart' show isBundleShareUnsupported;
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// The delivery choices for a calendar file (issue #2351).
enum CalendarExportChoice { save, share }

/// Asks how to deliver a calendar file: Save, Share (Save as… where the share
/// sheet cannot carry files) or Cancel. Dismissing returns `null`, as Cancel
/// does.
Future<CalendarExportChoice?> showCalendarExportChoiceDialog(
  BuildContext context,
) => showDialog<CalendarExportChoice>(
  context: context,
  builder: (context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('calendar-export-choice-dialog'),
      title: Text(l10n.exportCalendarDialogTitle),
      content: Text(l10n.exportCalendarDialogMessage),
      actions: [
        TextButton(
          key: const ValueKey('calendar-export-save'),
          onPressed: () => Navigator.of(context).pop(CalendarExportChoice.save),
          child: Text(l10n.exportJsonSave),
        ),
        TextButton(
          key: const ValueKey('calendar-export-share'),
          onPressed: () =>
              Navigator.of(context).pop(CalendarExportChoice.share),
          child: Text(
            isBundleShareUnsupported()
                ? l10n.exportJsonSaveAs
                : l10n.exportJsonShare,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.exportJsonCancel),
        ),
      ],
    );
  },
  animationStyle: AppMotion.styleFor(context),
);

/// The calendar export's consent dialog for the venue's postal address
/// (issue #2351), modelled on the venue-contact share dialog.
///
/// One checkbox, **Include the venue's address**, unticked by default.
/// Returns `null` when cancelled or dismissed (the caller writes nothing),
/// otherwise whether the box was ticked. Nothing is remembered: every export
/// starts unticked.
///
/// This is the only place the address may leave the device in a file: the
/// maintainer's decision (issue draft review, 2026-11-22) covers the calendar
/// export alone. Contacts are never offered here.
class CalendarAddressDialog extends StatefulWidget {
  const CalendarAddressDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (_) => const CalendarAddressDialog(),
    animationStyle: AppMotion.styleFor(context),
  );

  @override
  State<CalendarAddressDialog> createState() => _CalendarAddressDialogState();
}

class _CalendarAddressDialogState extends State<CalendarAddressDialog> {
  bool _includeAddress = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('calendar-address-dialog'),
      title: Text(l10n.exportCalendarAddressTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.exportCalendarAddressBody),
            const SizedBox(height: AppSpacing.xs),
            CheckboxListTile(
              key: const ValueKey('calendar-address-include'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includeAddress,
              onChanged: (value) =>
                  setState(() => _includeAddress = value ?? false),
              title: Text(l10n.exportCalendarAddressInclude),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('calendar-address-confirm'),
          onPressed: () => Navigator.of(context).pop(_includeAddress),
          child: Text(l10n.commonContinue),
        ),
      ],
    );
  }
}

/// The Programs list's checklist for "Export calendar (.ics)" (issue #2351).
///
/// [upcoming] programs are listed and ticked. **Show past programs** adds
/// [past] below them, unticked. Returns the ticked programs in list order, or
/// `null` when cancelled or dismissed. The app has no multi-select on the
/// Programs list, so this is where the caller picks.
class CalendarProgramPickerDialog extends StatefulWidget {
  const CalendarProgramPickerDialog({
    super.key,
    required this.upcoming,
    required this.past,
  });

  final List<Program> upcoming;
  final List<Program> past;

  static Future<List<Program>?> show(
    BuildContext context, {
    required List<Program> upcoming,
    required List<Program> past,
  }) => showDialog<List<Program>>(
    context: context,
    builder: (_) => CalendarProgramPickerDialog(upcoming: upcoming, past: past),
    animationStyle: AppMotion.styleFor(context),
  );

  @override
  State<CalendarProgramPickerDialog> createState() =>
      _CalendarProgramPickerDialogState();
}

class _CalendarProgramPickerDialogState
    extends State<CalendarProgramPickerDialog> {
  late final Set<String> _ticked = {for (final p in widget.upcoming) p.id};
  bool _showPast = false;

  List<Program> get _listed => [
    ...widget.upcoming,
    if (_showPast) ...widget.past,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final dateSetting = DateFormatScope.of(context);
    final listed = _listed;
    final chosen = [
      for (final p in listed)
        if (_ticked.contains(p.id)) p,
    ];
    return AlertDialog(
      key: const ValueKey('calendar-program-picker'),
      title: Text(l10n.exportCalendarPickTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.exportCalendarPickBody),
            if (widget.past.isNotEmpty)
              SwitchListTile(
                key: const ValueKey('calendar-show-past'),
                contentPadding: EdgeInsets.zero,
                value: _showPast,
                onChanged: (value) => setState(() {
                  _showPast = value;
                  // Hiding the past list also unticks it, so what is
                  // exported is always what is shown.
                  if (!value) _ticked.removeAll(widget.past.map((p) => p.id));
                }),
                title: Text(l10n.exportCalendarShowPast),
              ),
            if (listed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  widget.past.isEmpty
                      ? l10n.exportCalendarNoDated
                      : l10n.exportCalendarNoUpcoming,
                  key: const ValueKey('calendar-picker-empty'),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final program in listed)
                      CheckboxListTile(
                        key: ValueKey('calendar-pick-${program.id}'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _ticked.contains(program.id),
                        onChanged: (value) => setState(() {
                          if (value ?? false) {
                            _ticked.add(program.id);
                          } else {
                            _ticked.remove(program.id);
                          }
                        }),
                        title: Text(program.title),
                        subtitle: Text(
                          formatEventDate(
                            program.eventDate!,
                            dateSetting,
                            material,
                            l10n,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('calendar-picker-export'),
          onPressed: chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(chosen),
          child: Text(l10n.exportCalendarPickConfirm),
        ),
      ],
    );
  }
}
