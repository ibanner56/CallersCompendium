import '../privacy/data_classification.dart';
import '../privacy/field_registry.dart';
import '../privacy/settings_registry.dart';
import 'generated_sync_allow_list.dart';
import 'sync_record_kind.dart';

/// Maps one wire path to the persisted fields that give it meaning.
///
/// Empty [sourceFields] entries are structural containers. Their descendants
/// carry the classified source fields; the container is admitted only when at
/// least one descendant is admitted.
class SyncWireField {
  const SyncWireField(this.path, this.sourceFields);

  final String path;
  final List<String> sourceFields;
}

const _danceFields = [
  SyncWireField('id', ['dances.id']),
  SyncWireField('title', ['dances.title']),
  SyncWireField('authorIds', ['dance_authors.choreographer_id']),
  SyncWireField('form', ['dances.form']),
  SyncWireField('formation', []),
  SyncWireField('formation.shape', ['dances.formation_shape']),
  SyncWireField('formation.detail', ['dances.formation_detail']),
  SyncWireField('progression', ['dances.progression']),
  SyncWireField('phraseStructure', ['dances.phrase_structure']),
  SyncWireField('figures', ['dances.figures_json']),
  SyncWireField('hook', ['dances.hook']),
  SyncWireField('callingNotes', ['dances.calling_notes']),
  SyncWireField('walkthrough', ['dances.walkthrough']),
  SyncWireField('status', ['dances.status']),
  SyncWireField('level', ['dances.level']),
  SyncWireField('mixedLevel', ['dances.mixed_level']),
  SyncWireField('mixer', ['dances.mixer']),
  SyncWireField('rating', ['dances.rating']),
  SyncWireField('tunes', ['dances.tunes_json']),
  SyncWireField('customFields', []),
  SyncWireField('customFields.fieldId', ['custom_field_values.field_id']),
  SyncWireField('customFields.value', [
    'custom_field_values.value_text',
    'custom_field_values.value_num',
  ]),
  SyncWireField('tagIds', ['dance_tags.tag_id']),
  SyncWireField('links', []),
  SyncWireField('links.id', ['dance_links.id']),
  SyncWireField('links.kind', ['dance_links.kind']),
  SyncWireField('links.url', ['dance_links.url']),
  SyncWireField('links.targetDanceId', ['dance_links.target_dance_id']),
  SyncWireField('links.label', ['dance_links.label']),
  SyncWireField('links.transitive', ['dance_links.transitive']),
  SyncWireField('sourceCitations', []),
  SyncWireField('sourceCitations.sourceId', ['dance_sources.source_id']),
  SyncWireField('sourceCitations.page', ['dance_sources.page']),
  SyncWireField('sourceCitations.number', ['dance_sources.number']),
  SyncWireField('provenance', []),
  SyncWireField('provenance.source', ['provenance.source']),
  SyncWireField('provenance.externalId', ['provenance.external_id']),
  SyncWireField('provenance.importedAt', ['provenance.imported_at']),
  SyncWireField('provenance.permission', ['provenance.permission']),
  SyncWireField('provenance.license', ['provenance.license']),
  SyncWireField('provenance.sourceVersion', ['provenance.source_version']),
  SyncWireField('composedOn', ['dances.composed_on']),
  SyncWireField('revisedOn', ['dances.revised_on']),
  SyncWireField('createdAt', ['dances.created_at']),
  SyncWireField('updatedAt', ['dances.updated_at']),
  SyncWireField('deletedAt', ['dances.deleted_at']),
];

