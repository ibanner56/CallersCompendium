import '../model/choreographer.dart';
import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/dance_link.dart';
import '../model/formation.dart';
import '../model/program.dart';
import '../model/provenance.dart';
import '../model/published_source.dart';
import '../model/source_citation.dart';
import '../model/tag.dart';
import '../model/venue.dart';
import 'compendium_archive.dart';
import 'figure_codec.dart';

/// Builds the archive-shaped body for a choreographer.
Map<String, Object?> archiveChoreographerToJson(
  Choreographer c, {
  bool includeOptionalFields = false,
}) => {
  'id': c.id,
  'name': c.name,
  if (includeOptionalFields || c.website != null) 'website': c.website,
  if (includeOptionalFields || c.notes != null) 'notes': c.notes,
  if (includeOptionalFields || c.email != null) 'email': c.email,
  if (includeOptionalFields || c.location != null) 'location': c.location,
  'deceased': c.deceased,
};

/// Builds the archive-shaped body for a published source.
Map<String, Object?> archivePublishedSourceToJson(
  PublishedSource s, {
  bool includeOptionalFields = false,
}) => {
  'id': s.id,
  'title': s.title,
  if (includeOptionalFields || s.author != null) 'author': s.author,
  if (includeOptionalFields || s.year != null) 'year': s.year,
  if (includeOptionalFields || s.url != null) 'url': s.url,
  if (includeOptionalFields || s.notes != null) 'notes': s.notes,
};

/// Builds the archive-shaped body for a tag.
Map<String, Object?> archiveTagToJson(
  Tag t, {
  bool includeOptionalFields = false,
}) => {
  'id': t.id,
  'name': t.name,
  if (includeOptionalFields || t.color != null) 'color': t.color,
};

/// Builds the archive-shaped body for a custom-field definition.
Map<String, Object?> archiveCustomFieldDefToJson(
  CustomFieldDef f, {
  required bool includeShareable,
  bool includeOptionalFields = false,
}) => {
  'id': f.id,
  'key': f.key,
  'label': f.label,
  'type': f.type.name,
  if (includeOptionalFields || f.choices != null) 'choices': f.choices,
  'showInList': f.showInList,
  'searchable': f.searchable,
  if (includeShareable) 'shareable': f.shareable,
};

/// Builds the archive-shaped body for a dance.
Map<String, Object?> archiveDanceToJson(
  Dance d,
  Set<String> excludedFieldIds, {
  bool includeOptionalFields = false,
}) => {
  'id': d.id,
  'title': d.title,
  'authorIds': d.authorIds,
  'form': d.form.name,
  'formation': archiveFormationToJson(
    d.formation,
    includeOptionalFields: includeOptionalFields,
  ),
  'progression': d.progression.name,
  'phraseStructure': d.phraseStructure.raw,
  'figures': [for (final f in d.figures) figureToJson(f)],
  'hook': d.hook,
  'callingNotes': d.callingNotes,
  'walkthrough': d.walkthrough,
  'status': d.status.name,
  if (includeOptionalFields || d.level != null) 'level': d.level?.name,
  'mixedLevel': d.mixedLevel,
  'mixer': d.mixer,
  if (includeOptionalFields || d.rating != null) 'rating': d.rating,
  'tunes': d.tunes,
  'customFields': [
    for (final v in d.customFields)
      if (!excludedFieldIds.contains(v.fieldId))
        archiveCustomFieldValueToJson(v, danceId: d.id),
  ],
  'tagIds': d.tagIds,
  'links': [
    for (final l in d.links)
      archiveDanceLinkToJson(l, includeOptionalFields: includeOptionalFields),
  ],
  'sourceCitations': [
    for (final s in d.sourceCitations)
      archiveSourceCitationToJson(
        s,
        includeOptionalFields: includeOptionalFields,
      ),
  ],
  if (includeOptionalFields || d.provenance != null)
    'provenance': d.provenance == null
        ? null
        : archiveProvenanceToJson(
            d.provenance!,
            includeOptionalFields: includeOptionalFields,
          ),
  if (includeOptionalFields || d.composedOn != null)
    'composedOn': d.composedOn?.serialize(),
  if (includeOptionalFields || d.revisedOn != null)
    'revisedOn': d.revisedOn?.serialize(),
  'createdAt': archiveIso(d.createdAt),
  'updatedAt': archiveIso(d.updatedAt),
  if (includeOptionalFields || d.deletedAt != null)
    'deletedAt': d.deletedAt == null ? null : archiveIso(d.deletedAt!),
};

Map<String, Object?> archiveFormationToJson(
  Formation f, {
  bool includeOptionalFields = false,
}) => {
  'shape': f.shape.name,
  if (includeOptionalFields || f.detail != null) 'detail': f.detail,
};

Map<String, Object?> archiveCustomFieldValueToJson(
  CustomFieldValue v, {
  required String danceId,
}) {
  if (v.value is num && !isFiniteCustomFieldNumber(v.value)) {
    throw ArchiveEncodingException(danceId: danceId, fieldId: v.fieldId);
  }
  return {'fieldId': v.fieldId, 'value': v.value};
}

Map<String, Object?> archiveDanceLinkToJson(
  DanceLink l, {
  bool includeOptionalFields = false,
}) => {
  'id': l.id,
  'kind': l.kind.name,
  if (includeOptionalFields || l.url != null) 'url': l.url,
  if (includeOptionalFields || l.targetDanceId != null)
    'targetDanceId': l.targetDanceId,
  if (includeOptionalFields || l.label != null) 'label': l.label,
  if (includeOptionalFields || l.transitive) 'transitive': l.transitive,
};

