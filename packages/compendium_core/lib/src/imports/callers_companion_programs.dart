import 'package:meta/meta.dart';

import '../model/enums.dart';
import '../model/program.dart';
import '../model/provenance.dart';
import '../util/text_sanitizer.dart';
import '../util/uuid.dart';
import 'callers_companion_usr_archive.dart';
import 'program_slot_note.dart';
import 'structured_draft.dart';

/// The result of [buildCcPrograms]: the built [Program]s plus the non-fatal
/// [ImportIssue]s raised while building them.
@immutable
class CcProgramsResult {
  CcProgramsResult({
    List<Program> programs = const [],
    List<ImportIssue> issues = const [],
  }) : programs = List.unmodifiable(programs),
       issues = List.unmodifiable(issues);

  final List<Program> programs;
  final List<ImportIssue> issues;
}

/// Builds [Program]s from a Caller's Companion [CcUsrArchive]'s `Set`/`SetItem`
/// rows, resolving each item's CC dance reference to a local Compendium dance
/// id via [danceIdByCcRowId].
///
/// This is a **pure builder** — it takes no repository and performs no I/O,
/// mirroring [mapCallersCompanionDance]'s philosophy — so it is trivially
/// unit-testable and stays Flutter-free in the core. The app layer calls it
/// *after* the dance import commits (so [danceIdByCcRowId] maps CC `Dance`
/// record ids → the Compendium dance ids the commit wrote, plus dances the
/// review resolved outside the commit: a skipped re-import row's target, or a
/// row already committed through Import and edit), then persists the returned
/// programs via `ProgramRepository` and records them for undo. Wiring that
/// persistence/undo is an app-layer follow-up because [ImportPipeline] is
/// dance-only; keeping this a pure function avoids a large pipeline refactor in
/// this PR (see the PR notes).
///
/// **Parse-never-fails:** an unresolved dance reference, an unparseable event
/// date, or an empty slot degrades to a graceful fallback (a text slot or a
/// left-out slot, below; a null date; a skipped empty slot), with an
/// [ImportIssue] where the person should hear of it — never a throw.
///
/// **A dance that did not commit** (maintainer decisions on #1976,
/// 2026-10-30): a slot naming a CC dance [danceIdByCcRowId] does not resolve
/// becomes
/// - nothing, with an info issue, when the dance is not in the file's `Dance`
///   table ([CcUsrArchive.danceRecordIds]): it was deleted in Caller's
///   Companion;
/// - its title then a `Dance not imported (…)` line, with a warning, when it
///   is in [failedCcRowIds]: its commit failed;
/// - its title alone, from [danceTitleByCcRowId], when the import left it out
///   (Skip in review, or an ambiguous row an unattended import skipped);
/// - the `Dance not imported (…)` line alone, with a warning, when there is
///   no title to give.
CcProgramsResult buildCcPrograms(
  CcUsrArchive archive, {
  required Map<String, String> danceIdByCcRowId,
  Map<String, String> danceTitleByCcRowId = const {},
  Set<String> failedCcRowIds = const {},
  String Function()? newId,
  String Function()? newSlotId,
  DateTime? now,
}) {
  final mintId = newId ?? uuidV4;
  final mintSlotId = newSlotId ?? uuidV4;
  final timestamp = now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final issues = <ImportIssue>[];
  final programs = <Program>[];

  for (final set in archive.sets) {
    final (eventDate, dateIssue) = _parseEventDate(set.eventDate, set.recordId);
    if (dateIssue != null) issues.add(dateIssue);
    final title = _titleFor(set, eventDate);

    final slots = <ProgramSlot>[];
    var position = 0;
    // A dance flagged `Break` puts the break after it and its alternates
    // (#1974): the break is pending until the next item that is not an
    // alternate in the file ends that group, and is then due before the next
    // slot kept, which may be a left-out dance's promoted alternate (#1976).
    var breakPending = false;
    var breakDue = false;
    // Places the due break; a break a left-out dance has just made pending
    // for its own group stays pending.
    void addBreak() {
      breakDue = false;
      // Nothing to break between at the start, and a break right after
      // another (a deleted dance's, #1976) adds nothing.
      // An alternate break does not count: hiding alternates would hide it.
      if (slots.isEmpty || (slots.last.isBreak && !slots.last.isAlt)) return;
      slots.add(
        ProgramSlot(
          id: mintSlotId(),
          position: position++,
          text: Program.breakSlotText,
        ),
      );
    }

    // A left-out dance's first alternate takes its place (#1976), as removing
    // a slot in the program editor promotes one.
    var promoteAlt = false;
    for (final item in set.items) {
      String? danceId;
      String? text;
      final promoting = promoteAlt;
      final isAlt = item.isAlt && !promoting;
      promoteAlt = false;
      final cleanBreakText = _cleanNote(item.breakText);
      if (breakPending && !item.isAlt) {
        breakPending = false;
        breakDue = true;
      }
      if (item.danceRecordId case final ccId?) {
        danceId = danceIdByCcRowId[ccId];
        final known = archive.danceRecordIds;
        if (danceId == null && known != null && !known.contains(ccId)) {
          // Deleted in Caller's Companion: nothing to show (#1976, 5c). Its
          // break still follows it and its alternates.
          issues.add(
            ImportIssue(
              severity: ImportIssueSeverity.info,
              code: 'cc_program_deleted_dance',
              message:
                  'Set "$title" references dance #$ccId, which is not in the '
                  'file; left the slot out.',
            ),
          );
          if (item.breakAfter) breakPending = true;
          // A deleted dance that was itself promoted passes it on.
          promoteAlt = !isAlt;
          continue;
        }
        if (danceId == null) {
          final danceTitle = _cleanLine(danceTitleByCcRowId[ccId]);
          final marker =
              "$kUnresolvedDanceMarkerPrefix"
              "Caller's Companion dance #$ccId)";
          if (cleanBreakText == null &&
              danceTitle != null &&
              !failedCcRowIds.contains(ccId)) {
            // Left out of the import on purpose: the title reads as the slot.
            text = danceTitle;
          } else {
            // The marker sits on its own line, after a blank line, as
            // `danceTitleFromSlotNote` expects. A slot's own text, which a
            // real file never gives a dance slot, wins as before.
            text =
                cleanBreakText ??
                (danceTitle == null ? marker : '$danceTitle\n\n$marker');
            issues.add(
              ImportIssue(
                severity: ImportIssueSeverity.warning,
                code: 'cc_program_unresolved_dance',
                message:
                    'Set "$title" references dance #$ccId, which was not '
                    'imported; kept the slot as a text placeholder.',
              ),
            );
          }
        }
      } else {
        text = cleanBreakText;
      }

      if (danceId == null && (text == null || text.isEmpty)) {
        // A slot with neither a dance nor text cannot be represented; skip it.
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'cc_program_empty_slot',
            message: 'Skipped an empty slot in set "$title".',
          ),
        );
        // An empty alternate cannot take a left-out dance's place, and an
        // empty dance's alternate takes its place.
        promoteAlt = (promoting && item.isAlt) || !isAlt;
        continue;
      }

      if (breakDue) {
        // Unless this slot is a break already: the set's own, or a left-out
        // dance titled "Break", which would otherwise read as a second one.
        // (`!isAlt` is defensive: the first slot kept after a break falls due
        // is never an alternate, as promotion passes through left-out items.)
        final isOwnBreak =
            !isAlt &&
            text?.trim().toLowerCase() == Program.breakSlotText.toLowerCase();
        if (isOwnBreak) {
          breakDue = false;
        } else {
          addBreak();
        }
      }
      slots.add(
        ProgramSlot(
          id: mintSlotId(),
          position: position++,
          danceId: danceId,
          text: text,
          isAlt: isAlt,
          guestCaller: _cleanLine(item.guestCaller),
          danceMinutes: item.minutes,
        ),
      );
      if (item.breakAfter) breakPending = true;
    }
    if (breakPending || breakDue) {
      breakPending = false;
      addBreak();
    }
    // Decided on the slots built, so a skipped item's caller does not count.
    final keptSlots = _keepsSlotCallers(slots, set.caller)
        ? slots
        : [for (final slot in slots) slot.copyWith(clearGuestCaller: true)];

    programs.add(
      Program(
        id: mintId(),
        title: title,
        eventDate: eventDate,
        venue: _cleanLine(set.location),
        band: _cleanLine(set.band),
        caller: _cleanLine(set.caller),
        dancerLevel: _cleanLine(set.dancerLevel),
        notes: _cleanNote(set.notes) ?? '',
        hideAlternates: set.hideAlternates,
        slots: keptSlots,
        createdAt: timestamp,
        updatedAt: timestamp,
        // Provenance keyed on the CC `zk_Set_ID` (carried as [CcSet.recordId]),
        // so re-importing the same `.USR` dedupes onto this program instead of
        // creating a duplicate. Mirrors the CC dance provenance stamped by the
        // import pipeline (`source: callersCompanion`, `externalId: zk_*_ID`).
        provenance: Provenance(
          source: ProvenanceSource.callersCompanion,
          externalId: set.recordId,
          importedAt: timestamp,
          sourceVersion: ccUsrSourceVersion,
        ),
      ),
    );
  }

  return CcProgramsResult(programs: programs, issues: issues);
}

