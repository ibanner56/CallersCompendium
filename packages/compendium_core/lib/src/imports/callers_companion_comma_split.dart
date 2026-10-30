import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/gate_facing.dart';
import 'callersbox_adapter.dart' show balanceFoldMoves;
import 'callersbox_figure_dialect.dart' show splitTopLevel;
import 'figure_front_end_fan_out.dart';
import 'figure_parser.dart';
import 'figure_text_scrub.dart';
import 'while_container.dart' show whileModifierMoves;

/// Reads a Caller's Companion body line that names several figures separated
/// by commas (#1975): `(8) Slide Left, Circle Left 3/4`, `(8) Partner R-hand
/// balance, box the gnat`, `(8) Partner swing, face down`. Returns `null` when
/// the line does not split, and the caller keeps its own reading.
///
/// [text] is the line without its beats prefix, [beats] its total and [parts]
/// a compound prefix's groups (`(4,4)`). The caller tries this when the line
/// did not read whole, or read with a note holding its last piece
/// ([noteSwallowsPieces]).
///
/// The maintainer's decisions on #1975:
/// * **Beats.** Every figure but the last keeps its default beats and the last
///   takes the rest (`Slide Left, Circle Left 3/4` in 8 is 2 + 6). When
///   nothing is left for the last, the line does not split: it is not read as
///   figures danced at the same time.
/// * **A balance before a move that carries one** folds into it
///   ([balanceFoldMoves]): `Partner R-hand balance, box the gnat` is one box
///   the gnat with its balance, `who` the pair that balances and `hand` its
///   hand.
/// * **A roll away or a give and take** after another figure modifies it:
///   the two become a [Figure.modifier] container sharing their beats (`Circle
///   Left 3/4, Partner Roll Away with half sashay`). No other move does.
/// * **A last piece that says where the dancers end up** fills the figure's
///   end facing when the figure has one and the value fits (`Partner swing,
///   face down`), and is otherwise the figure's note.
///
/// The rest is the author's:
/// * **Pieces.** The line is cut at its top-level commas. From the left, the
///   longest run of pieces that reads as one figure is taken, so `Ring
///   balance, spin to the right` stays one petronella. A run of more than one
///   piece must read with no note, so a figure cannot swallow the next one
///   into its note; a single piece may keep one, but not one that holds
///   another move's name or an amount the reading left unread (as free-text
///   entry reads), so `Balance and California Twirl` does not split off as a
///   balance.
/// * **The balance fold** differs from The Caller's Box's Fold 1, which needs
///   the balance and the move to name the same dancers: here the move takes
///   the pair the balance names when it names none itself, and a balance that
///   names no pair (a bare `Balance` reads as everyone) leaves the move's own.
///   A move that names other dancers, or cannot hold the pair (a petronella
///   has no `who`; a Rory O'More's takes no relationship), keeps the balance
///   as its own figure. A ring balance folds into a petronella, as Fold 1
///   does.
/// * **A place to end** is a last piece opening with `face`, `facing`, `end`
///   or `to`, scrubbed like the rest of the line.
/// * **Beats.** A figure's default is its taxonomy beats for the params it
///   has (a balanced swing is 16). A compound prefix with one group per figure
///   gives each its group, as #560 does for a clean split, and a line with no
///   beats leaves them unset.
///
/// Any other piece that reads as nothing keeps the line whole. At most
/// [_maxPieces] pieces are tried, so a hostile line cannot drive the
/// quadratic search.
List<Figure>? splitCallersCompanionCommaLine(
  String text, {
  required int beats,
  List<int> parts = const [],
}) {
  final pieces = [
    for (final piece in splitTopLevelCommas(text))
      if (piece.isNotEmpty) piece,
  ];
  if (pieces.length < 2 || pieces.length > _maxPieces) return null;

  final units = <_Unit>[];
  String? trailing;
  var i = 0;
  while (i < pieces.length) {
    final run = _longestRun(pieces, i);
    if (run != null) {
      units.add(run.unit);
      i = run.next;
      continue;
    }
    // Only the last piece may be a place to end, and only after a figure.
    if (i == pieces.length - 1 && units.isNotEmpty && _endsAt(pieces[i])) {
      // Scrubbed as the figures' own text is, so a note keeps no gendered
      // role word (#744).
      trailing = scrubFigureText(pieces[i]);
      break;
    }
    return null;
  }

  final folded = _foldBalances(units);
  final modified = _wrapModifiers(folded);
  if (modified.isEmpty) return null;
  if (trailing != null) {
    modified[modified.length - 1] = _withEnd(modified.last, trailing);
  }

  final shares = _shareBeats(modified, beats: beats, parts: parts);
  if (shares == null) return null;
  return [
    for (var k = 0; k < modified.length; k++) modified[k].build(shares[k]),
  ];
}

