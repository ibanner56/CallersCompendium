import 'package:compendium_core/compendium_core.dart';

import 'online_search.dart';
import 'program_import_online_resolver.dart';

/// How one ContraDB program activity resolved into a program slot (epic #291,
/// sub-issue #314). Drives the preview's per-slot label and the commit summary.
enum ContraDbActivityResolution {
  /// A linked dance imported (or de-duplicated) directly from ContraDB by its
  /// `/dances/{id}` identity — the strongest, exact result.
  linkedContraDb,

  /// The ContraDB dance couldn't be scraped (e.g. unpublished/removed), so the
  /// title was resolved via The Caller's Box under the #313 confident
  /// unique-exact-title rule.
  linkedCallersBox,

  /// Neither online path produced a confident dance, so the activity is kept as
  /// a free-text note slot — the safe floor (#312). Also every non-dance
  /// activity (announcement / waltz / break) from the program.
  note,
}

/// One resolved ContraDB program activity, ready to become an ordered
/// [ProgramSlot]. Carries the [danceId] to link (null for a note), the slot
/// [text] (a linked dance's attached note, which may be null; or the note
/// body), the display [title], and the [resolution] that produced it.
class ResolvedContraDbActivity {
  const ResolvedContraDbActivity._({
    required this.resolution,
    this.danceId,
    this.title,
    this.text,
  });

  /// A slot linked to [danceId] (from ContraDB identity or the Caller's Box
  /// fallback). [text] is the dance's attached program note verbatim, or null.
  factory ResolvedContraDbActivity.linked({
    required ContraDbActivityResolution resolution,
    required String danceId,
    required String title,
    String? text,
  }) {
    assert(
      resolution != ContraDbActivityResolution.note,
      'linked() requires a linked resolution',
    );
    return ResolvedContraDbActivity._(
      resolution: resolution,
      danceId: danceId,
      title: title,
      text: (text != null && text.trim().isNotEmpty) ? text.trim() : null,
    );
  }

  /// A free-text note slot carrying [text] verbatim (a program announcement, or
  /// the safe floor for a dance that couldn't be resolved).
  factory ResolvedContraDbActivity.note(String text) =>
      ResolvedContraDbActivity._(
        resolution: ContraDbActivityResolution.note,
        text: text.trim(),
      );

  final ContraDbActivityResolution resolution;

  /// The linked dance id, or null for a note slot.
  final String? danceId;

  /// The linked dance's title (for preview display); null for a note.
  final String? title;

  /// The slot's free text: a linked dance's attached note (nullable) or a note
  /// slot's body.
  final String? text;

  /// Whether this activity links a dance (vs. a free-text note).
  bool get isLinked => danceId != null;
}