/// The program title for [set], dated [eventDate] (its parsed `Date`).
///
/// A [CcSet.title] wins, though the `.USR` reader never sets one: CC Sets have
/// no title field. CC itself names a set by its zi_DateLocation_c
/// calculation, `YYYY/MM/DD - Location`, so the program takes that
/// ("2024/04/20 - NEFFA Contra Party", maintainer decision on #1976), or just
/// the date when there is no Location. Without a parsed date it is the
/// Location, else `Caller's Companion set — <raw date>`, else the set's id.
String _titleFor(CcSet set, DateTime? eventDate) {
  final title = _cleanLine(set.title);
  if (title != null) return title;
  final location = _cleanLine(set.location);
  if (eventDate != null) {
    final y = eventDate.year.toString().padLeft(4, '0');
    final m = eventDate.month.toString().padLeft(2, '0');
    final d = eventDate.day.toString().padLeft(2, '0');
    return location == null ? '$y/$m/$d' : '$y/$m/$d - $location';
  }
  if (location != null) return location;
  final date = _cleanLine(set.eventDate);
  if (date != null) return "Caller's Companion set — $date";
  return "Caller's Companion set #${set.recordId}";
}

/// Whether [slots], built from a set whose `Caller` is [setCaller], keep their
/// `SetItem.Caller` names (#1976).
///
/// CC fills a slot's caller with a first name ("Michael"), the set's own
/// caller's included, so on a set one person called every slot just repeats
/// them. The maintainer's rule (#1976, 2026-10-28, clarified 2026-10-30 and
/// 2026-10-31): keep the slots' callers when they name more than one caller,
/// when a name is not the set's own caller (matched by first name), or when
/// the set's `Caller` names several people ("Michael Smith & Lisa Greenleaf").
/// A set with no `Caller` keeps a lone name, as nothing else records who
/// called (the implementer's reading).
///
/// A slot name is the set's caller when its words begin the set caller's, read
/// from the given name on ([_setCallerWords]): "Michael" and "Michael Smith"
/// for "Michael Smith". Never the reverse, so on a set
/// called by "Mary" the slots "Mary Kate" and "Mary Lou" are two callers.
bool _keepsSlotCallers(List<ProgramSlot> slots, String? setCaller) {
  final caller = _cleanLine(setCaller);
  if (caller != null && _namesSeveralPeople(caller)) return true;
  final callerWords = caller == null ? null : _setCallerWords(caller);
  const setCallerKey = '\u0000';
  final names = <String>{
    for (final slot in slots)
      if (slot.guestCaller case final name?)
        if (_words(name) case final words when words.isNotEmpty)
          callerWords != null && _startsWith(callerWords, words)
              ? setCallerKey
              : words.join(' '),
  };
  if (names.length > 1) return true;
  if (names.isEmpty) return false;
  return names.single != setCallerKey;
}

