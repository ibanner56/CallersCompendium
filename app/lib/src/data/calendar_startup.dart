import 'dart:async';

import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';
import 'calendar_import.dart';
import 'calendar_import_settings.dart';

/// Whether the calendar import runs once when the app starts (#2353). Off by
/// default (ruling 3). Per-installation consent to a network fetch, like
/// `update_auto_check`: it does not sync, but a backup keeps it.
const String kCalendarImportOnStartupKey = 'calendar_import_on_startup';

/// What the startup run does: [CalendarStartupMode.report] (the default) or
/// [CalendarStartupMode.addDrafts]. Goes with the switch above.
const String kCalendarStartupModeKey = 'calendar_startup_mode';

/// This installation's last startup run, as JSON (see
/// [CalendarStartupResult]). Installation state: never transmitted.
const String kCalendarLastResultKey = 'calendar_last_result';

/// How many startup runs in a row have failed on this installation.
/// Installation state: never transmitted.
const String kCalendarStartupFailuresKey = 'calendar_startup_failures';

/// After this many failed startup runs in a row, Settings shows a quiet notice
/// (Claude's number, approved with #2353). Nothing else ever says so.
const int kCalendarStartupFailureNoticeThreshold = 3;

/// How long the startup run waits, when Device Sync is on, for the pass that
/// sync starts at launch, before it goes ahead anyway (Claude's number). The
/// wait delays only the run and its message, never the app. Its length is
/// quoted in docs/user/settings.md (Calendar).
const Duration kCalendarStartupSyncWait = Duration(seconds: 30);

/// What the startup run does with new events (#2353).
enum CalendarStartupMode {
  /// Works out which events are new and says so; creates nothing.
  report,

  /// Creates drafts for new events.
  addDrafts;

  /// The stored mode, or [report] for anything unknown.
  static CalendarStartupMode fromStored(Object? value) =>
      value == addDrafts.name ? addDrafts : report;
}

/// The last startup run, for Settings' last-result line.
class CalendarStartupResult {
  const CalendarStartupResult({
    required this.at,
    required this.ok,
    this.newEvents = 0,
    this.added = 0,
    this.reached = false,
  });

  final DateTime at;
  final bool ok;

  /// For a failed run: whether the calendar was reached and the failure was
  /// in reading it or writing the drafts, not in reaching it.
  final bool reached;
  final int newEvents;
  final int added;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'ok': ok,
    'new': newEvents,
    'added': added,
    if (reached) 'reached': true,
  };

  /// Null for anything that is not one: a corrupt value is no result.
  static CalendarStartupResult? fromStored(Object? value) {
    if (value is! Map) return null;
    final at = DateTime.tryParse('${value['at']}');
    final ok = value['ok'];
    if (at == null || ok is! bool) return null;
    int count(Object? v) => v is int && v >= 0 ? v : 0;
    return CalendarStartupResult(
      at: at,
      ok: ok,
      newEvents: count(value['new']),
      added: count(value['added']),
      reached: value['reached'] == true,
    );
  }
}

/// What a startup run found, for the message it shows.
sealed class CalendarStartupOutcome {
  const CalendarStartupOutcome();
}

/// The switch is off, no address is set, or nothing needs saying.
final class CalendarStartupQuiet extends CalendarStartupOutcome {
  const CalendarStartupQuiet();
}

/// The fetch failed. Shown nowhere but Settings.
final class CalendarStartupFailed extends CalendarStartupOutcome {
  const CalendarStartupFailed();
}

/// The fetch worked and there is something to say.
final class CalendarStartupFound extends CalendarStartupOutcome {
  const CalendarStartupFound({
    required this.body,
    required this.url,
    required this.newEvents,
    required this.changes,
    this.addedIds = const [],
  });

  /// The fetched feed, so Review opens the preview without fetching again.
  final String body;

  /// The address [body] was fetched from.
  final String url;

  /// New events: in report mode not imported; in add-drafts mode, imported.
  final int newEvents;

  /// Upstream changes and cancellations (#2354): counted, never applied.
  final int changes;

  /// Drafts the run created (add-drafts mode), for Undo and Show.
  final List<String> addedIds;
}

