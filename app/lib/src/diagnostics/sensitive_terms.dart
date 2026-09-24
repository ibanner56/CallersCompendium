import 'package:compendium_core/compendium_core.dart';

/// Collects the user-content strings that the *default* (scrubbed) diagnostics
/// export must redact (issue #458): dance / program / figure titles, notes,
/// free-text figure params, custom-field values and definitions, program notes,
/// slot text and guest callers, band/caller/venue labels, and tag names.
///
/// Gathered on demand from the local database at export time — export is a
/// deliberate, infrequent user action, so a full read is acceptable — and fed
/// to a [CrashRedactor].
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

  return terms;
}
