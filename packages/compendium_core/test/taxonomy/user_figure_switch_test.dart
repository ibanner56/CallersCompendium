import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Switching the uses of a figure of your own to the shipped figure of the
/// same name (#1023, maintainer decision 5).
void main() {
  final taxonomy = contraTaxonomy;
  final renderer = FigureRenderer(taxonomy);

  // A user's "swing" made before the app shipped one: who, a choice of
  // prefix (no default), 16 beats by default.
  final mine = UserFigureDefinition(
    template: '{who} [{prefix}] {move}',
    defaultBeats: 16,
    params: [
      UserFigureParam(
        key: 'who',
        kind: ParamKind.dancerSet,
        defaultValue: 'neighbors',
      ),
      UserFigureParam(
        key: 'prefix',
        kind: ParamKind.choice,
        choices: [
          UserFigureChoice(id: 'cbal', label: 'balance'),
          UserFigureChoice(id: 'cmelt', label: 'meltdown'),
        ],
      ),
    ],
  );
  final complete = UserFigureSwitch(
    target: 'swing',
    params: {'who': 'who', 'prefix': 'prefix'},
    choices: {
      'prefix': {'cbal': 'balance', 'cmelt': 'meltdown'},
    },
  );

  Figure use(Map<String, Object?> args, {int? beats, String? text}) {
    final draft = userFigureUseFigure(
      id: 'mine',
      args: args,
      text: 'placeholder',
      beats: beats,
    );
    final line =
        text ??
        FigureRenderer(
          taxonomy,
          userFigures: _catalog(mine),
        ).renderUserFigureCanonical(draft)!;
    return userFigureUseFigure(
      id: 'mine',
      args: args,
      text: line,
      beats: beats,
    );
  }

  List<Figure> switchAll(List<Figure> figures, [UserFigureSwitch? mapping]) =>
      switchUserFigureUsesIn(
        figures,
        'mine',
        mine,
        mapping ?? complete,
        taxonomy,
        FigureRenderer(taxonomy, userFigures: _catalog(mine)),
      );

  group('shippedFigureNamed', () {
    test('finds a move by display name or id, ignoring case and spacing', () {
      expect(shippedFigureNamed('Swing', taxonomy), 'swing');
      expect(shippedFigureNamed('  SWING ', taxonomy), 'swing');
      expect(shippedFigureNamed('box_the_gnat', taxonomy), 'box_the_gnat');
    });

    test('finds an alias, and a move before an alias of the same name', () {
      expect(shippedFigureNamed('meltdown swing', taxonomy), 'meltdown_swing');
      // Two aliases and the move are all named "pull by": the move wins.
      expect(shippedFigureNamed('pull by', taxonomy), 'pull_by');
    });

    test('a keyword, the custom move or nothing is no name', () {
      expect(shippedFigureNamed('zoom zoom', taxonomy), isNull);
      expect(shippedFigureNamed(customMoveId, taxonomy), isNull);
      expect(shippedFigureNamed('', taxonomy), isNull);
    });
  });

  group('targets and values', () {
    test('a parameter maps to one of the same kind, never to beats', () {
      expect(userFigureSwitchTargets(mine.params.first, 'swing', taxonomy), [
        'who',
      ]);
      expect(
        userFigureSwitchTargets(
          UserFigureParam(key: 'hand', kind: ParamKind.handedness),
          'allemande',
          taxonomy,
        ),
        ['hand'],
      );
      expect(
        userFigureSwitchTargets(
          UserFigureParam(key: 'n', kind: ParamKind.beats),
          'swing',
          taxonomy,
        ),
        isEmpty,
      );
    });

    test('a choice maps to any parameter with a list of values', () {
      expect(userFigureSwitchTargets(mine.params[1], 'swing', taxonomy), [
        'prefix',
        'endFacing',
      ]);
      expect(userFigureSwitchTargets(mine.params[1], 'balance', taxonomy), [
        'hand',
      ], reason: 'a handedness with its own list of values');
    });

    test('"not stated" is never a value to map to', () {
      expect(userFigureSwitchValues('balance', 'hand', taxonomy), [
        'right',
        'left',
      ]);
    });

    test('an unknown target offers nothing', () {
      expect(userFigureSwitchTargets(mine.params.first, 'nope', taxonomy), []);
      expect(userFigureSwitchValues('nope', 'who', taxonomy), isEmpty);
    });
  });

  group('userFigureSwitchProblems', () {
    test('a complete mapping has none', () {
      expect(userFigureSwitchProblems(mine, complete, taxonomy), isEmpty);
    });

    test('every parameter must be mapped', () {
      final problems = userFigureSwitchProblems(
        mine,
        UserFigureSwitch(
          target: 'swing',
          params: {'prefix': 'prefix'},
          choices: complete.choices,
        ),
        taxonomy,
      );
      expect(problems, ['"who" is not mapped']);
    });

    test('every choice value must be mapped, to a value the target has', () {
      expect(
        userFigureSwitchProblems(
          mine,
          UserFigureSwitch(
            target: 'swing',
            params: complete.params,
            choices: {
              'prefix': {'cbal': 'balance'},
            },
          ),
          taxonomy,
        ),
        ['"prefix" choice "cmelt" is not mapped'],
      );
      expect(
        userFigureSwitchProblems(
          mine,
          UserFigureSwitch(
            target: 'swing',
            params: complete.params,
            choices: {
              'prefix': {'cbal': 'balance', 'cmelt': 'unspecified'},
            },
          ),
          taxonomy,
        ),
        ['"prefix" choice "cmelt" cannot map to "unspecified"'],
      );
    });

    test('a parameter maps to a target of its kind, and only once', () {
      expect(
        userFigureSwitchProblems(
          mine,
          UserFigureSwitch(
            target: 'swing',
            params: {'who': 'prefix', 'prefix': 'prefix'},
            choices: complete.choices,
          ),
          taxonomy,
        ),
        ['"who" cannot map to "prefix"'],
      );
      final two = UserFigureDefinition(
        template: '{a} {b} {move}',
        defaultBeats: 8,
        params: [
          UserFigureParam(key: 'a', kind: ParamKind.dancerSet),
          UserFigureParam(key: 'b', kind: ParamKind.dancerSet),
        ],
      );
      expect(
        userFigureSwitchProblems(
          two,
          UserFigureSwitch(target: 'swing', params: {'a': 'who', 'b': 'who'}),
          taxonomy,
        ),
        ['"who" is mapped twice'],
      );
    });

    test('the target must be a shipped figure', () {
      for (final target in ['nope', customMoveId]) {
        expect(
          userFigureSwitchProblems(
            mine,
            UserFigureSwitch(target: target, params: complete.params),
            taxonomy,
          ),
          hasLength(1),
          reason: target,
        );
      }
    });
  });

  group('switchUserFigureUsesIn', () {
    test('a use becomes the shipped figure, its values mapped', () {
      final switched = switchAll([
        Figure(
          move: customMoveId,
          params: use({'who': 'partners', 'prefix': 'cbal'}).params,
          note: 'mind the wall',
          progression: true,
        ),
      ]).single;
      expect(switched.move, 'swing');
      expect(
        switched.params,
        {'who': 'partners', 'prefix': 'balance'},
        reason:
            'my 16 beats are what a balance and swing counts already, so '
            'they are not stated',
      );
      expect(taxonomy.effectiveParams(switched)['beats'], 16);
      expect(switched.note, 'mind the wall');
      expect(switched.progression, isTrue);
      expect(hasUserFigureReferenceKeys(switched), isFalse);
    });

    test('a value the use leaves unstated takes the figure\'s default, or '
        'the target\'s', () {
      final switched = switchAll([use(const {}, beats: 8)]).single;
      expect(
        switched.params,
        {'who': 'neighbors'},
        reason:
            'who from my default; no prefix, so swing\'s; 8 beats is '
            'swing\'s own, so not stated',
      );
      expect(renderer.renderCanonical(switched), contains('swing'));
    });

    test('beats are stated only where the target counts differently', () {
      expect(
        switchAll([
          use(const {'who': 'partners'}),
        ]).single.params['beats'],
        16,
        reason: 'my default beats, not swing\'s 8',
      );
      expect(
        switchAll([
          use(const {'who': 'partners'}, beats: 8),
        ]).single.params.containsKey('beats'),
        isFalse,
      );
    });

    test('a detached use is plain text, its stored line kept', () {
      final edited =
          userFigureUseFigure(
            id: 'mine',
            args: const {'who': 'partners'},
            text: 'partners swing',
          ).copyWith(
            params: {
              ...use(const {'who': 'partners'}).params,
              'text': 'partners swing twice',
            },
          );
      expect(userFigureUseOf(edited)!.attached, isFalse);
      final switched = switchAll([edited]).single;
      expect(switched.move, customMoveId);
      expect(switched.params, {'text': 'partners swing twice'});
    });

    test('a use whose choice is no longer the figure\'s is frozen', () {
      final stale = use(const {'prefix': 'cgone'}, text: 'neighbors swing');
      final switched = switchAll([stale]).single;
      expect(switched.move, customMoveId);
      expect(hasUserFigureReferenceKeys(switched), isFalse);
      expect(switched.params['text'], 'neighbors swing');
    });

    test('a value the target refuses freezes the use', () {
      // Mapped as complete, but the target's "who" can't hold a dancer set
      // the user's own could.
      final narrow = UserFigureDefinition(
        template: '{who} {move}',
        defaultBeats: 4,
        params: [UserFigureParam(key: 'who', kind: ParamKind.handedness)],
      );
      final figure = userFigureUseFigure(
        id: 'mine',
        args: const {'who': 'right'},
        text: 'right balance',
      );
      final switched = switchUserFigureUsesIn(
        [figure],
        'mine',
        narrow,
        UserFigureSwitch(target: 'balance', params: {'who': 'hand'}),
        taxonomy,
        renderer,
      ).single;
      expect(switched.move, 'balance', reason: 'right is a hand balance has');
      final refused = switchUserFigureUsesIn(
        [
          userFigureUseFigure(
            id: 'mine',
            args: const {'who': 'unspecified'},
            text: 'balance',
          ),
        ],
        'mine',
        narrow,
        UserFigureSwitch(target: 'balance', params: {'who': 'hand'}),
        taxonomy,
        renderer,
      ).single;
      expect(refused.move, customMoveId);
      expect(refused.params, {'text': 'balance'});
    });

    test('a mapped value the target doesn\'t have freezes the use', () {
      // Not a mapping the editor would offer, which checks the values: the
      // switch checks each use's own all the same.
      final switched = switchAll(
        [
          use(const {'prefix': 'cbal'}),
        ],
        UserFigureSwitch(
          target: 'swing',
          params: complete.params,
          choices: {
            'prefix': {'cbal': 'twirl', 'cmelt': 'meltdown'},
          },
        ),
      ).single;
      expect(switched.move, customMoveId);
      expect(hasUserFigureReferenceKeys(switched), isFalse);
    });

    test('uses inside containers switch; other figures stay as they are', () {
      final plain = Figure(move: 'allemande');
      final other = userFigureUseFigure(
        id: 'theirs',
        args: const {},
        text: 'whirl',
      );
      final figures = [
        plain,
        other,
        Figure.meanwhile(
          figures: [
            use(const {'who': 'partners'}),
            Figure(move: 'balance'),
          ],
          beats: 16,
        ),
      ];
      final switched = switchAll(figures);
      expect(switched[0], same(plain));
      expect(switched[1], same(other));
      expect(switched[2].subFigures.first.move, 'swing');
      final untouched = [plain, other];
      expect(switchAll(untouched), same(untouched));
    });
  });
}

UserFigureCatalog _catalog(UserFigureDefinition definition) =>
    UserFigureCatalog.fromEntries([
      UserGlossaryEntry(
        id: 'mine',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'swing',
        definition: 'Mine.',
        description: 'Mine.',
        payload: definition.toJson(),
        createdAt: DateTime.utc(2026),
      ),
    ]);
