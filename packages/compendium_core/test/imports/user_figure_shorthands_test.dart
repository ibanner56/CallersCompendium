import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Shorthands for the user's own new figures (#1023): tokens that insert a
/// use of one of their figures with fixed values.
void main() {
  Map<String, Object?> entry({
    Object? token = 'ZM',
    Object? figure = 'zoom-id',
    Object? name = 'zoom',
    Object? args = const {'who': 'neighbors', 'pace': 'c1'},
    Object? beats,
  }) => {
    'token': token,
    'figure': figure,
    'name': name,
    'args': args,
    'beats': ?beats,
  };

  group('decode', () {
    test('round-trips what it encodes, beats or none', () {
      final shorthands = [
        UserFigureShorthand(
          token: 'ZM',
          figureId: 'zoom-id',
          figureName: 'zoom',
          args: const {'who': 'neighbors', 'fast': true, 'count': 2},
          beats: 6,
        ),
        UserFigureShorthand(
          token: 'zz',
          figureId: 'zoom-id',
          figureName: 'zoom',
        ),
      ];
      final store = UserFigureShorthands(shorthands);
      expect(store.toJson().last, isNot(contains('beats')));
      final decoded = UserFigureShorthands.decode(jsonEncode(store.toJson()));
      expect(decoded.shorthands, shorthands);
      expect(
        UserFigureShorthands.decode(store.toJson()).shorthands,
        shorthands,
      );
    });

    test('never throws, and keeps an entry only whole', () {
      for (final bad in <Object?>[
        null,
        42,
        '{not json',
        {'token': 'x'},
      ]) {
        expect(
          UserFigureShorthands.decode(bad).isEmpty,
          isTrue,
          reason: '$bad',
        );
      }
      // Each bad entry has a token of its own, so it is dropped for what is
      // wrong with it, not as a second use of a token.
      final kept = UserFigureShorthands.decode([
        entry(),
        entry(token: '   '),
        entry(token: 'x' * (maxShorthandTokenLength + 1)),
        entry(token: 7),
        entry(token: 'bad1', figure: ''),
        entry(token: 'bad2', figure: 'not an id!'),
        entry(token: 'bad3', name: ''),
        entry(token: 'bad4', args: 'who=neighbors'),
        entry(
          token: 'bad5',
          args: {for (var i = 0; i <= maxUserFigureParams; i++) 'p$i': 'v'},
        ),
        entry(
          token: 'bad6',
          args: {
            'who': const ['neighbors'],
          },
        ),
        entry(
          token: 'bad7',
          args: {'text': 'x' * (maxUserFigureTextArgLength + 1)},
        ),
        entry(token: 'bad8', beats: -1),
        entry(token: 'bad9', beats: maxUserFigureDefaultBeats + 1),
        entry(token: 'bad10', beats: 'eight'),
        'not a map',
      ]);
      expect([for (final s in kept.shorthands) s.token], ['ZM']);
    });

    test('a token already taken keeps its first entry, ignoring case', () {
      final store = UserFigureShorthands.decode([
        entry(figure: 'first'),
        entry(token: ' zm ', figure: 'second'),
      ]);
      expect([for (final s in store.shorthands) s.figureId], ['first']);
    });

    test('keeps at most the bound', () {
      final store = UserFigureShorthands.decode([
        for (var i = 0; i < maxUserFigureShorthands + 5; i++)
          entry(token: 't$i'),
      ]);
      expect(store.shorthands, hasLength(maxUserFigureShorthands));
    });

    test('keeps beats of 0, as a figure\'s own default beats may be', () {
      expect(
        UserFigureShorthands.decode([entry(beats: 0)]).shorthands.single.beats,
        0,
      );
    });

    test('keeps only what a use could hold, so the line it inserts stays a '
        'use', () {
      for (final shorthand in UserFigureShorthands.decode([
        entry(),
        entry(token: 'b', beats: 4),
      ]).shorthands) {
        final use = userFigureUseOf(
          userFigureUseFigure(
            id: shorthand.figureId,
            args: shorthand.args,
            text: 'line',
            beats: shorthand.beats,
          ),
        );
        expect(use, isNotNull);
        expect(use!.attached, isTrue);
      }
    });
  });

  test('resolves a whole line, ignoring case and surrounding space', () {
    final store = UserFigureShorthands.decode([entry()]);
    expect(store.resolve('  zm ')?.figureId, 'zoom-id');
    expect(store.resolve('zm twice'), isNull);
    expect(store.resolve(''), isNull);
  });

  group('sync', () {
    test('is a whole collection, compared and combined token by token, held '
        'to the same bound', () {
      expect(
        syncWholeCollectionSettingKeys,
        contains('user_figure_shorthands'),
      );
      expect(
        syncCollectionLimit('user_figure_shorthands'),
        maxUserFigureShorthands,
      );
      final diff = compareSyncCollection(
        'user_figure_shorthands',
        [entry(), entry(token: 'mine')],
        [
          entry(token: 'zm', args: const {'who': 'partners'}),
          entry(token: 'theirs'),
        ],
      )!;
      expect([for (final e in diff.onlyLocal) e.label], ['mine']);
      expect([for (final e in diff.onlyOther) e.label], ['theirs']);
      expect([for (final c in diff.changed) c.local.key], ['zm']);
    });

    test('waits for every device to read the figures themselves', () {
      expect(
        SyncCapabilityPolicy.build.capabilityFor(
          SyncRecordKind.setting,
          userFigureShorthandsSettingKey,
        ),
        SyncCapabilities.glossaryV2,
      );
    });

    test('is shareable, so a server built with this registry accepts it', () {
      expect(
        classifySettingsKey(userFigureShorthandsSettingKey)?.egress,
        EgressClass.shareable,
      );
    });
  });
}
