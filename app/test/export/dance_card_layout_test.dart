import 'package:compendium_app/src/export/dance_pdf.dart';
import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The PDF byte tests only see `%PDF`; these assert what is actually laid out,
/// via the widget lists the builders produce from a `DanceCardContent`.
void main() {
  final now = DateTime.utc(2026, 1, 1);
  const labels = DanceExportLabels();
  final fig = FigureRenderer(contraTaxonomy);

  Dance dance({
    String callingNotes = ' The role1s lead out. ',
    String walkthrough = 'Everyone forms a big circle.',
    List<String> tunes = const ['Tune One'],
    String hook = '',
  }) => Dance(
    id: 'd1',
    title: "Rory O'More",
    callingNotes: callingNotes,
    walkthrough: walkthrough,
    tunes: tunes,
    hook: hook,
    figures: [
      Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
    ],
    createdAt: now,
    updatedAt: now,
  );

  DanceCardContent content(
    Dance d, {
    Set<DanceShareField> fields = DanceShareField.allExceptTunes,
    Dialect? dialect,
    List<String> sourceLines = const [],
  }) => DanceCardContent.build(
    d,
    dialect: dialect ?? Dialect.canonical,
    authorNames: const ['Carol Ormand'],
    formationLabel: 'Duple improper',
    statusLabel: 'Active',
    renderer: fig,
    labels: labels,
    fields: fields,
    sourceLines: sourceLines,
  );

  /// Every string a list of widgets lays out (headers and text).
  List<String> textsOf(Iterable<pw.Widget> widgets) => [
    for (final w in widgets)
      if (w is pw.Header)
        ...textsOf([?w.child])
      else if (w is pw.RichText)
        w.text.toPlainText(),
  ];

  List<pw.Widget> danceCard(Dance d, DanceCardContent c, Dialect dialect) =>
      danceCardWidgets(d, c, fig, dialect, labels);

  group('danceCardWidgets', () {
    test('omits calling notes when the field is deselected', () {
      final d = dance();
      final withNotes = textsOf(danceCard(d, content(d), Dialect.canonical));
      expect(withNotes, contains(labels.callingNotes));
      expect(withNotes, contains('The role1s lead out.'));

      final without = textsOf(
        danceCard(
          d,
          content(d, fields: {DanceShareField.walkthrough}),
          Dialect.canonical,
        ),
      );
      expect(without, isNot(contains(labels.callingNotes)));
      expect(without, isNot(contains('The role1s lead out.')));
      expect(without, contains('Everyone forms a big circle.'));
    });

    test('renders walkthrough in the requested dialect', () {
      final d = dance(walkthrough: 'The role1s circle left.');
      final canonical = textsOf(danceCard(d, content(d), Dialect.canonical));
      final larks = textsOf(
        danceCard(
          d,
          content(d, dialect: Dialect.larksRobins),
          Dialect.larksRobins,
        ),
      );
      expect(canonical, contains('The role1s circle left.'));
      expect(larks, contains('The larks circle left.'));
      expect(larks, isNot(contains('The role1s circle left.')));
    });

    test('omits blank notes and walkthrough headings', () {
      final d = dance(callingNotes: '  ', walkthrough: '');
      final texts = textsOf(danceCard(d, content(d), Dialect.canonical));
      expect(texts, isNot(contains(labels.callingNotes)));
      expect(texts, isNot(contains(labels.walkthrough)));
    });

    test('tunes appear only when selected', () {
      final d = dance();
      expect(
        textsOf(danceCard(d, content(d), Dialect.canonical)),
        isNot(contains('Tune One')),
      );
      expect(
        textsOf(
          danceCard(
            d,
            content(d, fields: DanceShareField.all),
            Dialect.canonical,
          ),
        ),
        contains('Tune One'),
      );
    });
  });

  const sourceLines = ['Give-and-Take — A. Author, 1990 (p. 12)'];

  group('hook and sources (OUT-6)', () {
    test('appear on the dance PDF only when selected', () {
      final d = dance(hook: 'Open with a long swing');
      final off = textsOf(danceCard(d, content(d), Dialect.canonical));
      expect(off, isNot(contains('${labels.hook}: Open with a long swing')));
      expect(off, isNot(contains(labels.sources)));

      final on = textsOf(
        danceCard(
          d,
          content(
            d,
            fields: {DanceShareField.hook, DanceShareField.sources},
            sourceLines: sourceLines,
          ),
          Dialect.canonical,
        ),
      );
      expect(on, contains('${labels.hook}: Open with a long swing'));
      expect(on, contains(labels.sources));
      expect(on, contains(sourceLines.single));
    });
  });

  group('programAppendixWidgets', () {
    List<pw.Widget> appendix(
      Dance d, {
      required bool withContent,
      Set<DanceShareField> fields = DanceShareField.allExceptTunes,
      Dialect? dialect,
      List<String> sources = const [],
    }) => programAppendixWidgets(
      [
        (
          dance: d,
          isAlternate: false,
          content: withContent
              ? content(
                  d,
                  fields: fields,
                  dialect: dialect,
                  sourceLines: sources,
                )
              : null,
        ),
      ],
      fig,
      dialect ?? Dialect.canonical,
      labels,
      const ProgramExportLabels(),
    );

    test('program appendix card and dance PDF carry the same notes text', () {
      for (final fields in [
        DanceShareField.allExceptTunes,
        DanceShareField.all,
        {DanceShareField.walkthrough},
        <DanceShareField>{},
      ]) {
        final d = dance();
        final c = content(d, fields: fields, dialect: Dialect.larksRobins);
        final card = textsOf(danceCard(d, c, Dialect.larksRobins));
        final appended = textsOf(
          appendix(
            d,
            withContent: true,
            fields: fields,
            dialect: Dialect.larksRobins,
          ),
        );
        final reason = fields.map((f) => f.name).toList().toString();
        for (final block in [
          labels.callingNotes,
          c.callingNotes,
          labels.walkthrough,
          c.walkthrough,
          'Tune One',
        ]) {
          if (block == null) continue;
          expect(
            appended.contains(block),
            card.contains(block),
            reason: reason,
          );
        }
      }
    });

    test('without card labels the appendix is title and figures only', () {
      final texts = textsOf(
        appendix(dance(), withContent: false, fields: DanceShareField.all),
      );
      expect(texts, contains("Rory O'More"));
      expect(texts, isNot(contains(labels.callingNotes)));
      expect(texts, isNot(contains(labels.walkthrough)));
      expect(texts, isNot(contains('Carol Ormand')));
    });

    group('a dance with no structured figures (OUT-10)', () {
      Dance figureless() => Dance(
        id: 'd2',
        title: 'Notes Only Reel',
        callingNotes: 'Watch the slide.',
        walkthrough: 'Circle left.',
        figures: const [],
        createdAt: now,
        updatedAt: now,
      );

      test('still gets its card when notes or a walkthrough are selected', () {
        final d = figureless();
        final texts = textsOf(
          appendix(
            d,
            withContent: true,
            fields: DanceShareField.allExceptTunes,
          ),
        );
        expect(texts, contains('Notes Only Reel'));
        expect(texts, contains('Watch the slide.'));
        expect(texts, contains('Circle left.'));
      });

      test('gets a card for a selected hook or source alone (OUT-6)', () {
        final d = Dance(
          id: 'd3',
          title: 'Cited Reel',
          hook: 'Starts with a pass-through',
          figures: const [],
          createdAt: now,
          updatedAt: now,
        );
        final texts = textsOf(
          appendix(
            d,
            withContent: true,
            fields: {DanceShareField.hook, DanceShareField.sources},
            sources: sourceLines,
          ),
        );
        expect(texts, contains('Cited Reel'));
        expect(texts, contains('${labels.hook}: Starts with a pass-through'));
        expect(texts, contains(labels.sources));
        expect(texts, contains(sourceLines.single));
        // Deselected: nothing to put beneath the title, so no card.
        expect(
          textsOf(
            appendix(
              d,
              withContent: true,
              fields: {DanceShareField.formation},
              sources: sourceLines,
            ),
          ),
          isEmpty,
        );
      });

      test('gets no card when neither field is selected', () {
        final texts = textsOf(
          appendix(
            figureless(),
            withContent: true,
            fields: {DanceShareField.formation},
          ),
        );
        expect(texts, isEmpty);
      });

      test('gets no card in the figures-only appendix (no card content)', () {
        final texts = textsOf(
          appendix(
            figureless(),
            withContent: false,
            fields: DanceShareField.all,
          ),
        );
        expect(texts, isEmpty);
      });
    });

    test('a deselected field is absent and a selected one present', () {
      final d = dance();
      final only = textsOf(
        appendix(d, withContent: true, fields: {DanceShareField.callingNotes}),
      );
      expect(only, contains('The role1s lead out.'));
      expect(only, isNot(contains('Everyone forms a big circle.')));
    });
  });

  group('page format', () {
    testWidgets('buildDancePdf and buildProgramPdf accept a page format', (
      tester,
    ) async {
      final d = dance();
      expect(
        await buildDancePdf(
          d,
          dialect: Dialect.canonical,
          authorNames: const [],
          formationLabel: 'Duple improper',
          statusLabel: 'Active',
          pageFormat: PdfPageFormat.letter,
        ),
        isNotEmpty,
      );
      expect(
        await buildProgramPdf(
          Program(id: 'p1', title: 'Night', createdAt: now, updatedAt: now),
          titleFor: (_) => null,
          pageFormat: PdfPageFormat.letter,
        ),
        isNotEmpty,
      );
    });
  });
}
