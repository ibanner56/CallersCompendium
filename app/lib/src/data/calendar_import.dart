import 'dart:convert';
import 'dart:math' as math;

import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart';

import '../diagnostics/error_log.dart';
import 'calendar_import_settings.dart';
import 'display_defaults.dart';
import 'import_io.dart' show calendarFeedFetchUrl;
import 'program_templates.dart';

/// Which calendar a program came from (pre-release audit finding E1-01),
/// without the calendar's address: what [Program.calendarFeedDigest] holds.
///
/// The address is a secret (a private calendar's holds an access token), so
/// it is never stored on a program. Each draft instead gets a digest: a
/// 128-bit salt drawn at random for that program, then the first 128 bits of
/// HMAC-SHA256 keyed with the salt over the address in a normal form
/// ([normalizedCalendarFeedAddress]), both as lower-case hex, 64 digits in
/// all. [matches] recomputes it with the program's own salt
/// over the address being read. Because every program's salt differs, two
/// programs from one calendar, or two libraries with the same calendar, hold
/// unrelated values; someone holding a digest who guesses the exact address
/// can confirm it, which is what the privacy registry's
/// `programs.calendar_feed_digest` note records.
class CalendarFeedSource {
  /// [random] is a test seam; it defaults to [math.Random.secure].
  CalendarFeedSource(String url, {math.Random? random})
    : _address = utf8.encode(normalizedCalendarFeedAddress(url)),
      _random = random ?? math.Random.secure();

  final List<int> _address;
  final math.Random _random;

  static final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

  /// A new digest of this address, with a fresh salt: one per draft.
  String newDigest() {
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    return '${_hex(salt)}${_mac(salt)}';
  }

  /// Whether [digest] was made from this address. False for null and for
  /// anything not in [newDigest]'s shape.
  bool matches(String? digest) {
    if (digest == null || !_digestPattern.hasMatch(digest)) return false;
    final salt = [
      for (var i = 0; i < 32; i += 2)
        int.parse(digest.substring(i, i + 2), radix: 16),
    ];
    return _mac(salt) == digest.substring(32);
  }

  String _mac(List<int> salt) =>
      _hex(Hmac(sha256, salt).convert(_address).bytes.sublist(0, 16));

  static String _hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
}

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
    this.feedDigest,
  });

  final CalendarImportCandidate candidate;
  final CalendarEntryState state;

  /// The [Program.calendarFeedDigest] its draft gets: which calendar it came
  /// from ([CalendarFeedSource.newDigest]). Set on every offered entry.
  final String? feedDigest;

  /// The saved venue record whose name matches the event's location, when
  /// exactly one does.
  final String? venueId;

  /// Whether the preview offers a tick box for it.
  bool get offered =>
      state == CalendarEntryState.fresh || state == CalendarEntryState.deleted;

  /// Whether that box starts ticked.
  bool get tickedByDefault => state == CalendarEntryState.fresh;
}

/// [url] as [CalendarFeedSource] digests it: trimmed, `webcal://` read as
/// `https://` ([calendarFeedFetchUrl]), then in [Uri]'s normal form, which
/// lower-cases the scheme and host, normalises percent-encoding and drops a
/// default port, as the fetch itself reads it. The path and query keep their
/// case. So two spellings of one address are one calendar. An address [Uri]
/// cannot read is used as it is: it cannot be fetched either.
String normalizedCalendarFeedAddress(String url) {
  final fetched = calendarFeedFetchUrl(url);
  try {
    return Uri.parse(fetched).toString();
  } on FormatException {
    // diagnostics: silent — not an error: such an address is never fetched.
    return fetched;
  }
}

/// What a calendar import found, ready to preview.
class CalendarImportPreview {
  const CalendarImportPreview({
    required this.entries,
    this.unreadableSeries = const [],
    this.skippedNoUid = 0,
    this.truncated = false,
    this.changes = const [],
    this.flagChanges = const [],
    this.stillFlagged = const [],
  });

  final List<CalendarImportEntry> entries;
  final List<String> unreadableSeries;
  final int skippedNoUid;
  final bool truncated;

  /// Programs whose event changed in the calendar (#2354), in date order.
  final List<CalendarChangeOffer> changes;

  /// Flags the import sets or clears when the caller presses Import (#2354).
  final List<CalendarFlagChange> flagChanges;

  /// Programs already flagged that stay flagged.
  final List<Program> stillFlagged;