const _programFields = [
  SyncWireField('id', ['programs.id']),
  SyncWireField('title', ['programs.title']),
  SyncWireField('eventDate', ['programs.event_date']),
  SyncWireField('venue', ['programs.venue']),
  SyncWireField('venueId', ['programs.venue_id']),
  SyncWireField('band', ['programs.band']),
  SyncWireField('caller', ['programs.caller']),
  SyncWireField('dancerLevel', ['programs.dancer_level']),
  SyncWireField('notes', ['programs.notes']),
  SyncWireField('status', ['programs.status']),
  SyncWireField('hideAlternates', ['programs.hide_alternates']),
  SyncWireField('slots', []),
  SyncWireField('slots.id', ['program_slots.id']),
  SyncWireField('slots.position', ['program_slots.position']),
  SyncWireField('slots.danceId', ['program_slots.dance_id']),
  SyncWireField('slots.text', ['program_slots.text']),
  SyncWireField('slots.isAlt', ['program_slots.is_alt']),
  SyncWireField('slots.guestCaller', ['program_slots.guest_caller']),
  SyncWireField('slots.plannedMinutes', ['program_slots.planned_minutes']),
  SyncWireField('slots.performedAt', ['program_slots.performed_at']),
  SyncWireField('provenance', []),
  SyncWireField('provenance.source', ['program_provenance.source']),
  SyncWireField('provenance.externalId', ['program_provenance.external_id']),
  SyncWireField('provenance.importedAt', ['program_provenance.imported_at']),
  SyncWireField('provenance.permission', ['program_provenance.permission']),
  SyncWireField('provenance.license', ['program_provenance.license']),
  SyncWireField('provenance.sourceVersion', [
    'program_provenance.source_version',
  ]),
  SyncWireField('createdAt', ['programs.created_at']),
  SyncWireField('updatedAt', ['programs.updated_at']),
  SyncWireField('deletedAt', ['programs.deleted_at']),
];

const _choreographerFields = [
  SyncWireField('id', ['choreographers.id']),
  SyncWireField('name', ['choreographers.name']),
  SyncWireField('website', ['choreographers.website']),
  SyncWireField('notes', ['choreographers.notes']),
  SyncWireField('email', ['choreographers.email']),
  SyncWireField('location', ['choreographers.location']),
  SyncWireField('deceased', ['choreographers.deceased']),
];

const _publishedSourceFields = [
  SyncWireField('id', ['published_sources.id']),
  SyncWireField('title', ['published_sources.title']),
  SyncWireField('author', ['published_sources.author']),
  SyncWireField('year', ['published_sources.year']),
  SyncWireField('url', ['published_sources.url']),
  SyncWireField('notes', ['published_sources.notes']),
];

const _tagFields = [
  SyncWireField('id', ['tags.id']),
  SyncWireField('name', ['tags.name']),
  SyncWireField('color', ['tags.color']),
];

const _customFieldDefFields = [
  SyncWireField('id', ['custom_field_defs.id']),
  SyncWireField('key', ['custom_field_defs.key']),
  SyncWireField('label', ['custom_field_defs.label']),
  SyncWireField('type', ['custom_field_defs.type']),
  SyncWireField('choices', ['custom_field_defs.choices_json']),
  SyncWireField('showInList', ['custom_field_defs.show_in_list']),
  SyncWireField('searchable', ['custom_field_defs.searchable']),
  SyncWireField('shareable', ['custom_field_defs.shareable']),
];

const _venueFields = [
  SyncWireField('id', ['venues.id']),
  SyncWireField('name', ['venues.name']),
  SyncWireField('address1', ['venues.address1']),
  SyncWireField('address2', ['venues.address2']),
  SyncWireField('city', ['venues.city']),
  SyncWireField('stateProv', ['venues.state_prov']),
  SyncWireField('country', ['venues.country']),
  SyncWireField('postalCode', ['venues.postal_code']),
  SyncWireField('plus4', ['venues.plus4']),
  SyncWireField('website', ['venues.website']),
  SyncWireField('sponsor', ['venues.sponsor']),
  SyncWireField('eventName', ['venues.event_name']),
  SyncWireField('time', ['venues.time']),
  SyncWireField('genericSchedule', ['venues.generic_schedule']),
  SyncWireField('price', ['venues.price']),
  SyncWireField('notes', ['venues.notes']),
  SyncWireField('contact1Name', ['venues.contact1_name']),
  SyncWireField('contact1Phone', ['venues.contact1_phone']),
  SyncWireField('contact1Email', ['venues.contact1_email']),
  SyncWireField('contact2Name', ['venues.contact2_name']),
  SyncWireField('contact2Phone', ['venues.contact2_phone']),
  SyncWireField('contact2Email', ['venues.contact2_email']),
  SyncWireField('provenance', []),
  SyncWireField('provenance.source', ['venue_provenance.source']),
  SyncWireField('provenance.externalId', ['venue_provenance.external_id']),
  SyncWireField('provenance.importedAt', ['venue_provenance.imported_at']),
  SyncWireField('provenance.permission', ['venue_provenance.permission']),
  SyncWireField('provenance.license', ['venue_provenance.license']),
  SyncWireField('provenance.sourceVersion', [
    'venue_provenance.source_version',
  ]),
];

