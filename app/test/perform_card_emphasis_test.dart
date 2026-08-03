import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';
import 'package:compendium_core/testing.dart';

final _renderer = FigureRenderer(contraTaxonomy);
final _now = DateTime.utc(2026, 1, 1);

Dance _danceWith(List<Figure> figures) => Dance(
  id: 'd1',
  title: 'Test Dance',
  form: DanceForm.contra,
  formation: const Formation(FormationShape.becketCw),
  figures: figures,
  createdAt: _now,
  updatedAt: _now,
);

Future<FormationColorsController> _controller() async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();
  final controller = FormationColorsController(repos.settings);
  await controller.load();
  return controller;
}

Future<void> _pump(WidgetTester tester, Dance dance) async {
  final c = await _controller();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

      home: Scaffold(
        body: FormationColorsScope(
          controller: c,
          child: PerformCard(
            dance: dance,
            renderer: _renderer,
            dialect: Dialect.larksRobins,
            textScale: 1.0,
          ),
        ),
      ),
    ),
  );
}

/// Collects the leaf `TextSpan`s (text + effective style) from any rich [Text]
/// whose flattened content equals [plain].
List<TextSpan> _leafSpansFor(WidgetTester tester, String plain) {
  final matches = <TextSpan>[];
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final span = widget.textSpan;
    if (span == null) continue;
    if (span.toPlainText() != plain) continue;
    span.visitChildren((s) {
      if (s is TextSpan && (s.text?.isNotEmpty ?? false)) matches.add(s);
      return true;
    });
  }
  return matches;
}

void main() {
  testWidgets('note markup renders as bold / underline spans', (tester) async {
    await _pump(
      tester,
      _danceWith([
        Figure(
          move: 'swing',
          params: const {'who': 'partners', 'beats': 16},
          note: 'say *this* and _that_',
        ),
      ]),
    );

    final spans = _leafSpansFor(tester, 'say this and that');
    expect(spans, isNotEmpty, reason: 'note should render as a rich Text');

    final bold = spans.firstWhere((s) => s.text == 'this');
    expect(bold.style?.fontWeight, FontWeight.bold);
    expect(bold.style?.decoration, isNot(TextDecoration.underline));

    final under = spans.firstWhere((s) => s.text == 'that');
    expect(under.style?.decoration, TextDecoration.underline);
    expect(under.style?.fontWeight, isNot(FontWeight.bold));
  });

  testWidgets('note semantics announces words without markup delimiters', (
    tester,
  ) async {
    await _pump(
      tester,
      _danceWith([
        Figure(
          move: 'swing',
          params: const {'who': 'partners', 'beats': 16},
          note: 'say *this* and _that_',
        ),
      ]),
    );

    // The stray * / _ delimiters must never appear in the semantics tree.
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp(r'note: say this and that')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'[*_]')), findsNothing);
    handle.dispose();
  });

  testWidgets('custom-figure markup is styled and dialect-substituted', (
    tester,
  ) async {
    await _pump(
      tester,
      _danceWith([
        testFigure(
          move: customMove,
          params: const {'text': '*role1s* cross the set', 'beats': 8},
        ),
      ]),
    );

    // larksRobins substitutes the role token "role1s" -> "larks"; the emphasis
    // span carries the substituted text AND the bold styling (delimiters
    // stripped before substitution so they never block the role boundary).
    final spans = _leafSpansFor(tester, 'larks cross the set');
    expect(spans, isNotEmpty);
    final bold = spans.firstWhere((s) => s.text == 'larks');
    expect(bold.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('custom underline semantics announces the substituted word', (
    tester,
  ) async {
    await _pump(
      tester,
      _danceWith([
        testFigure(
          move: customMove,
          params: const {'text': '_role1s_ swing', 'beats': 8},
        ),
      ]),
    );

    final handle = tester.ensureSemantics();
    // The label must announce the dialect-substituted word ("larks"), never the
    // raw role token or the underscore delimiters.
    expect(find.bySemanticsLabel(RegExp('larks swing')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('role1s')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('_')), findsNothing);
    handle.dispose();
  });

  testWidgets('non-custom canonical line is plain (no emphasis parsing)', (
    tester,
  ) async {
    await _pump(
      tester,
      _danceWith([
        Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
      ]),
    );
    // A canonical line renders as a plain Text (no TextSpan children).
    final plain = tester.widgetList<Text>(find.byType(Text)).where((w) {
      return w.data != null && w.data!.contains('swing');
    });
    expect(plain, isNotEmpty);
  });

  testWidgets('malformed markup degrades to literal text, no crash', (
    tester,
  ) async {
    await _pump(
      tester,
      _danceWith([
        Figure(
          move: 'swing',
          params: const {'who': 'partners', 'beats': 16},
          note: 'unterminated *bold and _under',
        ),
      ]),
    );
    expect(tester.takeException(), isNull);
    final spans = _leafSpansFor(tester, 'unterminated *bold and _under');
    expect(spans, isNotEmpty);
  });
}
