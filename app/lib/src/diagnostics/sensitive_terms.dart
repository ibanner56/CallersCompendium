import 'package:compendium_core/compendium_core.dart';

/// Collects the user-content strings that the *default* (scrubbed) diagnostics
/// export must redact (issue #458): dance / program / figure titles, notes,
/// walkthroughs, free-text figure params, link labels, custom-field values and
/// definitions, program notes, slot text and guest callers, band/caller/venue
/// labels, tag names, and every person / place / source field — venue names,
/// addresses and contacts, choreographer names and locations, published-source
/// authors — plus the serialized records the Device Sync review and deletion
/// queues hold.
///
/// Gathered on demand from the local database at export time — export is a
/// deliberate, infrequent user action, so a full read is acceptable — and fed
/// to a [CrashRedactor].
///
/// **Why the person / place / source columns are here.** The pinned `sqlite3`
/// renders every bound parameter into a failed statement's exception text
/// (`Causing statement: …, parameters: …`) and drift prints that verbatim, so
/// a constraint failure on a `venues` or `choreographers` write puts the whole
/// row — a contact's name, a street address, a locality — into the crash
/// record's `errorMessage`. Only phone numbers and emails are caught by the
/// always-on patterns; names and addresses are caught only if they are here.
/// `test/privacy/crash_log_term_sources_test.dart` reconciles this list
/// against the privacy registry so a new third-party or personal text column
/// cannot ship without a term source. Soft-deleted rows are read too
/// (`includeDeleted`, `listAllWithDeleted`): a tombstoned row is still bound
/// by the purge that removes it.
///
/// **Fail-closed (OWASP).** This deliberately does NOT swallow read errors. If
/// any source can't be read, the returned future *fails* so the caller aborts
/// the scrubbed export rather than emitting one that is silently missing terms
/// — which would leak exactly the content it was meant to strip, while still
/// being labelled "scrubbed". See `_export` in the diagnostics settings section
/// (`screens/settings/diagnostics_section.dart`).
///
/// Empty and very short strings are dropped: the redactor already ignores terms
/// below its minimum length, and blank titles/notes would otherwise be useless
/// (and potentially over-broad) match terms.
Future<Set<String>> collectSensitiveTerms(
  CompendiumRepositories repositories,
) async {
  final terms = <String>{};

  void add(Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.length >= 3) terms.add(text);
  }

  void addFigureContent(Figure figure) {
    add(figure.note);
    // A custom (free-text) figure keeps the caller's verbatim text in
    // params['text'] (taxonomy `customMove`), not in `note`.
    add(figure.params['text']);
    for (final child in figure.subFigures) {
      addFigureContent(child);
    }
  }

  for (final dance in await repositories.dances.listAll(includeDeleted: true)) {
    add(dance.title);
    add(dance.hook);
    add(dance.callingNotes);
    add(dance.walkthrough);
    for (final link in dance.links) {
      add(link.label);
    }
    switch (dance.tunesSource) {
      case DecodedTunes(:final tunes):
        for (final tune in tunes) {
          add(tune);
        }
      // Same rule as the figures case below: an undecodable tune list is still
      // the user's content, and treating it as absent would drop those terms
      // from the redaction set and let them through into a diagnostic report.
      // Adding the raw text over-redacts rather than under-redacts.
      case UnreadableTunes(:final storedJson):
        add(storedJson);
    }
    switch (dance.figuresSource) {
      case DecodedFigures(:final figures):
        for (final figure in figures) {
          addFigureContent(figure);
        }
      // An undecodable transcription is still the user's content: the stored
      // text holds move names, notes and free text exactly as typed. Treating
      // it as "no figures" here would quietly drop those terms from the
      // redaction set and let them through into a diagnostic report — the one
      // place where "we could not read it" must NOT mean "it is not there".
      case UnreadableFigures(:final storedJson):
        add(storedJson);
    }
    for (final field in dance.customFields) {
      add(field.value);
    }
  }

  for (final program in await repositories.programs.listAll(
    includeDeleted: true,
  )) {
    add(program.title);
    add(program.notes);
    add(program.band);
    add(program.caller);
    add(program.venue);
    add(program.dancerLevel);
    for (final slot in program.slots) {
      add(slot.text);
      add(slot.guestCaller);
    }
  }

  for (final tag in await repositories.tags.listAll()) {
    add(tag.name);
  }

  for (final def in await repositories.customFieldDefs.listAll()) {
    add(def.label);
    for (final choice in def.choices ?? const <String>[]) {
      add(choice);
    }
  }

  // People, places and sources. Every column the registry classifies as
  // third-party or personal data is here, plus the identity fields a user
  // would recognise as their own content (a hall's name, a book's title).
  for (final venue in await repositories.venues.listAll(includeDeleted: true)) {
    add(venue.name);
    add(venue.sponsor);
    add(venue.address1);
    add(venue.address2);
    add(venue.city);
    add(venue.stateProv);
    add(venue.country);
    add(venue.postalCode);
    add(venue.plus4);
    add(venue.notes);
    add(venue.contact1Name);
    add(venue.contact1Phone);
    add(venue.contact1Email);
    add(venue.contact2Name);
    add(venue.contact2Phone);
    add(venue.contact2Email);
  }

  for (final choreographer in await repositories.choreographers.listAll(
    includeDeleted: true,
  )) {
    add(choreographer.name);
    add(choreographer.website);
    add(choreographer.notes);
    add(choreographer.email);
    add(choreographer.location);
  }

  for (final entry
      in await repositories.publishedSources.listAllWithDeleted()) {
    add(entry.source.title);
    add(entry.source.author);
    add(entry.source.notes);
  }

  // Device Sync holds whole serialized records while a conflict awaits review
  // or a tombstone awaits retransmission. Their content is a peer's copy of
  // the same person / place / dance fields, not yet (or no longer) in the
  // entity tables above, so nothing else here would cover it. Added verbatim
  // — the same rule as an undecodable figures list: the stored text is the
  // user's content whether or not it can be read as structure.
  for (final row in await repositories.syncLocal.listReviewQueue()) {
    add(row.candidateBlob);
  }
  for (final row in await repositories.syncLocal.listPendingDeletions()) {
    add(row.tombstoneBlob);
  }

  return terms;
}
