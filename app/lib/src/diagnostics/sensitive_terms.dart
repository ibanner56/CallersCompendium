import 'package:compendium_core/compendium_core.dart';

import 'dart:convert';

import '../data/calendar_import_settings.dart'
    show kCalendarFeedUrlKey, kCalendarImportTitleFilterKey;
import '../data/display_defaults.dart'
    show
        isProgramTemplateBreakText,
        kDefaultProgramBandKey,
        kDefaultProgramCallerKey,
        kDefaultStartingProgramKey,
        tryDecodeStartingProgramTemplate;
import '../data/program_templates.dart'
    show kProgramTemplateKeyPrefix, tryDecodeProgramTemplate;
import '../data/settings_keys.dart' show kSyncIdKey;

/// Collects the user-content strings that the *default* (scrubbed) diagnostics
/// export must redact (issue #458): dance / program / figure titles, a dance's
/// other titles, formation detail, meter, key, Barnes reference and square
/// details, notes, walkthroughs, free-text figure params, link labels and
/// addresses, custom-field values and definitions, program notes, slot text
/// and guest callers, band/caller/venue labels, tag names, difficulty-level
/// labels, event-rule nicknames, and every person / place / source field —
/// venue names, websites, schedule/price text, addresses and contacts,
/// choreographer names and locations, published-source authors and urls —
/// plus the serialized records the Device Sync review and deletion queues
/// hold, and the caller's words kept in settings: saved searches, program
/// templates, the calendar address and its title filter.
///
/// Since the scrubbed export withholds `errorMessage` except for the typed
/// types in `CrashLogRecord.messageSafeErrorTypes` (whose message still passes
/// through the redactor), these terms are defence in depth for the stack
/// text, those messages and any other free text passed through the redactor; the
/// reasoning below about exception text describes why the list exists and why
/// it could never be complete on its own.
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
/// **Why fields the registry classifies non-personal are also here.** The
/// scrubbed export's UI label promises "user content … removed", a promise
/// the registry's `thirdParty`/personal-data axis does not itself scope to: a
/// hall's schedule text or a published source's URL is exactly as capable of
/// reaching a failed statement's echoed parameters as a dance title is, and
/// the same over-broad-crash-log risk applies. Every free-text column is
/// added on that basis, whatever its registry subject: the term-source test
/// requires a source for every TEXT column that is not a key, an enum, a code
/// or a JSON blob (`_isFreeTextColumn` there), so a new one cannot be
/// forgotten. A JSON-blob column (`figures_json`, `tunes_json`) is
/// deliberately not in that set: its content is already covered above,
/// through the decoded `Figure`/tune records, not as a raw column read. The
/// settings value column is such a blob too, so the settings that hold the
/// caller's own words are read by key below, and that test names them.
///
/// **Fail-closed (OWASP).** This deliberately does NOT swallow read errors. If
/// any source can't be read, the returned future *fails* so the caller aborts
/// the scrubbed export rather than emitting one that is silently missing terms
/// — which would leak exactly the content it was meant to strip, while still
/// being labelled "scrubbed". See `_export` in the diagnostics settings section
/// (`screens/settings/diagnostics_section.dart`).
///
/// Empty and single-character strings are dropped: the redactor already
/// ignores terms below its minimum length, and a blank or one-character
/// title/note would otherwise be a useless (and potentially over-broad) match
/// term. Two-character values — a US state code, a country code, a short
/// surname — are kept: [CrashRedactor] matches a term that short only on a
/// word boundary, so it cannot blank out an unrelated substring the way an
/// unbounded two-character match would.
Future<Set<String>> collectSensitiveTerms(
  CompendiumRepositories repositories,
) async {
  final terms = <String>{};

  void add(Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.length >= 2) terms.add(text);
  }

  void addFigureContent(Figure figure) {
    add(figure.note);
    // A custom (free-text) figure keeps its text in params['text'] (taxonomy
    // `customMove`), not in `note`. This is the stored form: the editor saves
    // it through the dialect chokepoint, so role words are canonical here.
    // The text as typed may still differ (for example in an autosave draft).
    add(figure.params['text']);
    // A use of a figure of your own (#1023) carries its arguments, which the
    // stored line may not show (a parameter the wording leaves out).
    if (figure.params[userFigureArgsKey]
        case final Map<Object?, Object?> args) {
      for (final value in args.values) {
        if (value is String) add(value);
      }
    }
    // A group's title is the user's own words, like a note.
    add(figure.containerTitle);
    for (final child in figure.subFigures) {
      addFigureContent(child);
    }
  }

  for (final dance in await repositories.dances.listAll(includeDeleted: true)) {
    add(dance.title);
    add(dance.formation.detail);
    add(dance.hook);
    add(dance.callingNotes);
    add(dance.walkthrough);
    add(dance.meter);
    add(dance.musicalKey);
    // Each other title, and the column's one-per-line form, which is what a
    // failed statement echoes.
    for (final title in dance.alternateTitles) {
      add(title);
    }
    add(alternateTitlesColumnText(dance.alternateTitles));
    add(dance.barnesReference);
    add(dance.repeatOrderText);
    add(dance.newPartnerText);
    for (final link in dance.links) {
      add(link.label);
      add(link.url);
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
    add(program.dialectName);
    // A digest of a third party's calendar event id (#2352): pseudonymous,
    // so a failed statement echoing it is redacted like the rest of the row.
    add(program.calendarEventKey);
    // Which calendar it came from (pre-release audit finding E1-01): personal
    // data about the caller, linkable to their calendar's address.
    add(program.calendarFeedDigest);
    // Pay is private bookkeeping. A failed statement echoes the stored minor
    // units, while the editor shows the decimal form: redact both.
    final pay = program.payMinorUnits;
    final currency = program.payCurrency;
    if (pay != null && currency != null) {
      add(currency);
      add('$pay');
      add(formatPayMinorUnits(pay, currency));
    }
    for (final slot in program.slots) {
      // The break token is the app's own word, not the caller's: as a term
      // it would blank "break" all through the stack text.
      if (!isProgramTemplateBreakText(slot.text)) add(slot.text);
      add(slot.guestCaller);
    }
  }

  for (final tag in await repositories.tags.listAll()) {
    add(tag.name);
  }

  // An event rule's nickname (#2340): a name the caller types.
  for (final rule in await repositories.eventRules.listAll(
    includeDeleted: true,
  )) {
    add(rule.nickname);
  }

  for (final def in await repositories.customFieldDefs.listAll()) {
    add(def.label);
    for (final choice in def.choices ?? const <String>[]) {
      add(choice);
    }
  }

  for (final entry
      in await repositories.difficultyLevels.listAllWithDeleted()) {
    add(entry.level.label);
  }

  // The user's own glossary (#709): their words defining and annotating
  // figures. Stored canonically, as figure notes are.
  for (final entry in await repositories.userGlossary.listAll(
    includeDeleted: true,
  )) {
    add(entry.name);
    add(entry.definition);
    add(entry.description);
    add(entry.notes);
    for (final keyword in entry.keywords) {
      add(keyword);
    }
    // A compound's payload holds more of the user's words: the parameter
    // names they chose, and each template figure's note. Read leniently, as
    // stored: an entry whose payload no longer decodes is still kept.
    if (entry.payload case final Map<Object?, Object?> payload) {
      if (payload['params'] case final List<Object?> params) {
        for (final param in params) {
          if (param is! Map) continue;
          add(param['key']);
          // A figure of your own's parameters (#1023) also carry a flag's
          // label, a default, and each choice's label.
          if (param['label'] case final String label) add(label);
          if (param['default'] case final String value) add(value);
          if (param['choices'] case final List<Object?> choices) {
            for (final choice in choices) {
              if (choice case {'label': final String label}) add(label);
            }
          }
        }
      }
      // ...and its wording template.
      if (payload['template'] case final String template) add(template);
      // A term's source citation (#1023), which can name a published author.
      add(glossaryTermSource(payload));
      if (payload['figures'] case final List<Object?> figures) {
        for (final raw in figures) {
          if (raw is! Map) continue;
          try {
            addFigureContent(figureFromJson(raw.cast<String, Object?>()));
          } on Object {
            // diagnostics: silent — a template that no longer decodes has no figure content to read; the entry's own text is still collected.
          }
        }
      }
    }
  }
  for (final note in await repositories.figureNotes.listAll(
    includeDeleted: true,
  )) {
    add(note.notes);
  }

  // People, places and sources. Every column the registry classifies as
  // third-party or personal data is here, plus every other free-text scalar
  // column on these entities — identity fields a user would recognise as
  // their own content (a hall's name, a book's title) and non-personal
  // freeform fields (a venue's schedule, price or website) that can equally
  // reach a crash log through an echoed write.
  for (final venue in await repositories.venues.listAll(includeDeleted: true)) {
    add(venue.name);
    add(venue.website);
    add(venue.sponsor);
    add(venue.eventName);
    add(venue.time);
    add(venue.genericSchedule);
    add(venue.price);
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
    add(entry.source.url);
    add(entry.source.notes);
  }

  // Device Sync holds whole serialized records while a conflict awaits review
  // or a tombstone awaits retransmission, and the parts of records a newer
  // version of the app added, kept to share back. Their content is a peer's copy of
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
  for (final row in await repositories.syncLocal.listRetainedSyncFields()) {
    add(row.payload);
  }

  // The caller's own words kept in settings values (pre-release audit finding
  // PRIV-07): a saved search's name and search text (#2325), a program
  // template's name and its slots' notes and rule labels (#2337, #2338), and
  // the calendar import's title filter. Read leniently: a value that does not
  // decode is still the caller's, so it goes in as stored, as an undecodable
  // figures list does.
  for (final key in await repositories.settings.keysWithPrefix(
    savedSearchKeyPrefix,
  )) {
    final value = await repositories.settings.get(key);
    if (value is Map) {
      add(value['name']);
      add(value['text']);
      // Words typed into the Filters panel that the search keeps: a tune
      // name, and a custom text field's value. Not every string in the
      // value: most are enum names (a sort, a scope) that are not the
      // caller's words and would blank common words in the stack text.
      if (value['facets'] case final Map<Object?, Object?> facets) {
        if (facets['tunes'] case final List<Object?> tunes) {
          tunes.forEach(add);
        }
        if (facets['textValues'] case final Map<Object?, Object?> values) {
          for (final filter in values.values) {
            if (filter is Map) add(filter['value']);
          }
        }
      }
    } else {
      add(value is String ? value : jsonEncode(value));
    }
  }
  for (final key in await repositories.settings.keysWithPrefix(
    kProgramTemplateKeyPrefix,
  )) {
    final value = await repositories.settings.get(key);
    final template = tryDecodeProgramTemplate(
      key.substring(kProgramTemplateKeyPrefix.length),
      value,
    );
    if (template == null) {
      add(value is String ? value : jsonEncode(value));
      continue;
    }
    add(template.name);
    for (final entry in template.entries) {
      if (!isProgramTemplateBreakText(entry.text)) add(entry.text);
    }
  }
  // The legacy Starting program, shown as the first template until the
  // caller first changes their templates, and kept after that.
  final startingProgram = await repositories.settings.get(
    kDefaultStartingProgramKey,
  );
  if (startingProgram != null) {
    final entries = tryDecodeStartingProgramTemplate(startingProgram);
    if (entries == null) {
      add(
        startingProgram is String
            ? startingProgram
            : jsonEncode(startingProgram),
      );
    } else {
      for (final entry in entries) {
        if (!isProgramTemplateBreakText(entry.text)) add(entry.text);
      }
    }
  }
  // The title filter is often one common word, and a term of three or more
  // characters is matched anywhere, so "dance" would blank much of the stack
  // text. Kept all the same, as a tag name is: the scrubbed export promises
  // the caller's words are gone, and a report short on detail is the safer
  // failure.
  add(await repositories.settings.get(kCalendarImportTitleFilterKey));
  // The names a new program starts with: the caller's own, and a band's.
  add(await repositories.settings.get(kDefaultProgramCallerKey));
  add(await repositories.settings.get(kDefaultProgramBandKey));
  // The Device Sync ID, which the registry classifies as personal data: a
  // failed sync request can name it.
  add(await repositories.settings.get(kSyncIdKey));

  // The calendar feed address (#2352). A private calendar's address embeds a
  // secret token, so the whole address goes in, and so does its scheme-less
  // form: a fetch error can name the `https://` URL a `webcal://` one was
  // rewritten to.
  final feedUrl = await repositories.settings.get(kCalendarFeedUrlKey);
  if (feedUrl is String) {
    add(feedUrl);
    final schemeEnd = feedUrl.indexOf('://');
    if (schemeEnd >= 0) add(feedUrl.substring(schemeEnd + 3));
  }

  return terms;
}
