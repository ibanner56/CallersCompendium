import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';
import 'calendar_import_settings.dart';
import 'display_defaults.dart';
import 'program_templates.dart';

/// How one calendar event stands against the collection (#2352).
enum CalendarEntryState {
  /// Not imported before: offered, ticked.
  fresh,

  /// A program already holds this event's key. Listed, not offered. Whatever
  /// changed in the calendar since is not looked at here (#2354).
  alreadyImported,

  /// Its `UID` is `<id>@callers-compendium` and a program has that id: this
  /// app exported it (#2351). Listed, not offered.
  fromThisApp,

  /// Only a program in Recently deleted holds its key: offered unticked
  /// ("You deleted this program").
  deleted,
}

/// One event in the calendar import preview.
class CalendarImportEntry {
  const CalendarImportEntry({
    required this.candidate,
    required this.state,
    this.venueId,
  });

  final CalendarImportCandidate candidate;
  final CalendarEntryState state;

  /// The saved venue record whose name matches the event's location, when
  /// exactly one does.
  final String? venueId;

  /// Whether the preview offers a tick box for it.
  bool get offered =>
      state == CalendarEntryState.fresh || state == CalendarEntryState.deleted;

  /// Whether that box starts ticked.
  bool get tickedByDefault => state == CalendarEntryState.fresh;
}

/// What a calendar import found, ready to preview.
class CalendarImportPreview {
  const CalendarImportPreview({
    required this.entries,
    this.unreadableSeries = const [],
    this.skippedNoUid = 0,
    this.truncated = false,
  });

  final List<CalendarImportEntry> entries;
  final List<String> unreadableSeries;
  final int skippedNoUid;
  final bool truncated;

  int get offeredCount => entries.where((e) => e.offered).length;

  /// Events not imported before, not counting ones deleted here.
  int get freshCount =>
      entries.where((e) => e.state == CalendarEntryState.fresh).length;
}

/// Parses [body] (a fetched feed) and compares it with the collection.
///
/// [today] is the local date ([clock] in the caller); [toLocal] converts a
/// UTC instant to local time. Both are parameters so tests can inject them.
/// Throws [NotACalendarException] for a body that is not a calendar.
Future<CalendarImportPreview> buildCalendarImportPreview(
  CompendiumRepositories repos, {
  required String body,
  required CalendarImportSettings settings,
  required DateTime today,
  DateTime Function(DateTime utc)? toLocal,
}) async {
  final plan = planCalendarImport(
    parseICalFeed(body),
    today: today,
    windowMonths: settings.windowMonths,
    titleFilter: settings.titleFilter,
    toLocal: toLocal,
  );
  final keyStates = await repos.programs.calendarEventKeyStates(
    plan.candidates.map((c) => c.eventKey),
  );
  final exportedStates = await repos.programs.programDeletedStates([
    for (final c in plan.candidates) ?c.exportedProgramId,
  ]);
  final venuesByFolded = <String, List<Venue>>{};
  for (final venue in await repos.venues.listAll()) {
    final folded = _venueFold(venue.name);
    if (folded != null) (venuesByFolded[folded] ??= []).add(venue);
  }
  String? venueIdFor(String? label) {
    if (label == null) return null;
    final folded = _venueFold(label);
    final matches = folded == null ? null : venuesByFolded[folded];
    return matches != null && matches.length == 1 ? matches.single.id : null;
  }

  final entries = <CalendarImportEntry>[];
  // One feed can list the same occurrence twice (a duplicated VEVENT); the
  // first is kept.
  final seen = <String>{};
  for (final c in plan.candidates) {
    if (!seen.add(c.eventKey)) continue;
    final CalendarEntryState state;
    if (c.exportedProgramId case final id?
        when exportedStates.containsKey(id)) {
      // Live or in Recently deleted: either way it is this app's own program.
      state = CalendarEntryState.fromThisApp;
    } else {
      state = switch (keyStates[c.eventKey]) {
        null => CalendarEntryState.fresh,
        false => CalendarEntryState.alreadyImported,
        true => CalendarEntryState.deleted,
      };
    }
    entries.add(
      CalendarImportEntry(
        candidate: c,
        state: state,
        venueId: venueIdFor(c.venueLabel),
      ),
    );
  }
  return CalendarImportPreview(
    entries: entries,
    unreadableSeries: plan.unreadableSeries,
    skippedNoUid: plan.skippedNoUid,
    truncated: plan.truncated,
  );
}

/// Creates one draft program per entry in [chosen] and returns their ids.
///
/// Each draft has the event's title ([untitledTitle] when it has none), its
/// date, its venue label (and linked venue record when one matched), status
/// Draft, the **Default template**'s slots (#2337,
/// [defaultProgramTemplateEntries]; none for Blank program), the default
/// caller and band, and the event's key.
/// Nothing from `DESCRIPTION`, `ORGANIZER`, `ATTENDEE` or `URL`: the parser
/// never reads them.
///
/// If a write fails, the drafts already written are removed again before the
/// error is rethrown, so an import is all or nothing.
Future<List<String>> commitCalendarImport(
  CompendiumRepositories repos, {
  required List<CalendarImportEntry> chosen,
  required String untitledTitle,
  required DateTime now,
}) async {
  final caller = await _defaultText(repos, kDefaultProgramCallerKey);
  final band = await _defaultText(repos, kDefaultProgramBandKey);
  final template = await _startingTemplate(repos);
  final created = <String>[];
  try {
    for (final entry in chosen) {
      final c = entry.candidate;
      final id = uuidV4();
      await repos.programs.create(
        Program(
          id: id,
          title: c.title.trim().isEmpty ? untitledTitle : c.title,
          eventDate: c.date,
          venue: c.venueLabel,
          venueId: entry.venueId,
          caller: caller,
          band: band,
          status: ProgramStatus.draft,
          slots: [
            for (final (i, slot) in template.indexed)
              ProgramSlot(
                id: uuidV4(),
                position: i,
                danceId: slot.danceId,
                text: slot.text,
              ),
          ],
          calendarEventKey: c.eventKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
      created.add(id);
    }
  } catch (_) {
    // diagnostics: silent — rethrown below; logged at the UI boundary.
    if (created.isNotEmpty) await repos.programs.hardDelete(created);
    rethrow;
  }
  return created;
}

Future<String?> _defaultText(CompendiumRepositories repos, String key) async {
  try {
    final stored = await repos.settings.get(key);
    final value = stored is String ? stored.trim() : '';
    return value.isEmpty ? null : value;
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'calendar_import._defaultText');
    return null;
  }
}

/// The Default template's entries whose dance is still live, as New program
/// uses them (#2337).
Future<List<ProgramTemplateEntry>> _startingTemplate(
  CompendiumRepositories repos,
) async {
  final List<ProgramTemplateEntry> entries;
  try {
    entries = await defaultProgramTemplateEntries(repos.settings);
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'calendar_import._template');
    return const [];
  }
  final out = <ProgramTemplateEntry>[];
  for (final entry in entries) {
    final danceId = entry.danceId;
    if (danceId != null && await repos.dances.getById(danceId) == null) {
      continue;
    }
    out.add(entry);
  }
  return out;
}

/// The typed-venue [VenueKey] fold of [name] (whitespace collapsed, case
/// folded), or null for a blank name.
String? _venueFold(String name) =>
    name.trim().isEmpty ? null : VenueKey.typed(name).typedVenue;
