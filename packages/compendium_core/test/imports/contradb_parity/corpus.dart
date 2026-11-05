// The parity corpus: ContraDB figures as ContraDB holds them (a `move` key) and
// as ContraDB renders them (`libfigure`'s `words`), so that one definition feeds
// both sides of the comparison:
//
//  * ContraDB side: the figure's [ContraFig.move], as in ContraDB's database.
//  * Collection side: the rendered [ContraFig.text] put on a page and imported
//    by the real [ContraDbHtmlAdapter], exactly as a user's import would.
//
// The rendered lines are taken from the importer's own tests
// (`contradb_figure_dialect_test.dart`, which model ContraDB's real output); the
// ContraDB `move` is what that text renders from. Nothing here was fetched from
// contradb.com.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

import '../../figures_support.dart';

/// One ContraDB figure: its stored `move` and the text ContraDB renders for it.
class ContraFig {
  const ContraFig(this.key, this.move, this.text, this.local, {this.alias});

  /// The alias this figure is shown as (see [ContraDbDance.aliases]), if any.
  final String? alias;

  /// A short unique name for this figure in test output.
  final String key;

  /// ContraDB's `move` key.
  final String move;

  /// The line ContraDB shows for it.
  final String text;

  /// The Collection move ids a faithful import produces (usually one), or
  /// `null` where the importer's result is a documented gap pinned elsewhere.
  final List<String>? local;
}

