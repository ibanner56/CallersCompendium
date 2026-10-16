import 'dart:convert';

import 'package:compendium_app/src/export/dance_share_bundle.dart';
import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A share bundle carries the user's own new figures its dances use (#1023,
/// plan C12): each one attached, inside containers too, without its notes;
/// none it can't find, and none only a detached use names.
void main() {
  final now = DateTime.utc(2026, 10, 16);

  UserGlossaryEntry figure(String id) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'figure $id',
    definition: 'A figure.',
    description: 'Of your own.',
    notes: 'only mine',
    payload: const {
      'form': 'contra',
      'template': '{move}',
      'defaultBeats': 8,
      'params': <Object?>[],
    },
    createdAt: now,
  );

  Figure use(String id) =>
      userFigureUseFigure(id: id, args: const {}, text: 'figure $id');

  final entries = {
    for (final id in ['a', 'b', 'c', 'd']) id: figure(id),
  };

  Dance dance(String id, List<Figure> figures) => Dance(
    id: id,
    title: 'Dance $id',
    figures: figures,
    createdAt: now,
    updatedAt: now,
  );

  // Uses a, inside a meanwhile b, and a detached use of c; d is unused, and
  // gone is not on this device.
  final first = dance('d1', [
    use('a'),
    Figure.meanwhile(figures: [use('b'), use('gone')], beats: 8),
    detachUserFigureUse(use('c')),
  ]);

  String danceBundle(Dance d) => buildDanceShareBundle(
    d,
    now: now,
    choreographerFor: (_) => null,
    tagFor: (_) => null,
    publishedSourceFor: (_) => null,
    customFieldFor: (_) => null,
    userFigureFor: (id) => entries[id],
  );

  test('a dance bundle carries each figure the dance uses, without its '
      'notes', () {
    final json = danceBundle(first);
    final archive = decodeArchive(json).archive;
    expect(archive.userFigures.map((f) => f.id).toSet(), {'a', 'b'});
    expect(json, isNot(contains('only mine')));
  });

  test('a dance bundle carries no figures without a lookup', () {
    final json = buildDanceShareBundle(
      first,
      now: now,
      choreographerFor: (_) => null,
      tagFor: (_) => null,
      publishedSourceFor: (_) => null,
      customFieldFor: (_) => null,
    );
    expect(
      (jsonDecode(json) as Map<String, Object?>).containsKey('userFigures'),
      isFalse,
    );
  });

  test('a program bundle carries the figures of every dance it embeds', () {
    final second = dance('d2', [use('a'), use('d')]);
    final dances = {'d1': first, 'd2': second};
    final json = buildProgramShareBundle(
      Program(
        id: 'p1',
        title: 'An evening',
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      now: now,
      danceFor: (id) => dances[id],
      choreographerFor: (_) => null,
      venueFor: (_) => null,
      tagFor: (_) => null,
      publishedSourceFor: (_) => null,
      customFieldFor: (_) => null,
      userFigureFor: (id) => entries[id],
    );
    expect(decodeArchive(json).archive.userFigures.map((f) => f.id).toSet(), {
      'a',
      'b',
      'd',
    });
    expect(json, isNot(contains('only mine')));
  });
}
