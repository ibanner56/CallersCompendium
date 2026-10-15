import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// The total byte budget on the user's glossary (entries and figure notes
/// together): [maxUserGlossaryBytes], enforced when a row is written.
///
/// The budget is a constructor parameter so the arithmetic is tested at a few
/// hundred bytes; the real constant is pinned against the backup file cap in
/// `app/test/data/backup_glossary_budget_test.dart`.
void main() {
  late CompendiumDatabase db;
  final created = DateTime.utc(2026, 10, 14, 9);

  setUp(() => db = CompendiumDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  UserGlossaryRepository entries(int maxBytes) =>
      UserGlossaryRepository(db, maxBytes: maxBytes);
  FigureNoteRepository notes(int maxBytes) =>
      FigureNoteRepository(db, maxBytes: maxBytes);

  UserGlossaryEntry entry(
    String id, {
    String kind = 'compound',
    String name = 'n',
    String definition = 'd',
    String description = 'd',
    List<String> keywords = const [],
    String? notes,
    Object? payload,
  }) => UserGlossaryEntry(
    id: id,
    kindName: kind,
    name: name,
    definition: definition,
    description: description,
    keywords: keywords,
    notes: notes,
    payload: payload,
    createdAt: created,
  );

  /// What [e] counts for, spelled out from the documented rule rather than
  /// read back from the code under test. Every value used here is already
  /// sanitised and in NFC, so the stored text is the text given.
  int weight(UserGlossaryEntry e) => glossaryRowBytes([
    e.id,
    e.kindName,
    e.name,
    e.definition,
    e.description,
    jsonEncode(e.keywords),
    e.notes,
    if (e.payload != null) jsonEncode(e.payload) else null,
  ]);

  int noteWeight(String figureId, String text) =>
      glossaryRowBytes([figureId, text]);

  Matcher overBudget() => isA<UserGlossaryEntryInvalid>()
      .having((e) => e.field, 'field', 'budget')
      .having((e) => e.isOverBudget, 'isOverBudget', isTrue);

  test(
    'the default budget is the documented constant, on both repositories',
    () {
      expect(maxUserGlossaryBytes, 4 * 1024 * 1024);
      expect(UserGlossaryRepository(db).maxBytes, maxUserGlossaryBytes);
      expect(FigureNoteRepository(db).maxBytes, maxUserGlossaryBytes);
      final repos = CompendiumRepositories(db, contraTaxonomy);
      expect(repos.userGlossary.maxBytes, maxUserGlossaryBytes);
      expect(repos.figureNotes.maxBytes, maxUserGlossaryBytes);
    },
  );

  test('a row counts for its text in UTF-8 bytes plus a fixed overhead', () {
    expect(glossaryRowBytes(const []), kGlossaryRowOverheadBytes);
    expect(
      glossaryRowBytes(const ['abc', null]),
      kGlossaryRowOverheadBytes + 3,
    );
    // Bytes, not UTF-16 units: 3 for a CJK character, 4 for an emoji (two
    // units).
    expect(glossaryRowBytes(const ['字']), kGlossaryRowOverheadBytes + 3);
    expect(glossaryRowBytes(const ['😀']), kGlossaryRowOverheadBytes + 4);
  });

  group('entries', () {
    test(
      'a write past the budget is refused as budget and stores nothing',
      () async {
        final a = entry('a');
        final b = entry('b');
        final glossary = entries(weight(a) + weight(b) - 1);
        await glossary.upsert(a);
        await expectLater(glossary.upsert(b), throwsA(overBudget()));
        expect((await glossary.listAll()).map((e) => e.id), ['a']);
        // Not a tombstone either: the write was rolled back whole.
        expect(
          (await glossary.listAll(includeDeleted: true)).map((e) => e.id),
          ['a'],
        );
      },
    );

    test('a write that lands exactly on the budget is stored', () async {
      final a = entry('a');
      final b = entry('b');
      final glossary = entries(weight(a) + weight(b));
      await glossary.upsert(a);
      await glossary.upsert(b);
      expect((await glossary.listAll()).map((e) => e.id), ['a', 'b']);
      await expectLater(glossary.upsert(entry('c')), throwsA(overBudget()));
    });

    // Each column, alone, must be counted: one left out of the sum lets that
    // column grow without limit, which is the hole being closed. The budget
    // sits one byte under the pair, so only an exact count refuses the second
    // write; and exactly on it, only an exact count accepts it.
    final heavy = <String, UserGlossaryEntry Function(String)>{
      'id': (_) => entry('i' * 200),
      'kind': (id) => entry(id, kind: 'k' * 200),
      'name': (id) => entry(id, name: 'n' * 200),
      'definition': (id) => entry(id, definition: 'd' * 3000),
      'description': (id) => entry(id, description: 'd' * 3000),
      'keywords': (id) => entry(id, keywords: ['k' * 200, 'j' * 200]),
      'notes': (id) => entry(id, notes: 'n' * 3000),
      'payload': (id) => entry(id, payload: {'pad': 'p' * 3000}),
      'definition in CJK': (id) => entry(id, definition: '字' * 1000),
      'definition in emoji': (id) => entry(id, definition: '😀' * 500),
    };
    for (final MapEntry(key: column, value: build) in heavy.entries) {
      test(
        'the $column of the other entries is counted, to the byte',
        () async {
          final a = build('a');
          final b = entry('b');
          final tight = entries(weight(a) + weight(b) - 1);
          await tight.upsert(a);
          await expectLater(tight.upsert(b), throwsA(overBudget()));

          // The same two, on a budget exactly their size, are both stored.
          final other = CompendiumDatabase(NativeDatabase.memory());
          addTearDown(other.close);
          final exact = UserGlossaryRepository(
            other,
            maxBytes: weight(a) + weight(b),
          );
          await exact.upsert(a);
          await exact.upsert(b);
          expect((await exact.listAll()).length, 2);
        },
      );
    }

    test(
      'an entry\'s own previous text is not counted twice on an edit',
      () async {
        final small = entry('a');
        final big = entry('a', definition: 'd' * 500);
        final glossary = entries(weight(big));
        await glossary.upsert(small);
        await glossary.upsert(big);
        await glossary.upsert(small);
        await glossary.upsert(big);
        expect((await glossary.getById('a'))!.definition, 'd' * 500);
      },
    );

    test('a refused edit leaves the stored entry as it was', () async {
      final a = entry('a');
      final glossary = entries(weight(a));
      await glossary.upsert(a, at: created);
      await expectLater(
        glossary.upsert(
          entry('a', definition: 'longer'),
          at: created.add(const Duration(days: 1)),
        ),
        throwsA(overBudget()),
      );
      final read = (await glossary.getById('a'))!;
      expect(read.definition, 'd');
      final row = await (db.select(
        db.userGlossaryEntries,
      )..where((t) => t.id.equals('a'))).getSingle();
      expect(row.updatedAt!.toUtc(), created);
    });

    test(
      'a deleted entry frees its room, and reviving it needs room again',
      () async {
        final a = entry('a');
        final b = entry('b');
        final glossary = entries(weight(a));
        await glossary.upsert(a, at: created);
        await glossary.delete('a', at: created.add(const Duration(days: 1)));
        await glossary.upsert(b, at: created.add(const Duration(days: 2)));
        // 'a' is a tombstone, so writing it again is a new write, and b fills the
        // budget.
        await expectLater(
          glossary.upsert(a, at: created.add(const Duration(days: 3))),
          throwsA(overBudget()),
        );
        expect((await glossary.listAll()).map((e) => e.id), ['b']);
      },
    );

    test('a glossary already over the budget can still be read, shrunk, '
        'rewritten and pruned, but not grown', () async {
      // Written before there was a budget: the roomy repository stands in.
      final roomy = entries(1 << 30);
      await roomy.upsert(entry('a', definition: 'd' * 400));
      await roomy.upsert(entry('b', definition: 'd' * 400));
      await roomy.upsert(entry('c', definition: 'd' * 400));
      final tight = entries(1);

      expect((await tight.listAll()).length, 3);

      // Smaller, and the same size, go through.
      await tight.upsert(entry('a', definition: 'd' * 399));
      await tight.upsert(entry('a', definition: 'e' * 399));
      expect((await tight.getById('a'))!.definition, 'e' * 399);

      // Larger, and a new entry, are refused even though the total is already
      // far past the budget.
      await expectLater(
        tight.upsert(entry('b', definition: 'd' * 401)),
        throwsA(overBudget()),
      );
      await expectLater(tight.upsert(entry('d')), throwsA(overBudget()));

      // A delete is not an upsert and is never refused.
      await tight.delete('c');
      expect((await tight.listAll()).map((e) => e.id), ['a', 'b']);
      // Still over, so still no new entry.
      await expectLater(tight.upsert(entry('d')), throwsA(overBudget()));
    });

    test('the refusal is distinct from a field bound', () async {
      final glossary = entries(1);
      await expectLater(
        glossary.upsert(entry('a')),
        throwsA(
          isA<UserGlossaryEntryInvalid>().having(
            (e) => e.field,
            'field',
            'budget',
          ),
        ),
      );
      await expectLater(
        glossary.upsert(entry('a', name: ' ')),
        throwsA(
          isA<UserGlossaryEntryInvalid>()
              .having((e) => e.field, 'field', 'name')
              .having((e) => e.isOverBudget, 'isOverBudget', isFalse),
        ),
      );
    });
  });

  test('rows applied from sync are not refused by the budget: a peer\'s row '
      'is applied or the devices never converge', () async {
    final glossary = entries(1);
    await glossary.writeFromSync(
      StoredUserGlossaryEntry(
        id: 'peer',
        kind: 'compound',
        name: 'n',
        definition: 'd' * 500,
        description: 'd',
        createdAt: created,
      ),
    );
    await notes(
      1,
    ).writeFromSync(const FigureNote(figureId: 'swing', notes: 'x'));
    expect((await glossary.getById('peer'))!.definition, 'd' * 500);
    expect((await notes(1).get('swing'))!.notes, 'x');
    // Over the budget now, so the editor's own path cannot add to it.
    await expectLater(glossary.upsert(entry('mine')), throwsA(overBudget()));
  });

  test('restoring is not held to the budget, but keeps every field bound, and '
      'what it leaves over the budget can be edited down, not grown', () async {
    final glossary = entries(1);
    await glossary.upsertFromRestore(entry('a', definition: 'd' * 500));
    await notes(1).setFromRestore('swing', 'n' * 500);
    expect((await glossary.getById('a'))!.definition, 'd' * 500);
    expect((await notes(1).get('swing'))!.notes, 'n' * 500);

    // The per-field bounds are the restore's own and still apply.
    await expectLater(
      glossary.upsertFromRestore(entry('b', name: ' ')),
      throwsA(
        isA<UserGlossaryEntryInvalid>().having((e) => e.field, 'field', 'name'),
      ),
    );
    await expectLater(
      notes(1).setFromRestore('swing', 'x' * (maxUserGlossaryTextLength + 1)),
      throwsA(
        isA<FigureNoteInvalid>().having(
          (e) => e.overBudget,
          'overBudget',
          false,
        ),
      ),
    );

    // The editor's own paths are still budgeted.
    await expectLater(glossary.upsert(entry('c')), throwsA(overBudget()));
    await expectLater(
      glossary.upsert(entry('a', definition: 'd' * 501)),
      throwsA(overBudget()),
    );
    await expectLater(
      notes(1).set('swing', 'n' * 501),
      throwsA(isA<FigureNoteInvalid>()),
    );
    await glossary.upsert(entry('a', definition: 'd' * 499));
    await notes(1).set('swing', 'n' * 499);
    expect((await glossary.getById('a'))!.definition, 'd' * 499);
  });

  group('figure notes share the budget', () {
    test('a note counts for its figure id and text, to the byte', () async {
      final a = entry('a');
      final tight = notes(weight(a) + noteWeight('swing', 'x') - 1);
      await entries(1 << 30).upsert(a);
      await expectLater(
        tight.set('swing', 'x'),
        throwsA(
          isA<FigureNoteInvalid>().having(
            (e) => e.overBudget,
            'overBudget',
            isTrue,
          ),
        ),
      );
      expect(await tight.listAll(includeDeleted: true), isEmpty);

      final exact = notes(weight(a) + noteWeight('swing', 'x'));
      await exact.set('swing', 'x');
      expect((await exact.get('swing'))!.notes, 'x');
    });

    test('notes count against entries, and entries against notes', () async {
      final a = entry('a');
      final both = weight(a) + noteWeight('swing', 'x');
      // A note first, then an entry that does not fit beside it.
      final glossary = entries(both - 1);
      await notes(both - 1).set('swing', 'x');
      await expectLater(glossary.upsert(a), throwsA(overBudget()));
      // And the other way: the entry's bytes make no room for the note.
      final other = CompendiumDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await UserGlossaryRepository(other, maxBytes: both - 1).upsert(a);
      await expectLater(
        FigureNoteRepository(other, maxBytes: both - 1).set('swing', 'x'),
        throwsA(
          isA<FigureNoteInvalid>().having(
            (e) => e.overBudget,
            'overBudget',
            isTrue,
          ),
        ),
      );
    });

    test('a note replaced by a shorter one, or a deleted one, is never refused '
        'when the glossary is over the budget', () async {
      final roomy = notes(1 << 30);
      await roomy.set('swing', 'n' * 300);
      final tight = notes(1);
      await tight.set('swing', 'n' * 299);
      await expectLater(
        tight.set('swing', 'n' * 300),
        throwsA(
          isA<FigureNoteInvalid>().having(
            (e) => e.overBudget,
            'overBudget',
            isTrue,
          ),
        ),
      );
      await expectLater(
        tight.set('balance', 'x'),
        throwsA(isA<FigureNoteInvalid>()),
      );
      await tight.set('swing', '');
      expect(await tight.listAll(), isEmpty);
    });

    test('deleting a note frees its room', () async {
      final a = entry('a');
      final both = weight(a) + noteWeight('swing', 'x');
      await notes(both).set('swing', 'x');
      await expectLater(
        entries(both - 1).upsert(entry('a', definition: 'dd')),
        throwsA(overBudget()),
        reason: 'the note takes the room an entry needs',
      );
      await notes(both).delete('swing');
      // A tombstone is not in the backup, so it counts for nothing.
      await entries(weight(a)).upsert(a);
      expect(await entries(weight(a)).getById('a'), isNotNull);
    });

    test(
      'an over-long note is still refused for length, not for budget',
      () async {
        await expectLater(
          notes(1 << 30).set('swing', 'x' * (maxUserGlossaryTextLength + 1)),
          throwsA(
            isA<FigureNoteInvalid>().having(
              (e) => e.overBudget,
              'overBudget',
              isFalse,
            ),
          ),
        );
      },
    );
  });
}