/// Runs the calendar import once at startup (#2353), if the caller turned it
/// on and an address is set; otherwise does nothing, fetching nothing.
///
/// Never touches a program that exists: in [CalendarStartupMode.addDrafts] it
/// creates drafts for new events only, with the manual import's rules
/// ([commitCalendarImport]), and it only counts upstream changes and
/// cancellations, never applying them ([applyCalendarUpdates] is not called).
///
/// A failure is silent: it is logged, recorded in [kCalendarLastResultKey],
/// and, if the calendar could not be reached, counted in
/// [kCalendarStartupFailuresKey]; a success resets the count, and a run
/// that reached the calendar but failed later leaves it as it is.
///
/// [now] and [today] are parameters so tests can inject them.
Future<CalendarStartupOutcome> runCalendarStartup(
  CompendiumRepositories repos, {
  required Future<String> Function(String url) fetcher,
  required DateTime now,
  required DateTime today,
  required String untitledTitle,
  DateTime Function(DateTime utc)? toLocal,
}) async {
  final settings = repos.settings;
  final CalendarImportSettings config;
  final CalendarStartupMode mode;
  try {
    if (await settings.get(kCalendarImportOnStartupKey) != true) {
      return const CalendarStartupQuiet();
    }
    config = await CalendarImportSettings.read(settings);
    mode = CalendarStartupMode.fromStored(
      await settings.get(kCalendarStartupModeKey),
    );
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'calendar_startup.settings');
    return const CalendarStartupQuiet();
  }
  if (!config.hasFeed) return const CalendarStartupQuiet();

  final String body;
  try {
    body = await fetcher(config.feedUrl!);
  } catch (error, stackTrace) {
    // Silent by design (ADR-002 §5, as for the update check). The error
    // carries no address (`fetchCalendarFeed`). Only this counts toward the
    // "couldn't be reached" notice.
    logCaughtError(error, stackTrace, source: 'calendar_startup.fetch');
    await _record(
      repos,
      CalendarStartupResult(at: now, ok: false),
      failures: _Failures.count,
    );
    return const CalendarStartupFailed();
  }
  final CalendarImportPreview preview;
  try {
    preview = await buildCalendarImportPreview(
      repos,
      body: body,
      feedUrl: config.feedUrl!,
      settings: config,
      today: today,
      toLocal: toLocal,
    );
  } catch (error, stackTrace) {
    // Reached, but not usable: recorded; the unreachable count is left as is.
    logCaughtError(error, stackTrace, source: 'calendar_startup.preview');
    await _record(
      repos,
      CalendarStartupResult(at: now, ok: false, reached: true),
      failures: _Failures.keep,
    );
    return const CalendarStartupFailed();
  }

  final fresh = [
    for (final e in preview.entries)
      if (e.state == CalendarEntryState.fresh) e,
  ];
  final changes =
      preview.changes.where(calendarOfferVisible).length +
      preview.flagChanges.where((f) => f.flag != null).length;
  var added = const <String>[];
  if (mode == CalendarStartupMode.addDrafts && fresh.isNotEmpty) {
    try {
      added = await commitCalendarImport(
        repos,
        chosen: fresh,
        untitledTitle: untitledTitle,
        now: now,
      );
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'calendar_startup.commit');
      await _record(
        repos,
        CalendarStartupResult(at: now, ok: false, reached: true),
        failures: _Failures.keep,
      );
      return const CalendarStartupFailed();
    }
  }
  await _record(
    repos,
    CalendarStartupResult(
      at: now,
      ok: true,
      newEvents: fresh.length,
      added: added.length,
    ),
    failures: _Failures.reset,
  );
  if (fresh.isEmpty && changes == 0) return const CalendarStartupQuiet();
  return CalendarStartupFound(
    body: body,
    url: config.feedUrl!,
    newEvents: fresh.length,
    changes: changes,
    addedIds: added,
  );
}

/// Waits, before [runCalendarStartup], for Device Sync's pass for this
/// launch, [launchSync] (null when sync is off or not set up).
///
/// Drafts another device imported carry their `calendar_event_key`, and only
/// once this device has pulled them does [buildCalendarImportPreview] know
/// those events are not new. Without the wait, two devices with add-drafts
/// mode on each create drafts for the same events, and sync keeps both.
///
/// Returns at once, waiting for nothing, when the startup run is off or has
/// no address. Otherwise returns when [launchSync] does, successfully or
/// not, or after [limit], whichever is first. A failed pass is logged and
/// otherwise ignored. It reads nothing for the run itself: [runCalendarStartup]
/// reads every setting afresh afterwards, so a switch turned off, or a filter
/// the pass pulled, during the wait is what the run sees.
Future<void> awaitLaunchSyncForCalendarStartup(
  SettingsRepository settings,
  Future<void>? launchSync, {
  Duration limit = kCalendarStartupSyncWait,
}) async {
  if (launchSync == null) return;
  try {
    if (await settings.get(kCalendarImportOnStartupKey) != true) return;
    if (!(await CalendarImportSettings.read(settings)).hasFeed) return;
  } catch (error, stackTrace) {
    // The run reads them again and handles the failure there.
    logCaughtError(error, stackTrace, source: 'calendar_startup.sync_wait');
    return;
  }
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  final timer = Timer(limit, finish);
  unawaited(
    launchSync
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) => logCaughtError(
            error,
            stackTrace,
            source: 'calendar_startup.launch_sync',
          ),
        )
        .whenComplete(finish),
  );
  await done.future;
  timer.cancel();
}

/// What a run does to the "couldn't be reached" count.
enum _Failures {
  /// The calendar could not be reached: one more.
  count,

  /// A successful run: back to none.
  reset,

  /// Reached, but reading it or saving the drafts failed: neither counts
  /// toward the notice nor clears it.
  keep,
}

Future<void> _record(
  CompendiumRepositories repos,
  CalendarStartupResult result, {
  required _Failures failures,
}) async {
  try {
    await repos.settings.set(kCalendarLastResultKey, result.toJson());
    if (failures == _Failures.keep) return;
    final prior = await repos.settings.get(kCalendarStartupFailuresKey);
    final count = prior is int && prior >= 0 ? prior : 0;
    await repos.settings.set(
      kCalendarStartupFailuresKey,
      failures == _Failures.count ? count + 1 : 0,
    );
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'calendar_startup._record');
  }
}

/// Clears the repeated-failure count, for an edited address (#2353).
Future<void> resetCalendarStartupFailures(SettingsRepository settings) =>
    settings.set(kCalendarStartupFailuresKey, 0);