const _settingFields = [
  SyncWireField('id', ['settings.key']),
  SyncWireField('value', ['settings.value_json']),
  SyncWireField('updatedAt', ['settings.updated_at']),
  SyncWireField('deletedAt', ['settings.deleted_at']),
  SyncWireField('existenceAt', ['settings.existence_at']),
];

/// The complete reviewed relation between wire paths and registry fields.
const Map<SyncRecordKind, List<SyncWireField>> syncWireFields = {
  SyncRecordKind.dance: _danceFields,
  SyncRecordKind.program: _programFields,
  SyncRecordKind.choreographer: _choreographerFields,
  SyncRecordKind.tag: _tagFields,
  SyncRecordKind.publishedSource: _publishedSourceFields,
  SyncRecordKind.customFieldDef: _customFieldDefFields,
  SyncRecordKind.venue: _venueFields,
  SyncRecordKind.setting: _settingFields,
};

/// Shareable source fields represented by metadata outside an archive body or by
/// an inline parent relationship. These are reviewed exceptions to the
/// source-field-to-body-path relation.
const Set<String> syncWireMappingExceptions = {
  'dances.existence_at',
  'choreographers.updated_at',
  'choreographers.deleted_at',
  'choreographers.existence_at',
  'venues.updated_at',
  'venues.deleted_at',
  'venues.existence_at',
  'programs.existence_at',
  'program_slots.program_id',
  'published_sources.updated_at',
  'published_sources.deleted_at',
  'published_sources.existence_at',
  'dance_authors.dance_id',
  'dance_authors.position',
  'dance_tags.dance_id',
  'dance_sources.dance_id',
  'dance_sources.position',
  'dance_links.dance_id',
  'custom_field_defs.updated_at',
  'custom_field_defs.deleted_at',
  'custom_field_defs.existence_at',
  'custom_field_values.dance_id',
  'provenance.dance_id',
  'program_provenance.program_id',
  'venue_provenance.venue_id',
  'tags.updated_at',
  'tags.deleted_at',
  'tags.existence_at',
};

/// Whether [source] is classified as data that may travel by Device Sync.
bool isShareableSourceField(String source) =>
    fieldClassifications[source]?.egress == EgressClass.shareable;

/// Whether a wire path is admitted by the generated allow-list.
bool isShareableWirePath(
  SyncRecordKind kind,
  String path, {
  String? settingsKey,
}) {
  if (kind == SyncRecordKind.setting &&
      path == 'value' &&
      settingsKey != null) {
    return classifySettingsKey(settingsKey)?.egress == EgressClass.shareable;
  }
  return generatedShareableWirePaths[kind]?.contains(path) ?? false;
}

/// Returns the registry fields represented by a wire path.
List<String> sourceFieldsForWirePath(SyncRecordKind kind, String path) {
  for (final field in syncWireFields[kind]!) {
    if (field.path == path) return field.sourceFields;
  }
  return const [];
}

/// Returns whether [path] is a structural ancestor of an admitted path.
bool hasShareableWireDescendant(SyncRecordKind kind, String path) =>
    generatedShareableWirePaths[kind]!.any(
      (candidate) => candidate.startsWith('$path.'),
    );