/// Resolves a parsed ContraDB [program] into ordered [ResolvedContraDbActivity]s
/// using the shipped import seams, preserving source order exactly.
///
/// Per activity:
/// - **Note activity** → a verbatim note slot; it is never searched online
///   (fidelity: announcements/waltz/break are not dances).
/// - **Linked dance** → resolved **identity-first**: imported via [contraDb]
///   ([OnlineSearchService.loadPreview] + [OnlineSearchService.import]) using the
///   known `/dances/{id}` id, so the shipped provenance/dedupe guards link to an
///   already-imported copy instead of duplicating. A same-titled *local* dance is
///   never assumed to be this dance — resolution keys on the ContraDB id, not a
///   fuzzy title. If the ContraDB scrape fails (unpublished/removed), it falls
///   back to [callersBox] by title under the #313 confident unique-exact rule;
///   if that also fails, the verbatim title (plus any attached note) is kept as a
///   note slot — nothing is invented or dropped.
///
/// Both services are injected [OnlineSearchService]s, so tests drive the whole
/// resolution with seam-backed fetchers and never touch the network. One fetch
/// per dance for the ContraDB identity import (+ one search/import for a Caller's
/// Box fallback); no crawling.
Future<List<ResolvedContraDbActivity>> resolveContraDbProgram(
  ContraDbProgram program, {
  required OnlineSearchService contraDb,
  required OnlineSearchService callersBox,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final resolved = <ResolvedContraDbActivity>[];
  for (final activity in program.activities) {
    if (!activity.isDance) {
      resolved.add(ResolvedContraDbActivity.note(activity.text ?? ''));
      continue;
    }
    resolved.add(
      await _resolveDance(
        activity,
        contraDb: contraDb,
        callersBox: callersBox,
        repos: repos,
        now: now,
      ),
    );
  }
  return resolved;
}

Future<ResolvedContraDbActivity> _resolveDance(
  ContraDbProgramActivity activity, {
  required OnlineSearchService contraDb,
  required OnlineSearchService callersBox,
  required CompendiumRepositories repos,
  DateTime? now,
}) async {
  final title = activity.title ?? '';
  final attachedNote = activity.text;

  // (a) IDENTITY-first: import the specific ContraDB dance by its id. Dedupe
  // guards return the existing dance id on a re-import, so this is idempotent.
  try {
    final row = OnlineSearchResultRow(
      source: OnlineSource.contraDb,
      id: activity.danceId!,
      name: title,
      author: '',
      formation: '',
    );
    final preview = await contraDb.loadPreview(repos, row, now: now);
    final result = await contraDb.import(
      repos,
      preview.plan,
      now: now,
      // Program import is non-interactive — no per-dance prompt (#797).
      // Pass duplicate() explicitly so the confident-match detection block
      // in the service is bypassed and pre-#797 behaviour is preserved by
      // construction rather than by assumption.
      ambiguousResolution: DedupeResolution.duplicate(),
    );
    final danceId = result.danceId;
    if (danceId != null) {
      return ResolvedContraDbActivity.linked(
        resolution: ContraDbActivityResolution.linkedContraDb,
        danceId: danceId,
        title: title,
        text: attachedNote,
      );
    }
  } on Exception catch (_) {
    // diagnostics: silent — scrape/import failure (e.g. an unpublished dance)
    // degrades to the Caller's Box fallback and ultimately a note slot;
    // surfaced via ResolvedContraDbActivity to the program import screen.
  }

  // (b) Caller's Box fallback by title (#313 confident unique-exact rule).
  if (title.isNotEmpty) {
    final tcbId = await resolveConfidentOnlineDanceId(
      title,
      service: callersBox,
      repos: repos,
      now: now,
    );
    if (tcbId != null) {
      return ResolvedContraDbActivity.linked(
        resolution: ContraDbActivityResolution.linkedCallersBox,
        danceId: tcbId,
        title: title,
        text: attachedNote,
      );
    }
  }

  // (c) Verbatim note floor: keep the title and any attached note, nothing lost.
  return ResolvedContraDbActivity.note(_noteFloor(title, attachedNote));
}

/// Builds the free-text floor for an unresolved dance: its verbatim title, plus
/// any attached note (joined so both real strings are preserved).
String _noteFloor(String title, String? note) {
  final parts = <String>[
    if (title.isNotEmpty) title,
    if (note != null && note.trim().isNotEmpty) note.trim(),
  ];
  return parts.join(' — ');
}

/// Builds ordered [ProgramSlot]s from resolved [activities], numbering positions
/// `0..n-1` in source order. Linked activities produce a dance slot (carrying any
/// attached note in [ProgramSlot.text]); note activities produce a free-text
/// slot. [newSlotId] mints a fresh id per slot.
///
/// Empty resolved activities (no dance and no text) are skipped so a slot never
/// violates [ProgramSlot]'s "danceId, text, or both" invariant; positions are
/// re-numbered over the kept slots so ordering stays contiguous.
List<ProgramSlot> buildContraDbProgramSlots(
  List<ResolvedContraDbActivity> activities, {
  required String Function() newSlotId,
}) {
  final slots = <ProgramSlot>[];
  var position = 0;
  for (final activity in activities) {
    final danceId = activity.danceId;
    final text = (activity.text != null && activity.text!.isNotEmpty)
        ? activity.text
        : null;
    if (danceId == null && text == null) continue;
    slots.add(
      ProgramSlot(
        id: newSlotId(),
        position: position,
        danceId: danceId,
        text: text,
      ),
    );
    position++;
  }
  return slots;
}
