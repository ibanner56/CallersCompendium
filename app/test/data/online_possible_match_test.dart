import 'dart:convert';

import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/plaintext_program_import.dart';
import 'package:compendium_app/src/data/program_import_online_resolver.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// The #1907 reporter's case through the real single-dance online path: a
/// Caller's Box `A-1 Reel {variant}` arriving in a collection that holds
/// `A1 Reel` and `A1 Reel (Imp Var)`, all by Chris Weiler.
String _variantJson({String name = 'A-1 Reel {variant}'}) => jsonEncode({
  'ID': '1606',
  'Name': name,
  'Authors': ['Chris Weiler'],
  'Permission': 'full',
  'FormationBase': 'Duple Minor - Improper',
  'Progression': 'Single',
  'phrases': [
    {
      'name': 'A1',
      'figures': ['(4) Neighbor balance', '(12) Neighbor swing'],
    },
  ],
});

const String _searchHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the database, your query matches 1.</p>
<table>
<tr>
  <td>&#x24bb;</td><td></td><td></td>
  <td><a href='dance.php?id=1606' target='_blank'>A-1 Reel {variant}</a></td>
  <td>Chris Weiler</td>
  <td>Duple Minor - Improper</td>
</tr>
</table>
</body></html>
''';

Future<CompendiumRepositories> _reporterCollection() async {
  final repos = openTestRepositories();
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(id: 'weiler', name: 'Chris Weiler'),
  );
  final stamp = DateTime.utc(2026);
  for (final (id, title) in [
    ('base', 'A1 Reel'),
    ('impvar', 'A1 Reel (Imp Var)'),
  ]) {
    await repos.dances.create(
      Dance(
        id: id,
        title: title,
        authorIds: const ['weiler'],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
  }
  return repos;
}

CallersBoxOnline _service() => CallersBoxOnline(
  jsonFetcher: (_) async => _variantJson(),
  searchFetcher: (_) async => _searchHtml,
);

const _row = OnlineSearchResultRow(
  source: OnlineSource.callersBox,
  id: '1606',
  name: 'A-1 Reel {variant}',
  author: 'Chris Weiler',
  formation: '',
);

void main() {
  test('with no resolution, a possible match is offered and nothing is '
      'written', () async {
    final repos = await _reporterCollection();
    final service = _service();
    final preview = await service.loadPreview(repos, _row);
    expect(preview.plan.verdict.isNewDance, isTrue);

    final result = await service.import(repos, preview.plan);

    expect(result.kind, OnlineImportKind.needsPossibleMatchChoice);
    expect(result.possibleMatchIds, ['base', 'impvar']);
    expect(await repos.dances.listAll(), hasLength(2));
  });

  test('an ambiguous verdict with no confident candidate is offered its '
      'possible matches too', () async {
    final repos = await _reporterCollection();
    final service = CallersBoxOnline(
      jsonFetcher: (_) async => _variantJson(name: 'A-1 Reel'),
    );
    final preview = await service.loadPreview(repos, _row);
    expect(preview.plan.verdict.isAmbiguous, isTrue);
    expect(preview.plan.verdict.hasConfidentMatch, isFalse);

    final result = await service.import(repos, preview.plan);

    expect(result.kind, OnlineImportKind.needsPossibleMatchChoice);
    expect(result.possibleMatchIds, ['base', 'impvar']);
    expect(await repos.dances.listAll(), hasLength(2));
  });

  test(
    'the chosen dance is replaced, though the verdict is still new',
    () async {
      final repos = await _reporterCollection();
      final service = _service();
      final preview = await service.loadPreview(repos, _row);

      final result = await service.import(
        repos,
        preview.plan,
        ambiguousResolution: DedupeResolution.link('impvar'),
      );

      expect(result.kind, OnlineImportKind.created);
      expect(result.danceId, 'impvar');
      final all = {for (final d in await repos.dances.listAll()) d.id: d};
      expect(all.keys, unorderedEquals(['base', 'impvar']));
      expect(all['impvar']!.title, 'A-1 Reel {variant}');
      expect(all['base']!.title, 'A1 Reel');
    },
  );

  test('"import as new" creates a dance and replaces nothing', () async {
    final repos = await _reporterCollection();
    final service = _service();
    final preview = await service.loadPreview(repos, _row);

    final result = await service.import(
      repos,
      preview.plan,
      ambiguousResolution: DedupeResolution.duplicate(),
    );

    expect(result.kind, OnlineImportKind.created);
    expect(await repos.dances.listAll(), hasLength(3));
    expect((await repos.dances.getById('impvar'))!.title, 'A1 Reel (Imp Var)');
  });

  test('the unattended program resolver still imports a new dance and never '
      'acts on a possible match', () async {
    final repos = await _reporterCollection();

    final resolved = await resolveUnmatchedOnline(
      [
        ParsedProgramLine(
          text: 'A-1 Reel {variant}',
          resolution: PlaintextLineResolution.unmatched,
        ),
      ],
      service: _service(),
      repos: repos,
    );

    expect(resolved.single.importedOnline, isTrue);
    final linked = resolved.single.danceId;
    expect(linked, isNot(anyOf('base', 'impvar')));
    final all = {for (final d in await repos.dances.listAll()) d.id: d};
    expect(all, hasLength(3));
    expect(all['impvar']!.title, 'A1 Reel (Imp Var)');
    expect(all[linked]!.title, 'A-1 Reel {variant}');
  });
}
