import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Conditional wording: `[if … then … else …]` (wording_conditions.dart).
void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final larks = Dialect.larksRobins;
  final swing = renderer.moveWordingVocabulary('swing', larks);

  String? stored(String text, [WordingVocabulary? vocabulary]) =>
      checkWording(text, vocabulary ?? swing).stored;

  WordingIssue? errorOf(String text, [WordingVocabulary? vocabulary]) =>
      checkWording(text, vocabulary ?? swing).error;

  String renderSwing(String display, Map<String, Object?> params) {
    final check = checkWording(display, swing);
    expect(check.error, isNull, reason: '$display: ${check.error}');
    return renderer.render(
      Figure(move: 'swing', params: params),
      larks.copyWith(moveWordings: {'swing': check.stored!}),
    );
  }

  group('stored form', () {
    test('a template with no condition is stored exactly as typed', () {
      for (final text in [
        '{who} {move}',
        '[{who} ]{move}',
        '  {move}  [and [{prefix}]] ',
        'if you like {move}',
        '{!prefix} {move}',
      ]) {
        expect(stored(text), text, reason: text);
      }
    });

    test('a condition is stored by meaning, inside a marker', () {
      expect(
        stored('[if who is robins then robins swing else {who} swing]'),
        "[{?if who is 'role2s'}robins swing{?else}{who} swing]",
      );
      expect(
        stored(
          '[if who is in (neighbors, next neighbors) and not prefix is none '
          'then x]',
        ),
        "[{?if who is in ('neighbors', 'nextNeighbors') and "
        "not prefix is 'none'}x]",
      );
    });

    test('renaming a role does not change what a stored condition tests', () {
      final kept = stored('[if who is robins then R else O]')!;
      final ravens = larks.copyWith(
        roles: {
          'role1': const RoleTerm('Lark'),
          'role2': const RoleTerm('Raven'),
        },
      );
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'role2s'}),
          ravens.copyWith(moveWordings: {'swing': kept}),
        ),
        'R',
      );
      // And it is shown in the new words when edited.
      expect(
        wordingForEditing(
          kept,
          renderer.moveWordingVocabulary('swing', ravens),
        ),
        '[if who is Ravens then R else O]',
      );
    });

    test('reads back to the display form it was saved from', () {
      for (final text in [
        '[if who is robins then robins swing else {who} swing]',
        '[if prefix is balance then balance and ]{who} swing',
        '[if who is partners then partner swing else if who is in '
            '(neighbors, next neighbors) then neighbor swing else {who} swing]',
        '[if (who is robins or who is larks) and beats is more than 8 then '
            'long {move}]',
        '[if not beats is at most 8 then x else  y]',
        '[if beats is not in (8, 16) then odd]',
        '[if endFacing is in then in else [if endFacing is in (up, down) '
            'then vertical]]',
        '[if who is empty then {move} else {who} {move}]',
        '[if who then a then b]',
      ]) {
        final saved = stored(text);
        expect(saved, isNotNull, reason: '$text: ${errorOf(text)}');
        expect(wordingForEditing(saved!, swing), text, reason: text);
        expect(stored(wordingForEditing(saved, swing)), saved, reason: text);
      }
    });

    test('a stored template only reads when well formed', () {
      for (final bad in [
        '[{?if who is}x]',
        "[{?if who is 'role2s'}x",
        "{?if who is 'role2s'}x",
        "[{?if who is 'role2s' and beats or prefix}x]",
        "[x{?else}y]",
        "[{?if who is robins}x]",
        "[{?if not}x]",
        "[{?if who is not more than 8}x]",
      ]) {
        expect(
          FigureRenderer.isValidMoveWordingTemplate(bad),
          isFalse,
          reason: bad,
        );
      }
      expect(
        FigureRenderer.isValidMoveWordingTemplate(
          "[{?if who is 'role2s'}x{?else if beats is at most 8}y{?else}z]",
        ),
        isTrue,
      );
    });

    test('an older build refuses every stored condition, so falls back', () {
      // The validator every build before conditions shipped with: a brace
      // must hold `!?\w+`.
      bool olderBuildAccepts(String template) {
        var depth = 0;
        for (var i = 0; i < template.length; i++) {
          final char = template[i];
          if (char == '[') {
            depth++;
          } else if (char == ']') {
            if (depth == 0) return false;
            depth--;
          } else if (char == '{') {
            final close = template.indexOf('}', i + 1);
            if (close < 0) return false;
            if (!RegExp(
              r'^!?\w+$',
            ).hasMatch(template.substring(i + 1, close))) {
              return false;
            }
            i = close;
          } else if (char == '}') {
            return false;
          }
        }
        return depth == 0;
      }

      for (final text in [
        '[if prefix then x]',
        '[if who is robins then a else b]',
        '{move}[if beats is 8 then !]',
      ]) {
        expect(olderBuildAccepts(stored(text)!), isFalse, reason: text);
      }
      expect(olderBuildAccepts(stored('[{who} ]{move}')!), isTrue);
    });
  });

  group('rendering a dialect wording', () {
    const display =
        '[if who is partners then partner swing else if who is in '
        '(neighbors, next neighbors) then neighbor swing else {who} swing]';

    test('shows the wording of the first condition that holds', () {
      expect(renderSwing(display, {'who': 'partners'}), 'partner swing');
      expect(renderSwing(display, {'who': 'nextNeighbors'}), 'neighbor swing');
      expect(renderSwing(display, {'who': 'role2s'}), 'robins swing');
    });

    test('with no else, shows nothing when no condition holds', () {
      const text = '[if prefix is balance then balance and ]{who} {move}';
      expect(
        renderSwing(text, {'prefix': 'balance'}),
        'balance and partner swing',
      );
      expect(renderSwing(text, {'prefix': 'none'}), 'partner swing');
    });

    test('numbers compare, and a choice of value is in or not', () {
      const text =
          '[if beats is more than 8 then long else short] '
          '[if endFacing is not in (up, down) then flat]';
      expect(renderSwing(text, {'beats': 16}), 'long flat');
      expect(renderSwing(text, {'beats': 8, 'endFacing': 'up'}), 'short');
    });

    test('and, or, not and parentheses', () {
      const text =
          '[if (who is robins or who is larks) and not prefix is none '
          'then role prefix else other]';
      expect(
        renderSwing(text, {'who': 'role1s', 'prefix': 'balance'}),
        'role prefix',
      );
      expect(renderSwing(text, {'who': 'role1s'}), 'other');
      expect(
        renderSwing(text, {'who': 'partners', 'prefix': 'balance'}),
        'other',
      );
    });

    test('a condition never adds a slot: values are text', () {
      final dialect = larks.copyWith(
        dancers: {'neighbors': '[if who then {move}]'},
      );
      final vocabulary = renderer.moveWordingVocabulary('swing', dialect);
      final saved = checkWording(
        '[if who then {who} ]swing',
        vocabulary,
      ).stored!;
      expect(
        renderer.render(
          Figure(move: 'swing', params: {'who': 'neighbors'}),
          dialect.copyWith(moveWordings: {'swing': saved}),
        ),
        '[if who then {move}] swing',
      );
    });

    test('a stored condition that does not fit the move is not used', () {
      final normal = renderer.render(Figure(move: 'swing'), larks);
      for (final unfit in [
        "[{?if nobody}x]",
        "[{?if who is 'clockwise'}x]",
        "[{?if who is more than 3}x]",
        "[{?if beats is 'role2s'}x]",
        "[{?if beats is 100}x]",
      ]) {
        expect(
          renderer.render(
            Figure(move: 'swing'),
            larks.copyWith(moveWordings: {'swing': unfit}),
          ),
          normal,
          reason: unfit,
        );
      }
    });

    test('a slot that is only text is tested for whether it is filled', () {
      final wave = renderer.moveWordingVocabulary('form_a_long_wave', larks);
      final check = checkWording(
        '[if subject is empty then {move} else {subject}]{balance}',
        wave,
      );
      expect(check.error, isNull);
      expect(
        checkWording('[if subject is Robins then x]', wave).error?.code,
        WordingIssueCode.presenceOnly,
      );
    });
  });

  group('a figure of your own', () {
    final definition = UserFigureDefinition(
      template: '{who} {move}',
      defaultBeats: 8,
      params: [
        UserFigureParam(
          key: 'who',
          kind: ParamKind.dancerSet,
          defaultValue: 'neighbors',
        ),
        UserFigureParam(
          key: 'style',
          kind: ParamKind.choice,
          choices: const [
            UserFigureChoice(id: 'a1', label: 'rock'),
            UserFigureChoice(id: 'a2', label: 'rock and roll'),
            UserFigureChoice(id: 'a3', label: 'not sure'),
            UserFigureChoice(id: 'a4', label: 'sure'),
            UserFigureChoice(id: 'a5', label: 'empty'),
          ],
        ),
        UserFigureParam(key: 'roll', kind: ParamKind.flag, label: 'roll'),
        UserFigureParam(key: 'note', kind: ParamKind.text),
      ],
    );
    final vocabulary = renderer.userFigureWordingVocabulary(definition, larks);

    String renderMine(String display, Map<String, Object?> args) {
      final check = checkWording(display, vocabulary);
      expect(check.error, isNull, reason: '$display: ${check.error}');
      final mine = UserFigureDefinition(
        template: check.stored!,
        defaultBeats: 8,
        params: definition.params,
      );
      expect(
        validateUserFigure(
          mine,
        ).where((i) => i.severity == ValidationSeverity.error),
        isEmpty,
      );
      final catalogued = FigureRenderer(
        contraTaxonomy,
        userFigures: _catalog(mine),
      );
      return catalogued.render(
        userFigureUseFigure(id: 'mine', args: args, text: ''),
        larks,
      );
    }

    test('tests an opposite, as it tests the parameter', () {
      const text = '[if otherWho is Larks then larks lead else {who} lead]';
      expect(renderMine(text, {'who': 'role2s'}), 'larks lead');
      expect(renderMine(text, {'who': 'role1s'}), 'larks lead');
      // A subject reads singular, as everywhere.
      expect(renderMine(text, {'who': 'partners'}), 'partner lead');
    });

    test('tests beats and a choice by its label, stored by its id', () {
      final check = checkWording(
        '[if style is in (rock and roll, sure) and beats is at least 8 then x]',
        vocabulary,
      );
      expect(
        check.stored,
        "[{?if style is in ('a2', 'a4') and beats is at least 8}x]",
      );
      const text = '[if style is sure and beats is at least 8 then x else y]';
      expect(renderMine(text, {'style': 'a4'}), 'x');
      expect(renderMine(text, {'style': 'a1'}), 'y');
    });

    test(
      'canonicalizing a template never reaches inside a stored condition',
      () {
        // A dialect whose role word is also a dancer token would otherwise
        // rewrite the value a condition tests.
        expect(
          mapUserFigureTemplateText(
            "neighbors [{?if who is 'neighbors'}neighbors{?else}x] {who}",
            (text) => text.replaceAll('neighbors', 'role1s'),
          ),
          "role1s [{?if who is 'neighbors'}role1s{?else}x] {who}",
        );
      },
    );

    test('a condition counts its name as used', () {
      final saved = checkWording(
        '[if roll then rolled ]{move}',
        vocabulary,
      ).stored!;
      final mine = UserFigureDefinition(
        template: saved,
        defaultBeats: 8,
        params: definition.params,
      );
      expect(mine.unusedParams, containsAll(['who', 'style', 'note']));
      expect(mine.unusedParams, isNot(contains('roll')));
    });

    test('a condition that does not fit is an error, not a silent change', () {
      final mine = UserFigureDefinition(
        template: "[{?if style is 'zz'}x]",
        defaultBeats: 8,
        params: definition.params,
      );
      expect(
        validateUserFigure(mine).map((i) => i.code),
        contains(UserFigureIssueCodes.badCondition),
      );
    });

    test('a parameter may not be named a reserved word, but may be "in"', () {
      for (final word in wordingReservedWords) {
        final mine = UserFigureDefinition(
          template: '{move}',
          defaultBeats: 8,
          params: [
            UserFigureParam(key: word.toUpperCase(), kind: ParamKind.flag),
          ],
        );
        expect(
          validateUserFigure(mine).map((i) => i.code),
          contains(UserFigureIssueCodes.badParamKey),
          reason: word,
        );
      }
      for (final word in [
        'in',
        'empty',
        'more',
        'than',
        'at',
        'least',
        'most',
      ]) {
        final mine = UserFigureDefinition(
          template: '{move}{$word}',
          defaultBeats: 8,
          params: [UserFigureParam(key: word, kind: ParamKind.flag)],
        );
        expect(
          validateUserFigure(
            mine,
          ).where((i) => i.severity == ValidationSeverity.error),
          isEmpty,
          reason: word,
        );
      }
    });
  });

  group('words read by where they stand', () {
    // Every operator word is a parameter name here, and a value too.
    final tricky = renderer.userFigureWordingVocabulary(
      UserFigureDefinition(
        template: '{move}',
        defaultBeats: 8,
        params: [
          UserFigureParam(
            key: 'in',
            kind: ParamKind.choice,
            choices: const [
              UserFigureChoice(id: 'c1', label: 'at'),
              UserFigureChoice(id: 'c2', label: 'least'),
              UserFigureChoice(id: 'c3', label: 'in'),
              UserFigureChoice(id: 'c4', label: 'more than ever'),
            ],
          ),
          UserFigureParam(key: 'more', kind: ParamKind.places),
          UserFigureParam(key: 'empty', kind: ParamKind.text),
          UserFigureParam(key: 'least', kind: ParamKind.flag),
          UserFigureParam(key: 'than', kind: ParamKind.direction),
        ],
      ),
      larks,
    );

    String? reads(String condition) =>
        checkWording('[if $condition then x]', tricky).stored;

    test('each has the one reading its place gives it', () {
      expect(
        reads(
          'in is in (at, least) and more is more than 2 and empty is not empty',
        ),
        "[{?if in is in ('c1', 'c2') and more is more than 2 and "
        "empty is not empty}x]",
      );
      expect(reads('in is in'), "[{?if in is 'c3'}x]");
      expect(reads('in is more than ever'), "[{?if in is 'c4'}x]");
      expect(reads('least and not least'), '[{?if least and not least}x]');
      expect(reads('than is in'), "[{?if than is 'in'}x]");
      expect(
        reads('than is in (in, out)'),
        "[{?if than is in ('in', 'out')}x]",
      );
      expect(reads('more is at least 3'), '[{?if more is at least 3}x]');
      expect(reads('empty'), '[{?if empty}x]');
      expect(reads('empty is empty'), '[{?if empty is empty}x]');
    });

    test('a condition with two readings is refused, naming both', () {
      final mine = renderer.userFigureWordingVocabulary(
        UserFigureDefinition(
          template: '{move}',
          defaultBeats: 8,
          params: [
            UserFigureParam(
              key: 'style',
              kind: ParamKind.choice,
              choices: const [
                UserFigureChoice(id: 'a1', label: 'rock'),
                UserFigureChoice(id: 'a2', label: 'rock and roll'),
                UserFigureChoice(id: 'a3', label: 'not sure'),
                UserFigureChoice(id: 'a4', label: 'sure'),
              ],
            ),
            UserFigureParam(key: 'roll', kind: ParamKind.flag),
          ],
        ),
        larks,
      );
      for (final condition in ['style is rock and roll', 'style is not sure']) {
        final issue = checkWording('[if $condition then x]', mine).error!;
        expect(issue.code, WordingIssueCode.ambiguous, reason: condition);
        // Each reading, written as offered, has one reading.
        for (final reading in [
          issue.data['readingA']!,
          issue.data['readingB']!,
        ]) {
          expect(
            checkWording('[if $reading then x]', mine).error,
            isNull,
            reason: reading,
          );
        }
        expect(issue.data['readingA'], isNot(issue.data['readingB']));
      }
      expect(
        checkWording('[if style is in (rock and roll) then x]', mine).stored,
        "[{?if style is 'a2'}x]",
      );
      expect(
        checkWording('[if (style is rock) and roll then x]', mine).stored,
        "[{?if style is 'a1' and roll}x]",
      );
    });
  });

  group('a stored condition shown in words reads back as it was', () {
    final mine = renderer.userFigureWordingVocabulary(
      UserFigureDefinition(
        template: '{move}',
        defaultBeats: 8,
        params: [
          UserFigureParam(
            key: 'style',
            kind: ParamKind.choice,
            choices: const [
              UserFigureChoice(id: 'a1', label: 'rock'),
              UserFigureChoice(id: 'a2', label: 'rock and roll'),
              UserFigureChoice(id: 'a3', label: 'not sure'),
              UserFigureChoice(id: 'a4', label: 'sure'),
              UserFigureChoice(id: 'a5', label: 'empty'),
            ],
          ),
          UserFigureParam(key: 'roll', kind: ParamKind.flag),
        ],
      ),
      larks,
    );

    test('and stays quick however many of its words have two readings', () {
      final mine = renderer.userFigureWordingVocabulary(
        UserFigureDefinition(
          template: '{move}',
          defaultBeats: 8,
          params: [
            UserFigureParam(
              key: 's',
              kind: ParamKind.choice,
              choices: const [
                UserFigureChoice(id: 'a1', label: 'rock'),
                UserFigureChoice(id: 'a2', label: 'rock and roll'),
              ],
            ),
            UserFigureParam(key: 'roll', kind: ParamKind.flag),
          ],
        ),
        larks,
      );
      final explicit = List.filled(
        20,
        '(s is in (rock and roll))',
      ).join(' and ');
      final plain = List.filled(20, 's is rock and roll').join(' and ');
      final watch = Stopwatch()..start();
      final stored = checkWording('[if $explicit then x]', mine).stored!;
      expect(wordingForEditing(stored, mine), contains('rock and roll'));
      expect(
        checkWording('[if $plain then x]', mine).error?.code,
        WordingIssueCode.ambiguous,
      );
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('a label may start with a word conditions use, or hold a comma', () {
      final mine = renderer.userFigureWordingVocabulary(
        UserFigureDefinition(
          template: '{move}',
          defaultBeats: 8,
          params: [
            UserFigureParam(
              key: 'style',
              kind: ParamKind.choice,
              choices: const [
                UserFigureChoice(id: 'b1', label: 'then go'),
                UserFigureChoice(id: 'b2', label: 'or roll'),
                UserFigureChoice(id: 'b3', label: 'a, b'),
                UserFigureChoice(id: 'b4', label: 'then'),
              ],
            ),
          ],
        ),
        larks,
      );
      for (final stored in [
        "[{?if style is in ('b1', 'b2')}x]",
        "[{?if style is not 'b2'}x]",
        "[{?if style is 'b3'}x]",
        "[{?if style is 'b4'}x]",
        "[{?if style is in ('b3', 'b4')}x]",
      ]) {
        final shown = wordingForEditing(stored, mine);
        expect(checkWording(shown, mine).stored, stored, reason: shown);
      }
    });

    test('a branch holding "else", as only an import can, reads back', () {
      for (final stored in [
        "[{?if roll}a else b]",
        "[{?if roll}x{?else if roll}else y]",
      ]) {
        final shown = wordingForEditing(stored, mine);
        final read = checkWording(shown, mine);
        expect(read.error, isNull, reason: shown);
        final assembled = assembleWordingNodes(
          parseStoredWording(read.stored!)!,
          (_) => '',
          (_) => true,
        ).text;
        expect(
          assembled,
          assembleWordingNodes(
            parseStoredWording(stored)!,
            (_) => '',
            (_) => true,
          ).text,
          reason: shown,
        );
      }
    });

    test('even where its plain words would have two readings', () {
      for (final stored in [
        "[{?if style is 'a1' and roll}x]",
        "[{?if style is 'a2'}x]",
        "[{?if style is not 'a4'}x]",
        "[{?if style is 'a3'}x]",
        // A choice renamed "empty" after the condition was saved.
        "[{?if style is 'a5'}x]",
        '[{?if style is empty}x]',
        "[{?if style is in ('a2', 'a5')}x]",
      ]) {
        final shown = wordingForEditing(stored, mine);
        final check = checkWording(shown, mine);
        expect(check.error, isNull, reason: '$stored → $shown');
        expect(check.stored, stored, reason: '$stored → $shown');
      }
      // Plain words where they have one reading.
      expect(
        wordingForEditing("[{?if style is 'a1'}x]", mine),
        '[if style is rock then x]',
      );
    });
  });

  group('messages say what is wrong and how to fix it', () {
    void expectIssue(
      String text,
      WordingIssueCode code, {
      Map<String, String> data = const {},
      WordingVocabulary? vocabulary,
    }) {
      final check = checkWording(text, vocabulary ?? swing);
      final issue = check.issues.firstWhere(
        (i) => i.code == code,
        orElse: () => fail('$text: expected $code, got ${check.issues}'),
      );
      data.forEach((key, value) {
        expect(issue.data[key], value, reason: '$text: $key');
      });
      expect(issue.start, inInclusiveRange(0, text.length), reason: text);
      expect(
        issue.end,
        inInclusiveRange(issue.start, text.length),
        reason: text,
      );
    }

    test('brackets and braces', () {
      expectIssue('[if who then x', WordingIssueCode.unclosedGroup);
      expectIssue('[{who} swing', WordingIssueCode.unclosedGroup);
      expectIssue('swing]', WordingIssueCode.strayCloseBracket);
      expectIssue('{who swing', WordingIssueCode.unclosedSlot);
      expectIssue('who} swing', WordingIssueCode.strayCloseBrace);
      expectIssue(
        '{who and} swing',
        WordingIssueCode.badSlot,
        data: {'found': '{who and}', 'fix': '{who}'},
      );
      expectIssue(
        '{if who is robins} swing',
        WordingIssueCode.conditionInBraces,
        data: {'fix': '[if who is robins then …]'},
      );
      expectIssue(
        '{who is robins} swing',
        WordingIssueCode.conditionInBraces,
        data: {'fix': '[if who is robins then …]'},
      );
    });

    test('the parts of a conditional', () {
      expectIssue(
        '[if then x]',
        WordingIssueCode.missingCondition,
        data: {'word': 'if'},
      );
      expectIssue(
        '[if who is robins then a else if then b]',
        WordingIssueCode.missingCondition,
        data: {'word': 'else if'},
      );
      expectIssue(
        '[if who is robins x]',
        WordingIssueCode.expectedConnective,
        data: {'found': 'x'},
      );
      expectIssue(
        '[if who is robins]',
        WordingIssueCode.missingThen,
        data: {'condition': 'who is robins'},
      );
      expectIssue('[if who is robins: x]', WordingIssueCode.colonForThen);
      expectIssue(
        '[if who is robins then a else b else c]',
        WordingIssueCode.secondElse,
      );
      expectIssue(
        '[if who and then x]',
        WordingIssueCode.missingCondition,
        data: {'word': 'and'},
      );
    });

    test('names', () {
      expectIssue(
        '[if hwo is robins then x]',
        WordingIssueCode.unknownNameAfterIf,
        data: {'found': 'hwo', 'suggestion': 'who'},
      );
      expectIssue(
        '[if prefix and hwo then x]',
        WordingIssueCode.unknownName,
        data: {'found': 'hwo', 'suggestion': 'who'},
      );
      expectIssue(
        '[if {who} is robins then x]',
        WordingIssueCode.nameInBraces,
        data: {'name': 'who', 'found': '{who}'},
      );
      final names = checkWording(
        '[if nobody then x]',
        swing,
      ).error!.data['names']!;
      expect(names, contains('who'));
      expect(names, contains('endFacing'));
    });

    test("isn't, symbols and quotes", () {
      expectIssue(
        "[if who isn't robins then x]",
        WordingIssueCode.isntForIsNot,
        data: {'fix': 'who is not robins'},
      );
      expectIssue(
        '[if who isn’t robins then x]',
        WordingIssueCode.isntForIsNot,
        data: {'fix': 'who is not robins'},
      );
      expectIssue('[if who isnt robins then x]', WordingIssueCode.isntForIsNot);
      expectIssue(
        '[if who = robins then x]',
        WordingIssueCode.symbolForWord,
        data: {'word': 'is', 'fix': 'who is robins'},
      );
      expectIssue(
        '[if who != robins then x]',
        WordingIssueCode.symbolForWord,
        data: {'word': 'is not', 'fix': 'who is not robins'},
      );
      expectIssue(
        '[if beats >= 8 then x]',
        WordingIssueCode.symbolForWord,
        data: {'word': 'is at least', 'fix': 'beats is at least 8'},
      );
      expectIssue(
        '[if beats > 8 then x]',
        WordingIssueCode.symbolForWord,
        data: {'word': 'is more than'},
      );
      expectIssue(
        '[if prefix && who then x]',
        WordingIssueCode.symbolForWord,
        data: {'word': 'and'},
      );
      expectIssue(
        '[if !prefix then x]',
        WordingIssueCode.symbolForWord,
        data: {'word': 'not', 'fix': 'not prefix'},
      );
      expectIssue(
        '[if who is "robins" then x]',
        WordingIssueCode.quotedValue,
        data: {'fix': 'who is robins'},
      );
    });

    test('values', () {
      expectIssue(
        '[if who is robbins then x]',
        WordingIssueCode.unknownValue,
        data: {'found': 'robbins', 'suggestion': 'robins', 'name': 'who'},
      );
      expectIssue(
        '[if who is then x]',
        WordingIssueCode.expectedValue,
        data: {'name': 'who'},
      );
      expectIssue(
        '[if who is robins larks then x]',
        WordingIssueCode.expectedConnectiveList,
        data: {'fix': 'who is in (robins, larks)'},
      );
      expectIssue(
        '[if who is in robins, larks then x]',
        WordingIssueCode.listNeedsParens,
        data: {'fix': 'who is in (robins, larks)'},
      );
      expectIssue(
        '[if who is one of robins, larks then x]',
        WordingIssueCode.oneOfForIsIn,
        data: {'fix': 'who is in (robins, larks)'},
      );
      expectIssue(
        '[if who is none of robins or larks then x]',
        WordingIssueCode.oneOfForIsIn,
        data: {'fix': 'who is not in (robins, larks)'},
      );
      expectIssue('[if who is in () then x]', WordingIssueCode.emptyList);
      expectIssue(
        '[if who is in (robins, then x]',
        WordingIssueCode.expectedValue,
      );
      expectIssue(
        '[if who is in (robins larks) then x]',
        WordingIssueCode.expectedListSeparator,
        data: {'found': 'larks'},
      );
      expectIssue(
        '[if who is in (robins then x]',
        WordingIssueCode.unclosedParen,
      );
    });

    test('kinds', () {
      expectIssue(
        '[if who is more than 2 then x]',
        WordingIssueCode.notANumber,
        data: {'name': 'who', 'op': 'more than'},
      );
      expectIssue(
        '[if beats is more than eight then x]',
        WordingIssueCode.expectedNumber,
        data: {'found': 'eight', 'example': '8'},
      );
      expectIssue(
        '[if beats is more than 100 then x]',
        WordingIssueCode.numberOutOfRange,
        data: {'min': '0', 'max': '64', 'found': '100'},
      );
      expectIssue('[if beats is 8.5 then x]', WordingIssueCode.numberNotWhole);
      expectIssue(
        '[if beats is not more than 8 then x]',
        WordingIssueCode.negatedComparison,
        data: {'fix': 'beats is at most 8'},
      );
      final allemande = renderer.moveWordingVocabulary('allemande', larks);
      expectIssue(
        '[if travel is 0.3 then x]',
        WordingIssueCode.numberNotQuarter,
        vocabulary: allemande,
      );
      expect(
        checkWording('[if travel is 1½ then x]', allemande).stored,
        '[{?if travel is 1.5}x]',
      );
      expect(
        checkWording('[if travel is once then x]', allemande).stored,
        '[{?if travel is 1}x]',
      );
      final wave = renderer.moveWordingVocabulary('form_a_long_wave', larks);
      expectIssue(
        '[if balance is on then x]',
        WordingIssueCode.flagCompare,
        data: {'name': 'balance'},
        vocabulary: wave,
      );
    });

    test('mixing and and or', () {
      expectIssue(
        '[if who is robins or who is larks and prefix then x]',
        WordingIssueCode.mixedAndOr,
        data: {
          'fixA': 'who is robins or (who is larks and prefix)',
          'fixB': '(who is robins or who is larks) and prefix',
        },
      );
      for (final fix in [
        '[if who is robins or (who is larks and prefix) then x]',
        '[if (who is robins or who is larks) and prefix then x]',
      ]) {
        expect(errorOf(fix), isNull, reason: fix);
      }
      expectIssue('[if (who is robins then x]', WordingIssueCode.unclosedParen);
      expectIssue('[if () then x]', WordingIssueCode.emptyParens);
      expectIssue(
        '[if who is robins) then x]',
        WordingIssueCode.strayCloseParen,
      );
    });

    test('a second value written as a second test, or after a comma', () {
      expectIssue(
        '[if who is robins or larks then x]',
        WordingIssueCode.valueAfterConnective,
        data: {
          'found': 'larks',
          'word': 'or',
          'fixA': 'who is robins or who is larks',
          'fixB': 'who is in (robins, larks)',
        },
      );
      expectIssue(
        '[if who is not robins or larks then x]',
        WordingIssueCode.valueAfterConnective,
        data: {
          'fixA': 'who is not robins and who is not larks',
          'fixB': 'who is not in (robins, larks)',
        },
      );
      expectIssue(
        '[if who is robins, larks then x]',
        WordingIssueCode.expectedConnectiveList,
        data: {'fix': 'who is in (robins, larks)'},
      );
      for (final fix in [
        'who is robins or who is larks',
        'who is in (robins, larks)',
        'who is not robins and who is not larks',
        'who is not in (robins, larks)',
      ]) {
        expect(errorOf('[if $fix then x]'), isNull, reason: fix);
      }
    });

    test('a decimal comma, and nothing to test', () {
      final allemande = renderer.moveWordingVocabulary('allemande', larks);
      expectIssue(
        '[if travel is 1,5 then x]',
        WordingIssueCode.expectedNumber,
        data: {'found': '1,5', 'example': '1.5'},
        vocabulary: allemande,
      );
      expect(
        checkWording('[if beats is in (8,16) then x]', swing).stored,
        '[{?if beats is in (8, 16)}x]',
      );
      expectIssue(
        '[if who is robins then x]',
        WordingIssueCode.nothingToTest,
        vocabulary: WordingVocabulary(const []),
      );
    });

    test('warnings: the template saves, but likely not as meant', () {
      final everyone = checkWording(
        '[if who is ones then everyone else swing]',
        swing,
      );
      expect(everyone.error, isNull);
      expect(everyone.warnings.single.code, WordingIssueCode.elseAfterWord);
      expect(everyone.warnings.single.data['phrase'], 'everyone else');
      expect(
        checkWording(
          '[if who is ones then [everyone else] swing]',
          swing,
        ).issues,
        isEmpty,
      );
      expect(
        checkWording(
          '[if prefix then a otherwise b]',
          swing,
        ).warnings.single.code,
        WordingIssueCode.otherwiseWord,
      );
      final mine = renderer.userFigureWordingVocabulary(
        UserFigureDefinition(
          template: '{move}',
          defaultBeats: 8,
          params: [
            UserFigureParam(
              key: 'size',
              kind: ParamKind.choice,
              choices: const [UserFigureChoice(id: 'e', label: 'empty')],
            ),
          ],
        ),
        larks,
      );
      final empty = checkWording('[if size is empty then x]', mine);
      expect(empty.stored, '[{?if size is empty}x]');
      expect(empty.warnings.single.code, WordingIssueCode.emptyMeansNoValue);
      expect(empty.warnings.single.data['fix'], 'size is in (empty)');
      expect(
        checkWording('[if size is in (empty) then x]', mine).stored,
        "[{?if size is 'e'}x]",
      );
    });

    test('every fix a message offers reads without that error', () {
      for (final text in [
        "[if who isn't robins then x]",
        '[if who = robins then x]',
        '[if beats >= 8 then x]',
        '[if who is one of robins, larks then x]',
        '[if who is in robins, larks then x]',
        '[if who is "robins" then x]',
        '[if who is in ("robins", "larks") then x]',
        '[if who is “next neighbors” then x]',
        '[if beats is not more than 8 then x]',
        '[if who is robins larks then x]',
      ]) {
        final issue = errorOf(text)!;
        final fix = issue.data['fix']!;
        final fixed = '[if $fix then x]';
        expect(errorOf(fixed), isNull, reason: '$text → $fixed');
      }
    });
  });

  test('no built-in parameter or slot is named a reserved word', () {
    for (final def in contraTaxonomy.moves.values) {
      final names = renderer.moveWordingVocabulary(def.id, larks).names;
      for (final name in names) {
        expect(
          wordingReservedWords.contains(name.name.toLowerCase()),
          isFalse,
          reason: '${def.id}.${name.name}',
        );
      }
    }
  });

  test('every built-in value has a word of its own', () {
    for (final def in contraTaxonomy.moves.values) {
      for (final name in renderer.moveWordingVocabulary(def.id, larks).names) {
        final words = <String, Object>{};
        for (final value in name.values) {
          final word = value.word.toLowerCase();
          expect(
            words.containsKey(word),
            isFalse,
            reason: '${def.id}.${name.name}: "$word"',
          );
          words[word] = value.value;
          expect(word.trim(), isNotEmpty, reason: '${def.id}.${name.name}');
        }
      }
    }
  });
}

UserFigureCatalog _catalog(UserFigureDefinition definition) =>
    UserFigureCatalog.fromEntries([
      UserGlossaryEntry(
        id: 'mine',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'lead',
        definition: 'Mine.',
        description: 'Mine.',
        payload: definition.toJson(),
        createdAt: DateTime.utc(2026),
      ),
    ]);
