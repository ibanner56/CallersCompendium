// Opt-in live check of the ContraDB Advanced translation. Not shipped, and never
// run by CI or by the test suite: it sends a handful of real requests to
// https://contradb.com/api/v1/dances. Run from `packages/compendium_core/`:
//
//     dart run tool/check_contradb_translation_live.dart
//
// What it checks: that the server ACCEPTS every operator the translator emits
// (`and`, `or`, `no`, `&`, `not`, `then`, `figure`), by sending one expression
// for each and reporting the HTTP status and `numberMatching`. A server error
// here means the translator emits something ContraDB rejects.
//
// What it does not check: that the matched dances are the right ones. That
// rests on reading ContraDB's `lib/filter_dances.rb` and `lib/search_match.rb`;
// compare the counts below with the same search typed into contradb.com's own
// advanced search if a result looks wrong.
//
// Be polite: ContraDB scans every dance for each request, so this sends one
// request per expression, with `count` 1, and nothing else.
import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';

Future<void> main() async {
  final cases = <String, DanceFilter>{
    'figure': FigureFilter.leaf('swing'),
    'or (two moves)': FigureFilter.leaf('allemande'),
    'and': AndFilter([FigureFilter.leaf('swing'), FigureFilter.leaf('chain')]),
    'no': NotFilter(FigureFilter.leaf('hey')),
    '& (same figure)': FigureFilter(
      FigureAnd([FigureLeaf('swing'), FigureLeaf('balance')]),
    ),
    'not (figurewise)': FigureFilter(
      FigureAnd([FigureLeaf('swing'), FigureNot(FigureLeaf('balance'))]),
    ),
    'alias: see saw': FigureFilter.leaf('see_saw'),
    'alias: swat the flea': FigureFilter.leaf('swat_the_flea'),
    'do si do (& not see saw)': FigureFilter.leaf('do_si_do'),
    'box the gnat (& not swat)': FigureFilter.leaf('box_the_gnat'),
    'pull by (or of two)': FigureFilter.leaf('pull_by'),
    'then': ThenFilter(FigureLeaf('swing'), FigureLeaf('chain')),
    'then (wrap)': ThenFilter(FigureLeaf('chain'), FigureLeaf('swing')),
  };

  final client = HttpClient();
  var failures = 0;
  try {
    for (final entry in cases.entries) {
      final translation = translateDanceFilterToContraDb(entry.value);
      if (translation is! ContraDbAdvancedExpression) {
        stdout.writeln(
          'REFUSED  ${entry.key}: ${(translation as ContraDbAdvancedRefused).reason}',
        );
        failures++;
        continue;
      }
      final body = buildContraDbFilterBody(translation.expression, count: 1);
      final request = await client.postUrl(
        Uri.parse('https://contradb.com/api/v1/dances'),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final text = await utf8.decodeStream(response);
      var detail = '';
      if (response.statusCode == 200) {
        final decoded = jsonDecode(text);
        detail = decoded is Map
            ? 'numberMatching=${decoded['numberMatching']} '
                  'numberSearched=${decoded['numberSearched']}'
            : 'unexpected body';
      } else {
        failures++;
      }
      stdout.writeln(
        '${response.statusCode == 200 ? 'ok      ' : 'REJECTED'} '
        '${entry.key.padRight(18)} ${jsonEncode(translation.expression)}  $detail',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  } finally {
    client.close();
  }
  stdout.writeln(failures == 0 ? '\nAll accepted.' : '\n$failures failed.');
  exit(failures == 0 ? 0 : 1);
}
