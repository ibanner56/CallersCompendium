import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A shared archive's `userFigures` section (#1023, plan C12): the user's own
/// new figures its dances use, without their notes, written in share mode only
/// and never a version bump (maintainer decision on PR 10), and read back only
/// whole and only when a dance in the archive uses it.
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

  UserGlossaryEntry zoom({String? notes, String name = 'zoom'}) =>
      UserGlossaryEntry(
        id: 'zoom-id',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: name,
        definition: 'A fast figure.',
        description: 'Of your own.',
        keywords: const ['fast'],
        notes: notes,
        payload: payload(),
        createdAt: created,
      );

  /// An archive whose one dance uses each of [uses] (by default, each of
  /// [figures]), carrying [figures].
  CompendiumArchive archive(
    List<UserGlossaryEntry> figures, {
    Iterable<String>? uses,
  }) => CompendiumArchive(
    exportedAt: created,
    dances: [
      Dance(
        id: 'd1',
        title: 'Zoom Reel',
        figures: [
          for (final id in uses ?? figures.map((f) => f.id))
            userFigureUseFigure(id: id, args: const {}, text: id),
        ],
        createdAt: created,
        updatedAt: created,
      ),
    ],
    userFigures: figures,
  );

  Map<String, Object?> encoded(
    CompendiumArchive a, {
    ArchiveSerializationMode mode = ArchiveSerializationMode.share,
  }) => jsonDecode(encodeArchive(a, mode: mode)) as Map<String, Object?>;

  Map<String, Object?> zoomJson() =>
      ((encoded(archive([zoom()]))['userFigures']! as List).single as Map)
          .cast<String, Object?>();

  test('share mode writes each figure without its notes or kind, and the '
      'stamp is what it would be without them', () {
    final json = encoded(archive([zoom(notes: 'mine only')]));
    final figure = ((json['userFigures']! as List).single as Map)
        .cast<String, Object?>();
    expect(figure['id'], 'zoom-id');
    expect(figure['payload'], payload());
    expect(figure.containsKey('notes'), isFalse);
    expect(figure.containsKey('kind'), isFalse);
    expect(
      json['schemaVersion'],
      encoded(archive(const [], uses: ['zoom-id']))['schemaVersion'],
    );
    expect(json['schemaVersion'], lessThanOrEqualTo(archiveSchemaVersion));
  });

  test('backup mode never writes the section', () {
    final json = encoded(
      archive([zoom()]),
      mode: ArchiveSerializationMode.backup,
    );
    expect(json.containsKey('userFigures'), isFalse);
  });

  test('no section when no figure is carried', () {
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

  test('a missing, empty or blank description is read as none, not a figure '
      'to drop', () {
    for (final description in <Object?>[null, '', '   ', '\u200b']) {
      final json = encoded(archive([zoom()]));
      final figure = ((json['userFigures']! as List).single as Map)
          .cast<String, Object?>();
      if (description == null) {
        figure.remove('description');
      } else {
        figure['description'] = description;
      }
      (json['userFigures']! as List)[0] = figure;
      final result = decodeArchive(jsonEncode(json));
      expect(result.errors, isEmpty, reason: '$description');
      expect(
        result.archive.userFigures.single.description,
        isEmpty,
        reason: '$description',
      );
    }
  });

  test('only whole figures are kept; the rest are a warning, never an '
      'error', () {
    Map<String, Object?> entry(Map<String, Object?> changes) => {
      ...zoomJson(),
      ...changes,
    };
    final bad = <Object?>[
      entry({'id': 'blank-name', 'name': '  '}),
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
      entry({'id': 'e\u0301-not-normal'}),
      entry({
        'id': 'big-payload',
        'payload': {
          ...payload(),
          'padding': 'x' * maxUserGlossaryPayloadLength,
        },
      }),
      'not an object',
    ];
    final ids = [
      for (final e in bad)
        if (e is Map && e['id'] is String) e['id']! as String,
    ];
    final json = {
      ...encoded(archive(const [], uses: ['zoom-id', ...ids])),
      'userFigures': [
        ...bad,
        entry({}),
        entry({'name': 'a second zoom'}),
        entry({'id': 'no-dance-uses-it'}),
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
    expect(
      result.warnings,
      containsAll([
        startsWith('${bad.length} userFigures entries could not be read'),
        startsWith('1 userFigures entries no dance uses'),
        startsWith('1 userFigures entries repeat an id'),
      ]),
    );
  });

  test('a figure no dance in the archive uses is not kept', () {
    final result = decodeArchive(
      encodeArchive(archive([zoom()], uses: const [])),
    );
    expect(result.archive.userFigures, isEmpty);
    expect(result.warnings, contains(contains('no dance uses')));
  });

  test('a figure\'s text is scrubbed as imported text is', () {
    final json = encoded(archive([zoom()]));
    json['userFigures'] = [
      {...zoomJson(), 'name': 'zo\u202Eom'},
    ];
    expect(archiveFromJson(json).archive.userFigures.single.name, 'zoom');
  });

  test('a section that is not an array is ignored with a warning', () {
    final result = archiveFromJson({
      ...encoded(archive(const [], uses: ['zoom-id'])),
      'userFigures': {'zoom-id': true},
    });
    expect(result.errors, isEmpty);
    expect(result.archive.userFigures, isEmpty);
    expect(result.warnings, contains(contains('not a JSON array')));
  });

  test('at most $kMaxArchiveUserFigures figures are read', () {
    final ids = [for (var i = 0; i <= kMaxArchiveUserFigures; i++) 'f$i'];
    final result = archiveFromJson({
      ...encoded(archive(const [], uses: ids)),
      'userFigures': [
        for (final id in ids) {...zoomJson(), 'id': id},
      ],
    });
    expect(result.archive.userFigures, hasLength(kMaxArchiveUserFigures));
    expect(result.warnings, contains(contains('more than')));
  });

  test('archives that differ only in a figure are not equal', () {
    expect(archive([zoom()]), isNot(archive([zoom(name: 'whizz')])));
    expect(archive([zoom()]), archive([zoom()]));
    expect(archive([zoom()]).hashCode, archive([zoom()]).hashCode);
  });
}