  /// Programs that are, or on Import will be, flagged: for information only.
  List<CalendarFlagChange> get flagged => [
    for (final f in flagChanges)
      if (f.flag != null) f,
    for (final p in stillFlagged)
      CalendarFlagChange(program: p, flag: p.calendarFlag),
  ];

  /// Whether Import has something to write with no box ticked: a flag to
  /// set or clear, or a change the caller saw and left unticked (recorded so
  /// it is not offered again). An offer with nothing to show is recorded only
  /// alongside such a write, so a review with nothing to show never rewrites
  /// every program.
  bool get hasPendingWrites =>
      flagChanges.isNotEmpty || changes.any(calendarOfferVisible);

  int get offeredCount => entries.where((e) => e.offered).length;

  /// Events not imported before, not counting ones deleted here.
  int get freshCount =>
      entries.where((e) => e.state == CalendarEntryState.fresh).length;
}

/// Parses [body] (a fetched feed) and compares it with the collection.
///
/// [feedUrl] is the address [body] was fetched from: each draft records which
/// calendar it came from ([CalendarFeedSource]), and only programs whose
/// recorded calendar is this one get change offers, flags and
/// [CalendarImportPreview.stillFlagged]. A program from another calendar, or
/// with none recorded, is left as it is; its event is still recognised as
/// [CalendarEntryState.alreadyImported].
/// [today] is the local date ([clock] in the caller); [toLocal] converts a
/// UTC instant to local time. Both are parameters so tests can inject them.
/// Throws [NotACalendarException] for a body that is not a calendar.
Future<CalendarImportPreview> buildCalendarImportPreview(
  CompendiumRepositories repos, {
  required String body,
  required String feedUrl,
  required CalendarImportSettings settings,
  required DateTime today,
  DateTime Function(DateTime utc)? toLocal,
  math.Random? random,
}) async {
  final source = CalendarFeedSource(feedUrl, random: random);
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
  final venueNames = <String, String>{};
  for (final venue in await repos.venues.listAll()) {
    venueNames[venue.id] = venue.name;
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
    final offered =
        state == CalendarEntryState.fresh ||
        state == CalendarEntryState.deleted;
    entries.add(
      CalendarImportEntry(
        candidate: c,
        state: state,
        venueId: venueIdFor(c.venueLabel),
        feedDigest: offered ? source.newDigest() : null,
      ),
    );
  }
  // #2354: what changed upstream for programs already imported, and which
  // ones the calendar cancelled or no longer has. Nothing is written here.
  // Only programs imported from this calendar are compared with it
  // (pre-release audit finding E1-01): one from another calendar, or with no
  // calendar recorded, would otherwise read as gone from this one.
  final candidatesByKey = <String, CalendarImportCandidate>{};
  for (final c in plan.candidates) {
    // The first of a duplicated event, as the entries above keep it.
    candidatesByKey.putIfAbsent(c.eventKey, () => c);
  }
  final stillFlagged = <Program>[];
  final changes = <CalendarChangeOffer>[];
  final flagChanges = <CalendarFlagChange>[];
  final day0 = DateTime.utc(today.year, today.month, today.day);
  final horizonEnd = day0.add(const Duration(days: iCalRepeatHorizonDays));
  for (final program in await repos.programs.listAll()) {
    final key = program.calendarEventKey;
    if (key == null || !source.matches(program.calendarFeedDigest)) continue;
    final String? targetFlag;
    if (plan.cancelledAnywhereKeys.contains(key)) {
      targetFlag = calendarFlagCancelled;
    } else if (plan.knownKeys.contains(key)) {
      // Still in the calendar, wherever it moved.
      targetFlag = null;
    } else if (plan.canJudgeMissing &&
        _withinHorizon(program.eventDate, day0, horizonEnd)) {
      targetFlag = calendarFlagMissing;
    } else {
      // Not judged: outside the range read in full, or the feed was not read
      // whole. Left as it is.
      targetFlag = program.calendarFlag;
    }
    if (targetFlag != program.calendarFlag) {
      flagChanges.add(CalendarFlagChange(program: program, flag: targetFlag));
    } else if (targetFlag != null) {
      stillFlagged.add(program);
    }
    final candidate = candidatesByKey[key];
    if (candidate == null) continue;
    final offer = _changeOffer(
      program,
      candidate,
      venueIdFor,
      (id) => venueNames[id],
      toLocal ?? (utc) => utc.toLocal(),
    );
    if (offer != null) changes.add(offer);
  }
  changes.sort((a, b) => a.candidate.date.compareTo(b.candidate.date));
  return CalendarImportPreview(
    entries: entries,
    unreadableSeries: plan.unreadableSeries,
    skippedNoUid: plan.skippedNoUid,
    truncated: plan.truncated,
    changes: changes,
    flagChanges: flagChanges,
    stillFlagged: stillFlagged,
  );
}

