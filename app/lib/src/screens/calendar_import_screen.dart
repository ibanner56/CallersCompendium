import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/calendar_import.dart';
import '../data/calendar_import_settings.dart';
import '../data/calendar_startup.dart' show resetCalendarStartupFailures;
import '../data/date_format_scope.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../export/export_labels_l10n.dart';
import '../theme/app_spacing.dart';
import '../utils/l10n_joins.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/app_bar_text_action.dart';
import '../widgets/calendar_flag_label.dart';

/// Fetches a calendar feed's body. [fetchCalendarFeed] in production.
typedef CalendarFeedFetcher = Future<String> Function(String url);

/// Imports gigs from the caller's online calendar as draft programs (#2352).
///
/// The caller gives the address of an iCalendar feed (kept in Settings ▸
/// Program ▸ Calendar too) and presses **Fetch**. The screen fetches only
/// then: nothing runs on open, in the background, or on resume. The preview
/// lists new events ticked, events whose program the caller deleted unticked,
/// and events already imported or exported by this app for information.
/// **Import** creates the ticked drafts, offers **Undo**
/// ([undoCalendarImportDrafts], then [undoCalendarUpdates]), and pops with
/// their ids.
class CalendarImportScreen extends StatefulWidget {
  const CalendarImportScreen({
    super.key,
    this.fetcher,
    this.toLocal,
    this.prefetchedBody,
    this.prefetchedUrl,
  });

  /// The address [prefetchedBody] came from. The body is used only while the
  /// saved address is still that one: after an address change, it would
  /// preview the wrong calendar.
  final String? prefetchedUrl;

  /// A feed the startup run already fetched (#2353): the preview is built
  /// from it on open, with no second fetch. **Fetch events** still fetches
  /// afresh.
  final String? prefetchedBody;

  /// Test seam; defaults to [fetchCalendarFeed].
  final CalendarFeedFetcher? fetcher;

  /// Converts a UTC instant to local time; defaults to [DateTime.toLocal].
  /// A test seam for the time zone.
  final DateTime Function(DateTime utc)? toLocal;

  @override
  State<CalendarImportScreen> createState() => _CalendarImportScreenState();
}

enum _Phase { loading, idle, fetching, preview, committing }

class _CalendarImportScreenState extends State<CalendarImportScreen> {
  final _addressController = TextEditingController();
  _Phase _phase = _Phase.loading;
  CalendarImportSettings _settings = const CalendarImportSettings();
  CalendarImportPreview? _preview;
  final Set<String> _ticked = {};

