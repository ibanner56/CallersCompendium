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
// What it shows, for a person to read: the figure text ContraDB matched in the
// first few dances (`matching_figures_html`, tags stripped), so a value mapping
// can be eyeballed against the condition it was meant to express ("full figure
// 8", "back then right"). A count of zero is not a verdict: check each
// condition alone before concluding a value is wrong, because two conditions
// that each match can still have no dance in common. It does not check that
// every matched dance is the right one; that rests on ContraDB's
// `lib/filter_dances.rb` and `lib/search_match.rb`.
//
// Be polite: ContraDB scans every dance for each request, so this sends one
// request per expression, with `count` 3, and nothing else.
import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';

DanceFilter _leaf(String move, Map<String, Object?> params) =>
    FigureFilter.leaf(move, params: params);

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
    // Figure parameters, one request per shape: positions, the free-text
    // filler, the alias pin, the `or` of two spellings or figures, and the
    // highest position (a `hey` ricochet). ContraDB raises on a position past a
    // figure's last formal, so a wrong one shows up as REJECTED.
    'param: swing who+beats': _leaf('swing', {'who': 'partners', 'beats': 16}),
    'param: swing prefix': _leaf('swing', {'prefix': 'meltdown'}),
    'param: chain hand+where': _leaf('chain', {
      'hand': 'left',
      'where': 'across',
    }),
    'param: circle dir+places': _leaf('circle', {
      'direction': 'left',
      'places': 4,
      'beats': 8,
    }),
    'param: contra corners text filler': _leaf('contra_corners', {'beats': 16}),
    'param: figure 8 above (or)': _leaf('figure_8', {'where': 'above'}),
    'param: figure 8 fraction': _leaf('figure_8', {
      'where': 'below',
      'fraction': 'full',
    }),
    'param: hey rico2+beats (pos 9)': _leaf('hey', {'rico2': true, 'beats': 8}),
    'param: poussette fraction+dir': _leaf('poussette', {
      'fraction': 'half',
      'direction': 'clockwise',
    }),
    'param: see saw pin': _leaf('see_saw', {'who': 'neighbors', 'beats': 8}),
    'param: swat the flea pin': _leaf('swat_the_flea', {'beats': 4}),
    'param: do si do travel': _leaf('do_si_do', {'travel': 1.5}),
    'param: allemande + orbit': _leaf('allemande', {
      'who': 'role2s',
      'hand': 'left',
      'travel': 1.5,
      'beats': 8,
    }),
    'param: pull by who': _leaf('pull_by', {'who': 'neighbors'}),
    'param: pull by either': _leaf('pull_by', {'hand': 'right', 'beats': 2}),
    'param: square through places': _leaf('square_through', {'places': 3}),
    'param: star grip': _leaf('star', {'grip': 'wristGrip'}),
    'param: down the hall ender': _leaf('down_the_hall', {
      'ender': 'circle',
      'facing': 'backward',
    }),
    'then': ThenFilter(FigureLeaf('swing'), FigureLeaf('chain')),
    'then (wrap)': ThenFilter(FigureLeaf('chain'), FigureLeaf('swing')),
    'any figure': FigureFilter(anyFigure),
    'then (any figure, swing)': ThenFilter(anyFigure, FigureLeaf('swing')),
    'then (swing, any figure)': ThenFilter(FigureLeaf('swing'), anyFigure),
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
      final body = buildContraDbFilterBody(translation.expression, count: 3);
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
        if (decoded is Map && decoded['dances'] is List) {
          for (final dance in (decoded['dances'] as List).take(2)) {
            if (dance is! Map) continue;
            final shown = '${dance['matching_figures_html'] ?? ''}'
                .replaceAll(RegExp('<[^>]+>'), ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            detail +=
                '\n             matched: ${shown.length > 140 ? shown.substring(0, 140) : shown}';
          }
        }
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