/// "No longer in the calendar" is judged only for a program dated from today
/// up to [iCalRepeatHorizonDays] ahead: the range in which single events and
/// every occurrence of a repeating series are both read in full. A program
/// outside it is never reported gone, so one whose event moved out of range is
/// left alone (#2354).
bool _withinHorizon(DateTime? date, DateTime day0, DateTime end) =>
    date != null && !date.isBefore(day0) && !date.isAfter(end);

/// An upstream change to a program a calendar import created (#2354).
class CalendarChangeOffer {
  const CalendarChangeOffer({
    required this.program,
    required this.candidate,
    required this.untouched,
    required this.title,
    required this.date,
    required this.venue,
    this.start = false,
    this.end = false,
    this.shownVenue,
    this.venueId,
  });

  /// The venue the program shows now: its linked record's name, else its
  /// typed label. The "before" side of a venue change.
  final String? shownVenue;

  /// The program as stored now.
  final Program program;

  /// The event as it is now.
  final CalendarImportCandidate candidate;

  /// [Program.isUntouchedCalendarDraft]: the offer starts ticked. Otherwise
  /// it starts unticked. Either way only the fields that changed upstream,
  /// and differ from the program now, are offered.
  final bool untouched;

  /// Which fields the offer would change; each differs from the program now.
  final bool title;
  final bool date;
  final bool venue;

  /// The start and the end time (#2423), each on its own like the other
  /// fields: an all-day event has neither, so taking it clears them.
  final bool start;
  final bool end;

  /// Whether either time is offered: one "Time" line in the review.
  bool get time => start || end;

  /// The saved venue record the new location matches, if one does.
  final String? venueId;
}

/// A flag a calendar import sets (or, with a null [flag], clears) on Import.
class CalendarFlagChange {
  const CalendarFlagChange({required this.program, required this.flag});

  final Program program;
  final String? flag;
}

CalendarChangeOffer? _changeOffer(
  Program program,
  CalendarImportCandidate c,
  String? Function(String? label) venueIdFor,
  String? Function(String id) venueName,
  DateTime Function(DateTime utc) toLocal,
) {
  final stored = program.calendarEventFingerprint;
  if (stored == c.fingerprint) return null;
  final upstream = calendarFingerprintChanges(stored, c.fingerprint);
  // With no usable fingerprint (one this build cannot read, or none), compare
  // the program's own values: it is treated as worked on.
  final untouched = upstream != null && program.isUntouchedCalendarDraft;
  final newTitle = c.title.trim().isEmpty ? null : c.title;
  final titleDiffers = newTitle != null && newTitle != program.title;
  final dateDiffers = c.date != program.eventDate;
  // The venue the caller sees: a linked record's name, else the typed label.
  final shownVenue = program.venueId == null
      ? program.venue
      : (venueName(program.venueId!) ?? program.venue);
  final venueDiffers = (c.venueLabel ?? '') != (shownVenue ?? '');
  final startDiffers = c.startMinute != program.startMinute;
  final endDiffers = c.endMinute != program.endMinute;
  final title = titleDiffers && (upstream?.title ?? true);
  // The date is offered only when the event's own local date moved, not
  // merely because it differs from a date the caller edited. The date part
  // alone cannot say so: a UTC event's is its UTC date, which can move
  // while the local date stays and the other way round, and a calendar can
  // re-save an event from a local time to UTC or back.
  final date =
      dateDiffers &&
      (upstream == null ||
          (calendarFingerprintLocalDateMoved(stored, c, toLocal) ?? true));
  final venue = venueDiffers && (upstream?.venue ?? true);
  final start = startDiffers && (upstream?.start ?? true);
  final end = endDiffers && (upstream?.end ?? true);
  if (!title && !date && !venue && !start && !end) {
    // Changed upstream to what the program already says: nothing to offer,
    // but the new fingerprint is recorded on the next Import.
    return CalendarChangeOffer(
      program: program,
      candidate: c,
      untouched: untouched,
      title: false,
      date: false,
      venue: false,
    );
  }
  return CalendarChangeOffer(
    program: program,
    candidate: c,
    untouched: untouched,
    title: title,
    date: date,
    venue: venue,
    start: start,
    end: end,
    shownVenue: shownVenue,
    venueId: venueIdFor(c.venueLabel),
  );
}