/// Name suffixes, which may follow a name with or without a comma ("Michael
/// Smith, Jr.") without being another name or a given name.
const Set<String> _nameSuffixes = {'jr', 'sr', 'ii', 'iii', 'iv'};

/// Whether a set's [caller] names more than one person: joined by `&`, `+`,
/// `/`, `;`, or the word "and" or "with", or by a comma that sets off anything
/// but a name suffix ("Michael Smith, Jr."). A comma between two single words
/// is read as two people, not "Last, First": "Michael, Lisa" and "Smith,
/// Michael" cannot be told apart, and keeping the slot callers loses nothing
/// (the implementer's reading).
bool _namesSeveralPeople(String caller) {
  final lower = caller.toLowerCase();
  if (RegExp(r'[&+/;]').hasMatch(lower)) return true;
  final words = _words(lower);
  if (words.contains('and') || words.contains('with')) return true;
  final parts = [
    for (final part in lower.split(','))
      if (_words(part) case final words when words.isNotEmpty) words,
  ];
  return parts
          .where((w) => !(w.length == 1 && _nameSuffixes.contains(w.single)))
          .length >
      1;
}

/// The set caller's words from the given name on: a leading dotted title or
/// initial ("Dr. Michael Smith", "J. Michael Smith") is skipped provided two
/// words other than trailing name suffixes still remain, so an initial never
/// leaves just a surname ("J. Smith, Jr."). The suffix itself is kept, so a
/// slot naming "Michael Smith Jr" still matches "Michael Smith, Jr.".
List<String> _setCallerWords(String caller) {
  final raw = caller
      .replaceAll(',', ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  var named = raw.length;
  while (named > 1 &&
      _nameSuffixes.contains(
        raw[named - 1].toLowerCase().replaceAll('.', ''),
      )) {
    named--;
  }
  var first = 0;
  while (named - first > 2 && raw[first].endsWith('.')) {
    first++;
  }
  return _words(raw.skip(first).join(' '));
}

/// [name] lower-cased and split on whitespace and commas, with `.` dropped.
List<String> _words(String name) => [
  for (final word in name.toLowerCase().split(RegExp(r'[\s,]+')))
    if (word.replaceAll('.', '') case final w when w.isNotEmpty) w,
];

/// Whether [words] begins with [start].
bool _startsWith(List<String> words, List<String> start) {
  if (start.length > words.length) return false;
  for (var i = 0; i < start.length; i++) {
    if (words[i] != start[i]) return false;
  }
  return true;
}

(DateTime?, ImportIssue?) _parseEventDate(String? raw, String recordId) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return (null, null);

  // ISO-ish first (what DateTime.tryParse handles).
  final iso = DateTime.tryParse(value);
  if (iso != null) return (DateTime.utc(iso.year, iso.month, iso.day), null);

  // Common US FileMaker shape: M/D/YYYY or M-D-YYYY.
  final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(value);
  if (m != null) {
    var year = int.parse(m.group(3)!);
    if (year < 100) year += year < 70 ? 2000 : 1900;
    final month = int.parse(m.group(1)!);
    final day = int.parse(m.group(2)!);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      final date = DateTime.utc(year, month, day);
      // DateTime silently normalises impossible dates (e.g. 2/31 → Mar 2), so
      // reject anything that didn't round-trip rather than storing a wrong day.
      if (date.year == year && date.month == month && date.day == day) {
        return (date, null);
      }
    }
  }

  return (
    null,
    ImportIssue(
      severity: ImportIssueSeverity.warning,
      code: 'cc_program_unparsed_date',
      message:
          'Could not parse the event date "$value" for set #$recordId; left '
          'unset.',
    ),
  );
}

/// Sanitizes a single-line imported field (title, venue, band, caller,
/// dancer level, guest caller), stripping control, bidi-override and
/// invisible/format characters plus any embedded tab/newline/CR (issue
/// #444/#611, mirroring `callers_companion_mapping.dart`'s `_sanitizeLine`).
/// Returns null for null/blank/all-stripped input.
String? _cleanLine(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final clean = sanitizeImportedText(trimmed, allowLineBreaks: false).trim();
  return clean.isEmpty ? null : clean;
}

/// Sanitizes a multi-line prose imported field (program notes, break text),
/// stripping control/bidi/format spoofing characters while preserving
/// legitimate newlines (issue #444/#611, mirroring
/// `callers_companion_mapping.dart`'s `_joinNotes`). Returns null for
/// null/blank/all-stripped input.
String? _cleanNote(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final clean = sanitizeImportedText(trimmed).trim();
  return clean.isEmpty ? null : clean;
}