/// Whether [figures], the whole-line reading of [text], hid the line's later
/// pieces in a note: a note holding the last piece, as `Larks pull by Left,
/// Partner pull by Right, Robins allemande Left 1.0` reads as a pull by
/// noting the rest. A note from the figure's own bracket does not count.
bool noteSwallowsPieces(String text, List<Figure> figures) {
  final pieces = [
    for (final piece in splitTopLevelCommas(text))
      if (piece.isNotEmpty) piece,
  ];
  if (pieces.length < 2) return false;
  final last = scrubFigureText(pieces.last).toLowerCase();
  return figures.any(
    (f) => f.note != null && f.note!.toLowerCase().contains(last),
  );
}

/// The most pieces a line is split into.
const int _maxPieces = 6;

/// [text] cut at its commas outside brackets, each piece trimmed.
List<String> splitTopLevelCommas(String text) => splitTopLevel(text, ',');

/// One figure of the split, before its beats are known: the figure itself,
/// or a core figure and the roll away or give and take that modifies it,
/// with the container's [note].
class _Unit {
  _Unit(this.figure, {this.modifier, this.note, this.foldedBeats = 0});

  final Figure figure;
  final Figure? modifier;
  final String? note;

  /// For a folded balance, the balance's and the move's default beats added
  /// up, as The Caller's Box adds its two lines' beats.
  final int foldedBeats;

  /// What it takes when it is not the last: the core figure's taxonomy beats
  /// for the params it has, or, for a folded balance, the two figures' beats
  /// when that is more (the taxonomy gives a balanced swing 16 but a balanced
  /// box the gnat only its own 4).
  int get defaultBeats {
    final d = contraTaxonomy.effectiveParams(_withBeats(figure, null))['beats'];
    final own = d is int ? d : 0;
    return own > foldedBeats ? own : foldedBeats;
  }

  Figure build(int? beats) {
    final m = modifier;
    if (m == null) return _withBeats(figure, beats);
    // The children carry no beats of their own, as after `while`.
    return Figure.modifier(
      figures: [_withBeats(figure, null), _withBeats(m, null)],
      beats: beats ?? 0,
      note: note,
    );
  }
}

/// The longest run of pieces from [start] that reads as one figure. The whole
/// line is not tried: the caller only splits a line that did not read whole.
({_Unit unit, int next})? _longestRun(List<String> pieces, int start) {
  for (var end = pieces.length; end > start; end--) {
    if (start == 0 && end == pieces.length) continue;
    final runText = pieces.sublist(start, end).join(', ');
    // As free-text entry reads: a note that holds another move's name or an
    // unread amount is a piece the reading did not account for.
    final read = parseFigureLinesFanOut(
      runText,
      beats: 0,
      demoteNoteTails: true,
    );
    if (read.length != 1) continue;
    final f = read.single;
    if (f.isCustom || f.isContainer) continue;
    if (end - start > 1 && f.note != null) continue;
    return (unit: _Unit(f), next: end);
  }
  return null;
}

/// Folds a balance into the move after it when that move carries one.
List<_Unit> _foldBalances(List<_Unit> units) {
  final out = <_Unit>[];
  for (var i = 0; i < units.length; i++) {
    final balance = units[i].figure;
    if (i + 1 < units.length) {
      final folded = _foldBalance(balance, units[i + 1].figure);
      if (folded != null) {
        out.add(
          _Unit(
            folded,
            foldedBeats: units[i].defaultBeats + units[i + 1].defaultBeats,
          ),
        );
        i++;
        continue;
      }
    }
    out.add(units[i]);
  }
  return out;
}

/// [move] with [balance] folded in, or `null` when [balance] is no balance,
/// the move does not take one or already has one, or it names other dancers
/// than the balance does.
Figure? _foldBalance(Figure balance, Figure move) {
  if (balance.move == 'balance_the_ring') {
    // A ring balance folds into a petronella only, as Fold 1 does.
    if (move.move != 'petronella' || move.params['balance'] == true) {
      return null;
    }
    return move.copyWith(
      params: {...move.params, 'balance': true},
      note: combineFigureNotes(balance.note, move.note),
    );
  }
  if (balance.move != 'balance') return null;
  if (!balanceFoldMoves.contains(move.move)) return null;
  final def = contraTaxonomy.resolve(move.move);
  if (def == null) return null;
  final params = {...move.params};
  if (move.move == 'swing') {
    final prefix = params['prefix'];
    if (prefix != null && prefix != 'none') return null;
    params['prefix'] = 'balance';
  } else {
    if (params['balance'] == true) return null;
    params['balance'] = true;
  }
  // A bare `Balance` reads as everyone, which names no pair to start with.
  final balanceWho = balance.params['who'];
  final who = balance.assumedSubject || balanceWho == 'everyone'
      ? null
      : balanceWho;
  var assumed = move.assumedSubject;
  if (who != null) {
    // A pair the move cannot hold keeps the balance its own figure: a
    // petronella has no `who` (its balance is the whole ring's), and a Rory
    // O'More's `who` takes no relationship.
    final whoSpec = def.params['who'];
    if (whoSpec == null) return null;
    final choices = whoSpec.choices;
    if (choices != null && !choices.contains(who)) return null;
    final moveWho = move.params['who'];
    if (moveWho != null && !move.assumedSubject && moveWho != who) return null;
    params['who'] = who;
    assumed = false;
  }
  final hand = balance.params['hand'];
  if (hand != null &&
      def.params.containsKey('hand') &&
      !move.params.containsKey('hand')) {
    params['hand'] = hand;
  }
  return move.copyWith(
    params: params,
    note: combineFigureNotes(balance.note, move.note),
    assumedSubject: assumed,
  );
}

