import 'package:compendium_core/compendium_core.dart';

void main(List<String> args) {
  final r = FigureRenderer(contraTaxonomy);
  final d = Dialect.larksRobins;
  final lines = [
    'neighbor balance & swing',
    'N bal & swing',
    'partners swing',
    'P swing',
    'ladies chain',
    'ladies chain over and back',
    'robins chain across',
    'half hey, ladies start by the right',
    'half hey ladies pass right shoulders',
    'hey for four, robins start by right shoulder',
    'circle left 3/4',
    'circle left 3 places',
    'circle left 3/4 and pass through',
    'long lines forward and back',
    'long lines',
    'balance the ring and petronella',
    'petronella twice',
    'petronella turn x2',
    'right and left through',
    'R&L thru',
    'pass through to new neighbors',
    'pass through up and down',
    'gents allemande left 1 1/2',
    'larks allemande left 1.5',
    'allemande left 1 1/2 with neighbor',
    'neighbor allemande left once and a half',
    'mad robin, ladies in front',
    'mad robin robins in the middle',
    'star left 1x',
    'star right with hands across',
    'down the hall in lines of 4',
    'down the hall four in line, turn alone',
    'down the hall, turn as a couple',
    'swing on the side',
    'partner swing on the side',
    'partners balance and swing, end facing down',
    'balance and swing',
    'give and take to the larks side',
    'ones swing in the center',
    '1s swing',
    'box the gnat',
    'neighbor box the gnat',
    'neighbors box the gnat and swat the flea',
    'zig zag left',
    'ricochet hey',
    'slice left',
    'contra corners',
    'hey',
    'gypsy',
    'neighbor gypsy right',
    'neighbor right shoulder round',
    'neighbor do si do',
    'N dosido 1 1/2',
    'circle left 3/4; swing',
    'circle left (8); neighbor swing',
    'swing neighbor 16',
    '16 neighbor swing',
    'partner swing (12)',
    'ladies chain (8)',
    'California twirl',
    'star promenade',
    'wave of four, balance',
    'balance the wave',
    'robins allemande right 1 1/2 while larks orbit',
  ];
  for (final line in lines) {
    final figs = parseFreeTextFigureEntry(line, taxonomy: contraTaxonomy, dialect: d);
    final out = figs.map((f) {
      final eff = contraTaxonomy.effectiveParams(f);
      final s = r.renderSummary(f, d);
      final note = f.note == null ? '' : ' [note: ${f.note}]';
      final cust = f.isCustom ? ' {CUSTOM ${f.customOrigin.name}}' : '';
      return '"$s"$note (${eff['beats']}b)$cust';
    }).join(' | ');
    print('$line  =>  $out');
  }
}
