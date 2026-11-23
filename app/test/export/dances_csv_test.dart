import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/dances_csv.dart';
import 'package:compendium_app/src/export/export_labels_l10n.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'rfc4180_test_reader.dart';

/// The dances CSV export (#2332): what it carries, what it leaves out, and the
/// file format it always writes.
void main() {
  final now = DateTime.utc(2026, 11, 23);
  final en = lookupAppLocalizations(const Locale('en'));
  final plainRenderer = FigureRenderer(shippedTaxonomies.anyForm);

  final author = Choreographer(
    id: 'c1',
    name: 'Mary Example',
    email: 'mary.secret@example.invalid',
    location: 'Secretville, Nowhere',
    deceased: true,
  );
  final interpreter = Choreographer(
    id: 'c2',
    name: 'Ivan Interpreter',
    email: 'ivan.secret@example.invalid',
    location: 'Hiddenham',
  );
  final sharedField = CustomFieldDef(
    id: 'f-shared',
    key: 'season',
    label: 'Season',
    type: CustomFieldType.text,
  );
  final privateField = CustomFieldDef(
    id: 'f-private',
    key: 'privateNote',
    label: 'Private column',
    type: CustomFieldType.text,
    shareable: false,
  );
  final countField = CustomFieldDef(
    id: 'f-count',
    key: 'count',
    label: 'Count',
    type: CustomFieldType.number,
  );
  final userFigure = UserGlossaryEntry(
    id: 'uf1',
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'zoom',
    definition: 'A figure.',
    description: 'Of your own.',
    notes: 'MY-PRIVATE-FIGURE-NOTE',
    payload: {
      'form': 'contra',
      'template': '{who} zoom',
      'defaultBeats': 8,
      'params': [
        {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
      ],
    },
    createdAt: now,
  );
  final lookups = DancesCsvLookups(
    choreographersById: {author.id: author, interpreter.id: interpreter},
    tagsById: {'t1': Tag(id: 't1', name: 'Favourite')},
    sourcesById: {
      's1': PublishedSource(id: 's1', title: 'Zesty Contras', author: 'L.'),
    },
    customFields: [sharedField, privateField, countField],
  );

  Dance dance({
    String id = 'd1',
    String title = 'Petronella',
    int? rating,
    List<Figure> figures = const [],
    String callingNotes = '',
    List<CustomFieldValue> customFields = const [],
  }) => Dance(
    id: id,
    title: title,
    authorIds: [author.id],
    interpreterIds: [interpreter.id],
    figures: figures,
    callingNotes: callingNotes,
    rating: rating,
    tagIds: const ['t1'],
    tunes: const ['Reel'],
    meter: '2/4',
    musicalKey: 'D',
    mixer: true,
    customFields: customFields,
    sourceCitations: [SourceCitation(sourceId: 's1', page: '12')],
    createdAt: now,
    updatedAt: now,
  );

  String build(
    List<Dance> dances, {
    AppLocalizations? l10n,
    DialectsByForm? dialects,
    FigureRenderer? renderer,
  }) => buildDancesCsv(
    dances,
    l10n: l10n ?? en,
    dialects: dialects ?? DialectsByForm.all(Dialect.larksRobins),
    renderer: renderer ?? plainRenderer,
    lookups: lookups,
  );

  group('what stays private', () {
    test("an author's email, location and deceased mark never appear", () {
      final csv = build([dance()]);
      for (final secret in [
        'mary.secret@example.invalid',
        'Secretville',
        'ivan.secret@example.invalid',
        'Hiddenham',
      ]) {
        expect(csv, isNot(contains(secret)), reason: secret);
      }
      final row = csvRecords(csv).single;
      expect(row[en.csvColumnAuthors], 'Mary Example');
      expect(
        row[en.csvColumnInterpreters],
        'Ivan Interpreter',
        reason: 'the name alone: no deceased mark beside it',
      );
      expect(csv, isNot(contains('†')));
      expect(csv.toLowerCase(), isNot(contains('deceased')));
    });

    test('a note on one of your own figures never appears', () {
      final renderer = FigureRenderer(
        shippedTaxonomies.anyForm,
        userFigures: UserFigureCatalog.fromEntries([userFigure]),
      );
      final csv = build([
        dance(
          figures: [
            userFigureUseFigure(
              id: userFigure.id,
              args: const {'who': 'neighbors'},
              text: 'neighbors zoom',
              beats: 8,
            ),
          ],
        ),
      ], renderer: renderer);
      expect(
        csvRecords(csv).single[en.csvColumnFigures],
        contains('zoom'),
        reason: 'the figure itself is exported, worded as it reads',
      );
      expect(csv, isNot(contains('MY-PRIVATE-FIGURE-NOTE')));
    });

    test('a custom field with Include in sharing off has no column and no '
        'value', () {
      final csv = build([
        dance(
          customFields: [
            CustomFieldValue(fieldId: sharedField.id, value: 'Winter'),
            CustomFieldValue(fieldId: privateField.id, value: 'TOP-SECRET'),
            CustomFieldValue(fieldId: countField.id, value: -3.0),
          ],
        ),
      ]);
      expect(csv, isNot(contains('TOP-SECRET')));
      expect(csv, isNot(contains('Private column')));
      final row = csvRecords(csv).single;
      expect(row['Season'], 'Winter');
      expect(row['Count'], '-3', reason: 'a plain number is not guarded');
    });
  });

  group('the star rating, the one exception to the share rules', () {
    test(
      'a rated dance exports its rating and an unrated one an empty cell',
      () {
        final rows = csvRecords(
          build([
            dance(id: 'd1', title: 'Alpha', rating: 4),
            dance(id: 'd2', title: 'Bravo'),
          ]),
        );
        expect(rows.map((r) => r[en.csvColumnTitle]), ['Alpha', 'Bravo']);
        expect(rows[0][en.csvColumnRating], '4');
        expect(rows[1][en.csvColumnRating], '');
      },
    );

    test('the share sanitiser still drops the rating', () {
      expect(sanitizeDanceForShare(dance(rating: 4)).rating, isNull);
    });
  });

  group('the file format never follows the region', () {
    for (final locale in ['da', 'de', 'fr', 'nl', 'ja']) {
      test('commas and UTF-8 with a byte-order mark under $locale', () {
        final previous = Intl.defaultLocale;
        Intl.defaultLocale = locale;
        addTearDown(() => Intl.defaultLocale = previous);
        final l10n = lookupAppLocalizations(Locale(locale));
        final csv = build([
          dance(
            customFields: [
              CustomFieldValue(fieldId: countField.id, value: 2.5),
            ],
          ),
        ], l10n: l10n);

        expect(utf8.encode(csv).take(3), [0xEF, 0xBB, 0xBF]);
        expect(csv, isNot(contains(';')));
        final rows = readRfc4180(csv);
        expect(rows.first.first, l10n.csvColumnTitle);
        expect(rows.first, contains(l10n.csvColumnFigures));
        expect(rows[1].length, rows.first.length);
        expect(
          csvRecords(csv).single['Count'],
          '2.5',
          reason: 'a decimal point, never a decimal comma',
        );
      });
    }
  });

  test('formula-like titles and notes are written as text', () {
    final csv = build([
      dance(id: 'd1', title: '=HYPERLINK("http://example.invalid","x")'),
      dance(id: 'd2', title: 'Plus', callingNotes: '+1+1'),
      dance(id: 'd3', title: 'Minus', callingNotes: '-1+1'),
      dance(id: 'd4', title: 'At', callingNotes: '@SUM(A1)'),
    ]);
    final rows = csvRecords(csv);
    final byTitle = {for (final r in rows) r[en.csvColumnTitle]!: r};
    expect(
      byTitle.keys,
      contains('\'=HYPERLINK("http://example.invalid","x")'),
    );
    expect(byTitle['Plus']![en.csvColumnCallingNotes], "'+1+1");
    expect(byTitle['Minus']![en.csvColumnCallingNotes], "'-1+1");
    expect(byTitle['At']![en.csvColumnCallingNotes], "'@SUM(A1)");
  });

  test('commas, quotes, line breaks, accents and Japanese survive an RFC 4180 '
      'read', () {
    const title = 'Café, "the" ダンス';
    const notes = 'Line one, with a comma\nLine "two"';
    final row = csvRecords(
      build([dance(title: title, callingNotes: notes)]),
    ).single;
    expect(row[en.csvColumnTitle], title);
    expect(row[en.csvColumnCallingNotes], notes);
    expect(row[en.csvColumnTags], 'Favourite');
    expect(row[en.csvColumnTunes], 'Reel');
    expect(row[en.csvColumnSources], 'Zesty Contras — L. (p. 12)');
    expect(row[en.csvColumnMixer], en.commonYes);
    expect(row[en.csvColumnMixedLevel], en.commonNo);
  });

  test('figures are worded in the active dialect, as the text export words '
      'them', () {
    final figured = dance(
      figures: [
        Figure(move: 'allemande', params: const {'who': 'role1s', 'beats': 8}),
        Figure(
          move: 'swing',
          params: const {'who': 'partners', 'beats': 16},
          progression: true,
          note: 'role2s end on the right',
        ),
      ],
    );
    final dialects = DialectsByForm.all(Dialect.leadsFollows);
    final cell = csvRecords(
      build([figured], dialects: dialects),
    ).single[en.csvColumnFigures]!;

    final text = danceToPlainText(
      figured,
      dialect: Dialect.leadsFollows,
      authorNames: [author.name],
      formationLabel: '',
      statusLabel: '',
      renderer: plainRenderer,
      labels: danceExportLabels(en),
    );
    final heading = danceExportLabels(en).heading(en.exportLabelFigures);
    final lines = text.split('\n');
    final start = lines.indexOf(heading) + 1;
    final textFigures = lines
        .skip(start)
        .takeWhile((l) => l.isNotEmpty)
        .join('\n');

    expect(cell, textFigures);
    expect(cell, contains('leads'), reason: 'the injected dialect is used');
    expect(cell, isNot(contains('larks')));
    expect(cell, contains('follows end on the right'));
  });

  test('the Barnes reference and the composed and interpreted dates have '
      'columns of their own', () {
    final ecd = Dance(
      id: 'e1',
      title: 'Hole in the Wall',
      form: DanceForm.ecd,
      authorIds: [author.id],
      interpreterIds: [interpreter.id],
      barnesReference: 'BIII p. 92',
      composedOn: PartialDate(1951),
      interpretedOn: PartialDate(1916, 3, 14),
      createdAt: now,
      updatedAt: now,
    );
    final row = csvRecords(build([ecd])).single;
    expect(row[en.csvColumnBarnes], 'BIII p. 92');
    expect(row[en.csvColumnComposed], '1951');
    expect(row[en.csvColumnInterpreted], '1916-03-14');

    final contra = csvRecords(build([dance()])).single;
    expect(contra[en.csvColumnBarnes], '');
    expect(contra[en.csvColumnComposed], '');
    expect(contra[en.csvColumnInterpreted], '');
  });

  test('the file name is the localized stem and the date', () {
    expect(
      dancesCsvFileName('dances', DateTime(2026, 11, 23)),
      'dances_2026-11-23.csv',
    );
    expect(
      dancesCsvFileName('tänze', DateTime(2026, 11, 23)),
      'tänze_2026-11-23.csv',
    );
  });
}
