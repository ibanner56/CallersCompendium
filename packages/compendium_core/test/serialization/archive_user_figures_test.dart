import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A shared archive's `userFigures` section (#1023, plan C12): the user's own
/// new figures its dances use, without their notes, written in share mode only
/// and never a version bump (maintainer decision on PR 10), and read back only
/// whole.
void main() {
  final created = DateTime.utc(2026, 10, 16);

  Map<String, Object?> payload({String template = '{who} {move}'}) => {
    'form': 'contra',
    'template': template,
    'defaultBeats': 8,
    'params': [
      {'key': 'who', 'kind': 'dancerSet', 'default': 'role1s'},
    ],
  };

  UserGlossaryEntry zoom({String? notes}) => UserGlossaryEntry(
    id: 'zoom-id',
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'zoom',
    definition: 'A fast figure.',
    description: 'Of your own.',
    keywords: const ['fast'],
    notes: notes,
    payload: payload(),
    createdAt: created,
  );

  CompendiumArchive archive(List<UserGlossaryEntry> figures) =>
      CompendiumArchive(exportedAt: created, userFigures: figures);

  Map<String, Object?> encoded(
    CompendiumArchive a, {
    ArchiveSerializationMode mode = ArchiveSerializationMode.share,
  }) => jsonDecode(encodeArchive(a, mode: mode)) as Map<String, Object?>;

  test('share mode writes each figure without its notes or kind, and the '
      'stamp is what it would be without them', () {
    final json = encoded(archive([zoom(notes: 'mine only')]));
    final figures = json['userFigures']! as List;
    final figure = (figures.single as Map).cast<String, Object?>();
    expect(figure['id'], 'zoom-id');
    expect(figure['payload'], payload());
    expect(figure.containsKey('notes'), isFalse);
    expect(figure.containsKey('kind'), isFalse);
    expect(json['schemaVersion'], encoded(archive(const []))['schemaVersion']);
    expect(json['schemaVersion'], lessThanOrEqualTo(archiveSchemaVersion));
  });

  test('backup mode never writes the section', () {
    final json = encoded(
      archive([zoom()]),
      mode: ArchiveSerializationMode.backup,
    );
    expect(json.containsKey('userFigures'), isFalse);
  });

  test('no section when no figure is used', () {
    expect(encoded(archive(const [])).containsKey('userFigures'), isFalse);
  });

  test('a figure reads back as the entry it was, as a custom figure without '
      'notes', () {
    final result = decodeArchive(encodeArchive(archive([zoom(notes: 'x')])));
    expect(result.errors, isEmpty);
    final read = result.archive.userFigures.single;
    expect(read.kind, UserGlossaryEntryKind.customFigure);
    expect(read.notes, isNull);
    expect(result.archive, archive([zoom()]));
  });

  test('only whole figures are kept; the rest are a warning, never an '
      'error', () {
    final good = encoded(archive([zoom()]))['userFigures']! as List;
    Map<String, Object?> entry(Map<String, Object?> changes) => {
      ...(good.single as Map).cast<String, Object?>(),
      ...changes,
    };
    final json = {
      ...encoded(archive(const [])),
      'userFigures': [
        entry({'id': 'blank-id', 'name': '  '}),
        entry({'id': ''}),
        entry({'id': 'no-date', 'createdAt': 'soon'}),
        entry({'id': 'bad-payload', 'payload': 'not a figure'}),
        entry({'id': 'bad-template', 'payload': payload(template: '{move')}),
        entry({'id': 'long-name', 'name': 'x' * 201}),
        entry({'id': 'bad-keywords', 'keywords': 'fast'}),
        entry({
          'id': 'keyword-type',
          'keywords': [3],
        }),
        'not an object',
        entry({}),
        entry({'name': 'a second zoom'}),
      ],
    };
    final result = archiveFromJson(json);
    expect(result.errors, isEmpty);
    expect(result.archive.userFigures.map((f) => f.id), ['zoom-id']);
    expect(
      result.archive.userFigures.single.name,
      'zoom',
      reason: 'the first entry for an id wins',
    );
    expect(result.warnings, contains(startsWith('10 userFigures entries')));
  });

  test('a figure\'s text is scrubbed as imported text is', () {
    final json = {
      ...encoded(archive([zoom()])),
    };
    final figure = ((json['userFigures']! as List).single as Map)
        .cast<String, Object?>();
    json['userFigures'] = [
      {...figure, 'name': 'zo‮om'},
    ];
    expect(archiveFromJson(json).archive.userFigures.single.name, 'zoom');
  });

  test('a section that is not an array is ignored with a warning', () {
    final result = archiveFromJson({
      ...encoded(archive(const [])),
      'userFigures': {'zoom-id': true},
    });
    expect(result.errors, isEmpty);
    expect(result.archive.userFigures, isEmpty);
    expect(result.warnings, contains(contains('not a JSON array')));
  });

  test('at most $kMaxArchiveUserFigures figures are read', () {
    final one =
        (encoded(archive([zoom()]))['userFigures']! as List).single as Map;
    final result = archiveFromJson({
      ...encoded(archive(const [])),
      'userFigures': [
        for (var i = 0; i <= kMaxArchiveUserFigures; i++) {...one, 'id': 'f$i'},
      ],
    });
    expect(result.archive.userFigures, hasLength(kMaxArchiveUserFigures));
    expect(result.warnings, contains(contains('more than')));
  });
}