Map<String, Object?> archiveSourceCitationToJson(
  SourceCitation s, {
  bool includeOptionalFields = false,
}) => {
  'sourceId': s.sourceId,
  if (includeOptionalFields || s.page != null) 'page': s.page,
  if (includeOptionalFields || s.number != null) 'number': s.number,
};

Map<String, Object?> archiveProvenanceToJson(
  Provenance p, {
  bool includeOptionalFields = false,
}) => {
  'source': p.source.name,
  if (includeOptionalFields || p.externalId != null) 'externalId': p.externalId,
  'importedAt': archiveIso(p.importedAt),
  if (includeOptionalFields || p.permission != null) 'permission': p.permission,
  if (includeOptionalFields || p.license != null) 'license': p.license,
  if (includeOptionalFields || p.sourceVersion != null)
    'sourceVersion': p.sourceVersion,
};

/// Builds the archive-shaped body for a program.
Map<String, Object?> archiveProgramToJson(
  Program p, {
  bool includeOptionalFields = false,
}) => {
  'id': p.id,
  'title': p.title,
  if (includeOptionalFields || p.eventDate != null)
    'eventDate': p.eventDate == null ? null : archiveIso(p.eventDate!),
  if (includeOptionalFields || p.venue != null) 'venue': p.venue,
  if (includeOptionalFields || p.venueId != null) 'venueId': p.venueId,
  if (includeOptionalFields || p.band != null) 'band': p.band,
  if (includeOptionalFields || p.caller != null) 'caller': p.caller,
  if (includeOptionalFields || p.dancerLevel != null)
    'dancerLevel': p.dancerLevel,
  'notes': p.notes,
  'status': p.status.name,
  if (includeOptionalFields || p.hideAlternates)
    'hideAlternates': p.hideAlternates,
  'slots': [
    for (final s in p.slots)
      archiveProgramSlotToJson(s, includeOptionalFields: includeOptionalFields),
  ],
  if (includeOptionalFields || p.provenance != null)
    'provenance': p.provenance == null
        ? null
        : archiveProvenanceToJson(
            p.provenance!,
            includeOptionalFields: includeOptionalFields,
          ),
  'createdAt': archiveIso(p.createdAt),
  'updatedAt': archiveIso(p.updatedAt),
  if (includeOptionalFields || p.deletedAt != null)
    'deletedAt': p.deletedAt == null ? null : archiveIso(p.deletedAt!),
};

Map<String, Object?> archiveProgramSlotToJson(
  ProgramSlot s, {
  bool includeOptionalFields = false,
}) => {
  'id': s.id,
  'position': s.position,
  if (includeOptionalFields || s.danceId != null) 'danceId': s.danceId,
  if (includeOptionalFields || s.text != null) 'text': s.text,
  'isAlt': s.isAlt,
  if (includeOptionalFields || s.guestCaller != null)
    'guestCaller': s.guestCaller,
  if (includeOptionalFields || s.plannedMinutes != null)
    'plannedMinutes': s.plannedMinutes,
  if (includeOptionalFields || s.performedAt != null)
    'performedAt': s.performedAt == null ? null : archiveIso(s.performedAt!),
};

/// Builds the archive-shaped body for a venue.
Map<String, Object?> archiveVenueToJson(
  Venue v, {
  bool includeOptionalFields = false,
}) => {
  'id': v.id,
  'name': v.name,
  if (includeOptionalFields || v.address1 != null) 'address1': v.address1,
  if (includeOptionalFields || v.address2 != null) 'address2': v.address2,
  if (includeOptionalFields || v.city != null) 'city': v.city,
  if (includeOptionalFields || v.stateProv != null) 'stateProv': v.stateProv,
  if (includeOptionalFields || v.country != null) 'country': v.country,
  if (includeOptionalFields || v.postalCode != null) 'postalCode': v.postalCode,
  if (includeOptionalFields || v.plus4 != null) 'plus4': v.plus4,
  if (includeOptionalFields || v.website != null) 'website': v.website,
  if (includeOptionalFields || v.sponsor != null) 'sponsor': v.sponsor,
  if (includeOptionalFields || v.eventName != null) 'eventName': v.eventName,
  if (includeOptionalFields || v.time != null) 'time': v.time,
  if (includeOptionalFields || v.genericSchedule != null)
    'genericSchedule': v.genericSchedule,
  if (includeOptionalFields || v.price != null) 'price': v.price,
  if (includeOptionalFields || v.notes != null) 'notes': v.notes,
  if (includeOptionalFields || v.contact1Name != null)
    'contact1Name': v.contact1Name,
  if (includeOptionalFields || v.contact1Phone != null)
    'contact1Phone': v.contact1Phone,
  if (includeOptionalFields || v.contact1Email != null)
    'contact1Email': v.contact1Email,
  if (includeOptionalFields || v.contact2Name != null)
    'contact2Name': v.contact2Name,
  if (includeOptionalFields || v.contact2Phone != null)
    'contact2Phone': v.contact2Phone,
  if (includeOptionalFields || v.contact2Email != null)
    'contact2Email': v.contact2Email,
  if (includeOptionalFields || v.provenance != null)
    'provenance': v.provenance == null
        ? null
        : archiveProvenanceToJson(
            v.provenance!,
            includeOptionalFields: includeOptionalFields,
          ),
};

String archiveIso(DateTime dt) => dt.toUtc().toIso8601String();