/// Figures whose import is a clean 1:1 onto one Collection move.
const List<ContraFig> cleanFigures = [
  ContraFig('swing', 'swing', 'neighbors swing', ['swing']),
  ContraFig('swing-balance', 'swing', 'partners balance & swing', ['swing']),
  ContraFig('swing-meltdown', 'swing', 'next neighbors meltdown swing', [
    'swing',
  ]),
  ContraFig('balance', 'balance', 'neighbors balance', ['balance']),
  ContraFig('balance-the-ring', 'balance the ring', 'balance the ring', [
    'balance_the_ring',
  ]),
  ContraFig('do-si-do', 'do si do', 'neighbors do si do 1½', ['do_si_do']),
  ContraFig('see-saw', 'do si do', 'neighbors seesaw', [
    'see_saw',
  ], alias: 'see saw'),
  ContraFig('swat-the-flea', 'box the gnat', 'partners swat the flea', [
    'swat_the_flea',
  ], alias: 'swat the flea'),
  ContraFig('chain', 'chain', 'ladles chain', ['chain']),
  ContraFig('circle', 'circle', 'circle left 3 places', ['circle']),
  ContraFig('long-lines', 'long lines', 'long lines forward & back', [
    'long_lines',
  ]),
  ContraFig('petronella', 'petronella', 'petronella', ['petronella']),
  ContraFig('petronella-balance', 'petronella', 'balance & petronella', [
    'petronella',
  ]),
  ContraFig('rlt', 'right left through', 'right left through', [
    'right_left_through',
  ]),
  ContraFig('star', 'star', 'star left 4 places', ['star']),
  ContraFig('allemande', 'allemande', 'gentlespoons allemande left once', [
    'allemande',
  ]),
  ContraFig('box-the-gnat', 'box the gnat', 'partners box the gnat', [
    'box_the_gnat',
  ]),
  ContraFig(
    'california-twirl',
    'California twirl',
    'partners California twirl',
    ['california_twirl'],
  ),
  ContraFig('butterfly-whirl', 'butterfly whirl', 'butterfly whirl', [
    'butterfly_whirl',
  ]),
  ContraFig('stand-still', 'stand still', 'stand still', ['stand_still']),
  ContraFig('gyre', 'gyre', 'neighbors gyre once', ['shoulder_round']),
  ContraFig('give-and-take', 'give & take', 'gentlespoons give & take ladles', [
    'give_and_take',
  ]),
  ContraFig('roll-away', 'roll away', 'gentlespoons roll away ladles', [
    'roll_away',
  ]),
  ContraFig('turn-alone', 'turn alone', 'turn alone', ['turn_alone']),
  ContraFig('pass-by', 'pass by', 'neighbors pass by right shoulders', [
    'pass_by',
  ]),
  ContraFig('mad-robin', 'mad robin', 'mad robin, gentlespoons in front', [
    'mad_robin',
  ]),
  ContraFig('pass-through', 'pass through', 'pass through', ['pass_through']),
  ContraFig('pull-by-dancers', 'pull by dancers', 'neighbors pull by right', [
    'pull_by',
  ]),
  ContraFig('gate', 'gate', 'ones gate neighbors to face up the set', ['gate']),
  ContraFig('contra-corners', 'contra corners', 'ones contra corners', [
    'contra_corners',
  ]),
  ContraFig('zig-zag', 'zig zag', 'partners zig left zag right', ['zig_zag']),
  ContraFig('slice', 'slice', 'slice left', ['slice']),
  ContraFig('down-the-hall', 'down the hall', 'down the hall forward', [
    'down_the_hall',
  ]),
  ContraFig('up-the-hall', 'up the hall', 'up the hall forward', [
    'up_the_hall',
  ]),
  ContraFig('figure-8', 'figure 8', 'ones figure 8 above', ['figure_8']),
  ContraFig('slide-along-set', 'slide along set', 'slide left along set', [
    'slide_along_set',
  ]),
  ContraFig(
    'form-long-waves',
    'form long waves',
    'form long waves - ladles face in, gentlespoons face out',
    ['form_long_waves'],
  ),
  ContraFig('square-through', 'square through', 'square through 4', [
    'square_through',
  ]),
  ContraFig('poussette', 'poussette', 'poussette', ['poussette']),
  ContraFig('arch-and-dive', 'arch & dive', 'ones arch twos dive', [
    'arch_and_dive',
  ]),
  ContraFig(
    'box-circulate',
    'box circulate',
    'box circulate - gentlespoons cross while ladles loop right',
    ['box_circulate'],
  ),
  ContraFig(
    'hey',
    'hey',
    'ladles start a full hey - rights in center, lefts on ends',
    ['hey'],
  ),
  ContraFig(
    'dolphin-hey',
    'dolphin hey',
    'dolphin hey - start with ones passing the first ladle by right shoulders',
    ['dolphin_hey'],
  ),
  ContraFig(
    'revolving-door',
    'revolving door',
    'revolving door - ladles take left hands and drop off partners on other side',
    ['revolving_door'],
  ),
  ContraFig(
    'cross-trails',
    'cross trails',
    'cross trails - partners across the set right shoulders, neighbors along the set left shoulders',
    ['cross_trails'],
  ),
  ContraFig(
    'facing-star',
    'facing star',
    'facing star clockwise 3 places with ones putting their right hands in and backing up',
    ['facing_star'],
  ),
  ContraFig('pull-by-direction', 'pull by direction', 'pull by right along', [
    'pull_by',
  ]),
  ContraFig('rory', "Rory O'More", "balance rory o'more right", [
    'rory_o_more',
  ]),
];

/// Renders a ContraDB dance page for [figures], one table row per figure.
String contraDbPage(
  String title,
  String choreographer,
  List<ContraFig> figures,
) {
  const esc = HtmlEscape();
  final rows = [
    for (final f in figures)
      '<tr><td>A1</td><td class=dance-show-beats>8</td>'
          '<td><div class="show-figure">${esc.convert(f.text)}</div></td></tr>',
  ].join();
  return '<!DOCTYPE html><html><head><title>x</title></head>'
      '<body class="dances-show-body">'
      '<h1 class="dance-show-title">${esc.convert(title)}</h1>'
      '<p class="dance-show-choreographer">by: <strong>'
      '<a href="/choreographers/1">${esc.convert(choreographer)}</a></strong></p>'
      '<p class="dance-show-formation">formation: improper </p>'
      '<table class="table table-bordered table-condensed contra-table-nonfluid">'
      '$rows</table></body></html>';
}

/// Imports [page] with the real ContraDB HTML adapter and returns the figures
/// the Collection would store.
Future<List<Figure>> importedFigures(String page) async {
  final adapter = ContraDbHtmlAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: page));
  final raw = await adapter.fetch(discovered.single);
  return figuresOf(adapter.parse(raw).dance);
}
