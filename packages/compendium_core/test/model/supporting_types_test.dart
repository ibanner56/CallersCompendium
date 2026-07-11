import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('Formation', () {
    test('value equality includes detail', () {
      expect(
        const Formation(FormationShape.becketCw),
        const Formation(FormationShape.becketCw),
      );
      expect(
        const Formation(FormationShape.becketCw, detail: 'double prog'),
        isNot(const Formation(FormationShape.becketCw)),
      );
    });
  });

  group('Choreographer', () {
    test('rejects empty names', () {
      expect(() => Choreographer(id: 'c1', name: '  '), throwsArgumentError);
    });

    test('"Traditional" is an ordinary row', () {
      expect(Choreographer(id: 'c1', name: 'Traditional').name, 'Traditional');
    });
  });

  group('Tag', () {
    test('rejects empty names', () {
      expect(() => Tag(id: 't1', name: ''), throwsArgumentError);
    });
  });

  group('DanceLink', () {
    test('relatedDance links require targetDanceId', () {
      expect(
        () => DanceLink(id: 'l1', kind: LinkKind.relatedDance, url: 'x'),
        throwsArgumentError,
      );
      expect(
        DanceLink(
          id: 'l1',
          kind: LinkKind.relatedDance,
          targetDanceId: 'd2',
        ).targetDanceId,
        'd2',
      );
    });

    test('url-kinds require a non-empty url', () {
      for (final kind in [LinkKind.source, LinkKind.video, LinkKind.other]) {
        expect(
          () => DanceLink(id: 'l1', kind: kind),
          throwsArgumentError,
          reason: kind.name,
        );
        expect(
          () => DanceLink(id: 'l1', kind: kind, url: '  '),
          throwsArgumentError,
        );
      }
      expect(
        DanceLink(id: 'l1', kind: LinkKind.video, url: 'https://y.t/v').url,
        'https://y.t/v',
      );
    });
  });

  group('CustomFieldDef', () {
    test('rejects empty keys', () {
      expect(
        () => CustomFieldDef(
          id: 'f1',
          key: ' ',
          label: 'X',
          type: CustomFieldType.text,
        ),
        throwsArgumentError,
      );
    });

    test('choice fields must declare choices', () {
      expect(
        () => CustomFieldDef(
          id: 'f1',
          key: 'level',
          label: 'L',
          type: CustomFieldType.choice,
        ),
        throwsArgumentError,
      );
      expect(
        () => CustomFieldDef(
          id: 'f1',
          key: 'level',
          label: 'L',
          type: CustomFieldType.choice,
          choices: [],
        ),
        throwsArgumentError,
      );
      final def = CustomFieldDef(
        id: 'f1',
        key: 'level',
        label: 'L',
        type: CustomFieldType.choice,
        choices: ['easy', 'hard'],
      );
      expect(def.choices, ['easy', 'hard']);
    });
  });

  group('CustomFieldValue.matchesType', () {
    CustomFieldDef def(CustomFieldType type, {List<String>? choices}) =>
        CustomFieldDef(
          id: 'f1',
          key: 'k',
          label: 'K',
          type: type,
          choices: choices,
        );

    test('text requires String', () {
      expect(
        CustomFieldValue(
          fieldId: 'f1',
          value: 'hi',
        ).matchesType(def(CustomFieldType.text)),
        isTrue,
      );
      expect(
        CustomFieldValue(
          fieldId: 'f1',
          value: 3,
        ).matchesType(def(CustomFieldType.text)),
        isFalse,
      );
    });

    test('number requires num', () {
      expect(
        CustomFieldValue(
          fieldId: 'f1',
          value: 3.5,
        ).matchesType(def(CustomFieldType.number)),
        isTrue,
      );
      expect(
        CustomFieldValue(
          fieldId: 'f1',
          value: '3',
        ).matchesType(def(CustomFieldType.number)),
        isFalse,
      );
    });

    test('boolean requires bool', () {
      expect(
        CustomFieldValue(
          fieldId: 'f1',
          value: true,
        ).matchesType(def(CustomFieldType.boolean)),
        isTrue,
      );
    });

    test('choice requires membership in declared choices', () {
      final d = def(CustomFieldType.choice, choices: ['a', 'b']);
      expect(
        CustomFieldValue(fieldId: 'f1', value: 'a').matchesType(d),
        isTrue,
      );
      expect(
        CustomFieldValue(fieldId: 'f1', value: 'z').matchesType(d),
        isFalse,
      );
    });
  });

  group('ValidationIssue', () {
    test('value equality and readable toString', () {
      const a = ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'phrase_overflow',
        message: 'm',
      );
      const b = ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'phrase_overflow',
        message: 'm',
      );
      expect(a, b);
      expect(a.toString(), contains('phrase_overflow'));
    });
  });
}
