import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../diagnostics/error_log.dart';

/// One Caller's Companion term as the import preview offers it (#1023,
/// maintainer decision 7), as the user may have edited it: what is added to
/// the Glossary as a term.
@immutable
class CcTermDraft {
  const CcTermDraft({
    required this.name,
    required this.definition,
    required this.description,
    this.notes,
    this.source,
  });

  /// The draft a CC term starts as (maintainer, 2026-10-16): its description
  /// is its definition, for the user to change, since CC has no description;
  /// its notes and source citation come as they are.
  factory CcTermDraft.of(CcTerm term) => CcTermDraft(
    name: term.name,
    definition: term.definition ?? '',
    description: term.definition ?? '',
    notes: term.notes,
    source: term.source,
  );

  final String name;
  final String definition;
  final String description;
  final String? notes;
  final String? source;

  /// Whether it has every field the importer requires: a name, a definition
  /// and a description. A glossary entry itself allows an empty description;
  /// this is the importer's own rule, which fills it from the definition.
  bool get complete =>
      name.trim().isNotEmpty &&
      definition.trim().isNotEmpty &&
      description.trim().isNotEmpty;

  CcTermDraft copyWith({
    String? name,
    String? definition,
    String? description,
  }) => CcTermDraft(
    name: name ?? this.name,
    definition: definition ?? this.definition,
    description: description ?? this.description,
    notes: notes,
    source: source,
  );
}

/// What [applyCcTermImport] did: the terms it added, by id, and how many it
/// could not add (refused by the Glossary's bounds or budget, or a failed
/// write). [undo] removes what it added.
class AppliedCcTermImport {
  AppliedCcTermImport({
    required this.addedIds,
    required this.failed,
    required this.undo,
  });

  final List<String> addedIds;
  final int failed;
  final Future<void> Function() undo;
}

/// Adds each of [drafts] to the user's glossary as a term (#1023, maintainer
/// decision 7), its text stored as the editor stores it
/// ([canonicalizeGlossaryText] for [dialect]), its source citation on its
/// payload ([glossaryTermPayload]).
///
/// Never throws: a term the glossary refuses, or whose write fails, is
/// counted in [AppliedCcTermImport.failed] and the rest are still added. The
/// undo erases what was added (`delete(permanent: true)`, so nothing is left
/// for sync to publish, and an entry a publication has already named is
/// tombstoned instead).
Future<AppliedCcTermImport> applyCcTermImport(
  UserGlossaryRepository glossary,
  List<CcTermDraft> drafts, {
  required Dialect dialect,
  required String Function() newId,
  required DateTime now,
}) async {
  String stored(String text) => canonicalizeGlossaryText(text.trim(), dialect);
  final added = <String>[];
  var failed = 0;
  for (final draft in drafts) {
    final notes = draft.notes?.trim();
    final entry = UserGlossaryEntry(
      id: newId(),
      kindName: UserGlossaryEntryKind.term.name,
      name: stored(draft.name),
      definition: stored(draft.definition),
      description: stored(draft.description),
      notes: notes == null || notes.isEmpty ? null : stored(notes),
      payload: glossaryTermPayload(
        defaultGlossaryEntryForm,
        source: draft.source,
      ),
      createdAt: now,
    );
    try {
      await glossary.upsert(entry, at: now);
      added.add(entry.id);
    } on UserGlossaryEntryInvalid {
      // diagnostics: silent — counted and reported to the user: a term over
      // the glossary's bounds or budget is theirs to shorten or make room for.
      failed++;
    } on Object catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'applyCcTermImport');
      failed++;
    }
  }
  return AppliedCcTermImport(
    addedIds: added,
    failed: failed,
    undo: () async {
      for (final id in added) {
        try {
          await glossary.delete(id, permanent: true);
        } on Object catch (e, stackTrace) {
          logCaughtError(e, stackTrace, source: 'applyCcTermImport.undo');
        }
      }
    },
  );
}
