import 'package:compendium_app/src/export/calling_card_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CallingCardLayout parse(String s) => CallingCardLayout.parse(s);

  group('CallingCardLayout.parse', () {
    test('the default layout and every example parse without issues', () {
      for (final MapEntry(:key, :value) in kCallingCardLayoutExamples.entries) {
        final layout = parse(value);
        expect(layout.issues, isEmpty, reason: key);
        expect(layout.rows, isNotEmpty, reason: key);
      }
      expect(
        kCallingCardLayoutExamples.values.first,
        kDefaultCallingCardLayout,
      );
    });

    test('one row per line, | splits blocks, comments and blanks skipped', () {
      final layout = parse('''
# a comment
title | formation right

figures
''');
      expect(layout.rows, hasLength(2));
      expect(layout.rows[0].map((b) => b.kind), [
        CallingCardBlockKind.title,
        CallingCardBlockKind.formation,
      ]);
      expect(layout.rows[0][1].align, CallingCardAlign.right);
      expect(layout.rows[1].single.kind, CallingCardBlockKind.figures);
    });

    test('options resolve to values, with defaults filled in', () {
      final b = parse(
        'notes size=11 bold italic center color=#B64545 lines=3 width=2',
      ).rows.single.single;
      expect(b.size, 11);
      expect(b.bold, isTrue);
      expect(b.italic, isTrue);
      expect(b.align, CallingCardAlign.center);
      expect(b.color, 0xB64545);
      expect(b.maxLines, 3);
      expect(b.width, 2);
      expect(b.label, isNull);

      final d = parse('notes').rows.single.single;
      expect(d.size, 8);
      expect(d.bold, isFalse);
      expect(d.maxLines, isNull);
      expect(parse('title').rows.single.single.size, 16);
    });

    test('a three-digit color expands', () {
      expect(parse('rule color=f00').rows.single.single.color, 0xFF0000);
    });

    test('quoted values keep spaces, | and #', () {
      final b = parse('notes label="Notes | #1: "').rows.single.single;
      expect(b.label, 'Notes | #1: ');
      expect(parse('notes label=""').rows.single.single.label, '');
      final t = parse('text "Called by me" size=12').rows.single.single;
      expect(t.text, 'Called by me');
      expect(t.size, 12);
    });

    test('curly quotes count as straight ones', () {
      final b = parse(
        'text \u201CCalled by me\u201D size=12',
      ).rows.single.single;
      expect(b.text, 'Called by me');
      expect(b.size, 12);
      expect(
        parse('notes label=\u201CNB: \u201D').rows.single.single.label,
        'NB: ',
      );
    });

    test('any space separates words, a no-break space included', () {
      final layout = parse('title\u00A0bold');
      expect(layout.issues, isEmpty);
      expect(layout.rows.single.single.bold, isTrue);
    });

    test('figures switches', () {
      final f = parse(
        'figures beats=off notes=no phrases=false dividers=off',
      ).rows.single.single;
      expect(f.beats, isFalse);
      expect(f.figureNotes, isFalse);
      expect(f.phrases, isFalse);
      expect(f.dividers, isFalse);
      final on = parse('figures beats=on').rows.single.single;
      expect(on.beats && on.figureNotes && on.phrases && on.dividers, isTrue);
    });

    test('figures highlight is off unless asked for, and on by default', () {
      expect(parse('figures').rows.single.single.highlight, isFalse);
      expect(parse('figures highlight').rows.single.single.highlight, isTrue);
      expect(
        parse('figures highlight=off').rows.single.single.highlight,
        isFalse,
      );
      final figures = parse(kDefaultCallingCardLayout).rows
          .expand((r) => r)
          .firstWhere((b) => b.kind == CallingCardBlockKind.figures);
      expect(figures.highlight, isTrue, reason: 'the default layout');
      expect(
        parse('title highlight').issues.single.kind,
        CallingCardIssueKind.unknownOption,
      );
    });

    test('space takes a bare number; rule takes a thickness', () {
      expect(parse('space 12').rows.single.single.space, 12);
      expect(parse('space size=3').rows.single.single.space, 3);
      expect(parse('space').rows.single.single.space, 6);
      expect(parse('rule thickness=2.5').rows.single.single.thickness, 2.5);
    });

    test('card sets the margin and adds no row', () {
      final layout = parse('card margin=9\ntitle');
      expect(layout.margin, 9);
      expect(layout.rows, hasLength(1));
      expect(parse('title').margin, CallingCardLayout.defaultMargin);
    });

    test('block names and option names ignore case', () {
      final b = parse('TITLE Bold').rows.single.single;
      expect(b.kind, CallingCardBlockKind.title);
      expect(b.bold, isTrue);
    });
  });

  group('issues', () {
    CallingCardLayoutIssue only(String source) {
      final issues = parse(source).issues;
      expect(issues, hasLength(1), reason: '$issues');
      return issues.single;
    }

    test(
      'an unknown block is reported and dropped; the rest of the row stays',
      () {
        final layout = parse('title\ntitel | formation');
        expect(layout.issues, [
          const CallingCardLayoutIssue(
            line: 2,
            kind: CallingCardIssueKind.unknownBlock,
            subject: 'titel',
          ),
        ]);
        expect(layout.rows[1].single.kind, CallingCardBlockKind.formation);
      },
    );

    test('an option the block does not take', () {
      expect(
        only('rule bold'),
        const CallingCardLayoutIssue(
          line: 1,
          kind: CallingCardIssueKind.unknownOption,
          subject: 'bold',
        ),
      );
      expect(only('title 12').kind, CallingCardIssueKind.unknownOption);
      expect(only('card bold').kind, CallingCardIssueKind.unknownOption);
    });

    test('a bad value keeps the default and names what was written', () {
      final layout = parse('title size=huge');
      expect(
        layout.issues.single,
        const CallingCardLayoutIssue(
          line: 1,
          kind: CallingCardIssueKind.badValue,
          subject: 'size',
          value: 'huge',
        ),
      );
      expect(layout.rows.single.single.size, 16);
      for (final bad in [
        'title size=2',
        'title size=200',
        'title color=red',
        'title lines=0',
        'title width=13',
        'title right=yes',
        'title bold=maybe',
        'title label',
        'figures beats=sometimes',
        'rule thickness=0',
        'space -1',
        'space 999',
        'card margin=-2',
      ]) {
        expect(only(bad).kind, CallingCardIssueKind.badValue, reason: bad);
      }
    });

    test('an unclosed quote drops the whole line', () {
      final layout = parse('title\ntext "oops');
      expect(layout.issues.single.kind, CallingCardIssueKind.unclosedQuote);
      expect(layout.issues.single.line, 2);
      expect(layout.rows, hasLength(1));
    });

    test('text needs words', () {
      expect(only('text').kind, CallingCardIssueKind.missingText);
      expect(only('text ""').kind, CallingCardIssueKind.missingText);
      expect(parse('text').rows, isEmpty);
    });

    test('card must be alone on its line', () {
      final layout = parse('card margin=4 | title');
      expect(layout.issues.single.kind, CallingCardIssueKind.cardNotAlone);
      expect(layout.margin, CallingCardLayout.defaultMargin);
      expect(layout.rows.single.single.kind, CallingCardBlockKind.title);
    });

    test('an empty side of | is reported', () {
      expect(only('title |').kind, CallingCardIssueKind.emptyBlock);
      expect(only('| title').kind, CallingCardIssueKind.emptyBlock);
    });

    test('a quoted block name is not a block', () {
      expect(only('"title"').kind, CallingCardIssueKind.unknownBlock);
    });
  });

  group('CallingCardSize', () {
    test('points and orientation', () {
      const s = CallingCardSize(5, 3, CallingCardUnit.inch);
      expect(s.widthPoints, 360);
      expect(s.heightPoints, 216);
      expect(s.isLandscape, isTrue);
      expect(
        s.oriented(landscape: false),
        const CallingCardSize(3, 5, CallingCardUnit.inch),
      );
      expect(s.oriented(landscape: true), s);
      expect(
        s.sameCardAs(const CallingCardSize(3, 5, CallingCardUnit.inch)),
        isTrue,
      );
      expect(
        s.sameCardAs(const CallingCardSize(3, 5, CallingCardUnit.millimetre)),
        isFalse,
      );
    });

    test('valid sides are 1 to 14 inches', () {
      expect(
        const CallingCardSize(1, 14, CallingCardUnit.inch).isValid,
        isTrue,
      );
      expect(
        const CallingCardSize(0.5, 3, CallingCardUnit.inch).isValid,
        isFalse,
      );
      expect(
        const CallingCardSize(5, 15, CallingCardUnit.inch).isValid,
        isFalse,
      );
      expect(
        const CallingCardSize(25.4, 50, CallingCardUnit.millimetre).isValid,
        isTrue,
      );
      expect(
        const CallingCardSize(double.nan, 3, CallingCardUnit.inch).isValid,
        isFalse,
      );
      for (final preset in kCallingCardSizePresets.values) {
        expect(preset.isValid, isTrue);
        expect(preset.isLandscape, isTrue);
      }
    });
  });

  group('CallingCardSettings', () {
    test('round-trips through JSON', () {
      const s = CallingCardSettings(
        enabled: true,
        size: CallingCardSize(148, 105, CallingCardUnit.millimetre),
        layout: 'title',
      );
      final json = s.toJson();
      expect(CallingCardSettings.isWellFormed(json), isTrue);
      expect(CallingCardSettings.fromJson(json), s);
    });

    test('the default layout is stored as absent', () {
      const s = CallingCardSettings(layout: kDefaultCallingCardLayout);
      expect(s.toJson().containsKey('layout'), isFalse);
      expect(CallingCardSettings.fromJson(s.toJson()).layout, isNull);
      expect(
        CallingCardSettings.fromJson({
          ...CallingCardSettings.defaults.toJson(),
          'layout': kDefaultCallingCardLayout,
        }).layout,
        isNull,
      );
      expect(
        CallingCardSettings.defaults.layoutSource,
        kDefaultCallingCardLayout,
      );
    });

    test('untrusted values fall back field by field', () {
      expect(CallingCardSettings.fromJson(null), CallingCardSettings.defaults);
      expect(CallingCardSettings.fromJson('x'), CallingCardSettings.defaults);
      final s = CallingCardSettings.fromJson({
        'enabled': 'yes',
        'width': 500,
        'height': 3,
        'unit': 'in',
        'layout': 7,
      });
      expect(s, CallingCardSettings.defaults);
      final kept = CallingCardSettings.fromJson({
        'enabled': true,
        'width': 4,
        'height': 6,
        'unit': 'ft',
        'layout': 'title',
      });
      expect(kept.enabled, isTrue);
      expect(kept.size, kDefaultCallingCardSize);
      expect(kept.layout, 'title');
    });

    test('isWellFormed rejects what fromJson would repair', () {
      final good = CallingCardSettings.defaults.toJson();
      expect(CallingCardSettings.isWellFormed(good), isTrue);
      for (final bad in <Object?>[
        null,
        [],
        {...good, 'enabled': 1},
        {...good, 'width': '5'},
        {...good, 'width': 0.1},
        {...good, 'unit': 'cm'},
        {...good, 'layout': false},
      ]) {
        expect(CallingCardSettings.isWellFormed(bad), isFalse, reason: '$bad');
      }
    });

    test(
      'several to a page round-trips; an older value reads as one per page',
      () {
        const s = CallingCardSettings(onSheets: true);
        expect(CallingCardSettings.fromJson(s.toJson()), s);
        final older = Map.of(CallingCardSettings.defaults.toJson())
          ..remove('sheets');
        expect(CallingCardSettings.isWellFormed(older), isTrue);
        expect(CallingCardSettings.fromJson(older).onSheets, isFalse);
        expect(
          CallingCardSettings.isWellFormed({...older, 'sheets': 'yes'}),
          isFalse,
        );
        expect(
          CallingCardSettings.fromJson({...older, 'sheets': 'yes'}).onSheets,
          isFalse,
        );
      },
    );

    test('copyWith can clear the layout', () {
      const s = CallingCardSettings(layout: 'title');
      expect(s.copyWith(layout: () => null).layout, isNull);
      expect(s.copyWith(enabled: true).layout, 'title');
    });
  });
}
