import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Figures of your own (#1023): the payload codec and its validation.
void main() {
  Map<String, Object?> zoom({
    Object? template = '{who} zoom around [{hand} hand] {style}',
    Object? params,
    Object? defaultBeats = 8,
  }) => {
    'form': 'contra',
    'template': template,
    'defaultBeats': defaultBeats,
    'params':
        params ??
        [
          {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
          {'key': 'hand', 'kind': 'handedness'},
          {
            'key': 'style',
            'kind': 'choice',
            'choices': [
              {'id': 'f', 'label': 'fast'},
              {'id': 's', 'label': 'slow'},
            ],
          },
        ],
  };

  Set<String> codes(UserFigureDefinition definition) => {
    for (final issue in validateUserFigure(definition)) issue.code,
  };

  UserFigureDefinition definitionWith(
    List<UserFigureParam> params, {
    String template = '{move}',
  }) =>
      UserFigureDefinition(template: template, defaultBeats: 8, params: params);

  group('decodeUserFigureDefinition', () {
    test('reads a definition and writes the same payload back', () {
      final definition = decodeUserFigureDefinition(zoom())!;
      expect(definition.form, 'contra');
      expect(definition.danceForm, DanceForm.contra);
      expect(definition.defaultBeats, 8);
      expect(definition.params.map((p) => p.key), ['who', 'hand', 'style']);
      expect(definition.param('style')!.choiceLabel('s'), 'slow');
      expect(definition.toJson(), zoom());
    });

    test('keeps keys it does not know, so an edit here cannot drop what a '
        'later build stored', () {
      final raw = {
        ...zoom(),
        'later': {'x': 1},
      };
      final definition = decodeUserFigureDefinition(raw)!;
      expect(definition.extra, {
        'later': {'x': 1},
      });
      expect(definition.toJson()['later'], {'x': 1});
    });

    test(
      'a missing form is contra; a form this build does not know is kept',
      () {
        final noForm = Map<String, Object?>.of(zoom())..remove('form');
        expect(decodeUserFigureDefinition(noForm)!.form, 'contra');
        final later = decodeUserFigureDefinition({...zoom(), 'form': 'mwsd'})!;
        expect(later.form, 'mwsd');
        expect(later.danceForm, isNull);
      },
    );

    test('strips control and bidi characters from the template and labels', () {
      final definition = decodeUserFigureDefinition(
        zoom(
          template: '{who} zoom\u202e around',
          params: [
            {'key': 'who', 'kind': 'dancerSet'},
            {'key': 'flourish', 'kind': 'flag', 'label': 'with\u200b flair'},
          ],
        ),
      )!;
      expect(definition.template, '{who} zoom around');
      expect(definition.param('flourish')!.label, 'with flair');
    });

    test('never throws on hostile input, and reads it as unusable', () {
      final deep = <String, Object?>{};
      var cursor = deep;
      for (var i = 0; i < 200; i++) {
        final next = <String, Object?>{};
        cursor['params'] = next;
        cursor = next;
      }
      final hostile = <Object?>[
        null,
        'text',
        42,
        deep,
        zoom(template: 7),
        zoom(defaultBeats: '8'),
        zoom(params: 'nope'),
        zoom(params: [null]),
        zoom(
          params: [
            {'key': 'who', 'kind': 'notAKind'},
          ],
        ),
        zoom(
          params: [
            {'key': 3, 'kind': 'dancerSet'},
          ],
        ),
        zoom(params: List.filled(17, {'key': 'x', 'kind': 'flag'})),
        zoom(
          params: [
            {
              'key': 'style',
              'kind': 'choice',
              'choices': List.filled(33, {'id': 'a', 'label': 'a'}),
            },
          ],
        ),
        zoom(
          params: [
            {'key': 'who', 'kind': 'flag', 'default': double.nan},
          ],
        ),
        zoom(template: '{who'),
        zoom(template: '{unknown}'),
        {...zoom(), 'copiedFrom': 4},
        {...zoom(), 'copiedFrom': 'x' * 65},
        {...zoom(), 'form': 'x' * 33},
        zoom(
          params: [
            {'key': 'where', 'kind': 'text', 'default': 'x' * 1001},
          ],
        ),
      ];
      for (final raw in hostile) {
        expect(
          decodeUserFigureDefinition(raw),
          isNull,
          reason: jsonEncode(raw, toEncodable: (o) => o.toString()),
        );
      }
    });
  });

  group('validateUserFigure', () {
    test('a well-formed figure has no issues', () {
      expect(codes(decodeUserFigureDefinition(zoom())!), isEmpty);
    });

    test('offers the opposite of each parameter whose kind has one, and '
        'nothing for the rest', () {
      final definition = decodeUserFigureDefinition(zoom())!;
      expect(definition.slots, {
        'move',
        'beats',
        'who',
        'otherWho',
        'hand',
        'otherHand',
        'style',
      });
    });

    test('a parameter only its opposite fills counts as used', () {
      final definition = definitionWith([
        UserFigureParam(key: 'hand', kind: ParamKind.handedness),
      ], template: '{move} {otherHand}');
      expect(definition.unusedParams, isEmpty);
      expect(codes(definition), isEmpty);
    });

    test('an unused parameter is only a warning', () {
      final definition = definitionWith([
        UserFigureParam(key: 'hand', kind: ParamKind.handedness),
      ]);
      final issues = validateUserFigure(definition);
      expect(issues.single.code, UserFigureIssueCodes.unusedParam);
      expect(issues.single.severity, ValidationSeverity.warning);
    });

    test('refuses a template slot the figure does not offer', () {
      expect(
        codes(definitionWith([], template: '{move} {hand}')),
        contains(UserFigureIssueCodes.unknownSlot),
      );
    });

    test('refuses reserved, role-token, repeated and opposite-shaped keys', () {
      for (final params in [
        [UserFigureParam(key: 'move', kind: ParamKind.text)],
        [UserFigureParam(key: 'beats', kind: ParamKind.text)],
        [UserFigureParam(key: 'text', kind: ParamKind.text)],
        [UserFigureParam(key: 'role1s', kind: ParamKind.text)],
        [UserFigureParam(key: 'Role1', kind: ParamKind.text)],
        [UserFigureParam(key: '9lives', kind: ParamKind.text)],
        [UserFigureParam(key: 'a b', kind: ParamKind.text)],
        [UserFigureParam(key: 'x' * 65, kind: ParamKind.text)],
        [
          UserFigureParam(key: 'hand', kind: ParamKind.handedness),
          UserFigureParam(key: 'hand', kind: ParamKind.shoulder),
        ],
        [
          UserFigureParam(key: 'hand', kind: ParamKind.handedness),
          UserFigureParam(key: 'otherHand', kind: ParamKind.text),
        ],
      ]) {
        expect(
          codes(definitionWith(params)),
          contains(UserFigureIssueCodes.badParamKey),
          reason: params.map((p) => p.key).join(', '),
        );
      }
    });

    test('an empty key is refused, and never throws', () {
      final definition = definitionWith([
        UserFigureParam(key: '', kind: ParamKind.handedness),
        UserFigureParam(key: '', kind: ParamKind.flag),
      ]);
      expect(() => definition.slots, returnsNormally);
      expect(() => definition.unusedParams, returnsNormally);
      expect(codes(definition), contains(UserFigureIssueCodes.badParamKey));
    });

    test('keys differing only in case are one key: they would share an '
        'opposite slot', () {
      expect(
        codes(
          definitionWith([
            UserFigureParam(key: 'hand', kind: ParamKind.handedness),
            UserFigureParam(key: 'Hand', kind: ParamKind.handedness),
          ], template: '{hand} {Hand}'),
        ),
        contains(UserFigureIssueCodes.badParamKey),
      );
      expect(
        codes(
          definitionWith([
            UserFigureParam(key: 'hand', kind: ParamKind.handedness),
            UserFigureParam(key: 'OtherHand', kind: ParamKind.text),
          ], template: '{hand} {OtherHand}'),
        ),
        contains(UserFigureIssueCodes.badParamKey),
      );
    });

    test('a figure may not declare beats: they are the use\'s own', () {
      expect(
        codes(
          definitionWith([UserFigureParam(key: 'n', kind: ParamKind.beats)]),
        ),
        contains(UserFigureIssueCodes.badParamKind),
      );
    });

    test('a choice needs well-formed, distinct choices, and only a choice may '
        'have them', () {
      UserFigureParam choice(List<UserFigureChoice> choices) =>
          UserFigureParam(key: 'c', kind: ParamKind.choice, choices: choices);
      for (final params in [
        [choice(const [])],
        [
          choice(const [
            UserFigureChoice(id: 'a', label: 'one'),
            UserFigureChoice(id: 'a', label: 'two'),
          ]),
        ],
        [
          choice(const [UserFigureChoice(id: 'A!', label: 'one')]),
        ],
        [
          choice(const [UserFigureChoice(id: 'a', label: ' ')]),
        ],
        [
          UserFigureParam(
            key: 'h',
            kind: ParamKind.handedness,
            choices: const [UserFigureChoice(id: 'a', label: 'one')],
          ),
        ],
      ]) {
        expect(
          codes(definitionWith(params)),
          contains(UserFigureIssueCodes.badChoices),
        );
      }
    });

    test('a default must be one of the parameter\'s values', () {
      expect(
        codes(
          definitionWith([
            UserFigureParam(
              key: 'hand',
              kind: ParamKind.handedness,
              defaultValue: 'sideways',
            ),
          ], template: '{hand}'),
        ),
        contains(UserFigureIssueCodes.badDefault),
      );
      expect(
        codes(
          definitionWith([
            UserFigureParam(
              key: 'c',
              kind: ParamKind.choice,
              choices: const [UserFigureChoice(id: 'a', label: 'one')],
              defaultValue: 'one',
            ),
          ], template: '{c}'),
        ),
        contains(UserFigureIssueCodes.badDefault),
        reason: 'a choice\'s default is its id, not its label',
      );
    });

    test('refuses default beats out of range and an empty form', () {
      expect(
        codes(
          UserFigureDefinition(
            template: '{move}',
            defaultBeats: 65,
            params: [],
          ),
        ),
        contains(UserFigureIssueCodes.badBeats),
      );
      expect(
        codes(
          UserFigureDefinition(
            form: '',
            template: '{move}',
            defaultBeats: 8,
            params: [],
          ),
        ),
        contains(UserFigureIssueCodes.badForm),
      );
    });
  });

  group('editing helpers', () {
    test('a template\'s literal text is mapped and its slots kept', () {
      expect(
        mapUserFigureTemplateText(
          'Leads {leads} [{!hand} hand] leads',
          (text) => text.replaceAll('eads', 'EADS'),
        ),
        'LEADS {leads} [{!hand} hand] lEADS',
      );
    });

    test('a new choice id is well-shaped and avoids those taken', () {
      final taken = <String>{};
      for (var i = 0; i < 50; i++) {
        final id = newUserFigureChoiceId(taken);
        expect(id, matches(RegExp(r'^[a-z0-9]{8}$')));
        expect(taken.add(id), isTrue);
      }
    });

    test('a payload\'s unknown keys are what an edit carries', () {
      expect(userFigurePayloadExtra({...zoom(), 'later': 1}), {'later': 1});
      expect(userFigurePayloadExtra(null), isEmpty);
    });
  });

  group('glossaryEntryForm', () {
    test('reads any kind of entry\'s form, contra when it names none', () {
      expect(glossaryEntryForm(null), 'contra');
      expect(glossaryEntryForm(const {'params': <Object?>[]}), 'contra');
      expect(glossaryEntryForm(const {'form': 'ecd'}), 'ecd');
      expect(glossaryEntryForm(const {'form': 3}), 'contra');
    });
  });
}
