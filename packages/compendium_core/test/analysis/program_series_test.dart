import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// A combined matrix and the repeated dances across several programs (#2349).
void main() {
  final now = DateTime.utc(2026, 7, 13);

  Figure fig(String moveId) => testFigure(move: moveId, params: {'beats': 16});
  Dance dance(String id, String moveId) => Dance(
    id: id,
    title: id,
    figures: [fig(moveId)],
    createdAt: now,
    updatedAt: now,
  );

  ProgramSlot slot(
    String id,
    int position, {
    String? danceId,
    String? text,
    bool alt = false,
  }) => ProgramSlot(
    id: id,
    position: position,
    danceId: danceId,
    text: text,
    isAlt: alt,
  );

  /// A program whose slots are [entries] in order: a dance id, `'|'` for a
  /// break, `'~'` for a free-text slot, or `'alt:<id>'` for an alternate.
  Program program(
    String id,
    List<String> entries, {
    DateTime? date,
    int? start,
  }) => Program(
    id: id,
    title: id,
    eventDate: date,
    startMinute: start,
    createdAt: now,
    updatedAt: now,
    slots: [
      for (var i = 0; i < entries.length; i++)
        switch (entries[i]) {
          '|' => slot('$id-$i', i, text: 'Break'),
          '~' => slot('$id-$i', i, text: 'Waltz'),
          final e when e.startsWith('alt:') => slot(
            '$id-$i',
            i,
            danceId: e.substring(4),
            alt: true,
          ),
          final e => slot('$id-$i', i, danceId: e),
        },
    ],
  );

  group('orderProgramsForSeries', () {
    test('by event date, then undated programs last by title', () {
      final ordered = orderProgramsForSeries([
        program('Zed', const [], date: null),
        program('Sunday', const [], date: DateTime(2026, 8, 2)),
        program('Alpha', const [], date: null),
        program('Saturday', const [], date: DateTime(2026, 8, 1)),
      ]);
      expect(
        [for (final p in ordered) p.id],
        ['Saturday', 'Sunday', 'Alpha', 'Zed'],
      );
    });

    test('one date: by start time, untimed after the timed, then by '
        'title', () {
      final day = DateTime.utc(2026, 8, 1);
      final ordered = orderProgramsForSeries([
        program('Evening dance', const [], date: day, start: 20 * 60),
        program('Workshop', const [], date: day, start: 14 * 60),
        program('Contra jam', const [], date: day),
        program('Afterparty', const [], date: day),
      ]);
      expect(
        [for (final p in ordered) p.id],
        ['Workshop', 'Evening dance', 'Afterparty', 'Contra jam'],
      );
    });
  });

  group('combineProgramsForMatrix', () {
    final dances = {
      for (final (id, move) in const [
        ('a', 'balance'),
        ('b', 'balance'),
        ('c', 'do_si_do'),
        ('d', 'balance'),
        ('e', 'do_si_do'),
      ])
        id: dance(id, move),
    };
    Dance resolve(String id) => dances[id]!;

    ProgramMatrix matrixOf(CombinedProgramMatrixInput input) =>
        buildProgramMatrix(
          input.dances,
          sections: input.sections,
          alternateGroups: input.alternateGroups,
        );

    int col(ProgramMatrix m, String moveId) =>
        m.columns.indexWhere((c) => c.moveId == moveId);

    test('rows follow the programs in event-date order, labelled by '
        'program', () {
      final input = combineProgramsForMatrix([
        program('Sun', const ['c', 'd'], date: DateTime(2026, 8, 2)),
        program('Sat', const ['a', '~', 'b'], date: DateTime(2026, 8, 1)),
      ], resolveDance: resolve);
      expect([for (final p in input.programs) p.id], ['Sat', 'Sun']);
      expect([for (final d in input.dances) d.id], ['a', 'b', 'c', 'd']);
      expect(input.programIndexByRow, [0, 0, 1, 1]);
      expect(input.omittedFreeTextCount, 1);
    });

    test('no alert between the last dance of one program and the first of '
        'the next, though neither program has a break', () {
      // Sat ends with a balance (b) and Sun opens with one (d).
      final input = combineProgramsForMatrix([
        program('Sat', const ['c', 'b'], date: DateTime(2026, 8, 1)),
        program('Sun', const ['d', 'e'], date: DateTime(2026, 8, 2)),
      ], resolveDance: resolve);
      final m = matrixOf(input);
      final balance = col(m, 'balance');
      expect(m.isCollision(1, balance), isFalse);
      expect(m.isCollision(2, balance), isFalse);
    });

    test('alerts within each program match its own matrix', () {
      final sat = program('Sat', const [
        'a',
        'b',
        '|',
        'd',
      ], date: DateTime(2026, 8, 1));
      final sun = program('Sun', const [
        'c',
        'e',
        'alt:a',
        'b',
      ], date: DateTime(2026, 8, 2));
      final combined = matrixOf(
        combineProgramsForMatrix([sun, sat], resolveDance: resolve),
      );
      var row = 0;
      for (final p in [sat, sun]) {
        // The program's own matrix as its Matrix tab builds it: its own
        // sections, null throughout when it has no break.
        final slots = p.slots.where((s) => s.danceId != null).toList();
        final ownMatrix = buildProgramMatrix(
          [for (final s in slots) resolve(s.danceId!)],
          sections: [
            for (final (i, s) in Program.sectionsForSlots(p.slots).indexed)
              if (p.slots[i].danceId != null) s,
          ],
          alternateGroups: [
            for (final (i, g) in Program.alternateGroupsForSlots(
              p.slots,
            ).indexed)
              if (p.slots[i].danceId != null) g,
          ],
        );
        for (var r = 0; r < ownMatrix.rows.length; r++, row++) {
          for (final c in ownMatrix.columns) {
            final ownCol = ownMatrix.columns.indexOf(c);
            final combinedCol = combined.columns.indexOf(c);
            expect(
              combined.isCollision(row, combinedCol),
              ownMatrix.isCollision(r, ownCol),
              reason: '${p.id} row $r ${c.moveId}',
            );
          }
        }
      }
      expect(row, combined.rows.length);
      // And the program's own break and alternates still work: a, b collide
      // in Sat; b and d do not (a break lies between them); in Sun, b
      // collides with the alternate a it could follow.
      final balance = col(combined, 'balance');
      expect(combined.isCollision(0, balance), isTrue);
      expect(combined.isCollision(2, balance), isFalse);
      expect(combined.isCollision(5, balance), isTrue);
      expect(combined.isCollision(6, balance), isTrue);
    });

    test('Introduced here is marked once across the set', () {
      final input = combineProgramsForMatrix([
        program('Sat', const ['a', 'c'], date: DateTime(2026, 8, 1)),
        program('Sun', const ['e', 'd'], date: DateTime(2026, 8, 2)),
      ], resolveDance: resolve);
      final m = matrixOf(input);
      final balance = col(m, 'balance');
      final doSiDo = col(m, 'do_si_do');
      expect(
        [for (var r = 0; r < 4; r++) m.isProgramDebut(r, balance)],
        [true, false, false, false],
      );
      expect(
        [for (var r = 0; r < 4; r++) m.isProgramDebut(r, doSiDo)],
        [false, true, false, false],
      );
    });

    test('alternates are rows of their own, marked as alternates', () {
      final input = combineProgramsForMatrix([
        program('Sat', const ['a', 'alt:b'], date: DateTime(2026, 8, 1)),
        program('Sun', const ['alt:c', 'd'], date: DateTime(2026, 8, 2)),
      ], resolveDance: resolve);
      expect(input.altRowIndices, {1, 2});
      // A group never spans two programs: Sun's leading alternate is a group
      // of its own, not one with Sat's last.
      expect(input.alternateGroups[1], isNot(input.alternateGroups[2]));
      expect(() => matrixOf(input), returnsNormally);
    });
  });

  group('findRepeatedDances', () {
    test('lists a dance in two programs, with program, position and whether '
        'it is an alternate', () {
      final repeats = findRepeatedDances([
        program('Sat', const ['a', 'b', 'alt:c']),
        program('Sun', const ['c', 'a']),
      ]);
      expect([for (final r in repeats) r.danceId], ['a', 'c']);
      expect(repeats[0].uses, const [
        RepeatedDanceUse(programIndex: 0, danceNumber: 1, isAlternate: false),
        RepeatedDanceUse(programIndex: 1, danceNumber: 2, isAlternate: false),
      ]);
      expect(repeats[0].isAlternateSomewhere, isFalse);
      expect(repeats[1].uses, const [
        RepeatedDanceUse(programIndex: 0, danceNumber: 2, isAlternate: true),
        RepeatedDanceUse(programIndex: 1, danceNumber: 1, isAlternate: false),
      ]);
      expect(repeats[1].isAlternateSomewhere, isTrue);
    });

    test('a dance that is an alternate in every program is only an '
        'alternate', () {
      final repeats = findRepeatedDances([
        program('Sat', const ['a', 'alt:b']),
        program('Sun', const ['c', 'alt:b']),
      ]);
      expect(repeats.single.isOnlyAlternate, isTrue);
      expect(repeats.single.isAlternateSomewhere, isTrue);
      final mixed = findRepeatedDances([
        program('Sat', const ['b']),
        program('Sun', const ['c', 'alt:b']),
      ]);
      expect(mixed.single.isOnlyAlternate, isFalse);
      expect(mixed.single.isAlternateSomewhere, isTrue);
    });

    test('a dance used twice in one program and in no other is not '
        'listed', () {
      final repeats = findRepeatedDances([
        program('Sat', const ['a', 'b', 'a']),
        program('Sun', const ['c']),
      ]);
      expect(repeats, isEmpty);
    });

    test('a dance whose only other use is outside the selection is not '
        'listed', () {
      final outside = program('Fri', const ['a']);
      final selection = [
        program('Sat', const ['a']),
        program('Sun', const ['b']),
      ];
      expect(findRepeatedDances([outside, ...selection]), isNotEmpty);
      expect(findRepeatedDances(selection), isEmpty);
    });

    test('positions skip alternates and breaks, as the set list does', () {
      final repeats = findRepeatedDances([
        program('Sat', const ['c', 'alt:d', '|', 'e', 'a']),
        program('Sun', const ['a']),
      ]);
      expect(repeats.single.uses.first.danceNumber, 3);
    });
  });
}
