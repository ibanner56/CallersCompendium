import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/dance_source_lines.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  PublishedSource source(String id, {String? author, int? year}) =>
      PublishedSource(
        id: id,
        title: 'Give-and-Take',
        author: author,
        year: year,
        url: 'https://example.org/secret-link',
      );

  Dance cited(List<SourceCitation> citations) => Dance(
    id: 'd1',
    title: 'Cited',
    sourceCitations: citations,
    createdAt: now,
    updatedAt: now,
  );

  test('prints title, author, year, page and number; never the URL', () {
    final lines = danceSourceLines(
      l10n,
      cited([SourceCitation(sourceId: 's1', page: '12', number: 'A1')]),
      (id) => source(id, author: 'A. Author', year: 1990),
    );
    expect(lines, ['Give-and-Take — A. Author, 1990 (p. 12, no. A1)']);
    expect(lines.single, isNot(contains('example.org')));
  });

  test('omits what is absent', () {
    expect(
      danceSourceLines(
        l10n,
        cited([SourceCitation(sourceId: 's1')]),
        (id) => source(id),
      ),
      ['Give-and-Take'],
    );
  });

  test('a purged source keeps its page under the unknown-source title', () {
    expect(
      danceSourceLines(
        l10n,
        cited([SourceCitation(sourceId: 'gone', page: '3')]),
        (_) => null,
      ),
      ['(unknown source) (p. 3)'],
    );
  });

  test('one line per citation, in order', () {
    final lines = danceSourceLines(
      l10n,
      cited([
        SourceCitation(sourceId: 'a', page: '1'),
        SourceCitation(sourceId: 'b', page: '2'),
      ]),
      (id) => source(id),
    );
    expect(lines, ['Give-and-Take (p. 1)', 'Give-and-Take (p. 2)']);
  });
}