/// Pairs a roll away or give and take with the figure before it.
List<_Unit> _wrapModifiers(List<_Unit> units) {
  final out = <_Unit>[];
  for (final unit in units) {
    // The moves that modify the figure before them (maintainer decision on
    // #1975), the same two as after `while`.
    if (whileModifierMoves.contains(unit.figure.move) &&
        out.isNotEmpty &&
        out.last.modifier == null) {
      final core = out.removeLast();
      out.add(
        _Unit(
          core.figure,
          modifier: unit.figure,
          foldedBeats: core.foldedBeats,
        ),
      );
      continue;
    }
    out.add(unit);
  }
  return out;
}

/// A piece that says where the dancers end up rather than naming a figure.
bool _endsAt(String piece) => _endPhrase.hasMatch(piece);

final RegExp _endPhrase = RegExp(
  r'^(?:end(?:ing)?\b|face\b|facing\b|to\b)',
  caseSensitive: false,
);

/// `face <x>` / `end facing <x>` / `end face <x>`: the facing named.
final RegExp _facingPhrase = RegExp(
  r'^(?:end(?:ing)?\s+)?(?:face|facing)\s+(.{1,40})$',
  caseSensitive: false,
);

/// [unit] with [trailing] as its end facing when its figure has one that
/// fits, and otherwise as its note (the container's, for a modifier).
_Unit _withEnd(_Unit unit, String trailing) {
  final f = unit.figure;
  if (unit.modifier != null) {
    return _Unit(
      f,
      modifier: unit.modifier,
      note: combineFigureNotes(unit.note, trailing),
      foldedBeats: unit.foldedBeats,
    );
  }
  final facing = _facingPhrase.firstMatch(trailing)?[1]?.trim();
  final value = facing == null ? null : _endFacingValue(f.move, facing);
  final ended = value != null
      ? f.copyWith(params: {...f.params, 'endFacing': value})
      : f.copyWith(note: combineFigureNotes(f.note, trailing));
  return _Unit(ended, foldedBeats: unit.foldedBeats);
}

/// The value [facing] gives [move]'s `endFacing`, or `null` when the move has
/// none or the words do not fit it.
String? _endFacingValue(String move, String facing) {
  final words = facing.toLowerCase();
  switch (move) {
    case 'swing':
    case 'gate':
      return gateFacings.contains(words) ? words : null;
    case 'courtesy_turn':
      return resolveDancerSetPhrase(facing);
  }
  return null;
}

/// Each unit's beats, or `null` when the line's beats leave nothing for the
/// last. A line with no beats gives every unit none.
///
/// A figure whose default is 0 beats, a formation such as form short waves
/// without its balance, takes none, and the last figure that takes beats takes
/// the rest (maintainer decision on #1975: form short waves is a zero-count
/// figure, so `(8) Circle Left 3/4, make short waves` is the circle in 8).
/// Every 0-beat default counts the same, the author's call.
List<int?>? _shareBeats(
  List<_Unit> units, {
  required int beats,
  required List<int> parts,
}) {
  if (parts.length >= 2 && parts.length == units.length) return parts;
  if (beats <= 0) return List.filled(units.length, null);
  final defaults = [for (final unit in units) unit.defaultBeats];
  final last = defaults.lastIndexWhere((d) => d > 0);
  if (last < 0) return null;
  var used = 0;
  for (var k = 0; k < last; k++) {
    used += defaults[k];
  }
  final rest = beats - used;
  if (rest <= 0) return null;
  return [
    for (var k = 0; k < units.length; k++)
      k == last
          ? rest
          : defaults[k] > 0
          ? defaults[k]
          : null,
  ];
}

Figure _withBeats(Figure figure, int? beats) {
  final params = {...figure.params};
  if (beats != null && beats > 0) {
    params['beats'] = beats;
  } else {
    params.remove('beats');
  }
  return figure.copyWith(params: params);
}
