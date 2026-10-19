import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// The user's own glossary entries and notes on shipped figures (#709).
void main() {
  late CompendiumDatabase db;
  late UserGlossaryRepository glossary;
  late FigureNoteRepository notes;
  final created = DateTime.utc(2026, 10, 14, 9);

  setUp(() {
    db = CompendiumDatabase(NativeDatabase.memory());
    glossary = UserGlossaryRepository(db);
    notes = FigureNoteRepository(db);
  });
  tearDown(() => db.close());

  UserGlossaryEntry entry({
    String id = 'e1',
    String kind = 'compound',
    String name = 'grand right and left',
    Object? payload = const {
      'params': <Object?>[],
      'figures': <Object?>[],
      'bindings': <Object?>[],
    },
    DateTime? createdAt,
  }) => UserGlossaryEntry(
    id: id,
    kindName: kind,
    name: name,
    definition: 'Pull by alternating hands around the ring.',
    description: 'Four pull-bys.',
    keywords: const ['grl', '  '],
    notes: 'from my cards',
    payload: payload,
    createdAt: createdAt ?? created,
  );

  group('glossary entries', () {
    test('round-trip, dropping blank keywords', () async {
      await glossary.upsert(entry());
      final read = (await glossary.getById('e1'))!;
      expect(read.name, 'grand right and left');
      expect(read.kind, UserGlossaryEntryKind.compound);
      expect(read.keywords, ['grl']);
      expect(read.notes, 'from my cards');
      expect(read.payload, {
        'params': <Object?>[],
        'figures': <Object?>[],
        'bindings': <Object?>[],
      });
      expect(read.createdAt, created);
    });

    test('an edit never moves the creation time', () async {
      await glossary.upsert(entry());
      await glossary.upsert(
        entry(createdAt: DateTime.utc(2030)).copyWith(name: 'GRL'),
      );
      final read = (await glossary.getById('e1'))!;
      expect(read.name, 'GRL');
      expect(read.createdAt, created);
    });

    test(
      'names need not be unique: a duplicate is kept, not refused',
      () async {
        await glossary.upsert(entry(id: 'a'));
        await glossary.upsert(entry(id: 'b', createdAt: created.add(_day)));
        expect((await glossary.listAll()).map((e) => e.id), ['a', 'b']);
      },
    );

    test('an unknown kind and a payload that no longer decodes are kept as '
        'they are', () async {
      await glossary.upsert(entry(kind: 'fromTheFuture'));
      await db.customStatement(
        "UPDATE user_glossary_entries SET payload_json = '{not json' "
        "WHERE id = 'e1'",
      );
      final read = (await glossary.getById('e1'))!;
      expect(read.kind, isNull);
      expect(read.kindName, 'fromTheFuture');
      expect(read.payload, isNull);
    });

    test(
      'a delete leaves a tombstone, stamped, that listAll can see',
      () async {
        await glossary.upsert(entry(), at: created);
        await glossary.delete('e1', at: created.add(_day));
        expect(await glossary.getById('e1'), isNull);
        expect(await glossary.listAll(), isEmpty);
        expect(
          (await glossary.listAll(includeDeleted: true)).map((e) => e.id),
          ['e1'],
        );
        final row = await (db.select(
          db.userGlossaryEntries,
        )..where((t) => t.id.equals('e1'))).getSingle();
        expect(row.deletedAt!.toUtc(), created.add(_day));
        expect(row.existenceAt, isNotNull);
      },
    );

    test('writing a deleted entry again revives it', () async {
      await glossary.upsert(entry(), at: created);
      await glossary.delete('e1', at: created.add(_day));
      await glossary.upsert(entry(), at: created.add(_day * 2));
      expect(await glossary.getById('e1'), isNotNull);
    });

    test('required text and bounds are enforced', () async {
      for (final bad in [
        entry().copyWith(name: '  '),
        entry().copyWith(definition: ''),
        entry().copyWith(
          description: 'd' * (maxUserGlossaryTextLength + 1),
        ),
        entry().copyWith(name: 'x' * (maxUserGlossaryNameLength + 1)),
        entry().copyWith(
          keywords: [for (var i = 0; i <= maxUserGlossaryKeywords; i++) 'k$i'],
        ),
      ]) {
        await expectLater(
          glossary.upsert(bad),
          throwsA(isA<UserGlossaryEntryInvalid>()),
        );
      }
      expect(await glossary.listAll(), isEmpty);
    });

    test('a description is optional: empty or blank is stored empty', () async {
      await glossary.upsert(entry().copyWith(description: ''));
      expect((await glossary.getById('e1'))!.description, isEmpty);
      await glossary.upsert(entry().copyWith(description: '​'));
      expect((await glossary.getById('e1'))!.description, isEmpty);
    });

    test('a payload that cannot be stored is refused, not thrown as an '
        'error', () async {
      for (final payload in <Object?>[
        {'x': double.infinity},
        {'Cafe\u0301': 1, 'Café': 2},
        {'big': 'x' * maxUserGlossaryPayloadLength},
        // Deep enough to overflow a recursive encoder, from a hand-edited
        // backup: refused before anything recursive reads it.
        _nested(100000),
      ]) {
        await expectLater(
          glossary.upsert(entry(payload: payload)),
          throwsA(
            isA<UserGlossaryEntryInvalid>().having(
              (e) => e.field,
              'field',
              'payload',
            ),
          ),
        );
      }
      expect(await glossary.listAll(), isEmpty);
    });

    test('a payload exactly at the depth bound is stored', () async {
      await glossary.upsert(
        entry(payload: {'nested': _nested(maxUserGlossaryPayloadDepth - 1)}),
      );
      expect(await glossary.getById('e1'), isNotNull);
      await expectLater(
        glossary.upsert(
          entry(payload: {'nested': _nested(maxUserGlossaryPayloadDepth)}),
        ),
        throwsA(isA<UserGlossaryEntryInvalid>()),
      );
    });

    test('entries created in the same second read back in id order', () async {
      await glossary.upsert(entry(id: 'b'));
      await glossary.upsert(entry(id: 'a'));
      expect((await glossary.listAll()).map((e) => e.id), ['a', 'b']);
    });

    test('watchAll re-emits on a change', () async {
      final emissions = glossary.watchAll().map((e) => e.length);
      final first = emissions.first;
      expect(await first, 0);
      final next = glossary.watchAll().skip(1).first;
      await glossary.upsert(entry());
      expect((await next).single.id, 'e1');
    });
  });

  group('figure notes', () {
    test('set, replace and read', () async {
      await notes.set('swing', 'role1s on the left');
      await notes.set('swing', 'role2s on the right');
      expect((await notes.get('swing'))!.notes, 'role2s on the right');
    });

    test('empty text deletes the note, softly', () async {
      await notes.set('swing', 'something');
      await notes.set('swing', '   ');
      expect(await notes.get('swing'), isNull);
      expect(
        (await notes.listAll(includeDeleted: true)).single.figureId,
        'swing',
      );
    });

    test('read back in figure id order', () async {
      await notes.set('swing', 'n');
      await notes.set('chain', 'n');
      expect((await notes.listAll()).map((n) => n.figureId), [
        'chain',
        'swing',
      ]);
    });

    test('a note on an id the taxonomy no longer has is kept', () async {
      await notes.set('retired_move', 'still here');
      expect((await notes.get('retired_move'))!.notes, 'still here');
    });

    test('an over-long note is refused', () async {
      await expectLater(
        notes.set('swing', 'x' * (maxUserGlossaryTextLength + 1)),
        throwsA(isA<FigureNoteInvalid>()),
      );
    });

    test('a figure id sync could not carry is refused, not stored', () async {
      for (final id in [
        '',
        'x' * (maxUserGlossaryNameLength + 1),
        _decomposedCafe,
      ]) {
        await expectLater(
          notes.set(id, 'A note.'),
          throwsA(isA<FigureNoteInvalid>()),
          reason: id,
        );
      }
      expect(await notes.listAll(includeDeleted: true), isEmpty);
    });
  });

  group('an id or kind sync could not carry is refused, not stored (#709): '
      'every peer would refuse the row, every pass', () {
    for (final (field, bad) in [
      ('id', ''),
      ('id', 'x' * (maxUserGlossaryNameLength + 1)),
      ('id', _decomposedCafe),
      ('kind', ''),
      ('kind', 'x' * (maxUserGlossaryNameLength + 1)),
      ('kind', _decomposedCafe),
    ]) {
      test(
        '$field: ${bad.length > 20 ? '${bad.length} units' : bad}',
        () async {
          await expectLater(
            glossary.upsert(field == 'id' ? entry(id: bad) : entry(kind: bad)),
            throwsA(
              isA<UserGlossaryEntryInvalid>().having(
                (e) => e.field,
                'field',
                field,
              ),
            ),
          );
          expect(await glossary.listAll(includeDeleted: true), isEmpty);
        },
      );
    }

    test('the longest id and kind sync carries are stored', () async {
      final longest = 'x' * maxUserGlossaryNameLength;
      await glossary.upsert(entry(id: longest));
      await glossary.upsert(entry(id: 'e2', kind: longest));
      expect((await glossary.listAll()).length, 2);
    });
  });
}

/// "café" with its accent as a separate combining mark: not normalised, so
/// inbound admission would refuse it as non-canonical.
const _decomposedCafe = 'cafe\u0301';

const _day = Duration(days: 1);

/// [depth] lists, each holding the next, the innermost holding a number.
Object _nested(int depth) {
  Object value = 1;
  for (var i = 0; i < depth; i++) {
    value = [value];
  }
  return value;
}