  /// Program ids whose upstream change is ticked (#2354).
  final Set<String> _acceptedChanges = {};
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final repos = RepositoriesScope.of(context);
    CalendarImportSettings settings;
    try {
      settings = await CalendarImportSettings.read(repos.settings);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'calendar_import_screen._load');
      settings = const CalendarImportSettings();
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _addressController.text = settings.feedUrl ?? '';
      _phase = _Phase.idle;
    });
    final body = widget.prefetchedBody;
    if (body != null &&
        widget.prefetchedUrl != null &&
        widget.prefetchedUrl == settings.feedUrl) {
      await _fetch(prefetched: body);
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _fetch({String? prefetched}) async {
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _error = l10n.importErrorEmptyUrl);
      return;
    }
    setState(() {
      _phase = _Phase.fetching;
      _error = null;
      _preview = null;
    });
    try {
      if (address != (_settings.feedUrl ?? '')) {
        await repos.settings.set(kCalendarFeedUrlKey, address);
        // A new address starts the startup run's failure count afresh.
        await resetCalendarStartupFailures(repos.settings);
        _settings = CalendarImportSettings(
          feedUrl: address,
          windowMonths: _settings.windowMonths,
          titleFilter: _settings.titleFilter,
        );
      }
      final body =
          prefetched ?? await (widget.fetcher ?? fetchCalendarFeed)(address);
      final now = clock.now();
      final preview = await buildCalendarImportPreview(
        repos,
        body: body,
        feedUrl: address,
        settings: _settings,
        today: DateTime(now.year, now.month, now.day),
        toLocal: widget.toLocal,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _ticked
          ..clear()
          ..addAll([
            for (final e in preview.entries)
              if (e.tickedByDefault) e.candidate.eventKey,
          ]);
        _acceptedChanges
          ..clear()
          ..addAll([
            for (final c in preview.changes)
              if (c.untouched && calendarOfferVisible(c)) c.program.id,
          ]);
        _phase = _Phase.preview;
      });
    } on UrlFetchException catch (error, stackTrace) {
      // The exception carries no address (import_io.dart).
      logCaughtError(
        error,
        stackTrace,
        source: 'calendar_import_screen._fetch',
      );
      if (!mounted) return;
      setState(() {
        _error = importErrorMessage(l10n, error);
        _phase = _Phase.idle;
      });
    } on NotACalendarException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'calendar_import_screen._fetch',
      );
      if (!mounted) return;
      setState(() {
        _error = l10n.importErrorNotACalendar;
        _phase = _Phase.idle;
      });
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'calendar_import_screen._fetch',
      );
      if (!mounted) return;
      setState(() {
        _error = l10n.calendarImportFailed;
        _phase = _Phase.idle;
      });
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null) return;
    final l10n = AppLocalizations.of(context);
    final repos = RepositoriesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final chosen = [
      for (final e in preview.entries)
        if (e.offered && _ticked.contains(e.candidate.eventKey)) e,
    ];
    if (chosen.isEmpty && !preview.hasPendingWrites) return;
    setState(() => _phase = _Phase.committing);
    final List<String> ids;
    final List<CalendarUpdateRecord> before;
    final now = clock.now().toUtc();
    try {
      ids = await commitCalendarImport(
        repos,
        chosen: chosen,
        untitledTitle: l10n.calendarImportUntitled,
        now: now,
      );
      try {
        before = await applyCalendarUpdates(
          repos,
          preview: preview,
          accepted: {..._acceptedChanges},
          now: now,
        );
      } catch (_) {
        // diagnostics: silent — rethrown below; logged at the outer catch.
        // The drafts go too, so Import is all or nothing.
        await repos.programs.hardDelete(ids);
        rethrow;
      }
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'calendar_import_screen._import',
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.preview);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.calendarImportFailed)),
      );
      return;
    }
    showUndoSnackBar(
      messenger,
      key: const ValueKey('calendar-import-committed-snackbar'),
      message: _appliedMessage(l10n, preview, ids.length),
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: accessible,
      onUndo: () async {
        final at = clock.now().toUtc();
        await undoCalendarImportDrafts(repos, ids, now: at);
        await undoCalendarUpdates(repos, before, now: at);
      },
    );
    if (mounted) navigator.pop(ids);
  }

  String _appliedMessage(
    AppLocalizations l10n,
    CalendarImportPreview preview,
    int created,
  ) {
    final updated = [
      for (final c in preview.changes)
        if (calendarOfferVisible(c) && _acceptedChanges.contains(c.program.id))
          c,
    ].length;
    final parts = [
      if (created > 0) l10n.calendarImportCommitted(created),
      if (updated > 0) l10n.calendarImportUpdated(updated),
    ];
    return parts.isEmpty
        ? l10n.calendarImportReviewed
        : joinSentences(l10n, parts);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = _preview;
    final busy = _phase == _Phase.fetching || _phase == _Phase.committing;
    final tickedCount = preview == null
        ? 0
        : preview.entries
              .where((e) => e.offered && _ticked.contains(e.candidate.eventKey))
              .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.calendarImportTitle),
        actions: [
          if (preview != null)
            AppBarTextAction(
              key: const ValueKey('calendar-import-commit'),
              label: l10n.calendarImportImport,
              icon: Icons.download_done,
              onPressed:
                  busy ||
                      (tickedCount == 0 &&
                          _acceptedChanges.isEmpty &&
                          !preview.hasPendingWrites)
                  ? null
                  : _import,
            ),
        ],
      ),
      body: _phase == _Phase.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                TextField(
                  key: const ValueKey('calendar-import-address'),
                  controller: _addressController,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.calendarAddressLabel,
                    helperText: l10n.calendarAddressHelper,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => busy ? null : _fetch(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: const ValueKey('calendar-import-fetch'),
                    onPressed: busy ? null : _fetch,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text(l10n.calendarImportFetch),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    error,
                    key: const ValueKey('calendar-import-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (preview != null) ..._previewChildren(context, preview),
              ],
            ),
    );
  }

  List<Widget> _previewChildren(
    BuildContext context,
    CalendarImportPreview preview,
  ) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final dateSetting = DateFormatScope.of(context);
    String dateOf(CalendarImportEntry e) =>
        formatEventDate(e.candidate.date, dateSetting, material, l10n);
    String titleOf(CalendarImportEntry e) => e.candidate.title.trim().isEmpty
        ? l10n.calendarImportUntitled
        : e.candidate.title;
    // The event's times beside its date (#2423), phrased as the set list
    // phrases a program's start and end.
    // Times as the program summary shows them, "(next day)" included.
    final use24Hour = use24HourClockOf(context);
    String? rangeOf(int? start, int? end) => danceTimesText(
      startMinute: start,
      endMinute: end,
      formatTime: (m) => formatTimeOfDay(m, l10n, use24Hour: use24Hour),
      labels: programExportLabels(l10n),
    );
    String? timesOf(CalendarImportEntry e) =>
        rangeOf(e.candidate.startMinute, e.candidate.endMinute);
    String subtitleOf(CalendarImportEntry e) =>
        [dateOf(e), ?timesOf(e), ?e.candidate.venueLabel].join(' · ');

    List<CalendarImportEntry> withState(CalendarEntryState s) =>
        preview.entries.where((e) => e.state == s).toList();
    final fresh = withState(CalendarEntryState.fresh);
    final deleted = withState(CalendarEntryState.deleted);
    final offers = [
      for (final c in preview.changes)
        if (calendarOfferVisible(c)) c,
    ];
    final offeredKeys = {for (final c in offers) c.candidate.eventKey};
    final already = [
      for (final e in withState(CalendarEntryState.alreadyImported))
        if (!offeredKeys.contains(e.candidate.eventKey)) e,
    ];
    final updated = offers.where((c) => c.untouched).toList();
    final changed = offers.where((c) => !c.untouched).toList();
    String changeText(CalendarChangeOffer c) => [
      if (c.date)
        l10n.calendarChangeDate(
          c.program.eventDate == null
              ? '—'
              : formatEventDate(
                  c.program.eventDate!,
                  dateSetting,
                  material,
                  l10n,
                ),
          formatEventDate(c.candidate.date, dateSetting, material, l10n),
        ),
      if (c.title) l10n.calendarChangeTitle(c.program.title, c.candidate.title),
      if (c.venue)
        l10n.calendarChangeVenue(
          c.shownVenue ?? '—',
          c.candidate.venueLabel ?? '—',
        ),
      if (c.time)
        l10n.calendarChangeTime(
          rangeOf(c.program.startMinute, c.program.endMinute) ?? '—',
          // Only the offered times change; an unoffered one stays as is.
          rangeOf(
                c.start ? c.candidate.startMinute : c.program.startMinute,
                c.end ? c.candidate.endMinute : c.program.endMinute,
              ) ??
              '—',
        ),
    ].join('\n');
    Widget offerTile(CalendarChangeOffer c) => CheckboxListTile(
      key: ValueKey('calendar-change-${c.program.id}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _acceptedChanges.contains(c.program.id),
      onChanged: _phase == _Phase.preview
          ? (v) => setState(() {
              if (v ?? false) {
                _acceptedChanges.add(c.program.id);
              } else {
                _acceptedChanges.remove(c.program.id);
              }
            })
          : null,
      title: Text(c.program.title),
      subtitle: Text(changeText(c)),
      isThreeLine: true,
    );
    final ours = withState(CalendarEntryState.fromThisApp);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    Widget tickable(CalendarImportEntry e, {String? note}) => CheckboxListTile(
      key: ValueKey('calendar-entry-${e.candidate.eventKey}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _ticked.contains(e.candidate.eventKey),
      onChanged: _phase == _Phase.preview
          ? (v) => setState(() {
              if (v ?? false) {
                _ticked.add(e.candidate.eventKey);
              } else {
                _ticked.remove(e.candidate.eventKey);
              }
            })
          : null,
      title: Text(titleOf(e)),
      subtitle: Text([subtitleOf(e), ?note].join('\n')),
      isThreeLine: note != null,
    );
    Widget listed(CalendarImportEntry e, IconData icon) => ListTile(
      key: ValueKey('calendar-entry-${e.candidate.eventKey}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(titleOf(e)),
      subtitle: Text(subtitleOf(e)),
    );

    return [
      const SizedBox(height: AppSpacing.md),
      Text(
        preview.entries.isEmpty
            ? l10n.calendarImportNothingFound
            : l10n.calendarImportSummary(preview.freshCount),
        key: const ValueKey('calendar-import-summary'),
      ),
      if (fresh.isNotEmpty) ...[
        header(l10n.calendarImportNewHeader),
        for (final e in fresh) tickable(e),
      ],
      if (deleted.isNotEmpty) ...[
        header(l10n.calendarImportDeletedHeader),
        for (final e in deleted)
          tickable(e, note: l10n.calendarImportDeletedNote),
      ],
      if (updated.isNotEmpty) ...[
        header(l10n.calendarImportUpdatedHeader),
        for (final c in updated) offerTile(c),
      ],
      if (changed.isNotEmpty) ...[
        header(l10n.calendarImportChangedHeader),
        Text(l10n.calendarImportChangedBody),
        for (final c in changed) offerTile(c),
      ],
      if (preview.flagged.isNotEmpty) ...[
        header(l10n.calendarImportFlaggedHeader),
        Text(l10n.calendarImportFlaggedBody),
        for (final f in preview.flagged)
          ListTile(
            key: ValueKey('calendar-flagged-${f.program.id}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_outlined),
            title: Text(f.program.title),
            subtitle: Text(calendarFlagLabel(l10n, f.flag)),
          ),
      ],
      if (already.isNotEmpty) ...[
        header(l10n.calendarImportAlreadyHeader),
        for (final e in already) listed(e, Icons.check_circle_outline),
      ],
      if (ours.isNotEmpty) ...[
        header(l10n.calendarImportFromThisAppHeader),
        for (final e in ours) listed(e, Icons.event_available_outlined),
      ],
      if (preview.unreadableSeries.isNotEmpty) ...[
        header(l10n.calendarImportUnreadableHeader),
        Text(l10n.calendarImportUnreadableBody),
        for (final title in preview.unreadableSeries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_repeat_outlined),
            title: Text(title.isEmpty ? l10n.calendarImportUntitled : title),
          ),
      ],
      if (preview.skippedNoUid > 0) ...[
        const SizedBox(height: AppSpacing.md),
        Text(l10n.calendarImportSkippedNoUid(preview.skippedNoUid)),
      ],
      if (preview.truncated) ...[
        const SizedBox(height: AppSpacing.md),
        Text(l10n.calendarImportTruncated(iCalMaxEvents)),
      ],
    ];
  }
}