/// Whether [offer] has anything to show the caller.
bool calendarOfferVisible(CalendarChangeOffer offer) =>
    offer.title || offer.date || offer.venue || offer.time;

/// The stamp a calendar import writes: [now] at the store's one-second
/// precision, and after [prior] so the write wins last-writer-wins.
DateTime calendarWriteStamp(DateTime now, DateTime prior) {
  final whole = DateTime.fromMillisecondsSinceEpoch(
    now.toUtc().millisecondsSinceEpoch ~/ 1000 * 1000,
    isUtc: true,
  );
  final next = prior.add(storedTimestampTick);
  return whole.isAfter(prior) ? whole : next;
}

/// Writes what the caller chose in the review (#2354): the ticked offers in
/// [accepted] update their programs, every other offer only records the
/// event's new fingerprint (so it is offered again only if the event changes
/// again), and every flag change is applied. Nothing is deleted or archived.
///
/// Each program is re-read first and skipped if it changed since the review
/// was built (another pane, or Device Sync): the review described the older
/// version. If a write fails, the ones already made are put back before the
/// error is rethrown. Returns what it wrote, for Undo
/// ([undoCalendarUpdates]).
Future<List<CalendarUpdateRecord>> applyCalendarUpdates(
  CompendiumRepositories repos, {
  required CalendarImportPreview preview,
  required Set<String> accepted,
  required DateTime now,
}) async {
  final before = <String, Program>{};
  final after = <String, Program>{};
  Program current(Program p) => after[p.id] ?? p;
  void stage(Program original, Program updated) {
    before.putIfAbsent(original.id, () => original);
    after[original.id] = updated;
  }

  final otherWrites = preview.hasPendingWrites;
  for (final offer in preview.changes) {
    final visible = calendarOfferVisible(offer);
    final take = visible && accepted.contains(offer.program.id);
    // An offer the caller saw is recorded, ticked or not; one with nothing
    // to show only rides along with some other write.
    if (!visible && !otherWrites) continue;
    final p = current(offer.program);
    final c = offer.candidate;
    var next = p.copyWith(calendarEventFingerprint: c.fingerprint);
    if (take) {
      next = next.copyWith(
        title: offer.title ? c.title : null,
        eventDate: offer.date ? c.date : null,
        venue: offer.venue ? c.venueLabel : null,
        clearVenue: offer.venue && c.venueLabel == null,
        // The caller ticked "Venue: old → new", so the venue they see
        // becomes the new one: linked to the record it matches, or unlinked.
        venueId: offer.venue ? offer.venueId : null,
        clearVenueId: offer.venue && offer.venueId == null,
        startMinute: offer.start ? c.startMinute : null,
        clearStartMinute: offer.start && c.startMinute == null,
        endMinute: offer.end ? c.endMinute : null,
        clearEndMinute: offer.end && c.endMinute == null,
      );
    }
    stage(offer.program, next);
  }
  for (final change in preview.flagChanges) {
    final p = current(change.program);
    stage(
      change.program,
      change.flag == null
          ? p.copyWith(clearCalendarFlag: true)
          : p.copyWith(calendarFlag: change.flag),
    );
  }
  final written = <CalendarUpdateRecord>[];
  try {
    for (final entry in after.entries) {
      final original = before[entry.key]!;
      final stored = await repos.programs.getById(original.id);
      if (stored == null || stored.updatedAt != original.updatedAt) continue;
      final stamp = calendarWriteStamp(now, stored.updatedAt);
      await repos.programs.update(
        entry.value.copyWith(
          updatedAt: stamp,
          // The import's own write keeps an untouched draft untouched.
          calendarWrittenAt: original.isUntouchedCalendarDraft ? stamp : null,
        ),
      );
      written.add(CalendarUpdateRecord(before: original, stamp: stamp));
    }
  } catch (_) {
    // diagnostics: silent — rethrown below; logged at the UI boundary.
    await undoCalendarUpdates(repos, written, now: now);
    rethrow;
  }
  return written;
}

