import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Compound shorthands (#709): tokens that stand for one of the user's own
/// compound figures with fixed values.
void main() {
  Map<String, Object?> entry({
    Object? token = 'GRL',
    Object? compound = 'grl',
    Object? name = 'grand right and left',
    Object? args = const {'who': 'neighbors', 'hand': 'right'},
  }) => {'token': token, 'compound': compound, 'name': name, 'args': args};

  group('decode', () {
    test('round-trips what it encodes', () {
      final shorthand = CompoundShorthand(
        token: 'GRL',
        compoundId: 'grl',
        compoundName: 'grand right and left',
        args: const {'who': 'neighbors', 'hand': 'right', 'balance': true},
      );
      final store = CompoundShorthands([shorthand]);
      final decoded = CompoundShorthands.decode(jsonEncode(store.toJson()));
      expect(decoded.shorthands, [shorthand]);
      expect(CompoundShorthands.decode(store.toJson()).shorthands, [shorthand]);
    });

    test('never throws, and keeps an entry only whole', () {
      for (final bad in <Object?>[
        null,
        42,
        '{not json',
        {'token': 'x'},
      ]) {
        expect(CompoundShorthands.decode(bad).isEmpty, isTrue, reason: '$bad');
      }
      // Each bad entry has a token of its own, so it is dropped for what is
      // wrong with it, not as a second use of a token.
      final kept = CompoundShorthands.decode([
        entry(),
        entry(token: '   '),
        entry(token: 'x' * (maxShorthandTokenLength + 1)),
        entry(token: 7),
        entry(token: 'bad1', compound: ''),
        entry(token: 'bad2', name: ''),
        entry(token: 'bad3', args: 'hand=right'),
        entry(
          token: 'bad4',
          args: {for (var i = 0; i <= maxCompoundParams; i++) 'p$i': 'v'},
        ),
        entry(token: 'bad5', args: {'': 'v'}),
        entry(
          token: 'bad6',
          args: {
            'hand': const ['right'],
          },
        ),
        entry(
          token: 'bad7',
          args: {'text': 'x' * (maxCompoundShorthandTextArgLength + 1)},
        ),
        'not a map',
      ]);
      expect([for (final s in kept.shorthands) s.token], ['GRL']);
    });

    test('a token already taken keeps its first entry, ignoring case', () {
      final store = CompoundShorthands.decode([
        entry(compound: 'first'),
        entry(token: ' grl ', compound: 'second'),
      ]);
      expect([for (final s in store.shorthands) s.compoundId], ['first']);
    });

    test('keeps at most the bound', () {
      final store = CompoundShorthands.decode([
        for (var i = 0; i < maxCompoundShorthands + 5; i++) entry(token: 't$i'),
      ]);
      expect(store.shorthands, hasLength(maxCompoundShorthands));
    });
  });

  test('resolves a whole line, ignoring case and surrounding space', () {
    final store = CompoundShorthands.decode([entry()]);
    expect(store.resolve('  grl ')?.compoundId, 'grl');
    expect(store.resolve('grl twice'), isNull);
    expect(store.resolve(''), isNull);
  });

  group('sync', () {
    test('is a whole collection, compared and combined token by token, held '
        'to the same bound', () {
      expect(syncWholeCollectionSettingKeys, contains('compound_shorthands'));
      expect(syncCollectionLimit('compound_shorthands'), maxCompoundShorthands);
      final diff = compareSyncCollection(
        'compound_shorthands',
        [entry(), entry(token: 'mine')],
        [
          entry(token: 'grl', args: const {'who': 'partners', 'hand': 'left'}),
          entry(token: 'theirs'),
        ],
      )!;
      expect([for (final e in diff.onlyLocal) e.label], ['mine']);
      expect([for (final e in diff.onlyOther) e.label], ['theirs']);
      expect([for (final c in diff.changed) c.local.key], ['grl']);
    });

    test('waits for every device to read the glossary', () {
      expect(
        SyncCapabilityPolicy.build.capabilityFor(
          SyncRecordKind.setting,
          compoundShorthandsSettingKey,
        ),
        SyncCapabilities.glossaryV1,
      );
    });
  });
}
