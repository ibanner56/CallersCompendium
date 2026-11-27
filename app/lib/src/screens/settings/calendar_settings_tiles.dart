import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/calendar_import_settings.dart';
import '../../data/calendar_startup.dart';
import '../../data/date_format_scope.dart';
import '../../data/regional_formats.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../theme/app_motion.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/dirty_dialog_guard.dart';
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

  /// The startup run's settings and state (#2353).
  bool _onStartup = false;
  CalendarStartupMode _startupMode = CalendarStartupMode.report;
  CalendarStartupResult? _lastResult;
  int _failures = 0;
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
      final onStartup = await repos.settings.get(kCalendarImportOnStartupKey);
      final mode = await repos.settings.get(kCalendarStartupModeKey);
      final last = await repos.settings.get(kCalendarLastResultKey);
      final failures = await repos.settings.get(kCalendarStartupFailuresKey);
      if (mounted) {
        setState(() {
          _settings = settings;
          _onStartup = onStartup == true;
          _startupMode = CalendarStartupMode.fromStored(mode);
          _lastResult = CalendarStartupResult.fromStored(last);
          _failures = failures is int && failures > 0 ? failures : 0;
        });
      }
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'calendar_settings._reload');
      if (mounted) {
        setState(() => _settings = const CalendarImportSettings());
      }
    }
  }

  /// Writes [value] under [key], or removes the key when [value] is `null`.
  /// [permanent] erases the row instead of tombstoning it, for a key that
  /// never syncs and whose value must not stay on disk.
  Future<void> _write(
    String key,
    Object? value, {
    bool permanent = false,
  }) async {
    final repos = RepositoriesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      if (value == null) {
        await repos.settings.remove(key, permanent: permanent);
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
    if (trimmed == (settings.feedUrl ?? '')) return;
    // A changed address clears the repeated-failure notice (#2353).
    await _write(kCalendarStartupFailuresKey, 0);
    // A cleared address is erased, not tombstoned: it holds a private
    // calendar's secret token and never syncs, so a tombstone would keep it
    // in the database with no peer to tell.
    await _write(
      kCalendarFeedUrlKey,
      trimmed.isEmpty ? null : trimmed,
      permanent: true,
    );
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

  String _lastResultText(AppLocalizations l10n, CalendarStartupResult r) {
    final when = formatEventDate(
      r.at.toLocal(),
      DateFormatScope.of(context),
      MaterialLocalizations.of(context),
      l10n,
    );
    if (!r.ok) {
      return r.reached
          ? l10n.calendarLastResultError(when)
          : l10n.calendarLastResultFailed(when);
    }
    if (r.added > 0) return l10n.calendarLastResultAdded(when, r.added);
    return l10n.calendarLastResultNew(when, r.newEvents);
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
        SwitchListTile(
          key: const ValueKey('calendar-settings-on-startup'),
          value: _onStartup,
          onChanged: settings == null
              ? null
              : (v) => _write(kCalendarImportOnStartupKey, v),
          title: Text(l10n.calendarOnStartupTitle),
          subtitle: Text(l10n.calendarOnStartupSubtitle),
          isThreeLine: true,
        ),
        if (_onStartup)
          SettingsDropdownRow(
            tileKey: const ValueKey('calendar-settings-startup-mode'),
            title: Text(l10n.calendarStartupModeTitle),
            subtitle: Text(
              _startupMode == CalendarStartupMode.report
                  ? l10n.calendarStartupModeReportSubtitle
                  : l10n.calendarStartupModeAddSubtitle,
            ),
            isThreeLine: true,
            dropdownBuilder: (expanded) =>
                AppDropdownField<CalendarStartupMode>(
                  key: const ValueKey('calendar-settings-startup-mode-field'),
                  compact: true,
                  fillWidth: expanded,
                  value: _startupMode,
                  onChanged: (v) {
                    _write(kCalendarStartupModeKey, v.name);
                  },
                  entries: [
                    AppDropdownEntry(
                      value: CalendarStartupMode.report,
                      label: l10n.calendarStartupModeReport,
                    ),
                    AppDropdownEntry(
                      value: CalendarStartupMode.addDrafts,
                      label: l10n.calendarStartupModeAdd,
                    ),
                  ],
                ),
          ),
        if (_lastResult case final last?)
          ListTile(
            key: const ValueKey('calendar-settings-last-result'),
            dense: true,
            leading: const Icon(Icons.history),
            title: Text(_lastResultText(l10n, last)),
          ),
        // A quiet notice, here only: no banner, no dialog (#2353).
        if (_failures >= kCalendarStartupFailureNoticeThreshold)
          ListTile(
            key: const ValueKey('calendar-settings-failure-notice'),
            leading: Icon(
              Icons.cloud_off_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(l10n.calendarStartupFailureNotice(_failures)),
            subtitle: Text(l10n.calendarStartupFailureHint),
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
    // Once the text differs from what the dialog opened with, a tap outside,
    // Escape and Back do nothing, so a stray tap does not lose a pasted
    // address (#2219).
    return DirtyDialogGuard(
      listenable: _controller,
      isDirty: () => _controller.text != widget.initial,
      child: AlertDialog(
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
      ),
    );
  }
}