/// Puts back the programs [applyCalendarUpdates] changed, as they were, with
/// a new stamp. A program the caller had not touched stays untouched. One
/// changed again since (another pane, or Device Sync) is left alone: putting
/// the old version back would lose that change.
Future<void> undoCalendarUpdates(
  CompendiumRepositories repos,
  List<CalendarUpdateRecord> records, {
  required DateTime now,
}) async {
  for (final record in records) {
    final original = record.before;
    final stored = await repos.programs.getById(original.id);
    // Still the version the import wrote, or leave it.
    if (stored == null || stored.updatedAt != record.stamp) continue;
    final stamp = calendarWriteStamp(now, stored.updatedAt);
    await repos.programs.update(
      original.copyWith(
        updatedAt: stamp,
        calendarWrittenAt: original.isUntouchedCalendarDraft ? stamp : null,
      ),
    );
  }
}

/// One program a calendar import updated: as it was, and the stamp written.
class CalendarUpdateRecord {
  const CalendarUpdateRecord({required this.before, required this.stamp});

  final Program before;
  final DateTime stamp;
}

/// Clears [program]'s calendar flag (the summary's "Clear calendar flag").
Future<void> clearCalendarFlag(
  CompendiumRepositories repos,
  Program program, {
  required DateTime now,
}) async {
  // The stored version, not the screen's copy, which may be older.
  final stored = await repos.programs.getById(program.id);
  if (stored == null || stored.calendarFlag == null) return;
  final stamp = calendarWriteStamp(now, stored.updatedAt);
  await repos.programs.update(
    stored.copyWith(
      clearCalendarFlag: true,
      updatedAt: stamp,
      calendarWrittenAt: stored.isUntouchedCalendarDraft ? stamp : null,
    ),
  );
}

/// Creates one draft program per entry in [chosen] and returns their ids.
///
/// Each draft has the event's title ([untitledTitle] when it has none), its
/// date, its start and end times when the event is timed (#2423), its venue
/// label (and linked venue record when one matched), status Draft, the
/// **Default template**'s slots (#2337, [defaultProgramTemplate]; none for
/// Blank program) and its live event rules while Event rules is on (#2342,
/// [newProgramEventRuleIds]), the default caller and band, the event's key,
/// and the calendar it came from ([CalendarImportEntry.feedDigest]).
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
  final (template, eventRuleIds) = await _startingTemplate(repos);
  final created = <String>[];
  // At the store's precision, so the untouched test compares equal values.
  final stamp = calendarWriteStamp(now, DateTime.utc(1970));
  try {
    for (final entry in chosen) {
      final c = entry.candidate;
      final id = uuidV4();
      await repos.programs.create(
        Program(
          id: id,
          title: c.title.trim().isEmpty ? untitledTitle : c.title,
          eventDate: c.date,
          // A timed event's start and end (#2423); an all-day one has none.
          startMinute: c.startMinute,
          endMinute: c.endMinute,
          venue: c.venueLabel,
          venueId: entry.venueId,
          caller: caller,
          band: band,
          status: ProgramStatus.draft,
          slots: [
            // A slot rule is saved as a placeholder that remembers its saved
            // search, so Fill still works on the draft later (#2338).
            for (final (i, slot) in template.indexed)
              programSlotForTemplateEntry(slot, position: i),
          ],
          // The Default template's rules, copied: choosing a template that
          // carries rules adds them (#2342).
          eventRuleIds: eventRuleIds,
          calendarEventKey: c.eventKey,
          calendarEventFingerprint: c.fingerprint,
          calendarFeedDigest: entry.feedDigest,
          calendarWrittenAt: stamp,
          createdAt: stamp,
          updatedAt: stamp,
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

/// The Default template's entries whose dance is still live, and its live
/// event rules ([newProgramEventRuleIds]), as New program uses them (#2337,
/// #2342).
Future<(List<ProgramTemplateEntry>, List<String>)> _startingTemplate(
  CompendiumRepositories repos,
) async {
  final ProgramTemplate? template;
  final List<String> eventRuleIds;
  try {
    template = await defaultProgramTemplate(repos.settings);
    eventRuleIds = await newProgramEventRuleIds(repos, template);
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'calendar_import._template');
    return (const <ProgramTemplateEntry>[], const <String>[]);
  }
  final entries = template?.entries ?? const <ProgramTemplateEntry>[];
  final out = <ProgramTemplateEntry>[];
  for (final entry in entries) {
    final danceId = entry.danceId;
    if (danceId != null && await repos.dances.getById(danceId) == null) {
      continue;
    }
    out.add(entry);
  }
  return (out, eventRuleIds);
}

/// The typed-venue [VenueKey] fold of [name] (whitespace collapsed, case
/// folded), or null for a blank name.
String? _venueFold(String name) =>
    name.trim().isEmpty ? null : VenueKey.typed(name).typedVenue;
