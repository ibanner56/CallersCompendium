import 'package:compendium_app/src/screens/dance_editor/phrase_groups_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/screen_size.dart';

/// What [_pump] hands back: the formula text field's controller, standing in
/// for the dance editor's phrase controller, and every text the rows wrote.
typedef _Host = ({TextEditingController formula, List<String> written});

Future<_Host> _pump(
  WidgetTester tester, {
  String text = '',
  Locale locale = const Locale('en'),
  double textScale = 1,
  Size size = const Size(800, 1400),
}) async {
  await setScreenSize(tester, size);
  final formula = TextEditingController(text: text);
  addTearDown(formula.dispose);
  final written = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: formula,
            builder: (context, _) {
              PhraseStructure? structure;
              try {
                structure = PhraseStructure.parse(formula.text);
              } on FormatException {
                structure = null;
              }
              return Column(
                children: [
                  PhraseGroupsEditor(
                    title: 'Phrase structure',
                    structure: structure,
                    onChanged: (raw, {required typed}) {
                      written.add(raw);
                      formula.text = raw;
                    },
                  ),
                  TextField(
                    key: const ValueKey('formula'),
                    controller: formula,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (formula: formula, written: written);
}

Finder _field(int row, String name) =>
    find.byKey(ValueKey('phrase-row-$row-$name'));

String? _text(WidgetTester tester, int row, String name) =>
    tester.widget<TextField>(_field(row, name)).controller?.text;

bool _enabled(WidgetTester tester, int row, String name) =>
    tester.widget<TextField>(_field(row, name)).enabled ?? true;

Future<void> _enter(
  WidgetTester tester,
  int row,
  String name,
  String text,
) async {
  await tester.enterText(_field(row, name), text);
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('formula')), text);
  await tester.pump();
}

void main() {
  group('the rows show the text', () {
    // The four structures from #2304, as The Caller's Box lists them.
    const examples = {
      '8*8*2': [('8', '8', '2')],
      '4*4*3': [('4', '4', '3')],
      '3*8*2 + 1*4*2': [('3', '8', '2'), ('1', '4', '2')],
      '2*8*2 + 2*10*2': [('2', '8', '2'), ('2', '10', '2')],
    };
    for (final MapEntry(key: text, value: rows) in examples.entries) {
      testWidgets(text, (tester) async {
        await _pump(tester, text: text);
        for (final (index, (phrases, bars, beats)) in rows.indexed) {
          expect(_text(tester, index, 'phrases'), phrases);
          expect(_text(tester, index, 'bars'), bars);
          expect(_text(tester, index, 'beats'), beats);
        }
        expect(_field(rows.length, 'bars'), findsNothing);
      });
    }

    testWidgets('a blank structure is the standard one row', (tester) async {
      await _pump(tester);
      expect(_text(tester, 0, 'phrases'), '4');
      expect(_text(tester, 0, 'bars'), '8');
      expect(_text(tester, 0, 'beats'), '2');
    });

    testWidgets('and read back as labels and beats', (tester) async {
      await _pump(tester, text: '2*8*2 + 2*10*2');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('phrase-rows-summary')))
            .data,
        'A1 A2 B1 B2 · 72 beats',
      );
    });

    testWidgets('and nothing shows while the stored text does not parse', (
      tester,
    ) async {
      await _pump(tester, text: '2*8');
      expect(find.byKey(const ValueKey('phrase-rows')), findsNothing);
    });
  });

  group('a row edit writes the unnamed text', () {
    testWidgets('a bar count changes one component, as the formula spells it', (
      tester,
    ) async {
      final host = await _pump(tester, text: '2*8*2 + 2*10*2');
      await _enter(tester, 1, 'bars', '9');
      expect(host.written, ['2*8*2 + 2*9*2']);
      expect(host.formula.text, '2*8*2 + 2*9*2');
    });

    testWidgets('slip jig: beats per bar 3', (tester) async {
      final host = await _pump(tester, text: '8*8*2');
      await _enter(tester, 0, 'phrases', '4');
      await _enter(tester, 0, 'bars', '4');
      await _enter(tester, 0, 'beats', '3');
      expect(host.written.last, '4*4*3');
    });

    testWidgets('rows that equal the standard write blank', (tester) async {
      final host = await _pump(tester, text: '4*6*2');
      await _enter(tester, 0, 'bars', '8');
      expect(host.written, ['']);
      expect(host.formula.text, '');
    });

    testWidgets('adding a row appends one phrase of 8 bars in the last '
        "row's beats; removing it goes back", (tester) async {
      final host = await _pump(tester, text: '8*8*3');
      await tester.tap(find.byKey(const ValueKey('phrase-rows-add')));
      await tester.pump();
      expect(host.written, ['8*8*3 + 1*8*3']);
      await tester.tap(find.byKey(const ValueKey('phrase-row-1-remove')));
      await tester.pump();
      expect(host.written, ['8*8*3 + 1*8*3', '8*8*3']);
      // One row has nothing to remove.
      expect(find.byKey(const ValueKey('phrase-row-0-remove')), findsNothing);
    });

    testWidgets('removing a middle row writes the others, in order, and the '
        'rows after it take its place', (tester) async {
      final host = await _pump(tester, text: '2*8*2 + 3*4*3 + 1*6*2');
      await tester.tap(find.byKey(const ValueKey('phrase-row-1-remove')));
      await tester.pump();
      expect(host.written, ['2*8*2 + 1*6*2']);
      expect(_text(tester, 1, 'phrases'), '1');
      expect(_text(tester, 1, 'bars'), '6');
      expect(_text(tester, 1, 'beats'), '2');
      expect(_field(2, 'bars'), findsNothing);
    });

    testWidgets('opening a structure writes nothing', (tester) async {
      final host = await _pump(tester, text: '2*8*2+2*10*2');
      expect(host.written, isEmpty);
      expect(host.formula.text, '2*8*2+2*10*2');
    });

    testWidgets('a value re-entered as it was keeps imported text as it is', (
      tester,
    ) async {
      final host = await _pump(tester, text: '3*8*2+1*4*2');
      // `08` is a different text for the field and the same number for the row.
      await _enter(tester, 0, 'bars', '08');
      expect(host.written, isEmpty);
      expect(host.formula.text, '3*8*2+1*4*2');
    });
  });

  group('an invalid row writes nothing and says why', () {
    for (final bars in ['', '0', '1001']) {
      testWidgets('bars "$bars"', (tester) async {
        final host = await _pump(tester, text: '2*8*2');
        await _enter(tester, 0, 'bars', bars);
        expect(host.written, isEmpty);
        expect(
          find.byKey(const ValueKey('phrase-rows-invalid')),
          findsOneWidget,
        );
        expect(find.text('1 to 1000'), findsOneWidget);
        // The next valid number writes again.
        await _enter(tester, 0, 'bars', '9');
        expect(host.written, ['2*9*2']);
        expect(find.byKey(const ValueKey('phrase-rows-invalid')), findsNothing);
      });
    }

    testWidgets('more beats than a structure may hold', (tester) async {
      final host = await _pump(tester, text: '1000*500*2');
      await _enter(tester, 0, 'bars', '501');
      expect(host.written, isEmpty);
      expect(find.byKey(const ValueKey('phrase-rows-invalid')), findsOneWidget);
    });

    testWidgets('more phrases than a structure may hold', (tester) async {
      final host = await _pump(tester, text: '1000*8*2');
      await tester.tap(find.byKey(const ValueKey('phrase-rows-add')));
      await tester.pump();
      expect(host.written, isEmpty);
      expect(find.byKey(const ValueKey('phrase-rows-invalid')), findsOneWidget);
    });

    testWidgets('no row is offered past the most components', (tester) async {
      await _pump(
        tester,
        text: List.filled(PhraseStructure.maxComponents, '1*1*1').join(' + '),
        size: const Size(800, 40000),
      );
      expect(find.byKey(const ValueKey('phrase-rows-add')), findsNothing);
    });
  });

  group('the rows follow the text', () {
    testWidgets('a formula typed in the field loads the rows', (tester) async {
      await _pump(tester, text: '4*8*2');
      await _type(tester, '6*8*2 + 1*4*3');
      expect(_text(tester, 0, 'phrases'), '6');
      expect(_text(tester, 1, 'beats'), '3');
    });

    testWidgets('a row typed into keeps its field and its caret', (
      tester,
    ) async {
      final host = await _pump(tester, text: '4*8*2');
      final before = tester.widget<TextField>(_field(0, 'bars')).controller;
      await _enter(tester, 0, 'bars', '1');
      await _enter(tester, 0, 'bars', '10');
      expect(host.written, ['4*1*2', '4*10*2']);
      // Writing its own text must not rebuild the rows under the caller.
      expect(
        identical(
          tester.widget<TextField>(_field(0, 'bars')).controller,
          before,
        ),
        isTrue,
      );
    });
  });

  group('while the formula is not valid', () {
    testWidgets('the rows stay, disabled, with the last valid structure', (
      tester,
    ) async {
      final host = await _pump(tester, text: '2*8*2');
      await _type(tester, '2*8*2 +');
      expect(_text(tester, 0, 'bars'), '8');
      expect(_enabled(tester, 0, 'bars'), isFalse);
      expect(_enabled(tester, 0, 'phrases'), isFalse);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('phrase-rows-add')))
            .onPressed,
        isNull,
      );
      expect(host.written, isEmpty);
    });

    testWidgets('and enable again when the text is as it was', (tester) async {
      final host = await _pump(tester, text: '2*8*2');
      await _type(tester, '2*8*2 +');
      await _type(tester, '2*8*2');
      expect(_enabled(tester, 0, 'bars'), isTrue);
      await _enter(tester, 0, 'bars', '9');
      expect(host.written, ['2*9*2']);
    });

    testWidgets('phrase names, which this form cannot keep, disable them too '
        'and write nothing', (tester) async {
      final host = await _pump(tester, text: '2*8*2');
      await _type(tester, 'A:2*8*2 + B:2*8*2');
      expect(_enabled(tester, 0, 'bars'), isFalse);
      expect(_text(tester, 0, 'bars'), '8');
      expect(_field(1, 'bars'), findsNothing);
      expect(host.written, isEmpty);
      await _type(tester, '2*8*2');
      expect(_enabled(tester, 0, 'bars'), isTrue);
    });

    testWidgets('and load the rows once the text parses', (tester) async {
      await _pump(tester, text: '2*8');
      await _type(tester, '5*8*2');
      expect(_text(tester, 0, 'phrases'), '5');
      expect(_enabled(tester, 0, 'phrases'), isTrue);
    });

    // The formula field sits under the rows, so a row set that grew or shrank
    // when it was disabled would move the field under the caller's caret.
    for (final scale in [1.0, 2.0]) {
      for (final locale in testSupportedLocales) {
        for (final width in [800.0, 320.0]) {
          testWidgets('the formula field does not move at text scale $scale '
              'in ${locale.languageCode} at $width dp', (tester) async {
            await _pump(
              tester,
              text: '2*8*2 + 2*10*2',
              locale: locale,
              textScale: scale,
              size: Size(width, 2400),
            );
            final field = find.byKey(const ValueKey('formula'));
            final before = tester.getTopLeft(field);
            await _type(tester, '2*8*2 +');
            expect(tester.getTopLeft(field), before);
            await _type(tester, 'A:2*8*2 + B:2*8*2');
            expect(tester.getTopLeft(field), before);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  // A label grows with the text size, so its field must, to the width there
  // is: the labels read in the fields (Bars per phrase, Mesures par phrase).
  for (final (scale, width, expected) in [
    (1.0, 800.0, 128.0),
    (2.0, 800.0, 256.0),
    (3.0, 800.0, 384.0),
    (3.0, 320.0, 320.0),
  ]) {
    testWidgets(
      'a number field is $expected dp wide at text scale $scale in $width dp',
      (tester) async {
        await _pump(
          tester,
          text: '2*8*2',
          textScale: scale,
          size: Size(width, 2400),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('phrase-row-0-bars'))).width,
          expected,
        );
      },
    );
  }

  testWidgets('three rows fit 320 dp at twice the text size', (tester) async {
    await _pump(
      tester,
      text: '2*8*2 + 2*10*2 + 1*4*3',
      textScale: 2,
      size: const Size(320, 2400),
    );
    expect(tester.takeException(), isNull);
  });
}