/// The result W11 can map to a `422` without accepting or rewriting input.
class SyncBodyValidation {
  const SyncBodyValidation.valid() : invalidPath = null;

  const SyncBodyValidation.invalid(this.invalidPath);

  final String? invalidPath;

  bool get isValid => invalidPath == null;
}

/// Projects an archive-shaped body down to shareable fields for W3.
Map<String, Object?> projectShareableRecordBody(
  SyncRecordKind kind,
  Map<String, Object?> body, {
  String? settingsKey,
  Set<String> allowedCustomFieldIds = const {},
}) {
  if (kind == SyncRecordKind.customFieldDef && body['shareable'] == false) {
    return {};
  }
  final projected = _projectValue(
    kind,
    '',
    body,
    settingsKey: settingsKey,
    allowedCustomFieldIds: allowedCustomFieldIds,
  );
  return Map<String, Object?>.from(projected as Map);
}

Object? _projectValue(
  SyncRecordKind kind,
  String path,
  Object? value, {
  String? settingsKey,
  Set<String> allowedCustomFieldIds = const {},
}) {
  final hasPath = path.isNotEmpty;
  final isShareable =
      hasPath && isShareableWirePath(kind, path, settingsKey: settingsKey);
  final hasDescendants = hasPath && hasShareableWireDescendant(kind, path);
  if (hasPath && !isShareable && !hasDescendants) {
    return _omitted;
  }
  if (value == null && (isShareable || hasDescendants)) return null;

  if (!hasDescendants && hasPath) return value;

  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) continue;
      final childPath = path.isEmpty
          ? entry.key as String
          : '$path.${entry.key}';
      final projected = _projectValue(
        kind,
        childPath,
        entry.value,
        settingsKey: settingsKey,
        allowedCustomFieldIds: allowedCustomFieldIds,
      );
      if (!identical(projected, _omitted)) {
        result[entry.key as String] = projected;
      }
    }
    return result;
  }
  if (value is List) {
    if (kind == SyncRecordKind.dance && path == 'customFields') {
      value = [
        for (final item in value)
          if (item is Map && allowedCustomFieldIds.contains(item['fieldId']))
            item,
      ];
    }
    return [
      for (final item in value)
        _projectValue(
          kind,
          path,
          item,
          settingsKey: settingsKey,
          allowedCustomFieldIds: allowedCustomFieldIds,
        ),
    ];
  }
  return _omitted;
}

/// Validates every key in a received body without modifying it.
SyncBodyValidation validateShareableRecordBody(
  SyncRecordKind kind,
  Map<String, Object?> body, {
  String? settingsKey,
}) {
  final invalid = _firstInvalid(kind, '', body, settingsKey: settingsKey);
  return invalid == null
      ? const SyncBodyValidation.valid()
      : SyncBodyValidation.invalid(invalid);
}

String? _firstInvalid(
  SyncRecordKind kind,
  String path,
  Object? value, {
  String? settingsKey,
}) {
  final hasPath = path.isNotEmpty;
  final isShareable =
      hasPath && isShareableWirePath(kind, path, settingsKey: settingsKey);
  final hasDescendants = hasPath && hasShareableWireDescendant(kind, path);
  if (hasPath && !isShareable && !hasDescendants) {
    return path;
  }
  if (hasPath && isShareable && !hasDescendants) return null;
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) return path;
      final childPath = path.isEmpty
          ? entry.key as String
          : '$path.${entry.key}';
      final invalid = _firstInvalid(
        kind,
        childPath,
        entry.value,
        settingsKey: settingsKey,
      );
      if (invalid != null) return invalid;
    }
  } else if (value is List) {
    for (final item in value) {
      final invalid = _firstInvalid(kind, path, item, settingsKey: settingsKey);
      if (invalid != null) return invalid;
    }
  }
  return null;
}

const _omitted = Object();
