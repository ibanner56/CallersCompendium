import '../taxonomy/param_types.dart';

/// How an English Country Dance movement's template becomes a line (ADR-006
/// §6.3, §6.4). `FigureRenderer` computes each `{param}` slot as it does for
/// contra, then hands ECD moves (IDs with the `ecd_` prefix) to this file to
/// word the ECD-only values and expand the template's optional groups.
/// Contra templates hold no optional group and never reach it.
///
/// The notation, from §6.3:
///
/// - `{param}` is the parameter's words;
/// - `[ ... ]` is dropped when any value inside it renders as nothing (not
///   stated, or absent), and kept, brackets removed, otherwise;
/// - `{?flag}` adds no words, and keeps its group only while `flag` is set.
///
/// The ADR's `{a | b}` choices are worded by [ecdSlotWords] instead: a
/// destination's "to"/"back to", and right and left through's "with" or
/// "without" hands.
const String ecdMovePrefix = 'ecd_';

final RegExp _group = RegExp(r'\[([^\[\]]*)\]');
final RegExp _slot = RegExp(r'\{(\??)(\w+)\}');

/// Whether [moveId] names an ECD movement, whose template this file expands.
bool isEcdMove(String moveId) => moveId.startsWith(ecdMovePrefix);

/// [template] expanded with [slots] (each parameter's words) and [params]
/// (for `{?flag}`), with spaces collapsed and no space left before a comma
/// or colon, or a comma or colon left at either end.
String expandEcdTemplate(
  String template,
  Map<String, String> slots,
  Map<String, Object?> params,
) {
  bool filled(Match m) =>
      m[1] == '?' ? params[m[2]] == true : (slots[m[2]] ?? '').isNotEmpty;
  String fill(String text) =>
      text.replaceAllMapped(_slot, (m) => m[1] == '?' ? '' : slots[m[2]] ?? '');
  final grouped = template.replaceAllMapped(_group, (group) {
    final inner = group[1]!;
    return _slot.allMatches(inner).every(filled) ? fill(inner) : '';
  });
  return fill(grouped)
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r' ([,:])'), (m) => m[1]!)
      .replaceAll(RegExp(r'([,:])(?=[,:])'), '')
      .replaceAll(RegExp(r'^[\s,:]+|[\s,:]+$'), '');
}

/// The words of a stated `destination` (§6.4): "back to place" for `place`,
/// "ending improper"/"ending proper" for the two ending states, and "to"
/// before every other place. Nothing for an unstated one.
String ecdDestinationPhrase(Object? value) => switch (value) {
  'place' => 'back to place',
  'allImproper' => 'ending improper',
  'allProper' => 'ending proper',
  'partnersPlace' => "to partner's place",
  'neighborsPlace' => "to neighbor's place",
  'diagonalsPlace' => "to diagonal's place",
  final String place when place != ParamVocab.unspecified =>
    'to ${_words(place)}',
  _ => '',
};

/// The ECD-only words of slot [name] of ECD move [moveId] with [params], or
/// null to keep the words `FigureRenderer` gave it. [forCanonical] is the
/// search and dedupe text, which keeps a stated value that the display
/// leaves unsaid (a set to the right).
String? ecdSlotWords(
  String moveId,
  String name,
  Map<String, Object?> params, {
  required bool forCanonical,
}) {
  final value = params[name];
  final move = moveId.substring(ecdMovePrefix.length);
  switch (name) {
    case 'destination':
      return ecdDestinationPhrase(value);
    case 'withHands':
      return switch (value) {
        'yes' => 'with hands',
        'no' => 'without hands',
        _ => '',
      };
    // A count of changes, bare: the template says "changes of".
    case 'changes':
      return value is int ? '$value' : '';
    case 'move' when move == 'circle':
      // With a stated step, the step word replaces "circle" (§7.3).
      return switch (params['step']) {
        'slipping' => 'slip',
        'skipping' => 'skip',
        _ => null,
      };
    case 'hand' when move == 'change_places':
      return switch (value) {
        'right' => 'by the right',
        'left' => 'by the left',
        'none' => 'without hands',
        _ => '',
      };
    // The poussette's `who` push unless the figure says they draw (§9.3):
    // "role2s push". A stated style with no `who` stands after a comma.
    case 'style' when move == 'poussette':
      final whoStated = _statesWho(params['who']);
      final word = switch (value) {
        'draw' => 'draw',
        'push' => 'push',
        _ => whoStated || params['switchPush'] == true ? 'push' : '',
      };
      return word.isEmpty || whoStated ? word : ', $word';
    // "Cloverleaf turn single" (§9.3): the variant leads.
    case 'shoulder' when move == 'turn_single' && value == 'cloverleaf':
      return '';
    case 'move'
        when move == 'turn_single' && params['shoulder'] == 'cloverleaf':
      return 'cloverleaf turn single';
    // A set's side is shown only when it is not right (§7.1).
    case 'direction' when move == 'set' && !forCanonical:
      return value == 'right' ? '' : null;
  }
  if (!forCanonical && value == 'counterclockwise') return 'counter-clockwise';
  return null;
}

/// [template], the template of ECD move [moveId], as [params] need it
/// worded: a run of changes that states no count reads "a circular hey",
/// "rights and lefts", not "changes of", and a forward and back that states
/// no direction names the movement rather than leaving a bare "a double",
/// and a hey that states whom its starters pass but not who they are reads
/// "hey for four, pass neighbor".
String ecdTemplateFor(
  String moveId,
  String template,
  Map<String, Object?> params,
) {
  final move = moveId.substring(ecdMovePrefix.length);
  if (params['changes'] is! int &&
      const {
        'circular_hey',
        'rights_and_lefts',
        'grand_chain',
      }.contains(move)) {
    return template
        .replaceFirst('[{changes}] ', '')
        .replaceFirst('changes of ', '');
  }
  // A hey's passer and passed are each shown alone; with no `who`, the
  // comma or colon that led it leads "pass {whom}" instead.
  if (!_statesWho(params['who'])) {
    template = template.replaceFirstMapped(
      RegExp(r'\[([,:]) \{who\}\] \[pass \{whom\}\]'),
      (m) => '[${m[1]} pass {whom}]',
    );
  }
  if (move == 'forward_and_back' && !_stated(params['where'])) {
    return '{who} [{formation}] forward and back, a {distance}';
  }
  return template;
}

bool _stated(Object? value) => value != null && value != ParamVocab.unspecified;

bool _statesWho(Object? who) =>
    who is List && who.any((t) => t != ParamVocab.unspecified);

/// The words of a star that returns to place by [hand] as the last step of
/// a sequence: "back by the left", so the line reads "right hands across
/// and back by the left" (§7.3). Null for a star that states no hand.
String? ecdStarReturn(Object? hand) =>
    hand == 'right' || hand == 'left' ? 'back by the $hand' : null;

String _words(String token) => token
    .replaceAllMapped(RegExp('(?<=[a-z])(?=[A-Z])'), (_) => ' ')
    .toLowerCase();

final RegExp _flagGroup = RegExp(r'\[([^\[\]]*)\{\?(\w+)\}([^\[\]]*)\]');

/// [template], an ECD display template, as a wording a caller can edit and
/// save: each group kept by a switch, `[{?flag}words]`, becomes the wording
/// condition `[if flag then words]` that says the same. Wording templates
/// already drop a `[ ... ]` group whose slots are all empty, so the other
/// groups stay as they are.
String ecdTemplateAsWording(String template) => template.replaceAllMapped(
  _flagGroup,
  (m) => '[if ${m[2]} then ${('${m[1]}${m[3]}').trim()}]',
);
