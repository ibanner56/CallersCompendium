import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/calendar_import_settings.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../theme/app_motion.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/section_header.dart';
import '../../widgets/settings_dropdown_row.dart';
import '../calendar_import_screen.dart';

/// Settings ▸ Program ▸ Calendar (#2352): the calendar feed's address, which
/// events an import looks at, and **Pull now**, which opens the calendar
/// import. Reads and writes the settings itself; nothing here fetches.
///
/// The tile shows the address only as set or not set, because a private
/// calendar's address holds a secret token; its text appears only in the
/// field where the caller edits it, here or on the import screen.
class CalendarSettingsTiles extends StatefulWidget {
  const CalendarSettingsTiles({super.key, this.openImport});

  /// Test seam: what **Pull now** does. Defaults to pushing
  /// [CalendarImportScreen].
  final Future<void> Function(BuildContext context)? openImport;

  @override
  State<CalendarSettingsTiles> createState() => _CalendarSettingsTilesState();
}

class _CalendarSettingsTilesState extends State<CalendarSettingsTiles> {
  CalendarImportSettings? _settings;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reload();
  }

  Future<void> _reload() async {
    final repos = RepositoriesScope.of(context);
    try {
      final settings = await CalendarImportSettings.read(repos.settings);
      if (mounted) setState(() => _settings = settings);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'calendar_settings._reload');
      if (mounted) {
        setState(() => _settings = const CalendarImportSettings());
      }
    }
  }

  Future<void> _write(String key, Object? value) async {
    final repos = RepositoriesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      if (value == null) {
        await repos.settings.remove(key);
      } else {
        await repos.settings.set(key, value);
      }
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'calendar_settings._write');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.calendarSettingsSaveError)),
      );
    }
    await _reload();
  }

  Future<String?> _editText({
    required String title,
    required String label,
    String? helper,
    required String initial,
    required Key fieldKey,
    TextInputType? keyboardType,
  }) => showDialog<String>(
    context: context,
    animationStyle: AppMotion.styleFor(context),
    builder: (_) => _TextSettingDialog(
      title: title,
      label: label,
      helper: helper,
      initial: initial,
      fieldKey: fieldKey,
      keyboardType: keyboardType,
    ),
  );

  Future<void> _editAddress(CalendarImportSettings settings) async {
    final l10n = AppLocalizations.of(context);
    final value = await _editText(
      title: l10n.calendarAddressLabel,
      label: l10n.calendarAddressLabel,
      helper: l10n.calendarAddressHelper,
      initial: settings.feedUrl ?? '',
      fieldKey: const ValueKey('calendar-settings-address-field'),
      keyboardType: TextInputType.url,
    );
    if (value == null || !mounted) return;
    final trimmed = value.trim();
    await _write(kCalendarFeedUrlKey, trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _editFilter(CalendarImportSettings settings) async {
    final l10n = AppLocalizations.of(context);
    final value = await _editText(
      title: l10n.calendarTitleFilterTitle,
      label: l10n.calendarTitleFilterTitle,
      helper: l10n.calendarTitleFilterHelper,
      initial: settings.titleFilter,
      fieldKey: const ValueKey('calendar-settings-filter-field'),
    );
    if (value == null || !mounted) return;
    final trimmed = value.trim();
    await _write(
      kCalendarImportTitleFilterKey,
      trimmed.isEmpty ? null : trimmed,
    );
  }

  Future<void> _pullNow() async {
    final open = widget.openImport;
    if (open != null) {
      await open(context);
    } else {
      await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(builder: (_) => const CalendarImportScreen()),
      );
    }
    // The import screen saves an address typed there.
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = _settings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.calendarSettingsHeader),
        ListTile(
          key: const ValueKey('calendar-settings-address'),
          enabled: settings != null,
          title: Text(l10n.calendarAddressLabel),
          subtitle: Text(
            settings?.hasFeed ?? false
                ? l10n.calendarAddressSet
                : l10n.calendarAddressNotSet,
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: settings == null ? null : () => _editAddress(settings),
        ),
        SettingsDropdownRow(
          tileKey: const ValueKey('calendar-settings-window'),
          title: Text(l10n.calendarWindowTitle),
          subtitle: Text(l10n.calendarWindowSubtitle),
          isThreeLine: true,
          dropdownBuilder: (expanded) => AppDropdownField<int>(
            key: const ValueKey('calendar-settings-window-field'),
            compact: true,
            fillWidth: expanded,
            value: settings?.windowMonths ?? kCalendarImportDefaultWindowMonths,
            onChanged: (v) {
              if (settings != null) {
                _write(kCalendarImportWindowMonthsKey, v);
              }
            },
            entries: [
              for (final months in kCalendarImportWindowChoices)
                AppDropdownEntry(
                  value: months,
                  label: l10n.calendarWindowOption(months),
                ),
            ],
          ),
        ),
        ListTile(
          key: const ValueKey('calendar-settings-filter'),
          enabled: settings != null,
          title: Text(l10n.calendarTitleFilterTitle),
          subtitle: Text(
            settings == null || settings.titleFilter.isEmpty
                ? l10n.calendarTitleFilterNone
                : l10n.calendarTitleFilterValue(settings.titleFilter),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: settings == null ? null : () => _editFilter(settings),
        ),
        ListTile(
          key: const ValueKey('calendar-settings-pull-now'),
          leading: const Icon(Icons.cloud_download_outlined),
          title: Text(l10n.calendarPullNowTitle),
          subtitle: Text(l10n.calendarPullNowSubtitle),
          onTap: _pullNow,
        ),
      ],
    );
  }
}

/// A one-field edit dialog that owns its controller, so the controller lives
/// exactly as long as the dialog, closing animation included.
class _TextSettingDialog extends StatefulWidget {
  const _TextSettingDialog({
    required this.title,
    required this.label,
    required this.helper,
    required this.initial,
    required this.fieldKey,
    required this.keyboardType,
  });

  final String title;
  final String label;
  final String? helper;
  final String initial;
  final Key fieldKey;
  final TextInputType? keyboardType;

  @override
  State<_TextSettingDialog> createState() => _TextSettingDialogState();
}

class _TextSettingDialogState extends State<_TextSettingDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: widget.fieldKey,
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          helperMaxLines: 3,
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('calendar-settings-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
