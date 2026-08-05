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

    test('withColor clears a colour, which copyWith structurally cannot', () {
      // The trap this exists for (issue #786): copyWith's `color ?? this.color`
      // makes a null argument indistinguishable from an omitted one, so the
      // obvious `copyWith(color: null)` silently keeps the old colour and a
      // "reset" action would appear to do nothing.
      final coloured = Tag(id: 't1', name: 'chestnut', color: 0xFF2196F3);
      expect(coloured.copyWith(color: null).color, 0xFF2196F3);
      expect(coloured.withColor(null).color, isNull);
    });

    test('withColor sets a colour and preserves id and name', () {
      final plain = Tag(id: 't1', name: 'chestnut');
      final coloured = plain.withColor(0xFF2196F3);
      expect(coloured.color, 0xFF2196F3);
      expect(coloured.id, 't1');
      expect(coloured.name, 'chestnut');
    });
  });

  group('PublishedSource', () {
    test('rejects empty titles', () {
      expect(() => PublishedSource(id: 's1', title: '  '), throwsArgumentError);
    });

    test('rejects a non-positive year', () {
      expect(
        () => PublishedSource(id: 's1', title: 'Book', year: 0),
        throwsArgumentError,
      );
      expect(
        () => PublishedSource(id: 's1', title: 'Book', year: -5),
        throwsArgumentError,
      );
      expect(PublishedSource(id: 's1', title: 'Book', year: 1651).year, 1651);
    });

    test('normalizes empty/whitespace optional strings to null', () {
      final s = PublishedSource(
        id: 's1',
        title: 'Book',
        author: '   ',
        url: '',
        notes: '\t',
      );
      expect(s.author, isNull);
      expect(s.url, isNull);
      expect(s.notes, isNull);
    });

    test('trims surrounding whitespace on optional strings', () {
      final s = PublishedSource(
        id: 's1',
        title: 'Book',
        author: '  Ralph Page  ',
        url: '  https://x.y  ',
        notes: '  seminal  ',
      );
      expect(s.author, 'Ralph Page');
      expect(s.url, 'https://x.y');
      expect(s.notes, 'seminal');
    });

    test('copyWith clear flags win over passed values', () {
      final s = PublishedSource(
        id: 's1',
        title: 'Book',
        author: 'A',
        year: 1990,
        url: 'https://x.y',
        notes: 'n',
      );
      final cleared = s.copyWith(
        author: 'ignored',
        clearAuthor: true,
        year: 2000,
        clearYear: true,
        url: 'ignored',
        clearUrl: true,
        notes: 'ignored',
        clearNotes: true,
      );
      expect(cleared.author, isNull);
      expect(cleared.year, isNull);
      expect(cleared.url, isNull);
      expect(cleared.notes, isNull);
      expect(cleared.title, 'Book');
    });

    test('copyWith replaces without clearing', () {
      final s = PublishedSource(id: 's1', title: 'Book', author: 'A');
      final updated = s.copyWith(title: 'Booke', author: 'B', year: 1651);
      expect(updated.title, 'Booke');
      expect(updated.author, 'B');
      expect(updated.year, 1651);
    });

    test('== and hashCode cover all fields', () {
      PublishedSource make() => PublishedSource(
        id: 's1',
        title: 'Book',
        author: 'A',
        year: 1990,
        url: 'https://x.y',
        notes: 'n',
      );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(make(), isNot(make().copyWith(title: 'Other')));
      expect(make(), isNot(make().copyWith(clearYear: true)));
    });
  });

  group('SourceCitation', () {
    test('normalizes empty/whitespace page & number to null', () {
      final c = SourceCitation(sourceId: 's1', page: '  ', number: '');
      expect(c.page, isNull);
      expect(c.number, isNull);
    });

    test('trims and preserves freeform page & number', () {
      final c = SourceCitation(
        sourceId: 's1',
        page: '  12-14 ',
        number: ' A1 ',
      );
      expect(c.page, '12-14');
      expect(c.number, 'A1');
    });

    test('== and hashCode cover all fields', () {
      SourceCitation make() =>
          SourceCitation(sourceId: 's1', page: '12', number: 'A1');
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(make(), isNot(SourceCitation(sourceId: 's2', page: '12')));
      expect(make(), isNot(SourceCitation(sourceId: 's1', page: '13')));
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

    test('value equality includes all fields', () {
      CustomFieldDef make({
        String id = 'f1',
        String key = 'level',
        String label = 'Level',
        CustomFieldType type = CustomFieldType.choice,
        List<String>? choices = const ['easy', 'hard'],
        bool showInList = false,
        bool searchable = true,
      }) => CustomFieldDef(
        id: id,
        key: key,
        label: label,
        type: type,
        choices: choices,
        showInList: showInList,
        searchable: searchable,
      );

      final a = make();
      final b = make();
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      expect(a, isNot(make(id: 'f2')));
      expect(a, isNot(make(key: 'tempo')));
      expect(a, isNot(make(label: 'Difficulty')));
      expect(a, isNot(make(type: CustomFieldType.text, choices: null)));
      expect(a, isNot(make(choices: ['easy', 'medium'])));
      expect(a, isNot(make(showInList: true)));
      expect(a, isNot(make(searchable: false)));

      // A null choices list is distinct from an empty/non-empty one.
      final withNullChoices = CustomFieldDef(
        id: 'f1',
        key: 'note',
        label: 'Note',
        type: CustomFieldType.text,
      );
      final withEmptyChoices = CustomFieldDef(
        id: 'f1',
        key: 'note',
        label: 'Note',
        type: CustomFieldType.text,
        choices: [],
      );
      expect(withNullChoices, isNot(withEmptyChoices));
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
