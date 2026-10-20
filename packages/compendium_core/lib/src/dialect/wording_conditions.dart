import '../taxonomy/param_types.dart';
import 'dialect.dart';

/// Conditional wording: `[if … then … else …]` in a wording template, both a
/// dialect's move wording and a figure of your own's.
///
/// A template is written and edited in its **display form**, the words a
/// caller types:
///
/// ```text
/// [if who is neighbors then neighbor swing else {who} swing]
/// ```
///
/// and stored in its **stored form**, where each condition is held by
/// meaning — a value as its token or choice id, never as a word — inside a
/// `{?…}` marker:
///
/// ```text
/// [{?if who is 'neighbors'}neighbor swing{?else}{who} swing]
/// ```
///
/// so renaming a role, a dancer word or a choice later never changes what a
/// saved condition tests, and an older build, whose validator refuses a `{`
/// holding anything but a slot name, falls back to its normal wording rather
/// than showing a condition as text. A template with no condition is stored
/// exactly as typed.
///
/// [checkWording] reads the display form against a [WordingVocabulary] (what
/// the template may test, and each value's words) and returns the stored form
/// or the issues that stop it; [wordingForEditing] turns the stored form back
/// into the display form. [parseStoredWording] reads the stored form for
/// rendering and validation, and [assembleWordingNodes] renders it.

/// Words a parameter may not be named, compared ignoring case: the words a
/// condition is built from that can stand where a parameter name does. The
/// other words of a condition (`in`, `empty`, `more`, `than`, …) are read
/// only after `is`, where no name can stand, so they stay free.
const Set<String> wordingReservedWords = {
  'if',
  'then',
  'else',
  'not',
  'and',
  'or',
  'is',
};

// ---------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------

/// What one test in a condition asks of its name.
enum WordingTestOp {
  /// `name`: a switch is on, or a detail is filled in.
  present,

  /// `name is empty`.
  empty,

  /// `name is not empty`.
  notEmpty,

  /// `name is value`.
  equals,

  /// `name is not value`.
  notEquals,

  /// `name is in (value, …)`.
  inList,

  /// `name is not in (value, …)`.
  notInList,

  /// `name is more than number`.
  moreThan,

  /// `name is less than number`.
  lessThan,

  /// `name is at least number`.
  atLeast,

  /// `name is at most number`.
  atMost,
}

/// A condition of a conditional group.
sealed class WordingCondition {
  const WordingCondition();

  /// The condition in the stored form: what two conditions are compared by.
  String get stored => _storedCondition(this);

  @override
  bool operator ==(Object other) =>
      other is WordingCondition && other.stored == stored;

  @override
  int get hashCode => stored.hashCode;
}

/// One test of one name.
final class WordingTest extends WordingCondition {
  const WordingTest(this.name, this.op, [this.values = const []]);

  final String name;
  final WordingTestOp op;

  /// The values tested against: a token or choice id ([String]) or a number
  /// ([num]). One for [WordingTestOp.equals], [WordingTestOp.notEquals] and
  /// the comparisons, one or more for the lists, none otherwise.
  final List<Object> values;
}

/// `not …`.
final class WordingNot extends WordingCondition {
  const WordingNot(this.inner);

  final WordingCondition inner;
}

/// `… and …`.
final class WordingAll extends WordingCondition {
  const WordingAll(this.parts);

  final List<WordingCondition> parts;
}

/// `… or …`.
final class WordingAny extends WordingCondition {
  const WordingAny(this.parts);

  final List<WordingCondition> parts;
}

/// The names [condition] tests.
Set<String> wordingConditionNames(WordingCondition condition) =>
    switch (condition) {
      WordingTest(:final name) => {name},
      WordingNot(:final inner) => wordingConditionNames(inner),
      WordingAll(:final parts) || WordingAny(:final parts) => {
        for (final part in parts) ...wordingConditionNames(part),
      },
    };

// ---------------------------------------------------------------------------
// Template tree
// ---------------------------------------------------------------------------

/// One part of a stored template.
sealed class WordingNode {
  const WordingNode();
}

/// Literal text, holding `{slot}` placeholders as written.
final class WordingText extends WordingNode {
  const WordingText(this.text);

  final String text;
}

/// `[…]`: left out when every slot in it is empty.
final class WordingGroup extends WordingNode {
  const WordingGroup(this.children);

  final List<WordingNode> children;
}

/// `[if … then … else if … then … else …]`.
final class WordingChoice extends WordingNode {
  const WordingChoice(this.branches, this.otherwise);

  /// Each `if`/`else if` condition with its wording, in order.
  final List<({WordingCondition condition, List<WordingNode> children})>
  branches;

  /// The `else` wording, or null when there is none.
  final List<WordingNode>? otherwise;
}

/// Every condition in [nodes], nested ones included.
Iterable<WordingCondition> wordingConditionsIn(List<WordingNode> nodes) sync* {
  for (final node in nodes) {
    switch (node) {
      case WordingText():
        break;
      case WordingGroup(:final children):
        yield* wordingConditionsIn(children);
      case WordingChoice(:final branches, :final otherwise):
        for (final branch in branches) {
          yield branch.condition;
          yield* wordingConditionsIn(branch.children);
        }
        if (otherwise != null) yield* wordingConditionsIn(otherwise);
    }
  }
}

/// Every name the conditions in [nodes] test.
Set<String> wordingTestedNames(List<WordingNode> nodes) => {
  for (final condition in wordingConditionsIn(nodes))
    ...wordingConditionNames(condition),
};

/// Whether [nodes] hold a condition.
bool wordingHasConditions(List<WordingNode> nodes) =>
    wordingConditionsIn(nodes).isNotEmpty;

// ---------------------------------------------------------------------------
// Stored form
// ---------------------------------------------------------------------------

const String _ifMarker = '{?if ';
const String _elseIfMarker = '{?else if ';
const String _elseMarker = '{?else}';

final RegExp _slotName = RegExp(r'^!?\w+$');
final RegExp _slotPlaceholder = RegExp(r'\{(!?\w+)\}');

final Map<String, List<WordingNode>?> _storedCache = {};
const int _maxStoredCache = 256;

/// [template] in the stored form as a tree, or null when it is not well
/// formed: a `[` or `{` left open, a `]` or `}` with nothing to close, a
/// brace holding anything but a slot name or a marker, or a marker out of
/// place or holding a condition that does not read. Whitespace around the
/// template is ignored, as it always was.
///
/// The tree is memoized per template, bounded, since every render of a
/// templated line reads it.
List<WordingNode>? parseStoredWording(String template) {
  final trimmed = template.trim();
  if (_storedCache.containsKey(trimmed)) return _storedCache[trimmed];
  if (_storedCache.length >= _maxStoredCache) _storedCache.clear();
  return _storedCache[trimmed] = _StoredParser(trimmed).parse();
}

/// [nodes] with every list of nodes under them unmodifiable: a cached tree is
/// shared by every render that reads its template. Its conditions are never
/// changed once read.
List<WordingNode> _frozen(List<WordingNode> nodes) => List.unmodifiable([
  for (final node in nodes)
    switch (node) {
      WordingText() => node,
      WordingGroup(:final children) => WordingGroup(_frozen(children)),
      WordingChoice(:final branches, :final otherwise) => WordingChoice(
        List.unmodifiable([
          for (final b in branches)
            (condition: b.condition, children: _frozen(b.children)),
        ]),
        otherwise == null ? null : _frozen(otherwise),
      ),
    },
]);

final class _StoredParser {
  _StoredParser(this.text);

  final String text;
  int i = 0;

  List<WordingNode>? parse() {
    final nodes = _sequence(inGroup: false, inChoice: false);
    if (nodes == null || i != text.length) return null;
    return _frozen(nodes);
  }

  /// Parts up to the end, a `]` (in a group) or an `{?else` marker (in a
  /// conditional's branch), which is left unread.
  List<WordingNode>? _sequence({
    required bool inGroup,
    required bool inChoice,
  }) {
    final nodes = <WordingNode>[];
    final literal = StringBuffer();
    void flush() {
      if (literal.isEmpty) return;
      nodes.add(WordingText(literal.toString()));
      literal.clear();
    }

    while (i < text.length) {
      final char = text[i];
      if (char == ']') {
        if (!inGroup) return null;
        break;
      }
      if (char == '}') return null;
      if (char == '{') {
        if (text.startsWith('{?', i)) {
          if (inChoice && text.startsWith('{?else', i)) break;
          return null;
        }
        final close = text.indexOf('}', i + 1);
        if (close < 0) return null;
        final name = text.substring(i + 1, close);
        if (!_slotName.hasMatch(name)) return null;
        literal.write(text.substring(i, close + 1));
        i = close + 1;
        continue;
      }
      if (char == '[') {
        flush();
        i++;
        if (text.startsWith(_ifMarker, i)) {
          final choice = _choice();
          if (choice == null) return null;
          nodes.add(choice);
        } else {
          final children = _sequence(inGroup: true, inChoice: false);
          if (children == null || i >= text.length || text[i] != ']') {
            return null;
          }
          i++;
          nodes.add(WordingGroup(children));
        }
        continue;
      }
      literal.write(char);
      i++;
    }
    flush();
    return nodes;
  }

  /// A conditional group from its `{?if` marker through its `]`.
  WordingChoice? _choice() {
    final branches =
        <({WordingCondition condition, List<WordingNode> children})>[];
    List<WordingNode>? otherwise;
    var marker = _ifMarker;
    while (true) {
      final condition = _marker(marker);
      if (condition == null) return null;
      final children = _sequence(inGroup: true, inChoice: true);
      if (children == null) return null;
      branches.add((condition: condition, children: children));
      if (text.startsWith(_elseIfMarker, i)) {
        marker = _elseIfMarker;
        continue;
      }
      if (text.startsWith(_elseMarker, i)) {
        i += _elseMarker.length;
        otherwise = _sequence(inGroup: true, inChoice: false);
        if (otherwise == null) return null;
      }
      break;
    }
    if (i >= text.length || text[i] != ']') return null;
    i++;
    return WordingChoice(branches, otherwise);
  }

  WordingCondition? _marker(String marker) {
    if (!text.startsWith(marker, i)) return null;
    final start = i + marker.length;
    final close = text.indexOf('}', start);
    if (close < 0) return null;
    final condition = parseStoredCondition(text.substring(start, close));
    i = close + 1;
    return condition;
  }
}

/// A condition in the stored form, or null when it does not read.
///
/// The stored form is strict: every value is quoted (`'role2s'`) or a plain
/// number, so where a word stands decides what it is, and `and` and `or` mix
/// only inside parentheses.
WordingCondition? parseStoredCondition(String source) {
  final tokens = _storedTokens(source);
  if (tokens == null) return null;
  final parser = _StoredConditionParser(tokens);
  final condition = parser.condition();
  if (condition == null || parser.i != tokens.length) return null;
  return condition;
}

final RegExp _storedToken = RegExp(
  r"\s*(?:(\()|(\))|(,)|'([A-Za-z0-9_]+)'|(-?\d+(?:\.\d+)?)|([A-Za-z_][A-Za-z0-9_]*))",
);

/// One token of a stored condition: a structural character, a quoted value,
/// a number or a word.
typedef _StoredToken = ({String kind, String text});

List<_StoredToken>? _storedTokens(String source) {
  final tokens = <_StoredToken>[];
  var index = 0;
  while (index < source.length) {
    if (source.substring(index).trim().isEmpty) break;
    final match = _storedToken.matchAsPrefix(source, index);
    if (match == null) return null;
    index = match.end;
    if (match[1] != null || match[2] != null || match[3] != null) {
      tokens.add((kind: 'punct', text: match[1] ?? match[2] ?? match[3]!));
    } else if (match[4] != null) {
      tokens.add((kind: 'value', text: match[4]!));
    } else if (match[5] != null) {
      tokens.add((kind: 'number', text: match[5]!));
    } else {
      tokens.add((kind: 'word', text: match[6]!));
    }
  }
  return tokens;
}

final class _StoredConditionParser {
  _StoredConditionParser(this.tokens);

  final List<_StoredToken> tokens;
  int i = 0;

  bool _word(String word) {
    if (i < tokens.length &&
        tokens[i].kind == 'word' &&
        tokens[i].text == word) {
      i++;
      return true;
    }
    return false;
  }

  bool _peekWord(int offset, String word) =>
      i + offset < tokens.length &&
      tokens[i + offset].kind == 'word' &&
      tokens[i + offset].text == word;

  bool _punct(String char) {
    if (i < tokens.length &&
        tokens[i].kind == 'punct' &&
        tokens[i].text == char) {
      i++;
      return true;
    }
    return false;
  }

  WordingCondition? condition() {
    final first = _unit();
    if (first == null) return null;
    final parts = [first];
    String? connective;
    while (true) {
      final next = _word('and')
          ? 'and'
          : _word('or')
          ? 'or'
          : null;
      if (next == null) break;
      if (connective != null && connective != next) return null;
      connective = next;
      final part = _unit();
      if (part == null) return null;
      parts.add(part);
    }
    if (connective == null) return first;
    return connective == 'and' ? WordingAll(parts) : WordingAny(parts);
  }

  WordingCondition? _unit() {
    if (_word('not')) {
      final inner = _unit();
      return inner == null ? null : WordingNot(inner);
    }
    if (_punct('(')) {
      final inner = condition();
      if (inner == null || !_punct(')')) return null;
      return inner;
    }
    if (i >= tokens.length || tokens[i].kind != 'word') return null;
    final name = tokens[i].text;
    if (wordingReservedWords.contains(name.toLowerCase())) return null;
    i++;
    if (!_word('is')) return WordingTest(name, WordingTestOp.present);
    final negated = _word('not');
    if (_word('empty')) {
      return WordingTest(
        name,
        negated ? WordingTestOp.notEmpty : WordingTestOp.empty,
      );
    }
    if (_word('in')) {
      if (!_punct('(')) return null;
      final values = <Object>[];
      do {
        final value = _value();
        if (value == null) return null;
        values.add(value);
      } while (_punct(','));
      if (!_punct(')')) return null;
      return WordingTest(
        name,
        negated ? WordingTestOp.notInList : WordingTestOp.inList,
        values,
      );
    }
    WordingTestOp? comparison;
    for (final (first, second, op) in const [
      ('more', 'than', WordingTestOp.moreThan),
      ('less', 'than', WordingTestOp.lessThan),
      ('at', 'least', WordingTestOp.atLeast),
      ('at', 'most', WordingTestOp.atMost),
    ]) {
      if (_peekWord(0, first) && _peekWord(1, second)) {
        i += 2;
        comparison = op;
        break;
      }
    }
    if (comparison != null) {
      if (negated) return null;
      if (i >= tokens.length || tokens[i].kind != 'number') return null;
      final number = num.parse(tokens[i++].text);
      return WordingTest(name, comparison, [number]);
    }
    final value = _value();
    if (value == null) return null;
    return WordingTest(
      name,
      negated ? WordingTestOp.notEquals : WordingTestOp.equals,
      [value],
    );
  }

  Object? _value() {
    if (i >= tokens.length) return null;
    final token = tokens[i];
    if (token.kind == 'value') {
      i++;
      return token.text;
    }
    if (token.kind == 'number') {
      i++;
      return num.parse(token.text);
    }
    return null;
  }
}

String _storedNumber(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

String _storedValue(Object value) =>
    value is num ? _storedNumber(value) : "'$value'";

/// Whether a value's word, written after `is`, could read as more than the
/// value: it has several words, or is spelled like an operator.
bool _needsList(String word) {
  final lower = word.trim().toLowerCase();
  return lower.contains(' ') ||
      lower.contains(',') ||
      lower.startsWith('(') ||
      {'empty', 'not', 'in', 'and', 'or', 'then', 'else', 'is'}.contains(lower);
}

String _storedCondition(WordingCondition condition) => _conditionText(
  condition,
  name: (name) => name,
  value: (_, value) => _storedValue(value),
);

/// [condition] as text, with [name] and [value] spelling each part: the one
/// writer of both forms, so they cannot drift apart.
String _conditionText(
  WordingCondition condition, {
  required String Function(String name) name,
  required String Function(String name, Object value) value,
  bool explicit = false,
}) {
  String unit(WordingCondition c, {required bool inChain}) {
    final text = _conditionText(
      c,
      name: name,
      value: value,
      explicit: explicit,
    );
    final grouped = c is WordingAll || c is WordingAny;
    final wrap =
        grouped ||
        (explicit &&
            inChain &&
            c is WordingTest &&
            c.op != WordingTestOp.present);
    return wrap ? '($text)' : text;
  }

  switch (condition) {
    case WordingTest(name: final n, :final op, :final values):
      final shown = name(n);
      String one() => value(n, values.first);
      String list() => [for (final v in values) value(n, v)].join(', ');
      return switch (op) {
        WordingTestOp.present => shown,
        WordingTestOp.empty => '$shown is empty',
        WordingTestOp.notEmpty => '$shown is not empty',
        // Written explicitly, a value of several words, or one spelled like
        // an operator ("empty"), goes in a list, and `is not` is always one,
        // so none can run into the words around it ("not sure", "rock and
        // roll") or read as the operator.
        WordingTestOp.equals when explicit && _needsList(one()) =>
          '$shown is in (${one()})',
        WordingTestOp.equals => '$shown is ${one()}',
        WordingTestOp.notEquals when explicit => '$shown is not in (${one()})',
        WordingTestOp.notEquals => '$shown is not ${one()}',
        WordingTestOp.inList => '$shown is in (${list()})',
        WordingTestOp.notInList => '$shown is not in (${list()})',
        WordingTestOp.moreThan => '$shown is more than ${one()}',
        WordingTestOp.lessThan => '$shown is less than ${one()}',
        WordingTestOp.atLeast => '$shown is at least ${one()}',
        WordingTestOp.atMost => '$shown is at most ${one()}',
      };
    case WordingNot(:final inner):
      return 'not ${unit(inner, inChain: false)}';
    case WordingAll(:final parts):
      return [for (final p in parts) unit(p, inChain: true)].join(' and ');
    case WordingAny(:final parts):
      return [for (final p in parts) unit(p, inChain: true)].join(' or ');
  }
}

/// [nodes] written back in the stored form.
String storedWordingText(List<WordingNode> nodes) {
  final out = StringBuffer();
  void write(List<WordingNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case WordingText(:final text):
          out.write(text);
        case WordingGroup(:final children):
          out.write('[');
          write(children);
          out.write(']');
        case WordingChoice(:final branches, :final otherwise):
          out.write('[');
          for (var b = 0; b < branches.length; b++) {
            out.write(b == 0 ? _ifMarker : _elseIfMarker);
            out.write(branches[b].condition.stored);
            out.write('}');
            write(branches[b].children);
          }
          if (otherwise != null) {
            out.write(_elseMarker);
            write(otherwise);
          }
          out.write(']');
      }
    }
  }

  write(nodes);
  return out.toString();
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// What a condition reads about one name when a line renders: the name's
/// [spec] (null for a slot that is only text, such as a long wave's
/// `subject`) and its [value] (the slot's text, for such a slot).
final class WordingSubject {
  const WordingSubject(this.spec, this.value);

  final ParamSpec? spec;
  final Object? value;
}

/// How a name can be tested.
enum WordingNameKind {
  /// On or off: tested bare or with `not`.
  flag,

  /// A number: every test.
  number,

  /// One of a closed set of values: every test but the comparisons.
  choices,

  /// Free text: whether it is filled in.
  text,

  /// A slot that is only text: whether it is filled in.
  slot,
}

/// How a name of [spec] can be tested; a null [spec] is a slot that is only
/// text.
WordingNameKind wordingNameKind(ParamSpec? spec) => switch (spec?.kind) {
  null => WordingNameKind.slot,
  ParamKind.flag => WordingNameKind.flag,
  ParamKind.text => WordingNameKind.text,
  ParamKind.rotation ||
  ParamKind.places ||
  ParamKind.beats => WordingNameKind.number,
  _ => WordingNameKind.choices,
};

bool _isFilled(WordingSubject subject) {
  final value = subject.value;
  if (value == null) return false;
  if (value is String) {
    return value.isNotEmpty && value != ParamVocab.unspecified;
  }
  if (value is bool) return value;
  return true;
}

/// Whether [condition] holds for [subjects]. A name with no subject, which
/// [wordingConditionsFit] rules out, reads as empty.
bool evaluateWordingCondition(
  WordingCondition condition,
  Map<String, WordingSubject> subjects,
) {
  switch (condition) {
    case WordingNot(:final inner):
      return !evaluateWordingCondition(inner, subjects);
    case WordingAll(:final parts):
      return parts.every((p) => evaluateWordingCondition(p, subjects));
    case WordingAny(:final parts):
      return parts.any((p) => evaluateWordingCondition(p, subjects));
    case WordingTest(:final name, :final op, :final values):
      final subject = subjects[name] ?? const WordingSubject(null, null);
      final value = subject.value;
      final number = value is num && _isFilled(subject) ? value : null;
      bool matches(Object v) => v is num ? number == v : value == v;
      return switch (op) {
        WordingTestOp.present => _isFilled(subject),
        WordingTestOp.empty => !_isFilled(subject),
        WordingTestOp.notEmpty => _isFilled(subject),
        WordingTestOp.equals => _isFilled(subject) && matches(values.first),
        WordingTestOp.notEquals =>
          !(_isFilled(subject) && matches(values.first)),
        WordingTestOp.inList => _isFilled(subject) && values.any(matches),
        WordingTestOp.notInList => !(_isFilled(subject) && values.any(matches)),
        WordingTestOp.moreThan =>
          number != null && number > (values.first as num),
        WordingTestOp.lessThan =>
          number != null && number < (values.first as num),
        WordingTestOp.atLeast =>
          number != null && number >= (values.first as num),
        WordingTestOp.atMost =>
          number != null && number <= (values.first as num),
      };
  }
}

/// Whether every condition in [nodes] fits [subjects], the names the
/// template may test with each one's spec: each name is one of them, each
/// test is one its kind takes, and each value is one of its values. A stored
/// template that does not fit is not used, as one that uses a slot it lacks
/// is not.
bool wordingConditionsFit(
  List<WordingNode> nodes,
  Map<String, ParamSpec?> subjects,
) {
  bool fits(WordingCondition condition) {
    switch (condition) {
      case WordingNot(:final inner):
        return fits(inner);
      case WordingAll(:final parts) || WordingAny(:final parts):
        return parts.every(fits);
      case WordingTest(:final name, :final op, :final values):
        if (!subjects.containsKey(name)) return false;
        final spec = subjects[name];
        final kind = wordingNameKind(spec);
        switch (op) {
          case WordingTestOp.present:
            return true;
          case WordingTestOp.empty || WordingTestOp.notEmpty:
            return kind != WordingNameKind.flag;
          case WordingTestOp.moreThan ||
              WordingTestOp.lessThan ||
              WordingTestOp.atLeast ||
              WordingTestOp.atMost:
            return kind == WordingNameKind.number &&
                values.length == 1 &&
                spec!.validate(_specNumber(spec, values.first));
          case WordingTestOp.equals ||
              WordingTestOp.notEquals ||
              WordingTestOp.inList ||
              WordingTestOp.notInList:
            if (kind == WordingNameKind.number) {
              return values.isNotEmpty &&
                  values.every((v) => spec!.validate(_specNumber(spec, v)));
            }
            if (kind != WordingNameKind.choices) return false;
            return values.isNotEmpty &&
                values.every(
                  (v) =>
                      v is String &&
                      v != ParamVocab.unspecified &&
                      spec!.validate(v),
                );
        }
    }
  }

  return wordingConditionsIn(nodes).every(fits);
}

/// [value] as the number type [spec] validates: an int for a whole-number
/// kind, whatever was stored.
Object _specNumber(ParamSpec spec, Object value) {
  if (value is! num) return value;
  if (spec.kind == ParamKind.rotation) return value;
  return value == value.roundToDouble() ? value.toInt() : value;
}

/// [nodes] rendered: [valueOf] gives each `{slot}` its text and [evaluate]
/// decides each condition. Returns the text and the slots it used, as a
/// `[…]` group needs to decide whether it is empty.
///
/// A conditional shows the wording of its first condition that holds, else
/// its `else` wording, else nothing; the slots of the wording it shows count
/// for any group around it. Slot values are inserted as text and never read
/// again, so a value can never add a slot, a group or a condition.
({Set<String> slots, String text}) assembleWordingNodes(
  List<WordingNode> nodes,
  String Function(String key) valueOf,
  bool Function(WordingCondition condition) evaluate,
) {
  final out = StringBuffer();
  final names = <String>{};
  for (final node in nodes) {
    switch (node) {
      case WordingText(:final text):
        out.write(
          text.replaceAllMapped(_slotPlaceholder, (m) => valueOf(m[1]!)),
        );
        names.addAll(_slotPlaceholder.allMatches(text).map((m) => m[1]!));
      case WordingGroup(:final children):
        final group = assembleWordingNodes(children, valueOf, evaluate);
        names.addAll(group.slots);
        final allEmpty =
            group.slots.isNotEmpty &&
            group.slots.every((name) => valueOf(name).isEmpty);
        if (!allEmpty) out.write(group.text);
      case WordingChoice(:final branches, :final otherwise):
        final chosen =
            branches
                .where((b) => evaluate(b.condition))
                .firstOrNull
                ?.children ??
            otherwise;
        if (chosen == null) continue;
        final shown = assembleWordingNodes(chosen, valueOf, evaluate);
        names.addAll(shown.slots);
        out.write(shown.text);
    }
  }
  return (slots: names, text: out.toString());
}

// ---------------------------------------------------------------------------
// Display form: vocabulary
// ---------------------------------------------------------------------------

/// The words one value of a name is written with: [word], the one a template
/// is shown with, and [alsoWords], others it may be typed as.
final class WordingValueWords {
  const WordingValueWords(this.value, this.word, [this.alsoWords = const []]);

  /// The token, choice id or number the words stand for.
  final Object value;
  final String word;
  final List<String> alsoWords;
}

/// One name a template may test: its [spec] (null for a slot that is only
/// text) and, for a name of [WordingNameKind.choices], the words of each of
/// its values; for a number, any words that stand for a number (`once`).
final class WordingName {
  WordingName(this.name, this.spec, [List<WordingValueWords> values = const []])
    : values = List.unmodifiable(values);

  final String name;
  final ParamSpec? spec;
  final List<WordingValueWords> values;

  WordingNameKind get kind => wordingNameKind(spec);

  /// The shown word for [value], or null when it has none.
  String? wordFor(Object value) {
    for (final v in values) {
      if (v.value == value) return v.word;
    }
    return null;
  }
}

/// What a template may test, and how each value is written: built by the
/// renderer for a move or a figure of your own in a dialect
/// (`FigureRenderer.moveWordingVocabulary`,
/// `FigureRenderer.userFigureWordingVocabulary`).
final class WordingVocabulary {
  WordingVocabulary(Iterable<WordingName> names)
    : names = List.unmodifiable(names) {
    for (final name in this.names) {
      _byLower.putIfAbsent(name.name.toLowerCase(), () => name);
    }
  }

  final List<WordingName> names;
  final Map<String, WordingName> _byLower = {};

  /// The name [text] spells, ignoring case, or null.
  WordingName? operator [](String text) => _byLower[text.toLowerCase()];

  /// Each name with its spec: what a stored template is checked against.
  Map<String, ParamSpec?> get subjects => {
    for (final name in names) name.name: name.spec,
  };
}

// ---------------------------------------------------------------------------
// Display form: issues
// ---------------------------------------------------------------------------

/// Why a template in the display form can't be saved, or a warning about
/// it. Each has a message in the app (`wording_issue_labels.dart`), filled
/// from [WordingIssue.data].
enum WordingIssueCode {
  // Brackets and braces.
  unclosedGroup,
  strayCloseBracket,
  unclosedSlot,
  strayCloseBrace,
  badSlot,
  conditionInBraces,
  tooLongStored,
  // Conditions.
  missingCondition,
  missingThen,
  colonForThen,
  unknownName,
  unknownNameAfterIf,
  nameInBraces,
  isntForIsNot,
  symbolForWord,
  quotedValue,
  unknownValue,
  expectedValue,
  listNeedsParens,
  oneOfForIsIn,
  emptyList,
  unclosedParen,
  strayCloseParen,
  emptyParens,
  expectedConnective,
  expectedConnectiveList,
  expectedListSeparator,
  valueAfterConnective,
  mixedAndOr,
  flagCompare,
  presenceOnly,
  notANumber,
  expectedNumber,
  numberOutOfRange,
  numberNotWhole,
  numberNotQuarter,
  negatedComparison,
  ambiguous,
  secondElse,
  nothingToTest,
  // Warnings.
  elseAfterWord,
  otherwiseWord,
  emptyMeansNoValue,
}

/// The codes that are warnings: the template saves, but likely not as meant.
const Set<WordingIssueCode> wordingWarningCodes = {
  WordingIssueCode.elseAfterWord,
  WordingIssueCode.otherwiseWord,
  WordingIssueCode.emptyMeansNoValue,
};

/// One issue with a template in the display form, at [start] to [end] of
/// its text.
final class WordingIssue {
  const WordingIssue(this.code, this.start, this.end, this.data);

  final WordingIssueCode code;
  final int start;
  final int end;

  /// The words the message quotes: `found`, `name`, `names`, `values`,
  /// `suggestion`, `fix`, `word`, `op`, `example`, `min`, `max`, `context`,
  /// `readingA`, `readingB`, `phrase`, as the code uses them.
  final Map<String, String> data;

  bool get isError => !wordingWarningCodes.contains(code);

  @override
  String toString() => 'WordingIssue($code, $start-$end, $data)';
}

/// The result of reading a template in the display form: its [stored] form,
/// null when an error stops it, and its [issues], errors first.
final class WordingCheck {
  const WordingCheck(this.stored, this.issues);

  final String? stored;
  final List<WordingIssue> issues;

  bool get hasErrors => issues.any((i) => i.isError);

  /// The first error, or null when the template saves.
  WordingIssue? get error => issues.where((i) => i.isError).firstOrNull;

  Iterable<WordingIssue> get warnings => issues.where((i) => !i.isError);
}

// ---------------------------------------------------------------------------
// Display form: writing
// ---------------------------------------------------------------------------

/// A conditional group a help text can offer as an example, testing what
/// [vocabulary] has: `[if who is neighbors then … else …]`.
String wordingConditionExample(WordingVocabulary vocabulary) =>
    '[if ${_DisplayReader('', vocabulary)._exampleCondition()} then … else …]';

/// What [vocabulary] lets a condition test, sorted, as a help text lists them.
List<String> wordingTestableNames(WordingVocabulary vocabulary) =>
    [for (final n in vocabulary.names) n.name]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

/// [stored] in the display form, its values in the words of [vocabulary]:
/// what an editor shows. A template that is not well formed is returned as
/// it is, so the editor can show what is wrong with it; a value with no word
/// shows as stored, so the editor reports it.
String wordingForEditing(String stored, WordingVocabulary vocabulary) {
  final nodes = parseStoredWording(stored);
  if (nodes == null || !wordingHasConditions(nodes)) return stored.trim();
  return displayWordingText(nodes, vocabulary);
}

/// [condition] in the display form, in the words of [vocabulary]. With
/// [explicit], each test in a chain is wrapped in parentheses, so the text
/// has one reading even where the words alone would have two.
String displayWordingCondition(
  WordingCondition condition,
  WordingVocabulary vocabulary, {
  bool explicit = false,
}) => _conditionText(
  condition,
  name: (name) => vocabulary[name]?.name ?? name,
  value: (name, value) {
    if (value is num) return _storedNumber(value);
    return vocabulary[name]?.wordFor(value) ?? '$value';
  },
  explicit: explicit,
);

/// [condition] in the display form, written so that reading it back against
/// [vocabulary] gives [condition] again: in its plain words when they have
/// that one reading, else explicitly ([displayWordingCondition]), so that
/// showing a stored condition never changes what it means. A value with no
/// word shows as stored either way, and reading it back reports it.
String readableWordingCondition(
  WordingCondition condition,
  WordingVocabulary vocabulary,
) {
  final expected = '[{?if ${condition.stored}}x]';
  final plain = displayWordingCondition(condition, vocabulary);
  if (checkWording('[if $plain then x]', vocabulary).stored == expected) {
    return plain;
  }
  return displayWordingCondition(condition, vocabulary, explicit: true);
}

/// [nodes] in the display form, each condition as
/// [readableWordingCondition] writes it.
String displayWordingText(
  List<WordingNode> nodes,
  WordingVocabulary vocabulary,
) {
  final out = StringBuffer();
  late final void Function(List<WordingNode>) write;
  // A branch's words holding "else" (only an imported template can) go in
  // brackets of their own, where "else" is wording: they read back as they
  // were, and, holding no slot, are always shown.
  void writeBranch(List<WordingNode> nodes) => write([
    for (final node in nodes)
      if (node is WordingText &&
          _elseWord.hasMatch(node.text) &&
          !_slotPlaceholder.hasMatch(node.text))
        WordingGroup([node])
      else
        node,
  ]);
  write = (nodes) {
    for (final node in nodes) {
      switch (node) {
        case WordingText(:final text):
          out.write(text);
        case WordingGroup(:final children):
          out.write('[');
          write(children);
          out.write(']');
        case WordingChoice(:final branches, :final otherwise):
          out.write('[');
          for (var b = 0; b < branches.length; b++) {
            out.write(b == 0 ? 'if ' : ' else if ');
            out.write(
              readableWordingCondition(branches[b].condition, vocabulary),
            );
            out.write(' then ');
            writeBranch(branches[b].children);
          }
          if (otherwise != null) {
            out.write(' else ');
            writeBranch(otherwise);
          }
          out.write(']');
      }
    }
  };

  write(nodes);
  return out.toString();
}

// ---------------------------------------------------------------------------
// Display form: reading
// ---------------------------------------------------------------------------

/// Reads [text], a template in the display form, against [vocabulary].
///
/// A template with no conditional group reads exactly as before and is
/// stored exactly as typed. A conditional group is `[if` followed by a
/// condition, `then` and its wording, then any number of `else if` …
/// `then` … and at most one `else` … before its `]`. One whitespace after
/// `then` and `else`, and one before `else`, belong to the words, not the
/// wording.
///
/// A condition's words are read by where they stand: a name only where a
/// test starts, an operator only after `is`, a value only where one is
/// due, matched against the values the name has. Every reading is tried; a
/// condition with two readings is refused, naming both, rather than one
/// chosen silently.
WordingCheck checkWording(String text, WordingVocabulary vocabulary) {
  final reader = _DisplayReader(text, vocabulary);
  final nodes = reader.read();
  final issues = [if (reader.error != null) reader.error!, ...reader.warnings];
  if (nodes == null || reader.error != null) return WordingCheck(null, issues);
  final stored = storedWordingText(nodes);
  if (stored.trim().length > kMaxMoveWordingLength) {
    return WordingCheck(null, [
      WordingIssue(WordingIssueCode.tooLongStored, 0, text.length, {
        'max': '$kMaxMoveWordingLength',
      }),
      ...reader.warnings,
    ]);
  }
  return WordingCheck(stored, issues);
}

/// A reading of a condition: what it means and where it ends.
typedef _Reading = ({WordingCondition condition, int end});

/// A reason a reading failed, at [pos]: the furthest, then the most
/// specific ([priority]), is the one reported.
typedef _Failure = ({int pos, int priority, WordingIssue issue});

/// Words that end a condition's run of words: what a value can't run into.
const Set<String> _structuralWords = {'and', 'or', 'then', 'else'};

/// Whole words that come before `else` in a phrase a caller might mean as
/// wording ("everyone else"), not as the start of the else part.
const Set<String> _elsePhraseWords = {
  'everyone',
  'everybody',
  'someone',
  'somebody',
  'anyone',
  'anybody',
  'no one',
  'nobody',
  'something',
  'anything',
  'everything',
  'nothing',
  'or',
  'what',
  'who',
  'where',
  'how',
};

/// Words a caller may mean as `else`, from other languages of conditions.
const Set<String> _elseLookalikes = {'otherwise', 'elif', 'elseif', 'elsif'};

/// Symbols for operators and connectives, with the words to write instead,
/// longest first so `>=` is not read as `>`.
const List<(String, String)> _operatorSymbols = [
  ('==', 'is'),
  ('!=', 'is not'),
  ('<>', 'is not'),
  ('>=', 'is at least'),
  ('<=', 'is at most'),
  ('≠', 'is not'),
  ('≥', 'is at least'),
  ('≤', 'is at most'),
  ('=', 'is'),
  ('>', 'is more than'),
  ('<', 'is less than'),
];

const List<(String, String)> _connectiveSymbols = [
  ('&&', 'and'),
  ('||', 'or'),
  ('&', 'and'),
  ('|', 'or'),
];

final RegExp _number = RegExp(r'(\d+(?:\.\d+)?)([¼½¾])?|([¼½¾])');
final RegExp _isntWord = RegExp("isn['’]?t", caseSensitive: false);
final RegExp _conditionShape = RegExp(
  r'^(if\b|.*\bis\b)',
  caseSensitive: false,
);
final RegExp _firstWord = RegExp(r'\w+');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _elseWord = RegExp(
  r"(^|[^\w'’])else($|[^\w'’])",
  caseSensitive: false,
);
final RegExp _orBetween = RegExp(r'\s+or\s+', caseSensitive: false);

bool _isWordChar(String char) {
  final code = char.codeUnitAt(0);
  if (char == '_' || char == "'" || char == '’') return true;
  if (code >= 0x30 && code <= 0x39) return true;
  if (code >= 0x41 && code <= 0x5a) return true;
  if (code >= 0x61 && code <= 0x7a) return true;
  // Letters beyond ASCII (é, ø, …) count as word characters.
  return code >= 0xc0 && char.toLowerCase() != char.toUpperCase();
}

bool _isSpace(String char) => char.trim().isEmpty;

bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

final class _DisplayReader {
  _DisplayReader(this.text, this.vocabulary);

  final String text;
  final WordingVocabulary vocabulary;

  WordingIssue? error;
  final List<WordingIssue> warnings = [];
  int i = 0;

  // -- Shared scanning helpers ---------------------------------------------

  int _skipSpace(int at) {
    var j = at;
    while (j < text.length && _isSpace(text[j])) {
      j++;
    }
    return j;
  }

  bool _boundaryAfter(int at) => at >= text.length || !_isWordChar(text[at]);

  bool _boundaryBefore(int at) => at <= 0 || !_isWordChar(text[at - 1]);

  /// The end of [word] at [at], ignoring case and with any run of spaces in
  /// [word] matching any run in the text, or null. A [word] ending in a word
  /// character must end where a word does.
  int? _matchWords(int at, String word) {
    var j = at;
    var k = 0;
    while (k < word.length) {
      if (_isSpace(word[k])) {
        if (j >= text.length || !_isSpace(text[j])) return null;
        while (k < word.length && _isSpace(word[k])) {
          k++;
        }
        j = _skipSpace(j);
        continue;
      }
      if (j >= text.length) return null;
      if (text[j].toLowerCase() != word[k].toLowerCase()) return null;
      j++;
      k++;
    }
    if (word.isNotEmpty && _isWordChar(word[word.length - 1])) {
      if (!_boundaryAfter(j)) return null;
    }
    return j;
  }

  /// The end of the keyword [word] (which may be two words) at [at], or null.
  int? _keyword(int at, String word) {
    if (!_boundaryBefore(at)) return null;
    return _matchWords(at, word);
  }

  /// The run of word characters at [at], or the single character there.
  String _wordAt(int at) {
    if (at >= text.length) return '';
    var j = at;
    while (j < text.length && _isWordChar(text[j])) {
      j++;
    }
    return j == at ? text[at] : text.substring(at, j);
  }

  /// The words from [at] up to the next structural word, `,`, `(`, `)` or
  /// `]`: what a value or a name the reader doesn't know was meant to be.
  String _runAt(int at) {
    var j = at;
    var lastWordEnd = at;
    while (j < text.length) {
      final char = text[j];
      if (char == ',' || char == ')' || char == '(' || char == ']') break;
      if (_isWordChar(char)) {
        if (_boundaryBefore(j) &&
            _structuralWords.any((w) => _keyword(j, w) != null) &&
            j > at) {
          break;
        }
        while (j < text.length && _isWordChar(text[j])) {
          j++;
        }
        lastWordEnd = j;
        continue;
      }
      if (!_isSpace(char)) lastWordEnd = j + 1;
      j++;
    }
    final run = text.substring(at, lastWordEnd).trim();
    return run.isEmpty ? _wordAt(at) : run;
  }

  /// A short quote of the text from [start]: at most [max] characters, with
  /// an ellipsis when cut.
  String _context(int start, [int max = 24]) {
    final end = start + max;
    if (end >= text.length) return text.substring(start).trim();
    return '${text.substring(start, end).trimRight()}…';
  }

  // -- Template structure ---------------------------------------------------

  List<WordingNode>? read() {
    final nodes = _sequence(groupStart: null, inChoice: false);
    if (nodes == null) return null;
    if (i < text.length) {
      // Only a `]` stops the top level early.
      _fail(WordingIssueCode.strayCloseBracket, i, i + 1, {
        'context': _context(i > 12 ? i - 12 : 0),
      });
      return null;
    }
    return nodes;
  }

  void _fail(
    WordingIssueCode code,
    int start,
    int end,
    Map<String, String> data,
  ) {
    error ??= WordingIssue(code, start, end, data);
  }

  /// Parts up to the end, a `]` (left unread) or, in a conditional's branch
  /// ([inChoice]), an `else` at its own level (left unread).
  List<WordingNode>? _sequence({
    required int? groupStart,
    required bool inChoice,
  }) {
    final nodes = <WordingNode>[];
    final literal = StringBuffer();
    void flush() {
      if (literal.isEmpty) return;
      nodes.add(WordingText(literal.toString()));
      literal.clear();
    }

    while (i < text.length) {
      final char = text[i];
      if (char == ']') {
        if (groupStart == null) {
          _fail(WordingIssueCode.strayCloseBracket, i, i + 1, {
            'context': _context(i > 12 ? i - 12 : 0),
          });
          return null;
        }
        break;
      }
      if (char == '}') {
        _fail(WordingIssueCode.strayCloseBrace, i, i + 1, {
          'context': _context(i > 12 ? i - 12 : 0),
          'example': '{${_exampleSlot()}}',
        });
        return null;
      }
      if (char == '{') {
        final close = text.indexOf('}', i + 1);
        final nextOpen = text.indexOf('{', i + 1);
        if (close < 0 || (nextOpen >= 0 && nextOpen < close)) {
          _fail(WordingIssueCode.unclosedSlot, i, i + 1, {
            'context': _context(i),
            'example': '{${_exampleSlot()}}',
          });
          return null;
        }
        final name = text.substring(i + 1, close);
        if (!_slotName.hasMatch(name)) {
          final inner = name.trim();
          final looksLikeCondition = _conditionShape.hasMatch(inner);
          _fail(
            looksLikeCondition
                ? WordingIssueCode.conditionInBraces
                : WordingIssueCode.badSlot,
            i,
            close + 1,
            {
              'found': text.substring(i, close + 1),
              'fix': looksLikeCondition
                  ? '[${inner.toLowerCase().startsWith('if') ? inner : 'if $inner'} then …]'
                  : '{${_slotSuggestion(inner)}}',
            },
          );
          return null;
        }
        literal.write(text.substring(i, close + 1));
        i = close + 1;
        continue;
      }
      if (char == '[') {
        flush();
        final start = i;
        i++;
        final ifStart = _skipSpace(i);
        final ifEnd = _keyword(ifStart, 'if');
        if (ifEnd != null) {
          final choice = _choice(start, ifStart, ifEnd);
          if (choice == null) return null;
          nodes.add(choice);
          continue;
        }
        final children = _sequence(groupStart: start, inChoice: false);
        if (children == null) return null;
        if (i >= text.length) {
          _fail(WordingIssueCode.unclosedGroup, start, start + 1, {
            'context': _context(start),
          });
          return null;
        }
        i++;
        nodes.add(WordingGroup(children));
        continue;
      }
      if (inChoice && _isWordChar(char) && _boundaryBefore(i)) {
        if (_keyword(i, 'else') != null) break;
        final word = _wordAt(i);
        if (_elseLookalikes.contains(word.toLowerCase())) {
          warnings.add(
            WordingIssue(WordingIssueCode.otherwiseWord, i, i + word.length, {
              'found': word,
            }),
          );
        }
        literal.write(word);
        i += word.length;
        continue;
      }
      literal.write(char);
      i++;
    }
    flush();
    return nodes;
  }

  /// A slot a message can offer as an example: the first that is not the
  /// figure's name or beats, else `move`.
  String _exampleSlot() =>
      vocabulary.names
          .where((n) => n.name != 'move' && n.name != 'beats')
          .firstOrNull
          ?.name ??
      'move';

  String _slotSuggestion(String inner) {
    final word = _firstWord.firstMatch(inner)?[0];
    return word ?? 'who';
  }

  /// A conditional group: [start] is its `[`, the `if` runs from [ifStart]
  /// to [ifEnd].
  WordingChoice? _choice(int start, int ifStart, int ifEnd) {
    final branches =
        <({WordingCondition condition, List<WordingNode> children})>[];
    List<WordingNode>? otherwise;
    var keywordStart = ifStart;
    var keyword = 'if';
    var at = ifEnd;
    while (true) {
      final condition = _conditionThen(keywordStart, keyword, at);
      if (condition == null) return null;
      i = condition.end;
      if (i < text.length && _isSpace(text[i])) i++;
      final children = _sequence(groupStart: start, inChoice: true);
      if (children == null) return null;
      if (i >= text.length) {
        _fail(WordingIssueCode.unclosedGroup, start, start + 1, {
          'context': _context(start),
        });
        return null;
      }
      if (text[i] == ']') {
        branches.add((condition: condition.condition, children: children));
        break;
      }
      // An `else` ends the branch: one space before it belongs to it.
      _trimOneTrailingSpace(children);
      branches.add((condition: condition.condition, children: children));
      _warnElsePhrase(children, i);
      final elseStart = i;
      i = _keyword(i, 'else')!;
      final next = _skipSpace(i);
      final ifAgain = _keyword(next, 'if');
      if (ifAgain != null) {
        keywordStart = elseStart;
        keyword = 'else if';
        at = ifAgain;
        continue;
      }
      if (i < text.length && _isSpace(text[i])) i++;
      otherwise = _sequence(groupStart: start, inChoice: true);
      if (otherwise == null) return null;
      if (i < text.length && text[i] != ']') {
        // A second `else`.
        final word = _wordAt(i);
        _fail(WordingIssueCode.secondElse, i, i + word.length, {
          'context': _context(start),
          'found': word,
        });
        return null;
      }
      if (i >= text.length) {
        _fail(WordingIssueCode.unclosedGroup, start, start + 1, {
          'context': _context(start),
        });
        return null;
      }
      break;
    }
    i++;
    return WordingChoice(branches, otherwise);
  }

  void _trimOneTrailingSpace(List<WordingNode> children) {
    if (children.isEmpty) return;
    final last = children.last;
    if (last is WordingText &&
        last.text.isNotEmpty &&
        _isSpace(last.text[last.text.length - 1])) {
      final trimmed = last.text.substring(0, last.text.length - 1);
      if (trimmed.isEmpty) {
        children.removeLast();
      } else {
        children[children.length - 1] = WordingText(trimmed);
      }
    }
  }

  /// Warns when the `else` at [elseAt] follows a word it reads as a phrase
  /// with ("everyone else"): that `else` starts the else part.
  void _warnElsePhrase(List<WordingNode> children, int elseAt) {
    if (children.isEmpty || children.last is! WordingText) return;
    final words = (children.last as WordingText).text.trimRight().split(
      _spaces,
    );
    if (words.isEmpty) return;
    final last = words.last.toLowerCase();
    final lastTwo = words.length >= 2
        ? '${words[words.length - 2]} ${words.last}'.toLowerCase()
        : '';
    final phrase = _elsePhraseWords.contains(lastTwo)
        ? lastTwo
        : _elsePhraseWords.contains(last)
        ? last
        : null;
    if (phrase == null) return;
    final shown = lastTwo == phrase
        ? '${words[words.length - 2]} ${words.last}'
        : words.last;
    warnings.add(
      WordingIssue(WordingIssueCode.elseAfterWord, elseAt, elseAt + 4, {
        'phrase': '$shown ${text.substring(elseAt, elseAt + 4)}',
        'word': shown,
      }),
    );
  }

  // -- Conditions -------------------------------------------------------------

  final List<_Failure> _failures = [];

  void _failAt(
    int pos,
    int priority,
    WordingIssueCode code,
    int start,
    int end,
    Map<String, String> data,
  ) {
    _failures.add((
      pos: pos,
      priority: priority,
      issue: WordingIssue(code, start, end, data),
    ));
  }

  /// The condition after [keyword] (`if` or `else if`, at [keywordStart],
  /// ending at [at]) through its `then`: one reading, its end after `then`.
  _Reading? _conditionThen(int keywordStart, String keyword, int at) {
    _failures.clear();
    final start = _skipSpace(at);
    if (start >= text.length ||
        text[start] == ']' ||
        _keyword(start, 'then') != null) {
      _fail(WordingIssueCode.missingCondition, keywordStart, start, {
        'word': text.substring(keywordStart, at),
        'example': _exampleCondition(),
      });
      return null;
    }
    final candidates =
        <String, ({WordingCondition condition, int end, int conditionEnd})>{};
    final readings = _condition(start, keywordStart: keywordStart);
    for (final reading in readings) {
      final k = _skipSpace(reading.end);
      final thenEnd = _keyword(k, 'then');
      if (thenEnd != null) {
        candidates.putIfAbsent(
          '${reading.condition.stored}@$thenEnd',
          () => (
            condition: reading.condition,
            end: thenEnd,
            conditionEnd: reading.end,
          ),
        );
        continue;
      }
      _expectedAfterCondition(reading, k, start);
    }
    if (candidates.isEmpty) {
      _reportFailure(keywordStart, start, keyword);
      return null;
    }
    if (candidates.length > 1) {
      final list = candidates.values.toList();
      final end = list
          .map((r) => r.conditionEnd)
          .reduce((a, b) => a > b ? a : b);
      final found = text.substring(start, end).trim();
      _fail(WordingIssueCode.ambiguous, start, end, {
        'found': found,
        'readingA': displayWordingCondition(
          list[0].condition,
          vocabulary,
          explicit: true,
        ),
        'readingB': displayWordingCondition(
          list[1].condition,
          vocabulary,
          explicit: true,
        ),
      });
      return null;
    }
    final only = candidates.values.single;
    _warnEmptyLabel(only.condition, start, only.conditionEnd);
    return (condition: only.condition, end: only.end);
  }

  /// Records why [reading], a whole condition from [start] whose words end
  /// before [k], is not followed by `then`.
  void _expectedAfterCondition(_Reading reading, int k, int start) {
    final before = text.substring(start, reading.end).trim();
    if (k >= text.length || text[k] == ']' || _keyword(k, 'else') != null) {
      _failAt(k, 1, WordingIssueCode.missingThen, start, reading.end, {
        'condition': before,
      });
      return;
    }
    if (text[k] == ')') {
      _failAt(k, 2, WordingIssueCode.strayCloseParen, k, k + 1, {
        'context': _context(start),
      });
      return;
    }
    if (text[k] == ':') {
      _failAt(k, 3, WordingIssueCode.colonForThen, k, k + 1, {
        'condition': before,
      });
      return;
    }
    for (final (symbol, word) in _connectiveSymbols) {
      if (text.startsWith(symbol, k)) {
        _failAt(k, 3, WordingIssueCode.symbolForWord, k, k + symbol.length, {
          'found': symbol,
          'word': word,
          'fix': '$before $word …',
        });
        return;
      }
    }
    final found = _wordAt(k);
    final last = _lastTest(reading.condition);
    if (last != null &&
        (last.op == WordingTestOp.equals ||
            last.op == WordingTestOp.notEquals)) {
      final info = vocabulary[last.name];
      // A second value, after a space or a comma: a list was meant.
      final valueAt = text[k] == ',' ? _skipSpace(k + 1) : k;
      final more = info == null ? null : _valueAt(info, valueAt);
      if (more != null && more.isNotEmpty) {
        final words = [
          info!.wordFor(last.values.first) ?? '${last.values.first}',
          info.wordFor(more.first.value) ?? '${more.first.value}',
        ];
        final not = last.op == WordingTestOp.notEquals ? 'not ' : '';
        _failAt(
          k,
          2,
          WordingIssueCode.expectedConnectiveList,
          k,
          k + found.length,
          {
            'before': before,
            'found': found,
            'fix': '${info.name} is ${not}in (${words.join(', ')})',
          },
        );
        return;
      }
    }
    _failAt(k, 1, WordingIssueCode.expectedConnective, k, k + found.length, {
      'before': before,
      'found': found,
    });
  }

  WordingTest? _lastTest(WordingCondition condition) => switch (condition) {
    WordingTest() => condition,
    WordingNot() => null,
    WordingAll(:final parts) ||
    WordingAny(:final parts) => _lastTest(parts.last),
  };

  void _reportFailure(int keywordStart, int start, String keyword) {
    if (_failures.isEmpty) {
      _fail(WordingIssueCode.missingCondition, keywordStart, start, {
        'word': keyword,
        'example': _exampleCondition(),
      });
      return;
    }
    var best = _failures.first;
    for (final failure in _failures.skip(1)) {
      if (failure.pos > best.pos ||
          (failure.pos == best.pos && failure.priority > best.priority)) {
        best = failure;
      }
    }
    error ??= best.issue;
  }

  /// A condition a message can offer as an example: a switch the template
  /// may test, else a value test, else a bare name.
  String _exampleCondition() {
    final flag = vocabulary.names
        .where((n) => n.kind == WordingNameKind.flag)
        .firstOrNull;
    if (flag != null) return flag.name;
    final values = vocabulary.names
        .where((n) => n.kind == WordingNameKind.choices && n.values.isNotEmpty)
        .firstOrNull;
    if (values != null) return '${values.name} is ${values.values.first.word}';
    final number = vocabulary.names
        .where((n) => n.kind == WordingNameKind.number)
        .firstOrNull;
    if (number != null) {
      return '${number.name} is more than ${_exampleNumber(number)}';
    }
    return vocabulary.names.isEmpty ? 'move' : vocabulary.names.first.name;
  }

  String _exampleNumber(WordingName name) => switch (name.spec?.kind) {
    ParamKind.rotation => '1.5',
    ParamKind.places => '2',
    _ => '8',
  };

  String _names() => wordingTestableNames(vocabulary).join(', ');

  String _values(WordingName name) =>
      [for (final v in name.values) v.word].join(', ');

  /// Every reading of a chain of tests joined by `and` or `or`, from [at].
  List<_Reading> _condition(int at, {required int keywordStart}) {
    final results = <_Reading>[];
    // Each state: the parts read, the connectives between them, where each
    // part starts and ends, and where the chain stands.
    final frontier =
        <
          ({
            List<WordingCondition> parts,
            List<String> ops,
            List<(int, int)> spans,
            int end,
          })
        >[];
    // Two readings that reach the same place with the same connectives stay
    // two however the chain goes on, which is all a refusal needs: keep at
    // most two there, and the reading stays linear however many of a
    // chain's words could be read two ways.
    final seen = <String>{};
    final atPlace = <String, int>{};
    void add(
      List<WordingCondition> parts,
      List<String> ops,
      List<(int, int)> spans,
      int end,
    ) {
      final place = '$end|${ops.toSet().join(',')}';
      final reading = '$place|${[for (final p in parts) p.stored].join('|')}';
      if (!seen.add(reading)) return;
      final count = atPlace.update(place, (n) => n + 1, ifAbsent: () => 1);
      if (count > 2) return;
      frontier.add((parts: parts, ops: ops, spans: spans, end: end));
    }

    for (final unit in _unit(at, keywordStart: keywordStart)) {
      add([unit.condition], const [], [(at, unit.end)], unit.end);
    }
    while (frontier.isNotEmpty) {
      final state = frontier.removeLast();
      final k = _skipSpace(state.end);
      final andEnd = _keyword(k, 'and');
      final orEnd = andEnd == null ? _keyword(k, 'or') : null;
      if (andEnd != null || orEnd != null) {
        final op = andEnd != null ? 'and' : 'or';
        final next = _skipSpace(andEnd ?? orEnd!);
        final units = _unit(next, keywordStart: keywordStart);
        for (final unit in units) {
          add([...state.parts, unit.condition], [...state.ops, op], [
            ...state.spans,
            (next, unit.end),
          ], unit.end);
        }
        if (units.isEmpty) {
          _valueAfterConnective(state.parts.last, op, at, k, next);
        }
      }
      // The chain may also end here, before an `and` read as part of a
      // value or name further on.
      final ops = state.ops.toSet();
      if (ops.length > 1) {
        _failAt(state.end, 4, WordingIssueCode.mixedAndOr, at, state.end, {
          'found': text.substring(at, state.end).trim(),
          ..._mixedFixes(state.spans, state.ops),
        });
        continue;
      }
      final condition = state.parts.length == 1
          ? state.parts.single
          : ops.single == 'and'
          ? WordingAll(state.parts)
          : WordingAny(state.parts);
      results.add((condition: condition, end: state.end));
    }
    return results;
  }

  /// Records, when the words after the connective [op] (at [k]) are a value
  /// of the test before it rather than a test ("who is robins or larks"),
  /// the two ways to write what was meant.
  void _valueAfterConnective(
    WordingCondition previous,
    String op,
    int chainStart,
    int k,
    int next,
  ) {
    final last = _lastTest(previous);
    if (last == null ||
        (last.op != WordingTestOp.equals &&
            last.op != WordingTestOp.notEquals)) {
      return;
    }
    final info = vocabulary[last.name];
    if (info == null || info.kind != WordingNameKind.choices) return;
    final more = _valueAt(info, next);
    if (more == null) return;
    final first = info.wordFor(last.values.first) ?? '${last.values.first}';
    final second = info.wordFor(more.first.value) ?? '${more.first.value}';
    final negated = last.op == WordingTestOp.notEquals;
    final repeat = negated
        ? '${info.name} is not $first and ${info.name} is not $second'
        : '${info.name} is $first or ${info.name} is $second';
    final list = '${info.name} is ${negated ? 'not ' : ''}in ($first, $second)';
    _failAt(
      next,
      3,
      WordingIssueCode.valueAfterConnective,
      next,
      more.first.end,
      {
        'found': text.substring(next, more.first.end),
        'word': op,
        'fixA': repeat,
        'fixB': list,
      },
    );
  }

  /// Two ways to group a chain that mixes `and` and `or`: `and` first, then
  /// `or` first.
  Map<String, String> _mixedFixes(List<(int, int)> spans, List<String> ops) {
    final parts = [for (final (s, e) in spans) text.substring(s, e).trim()];
    String group(String first) {
      final out = StringBuffer();
      var run = <String>[parts.first];
      void close() {
        out.write(run.length > 1 ? '(${run.join(' $first ')})' : run.single);
      }

      for (var p = 0; p < ops.length; p++) {
        if (ops[p] == first) {
          run.add(parts[p + 1]);
        } else {
          close();
          out.write(' ${ops[p]} ');
          run = [parts[p + 1]];
        }
      }
      close();
      return out.toString();
    }

    return {'fixA': group('and'), 'fixB': group('or')};
  }

  /// Every reading of one unit at [at]: `not` and a unit, a parenthesized
  /// condition, or a test.
  List<_Reading> _unit(int at, {required int keywordStart}) {
    final k = _skipSpace(at);
    if (k >= text.length || text[k] == ']' || _keyword(k, 'then') != null) {
      _failAt(k, 1, WordingIssueCode.missingCondition, keywordStart, k, {
        'word': _previousWord(k),
        'example': _exampleCondition(),
      });
      return const [];
    }
    final notEnd = _keyword(k, 'not');
    if (notEnd != null) {
      return [
        for (final r in _unit(notEnd, keywordStart: keywordStart))
          (condition: WordingNot(r.condition), end: r.end),
      ];
    }
    if (text[k] == '!' && !text.startsWith('!=', k)) {
      final rest = _skipSpace(k + 1);
      _failAt(k, 3, WordingIssueCode.symbolForWord, k, k + 1, {
        'found': '!',
        'word': 'not',
        'fix': 'not ${_runAt(rest)}',
      });
      return const [];
    }
    if (text[k] == '(') {
      final inner = _skipSpace(k + 1);
      if (inner < text.length && text[inner] == ')') {
        _failAt(inner, 2, WordingIssueCode.emptyParens, k, inner + 1, {});
        return const [];
      }
      final out = <_Reading>[];
      for (final r in _condition(inner, keywordStart: keywordStart)) {
        final close = _skipSpace(r.end);
        if (close < text.length && text[close] == ')') {
          out.add((condition: r.condition, end: close + 1));
          continue;
        }
        if (close >= text.length ||
            text[close] == ']' ||
            _keyword(close, 'then') != null) {
          _failAt(close, 2, WordingIssueCode.unclosedParen, k, k + 1, {
            'context': _context(k),
            'before': text.substring(k, r.end).trim(),
          });
          continue;
        }
        final found = _wordAt(close);
        _failAt(
          close,
          1,
          WordingIssueCode.expectedConnective,
          close,
          close + found.length,
          {
            'before': text.substring(inner, r.end).trim(),
            'found': found,
            'close': ')',
          },
        );
      }
      return out;
    }
    if (text[k] == ')') {
      _failAt(k, 2, WordingIssueCode.strayCloseParen, k, k + 1, {
        'context': _context(k > 12 ? k - 12 : 0),
      });
      return const [];
    }
    if (text[k] == '{') {
      final close = text.indexOf('}', k);
      final inner = close < 0 ? '' : text.substring(k + 1, close);
      final bare = inner.startsWith('!') ? inner.substring(1) : inner;
      if (close >= 0 && vocabulary[bare] != null) {
        _failAt(k, 3, WordingIssueCode.nameInBraces, k, close + 1, {
          'name': vocabulary[bare]!.name,
          'found': text.substring(k, close + 1),
        });
        return const [];
      }
    }
    if (vocabulary.names.isEmpty) {
      _failAt(
        k,
        5,
        WordingIssueCode.nothingToTest,
        k,
        k + _wordAt(k).length,
        {},
      );
      return const [];
    }
    // A name: one word, of the names the template may test.
    final word = _wordAt(k);
    final info = vocabulary[word];
    if (info == null || !_isWordChar(word[0])) {
      final reserved = wordingReservedWords.contains(word.toLowerCase());
      if (reserved) {
        _failAt(
          k,
          1,
          WordingIssueCode.missingCondition,
          keywordStart,
          k + word.length,
          {'word': _previousWord(k), 'example': _exampleCondition()},
        );
        return const [];
      }
      final suggestion = _suggest(word, [
        for (final n in vocabulary.names) n.name,
      ]);
      final afterIf = _isRightAfterIf(keywordStart, k);
      _failAt(
        k,
        1,
        afterIf
            ? WordingIssueCode.unknownNameAfterIf
            : WordingIssueCode.unknownName,
        k,
        k + word.length,
        {'found': word, 'suggestion': ?suggestion, 'names': _names()},
      );
      return const [];
    }
    return _test(info, k, k + word.length);
  }

  /// The word or symbol just before [at]: what a test was due after.
  String _previousWord(int at) {
    var j = at;
    while (j > 0 && _isSpace(text[j - 1])) {
      j--;
    }
    if (j == 0) return '';
    if (!_isWordChar(text[j - 1])) return text[j - 1];
    var start = j;
    while (start > 0 && _isWordChar(text[start - 1])) {
      start--;
    }
    final word = text.substring(start, j);
    // `else if` reads as one keyword.
    if (word.toLowerCase() == 'if') {
      var before = start;
      while (before > 0 && _isSpace(text[before - 1])) {
        before--;
      }
      if (before >= 4 &&
          text.substring(before - 4, before).toLowerCase() == 'else' &&
          _boundaryBefore(before - 4)) {
        return text.substring(before - 4, j);
      }
    }
    return word;
  }

  bool _isRightAfterIf(int keywordStart, int k) {
    final between = text.substring(keywordStart, k).trim().toLowerCase();
    return between == 'if';
  }

  /// Every reading of a test of [info], whose name runs from [nameStart] to
  /// [nameEnd].
  List<_Reading> _test(WordingName info, int nameStart, int nameEnd) {
    final bare = (
      condition:
          WordingTest(info.name, WordingTestOp.present) as WordingCondition,
      end: nameEnd,
    );
    final k = _skipSpace(nameEnd);
    final isEnd = _keyword(k, 'is');
    if (isEnd == null) {
      final isnt = _isntWord.matchAsPrefix(text, k);
      if (isnt != null && _boundaryAfter(isnt.end)) {
        _failAt(k, 5, WordingIssueCode.isntForIsNot, k, isnt.end, {
          'found': isnt[0]!,
          'fix':
              '${text.substring(nameStart, k)}is not${_clauseRest(isnt.end)}',
        });
        return [bare];
      }
      for (final (symbol, word) in _operatorSymbols) {
        if (text.startsWith(symbol, k)) {
          _failAt(k, 5, WordingIssueCode.symbolForWord, k, k + symbol.length, {
            'found': symbol,
            'word': word,
            'fix':
                '${text.substring(nameStart, nameEnd)} $word${_clauseRest(k + symbol.length)}',
          });
          return [bare];
        }
      }
      return [bare];
    }
    return _isClause(info, nameStart, isEnd);
  }

  /// The rest of a test's words from [at], with a leading space: what a fix
  /// keeps after the word it replaces.
  String _clauseRest(int at) {
    final start = _skipSpace(at);
    if (start >= text.length) return '';
    final rest = _clauseRun(start);
    return rest.isEmpty ? '' : ' $rest';
  }

  /// The words from [at] to the next of [stopAt] or `]`, keeping
  /// parentheses that belong to a list.
  String _clauseRun(int at, {Set<String> stopAt = _structuralWords}) {
    var j = at;
    var depth = 0;
    while (j < text.length) {
      final char = text[j];
      if (char == ']') break;
      if (char == '(') depth++;
      if (char == ')') {
        if (depth == 0) break;
        depth--;
      }
      if (depth == 0 &&
          _isWordChar(char) &&
          _boundaryBefore(j) &&
          stopAt.any((w) => _keyword(j, w) != null)) {
        break;
      }
      j++;
    }
    return text.substring(at, j).trim();
  }

  /// Every reading of what follows `is` (which ends at [at]) in a test of
  /// [info].
  List<_Reading> _isClause(WordingName info, int nameStart, int at) {
    final out = <_Reading>[];
    final afterIs = _skipSpace(at);
    var k = afterIs;
    final notEnd = _keyword(k, 'not');
    final negated = notEnd != null;
    if (negated) k = _skipSpace(notEnd);
    final testText = text.substring(nameStart, at).trim();
    final opText = negated ? '$testText not' : testText;

    // A value whose words begin with "not" ("not sure") is a reading too,
    // beside `is not` and the rest.
    if (negated && info.kind == WordingNameKind.choices) {
      for (final value
          in _valueAt(info, afterIs) ?? const <({Object value, int end})>[]) {
        out.add((
          condition: WordingTest(info.name, WordingTestOp.equals, [
            value.value,
          ]),
          end: value.end,
        ));
      }
    }

    if (k >= text.length ||
        text[k] == ']' ||
        (_keyword(k, 'then') != null &&
            (info.kind != WordingNameKind.choices ||
                _valueAt(info, k) == null))) {
      switch (info.kind) {
        case WordingNameKind.flag:
          _flagCompare(info, nameStart);
          return out;
        case WordingNameKind.text || WordingNameKind.slot:
          _failAt(k, 3, WordingIssueCode.presenceOnly, nameStart, k, {
            'name': info.name,
          });
          return out;
        case WordingNameKind.choices || WordingNameKind.number:
          break;
      }
      _failAt(k, 2, WordingIssueCode.expectedValue, nameStart, k, {
        'before': opText,
        'name': info.name,
        'example': _exampleValue(info),
        'values': _valueList(info),
      });
      return out;
    }

    // `is empty`.
    final emptyEnd = _keyword(k, 'empty');
    if (emptyEnd != null) {
      if (info.kind == WordingNameKind.flag) {
        _flagCompare(info, k);
      } else {
        out.add((
          condition: WordingTest(
            info.name,
            negated ? WordingTestOp.notEmpty : WordingTestOp.empty,
          ),
          end: emptyEnd,
        ));
      }
    }

    // `is in (…)`.
    final inEnd = _keyword(k, 'in');
    if (inEnd != null) {
      final open = _skipSpace(inEnd);
      if (open < text.length && text[open] == '(') {
        out.addAll(_list(info, negated, nameStart, k, open));
      } else if (info.kind == WordingNameKind.choices ||
          info.kind == WordingNameKind.number) {
        // Not a list: `in` may still be a value (a direction).
        final rest = _clauseRun(open);
        _failAt(open, 2, WordingIssueCode.listNeedsParens, k, open, {
          'fix':
              '${info.name} is ${negated ? 'not ' : ''}in (${rest.isEmpty ? _exampleValue(info) : rest})',
        });
      }
    }

    // `is one of …` and its kin.
    for (final (phrase, replacement) in const [
      ('one of', 'in'),
      ('any of', 'in'),
      ('none of', 'not in'),
      ('either', 'in'),
    ]) {
      final end = _keyword(k, phrase);
      if (end != null) {
        final rest = _clauseRun(
          _skipSpace(end),
          stopAt: const {'and', 'then', 'else'},
        ).replaceAll(_orBetween, ', ');
        final op = negated && replacement == 'in'
            ? 'not in'
            : negated
            ? 'in'
            : replacement;
        _failAt(end, 3, WordingIssueCode.oneOfForIsIn, k, end, {
          'found': text.substring(k, end),
          'word': 'is $op (…)',
          'fix':
              '${info.name} is $op (${rest.isEmpty ? _exampleValue(info) : rest})',
        });
      }
    }

    // Comparisons.
    for (final (phrase, op) in const [
      ('more than', WordingTestOp.moreThan),
      ('less than', WordingTestOp.lessThan),
      ('at least', WordingTestOp.atLeast),
      ('at most', WordingTestOp.atMost),
    ]) {
      final end = _keyword(k, phrase);
      if (end == null) continue;
      if (info.kind != WordingNameKind.number) {
        // Not a number: the words may still be a value ("more than ever").
        _failAt(end, 3, WordingIssueCode.notANumber, k, end, {
          'name': info.name,
          'op': phrase,
        });
        continue;
      }
      if (negated) {
        const flipped = {
          'more than': 'at most',
          'less than': 'at least',
          'at least': 'less than',
          'at most': 'more than',
        };
        _failAt(end, 4, WordingIssueCode.negatedComparison, nameStart, end, {
          'found': text.substring(nameStart, end),
          'fix': '${info.name} is ${flipped[phrase]}${_clauseRest(end)}',
        });
        continue;
      }
      final numberAt = _skipSpace(end);
      final number = _numberAt(info, numberAt, phrase);
      if (number != null) {
        out.add((
          condition: WordingTest(info.name, op, [number.value]),
          end: number.end,
        ));
      }
    }

    // A value.
    switch (info.kind) {
      case WordingNameKind.flag:
        if (emptyEnd == null) _flagCompare(info, k);
      case WordingNameKind.text || WordingNameKind.slot:
        if (emptyEnd == null) {
          _failAt(k, 3, WordingIssueCode.presenceOnly, nameStart, k, {
            'name': info.name,
          });
        }
      case WordingNameKind.number:
        if (_isComparisonOrList(k)) break;
        final number = _numberAt(info, k, 'is');
        if (number != null) {
          out.add((
            condition: WordingTest(
              info.name,
              negated ? WordingTestOp.notEquals : WordingTestOp.equals,
              [number.value],
            ),
            end: number.end,
          ));
        }
      case WordingNameKind.choices:
        // `is empty` always means no value, never a value called "empty"
        // (a warning says so).
        final values = _valueAt(
          info,
          k,
        )?.where((v) => emptyEnd == null || v.end != emptyEnd).toList();
        for (final value in values ?? const <({Object value, int end})>[]) {
          out.add((
            condition: WordingTest(
              info.name,
              negated ? WordingTestOp.notEquals : WordingTestOp.equals,
              [value.value],
            ),
            end: value.end,
          ));
        }
        if ((values == null || values.isEmpty) && out.isEmpty) {
          _unknownValue(info, k, opText);
        }
    }
    return out;
  }

  bool _isComparisonOrList(int k) =>
      _keyword(k, 'in') != null ||
      _keyword(k, 'empty') != null ||
      [
        'more than',
        'less than',
        'at least',
        'at most',
        'one of',
        'any of',
        'none of',
        'either',
      ].any((p) => _keyword(k, p) != null);

  void _flagCompare(WordingName info, int k) {
    _failAt(k, 4, WordingIssueCode.flagCompare, k, k + _wordAt(k).length, {
      'name': info.name,
    });
  }

  /// Records why no value of [info] is written at [k], after [opText] (the
  /// test's words up to the value: `who is`, or `who is` before `in (` when
  /// [listOpen], the list's `(`, is given).
  void _unknownValue(WordingName info, int k, String opText, {int? listOpen}) {
    const quotes = {'"', '“', '”', "'", '‘', '’', '«', '»', '„', '「', '」'};
    String unquote(String words) =>
        words.split('').where((c) => !quotes.contains(c)).join().trim();
    if (quotes.contains(text[k])) {
      if (listOpen != null) {
        // The whole list, its quotes taken out.
        final close = text.indexOf(')', listOpen);
        final end = close < 0 ? text.length : close;
        final inner = unquote(text.substring(listOpen + 1, end));
        _failAt(k, 4, WordingIssueCode.quotedValue, listOpen, end, {
          'found': text.substring(listOpen, end).trim(),
          'fix': '$opText in ($inner)',
        });
        return;
      }
      // The quoted words, to their closing quote: a value can hold "and".
      var close = k + 1;
      while (close < text.length && !quotes.contains(text[close])) {
        close++;
      }
      final end = close < text.length ? close + 1 : text.length;
      _failAt(k, 4, WordingIssueCode.quotedValue, k, end, {
        'found': text.substring(k, end),
        'fix': '$opText ${unquote(text.substring(k, end))}',
      });
      return;
    }
    if (_isComparisonOrList(k)) return;
    final found = _runAt(k);
    final suggestion = _suggest(found, [
      for (final v in info.values) ...[v.word, ...v.alsoWords],
    ]);
    _failAt(k, 2, WordingIssueCode.unknownValue, k, k + found.length, {
      'found': found,
      'name': info.name,
      'suggestion': ?suggestion,
      'values': _valueList(info),
    });
  }

  String _valueList(WordingName info) => switch (info.kind) {
    WordingNameKind.choices => _values(info),
    WordingNameKind.number => _numberRange(info),
    _ => '',
  };

  String _numberRange(WordingName info) {
    final (min, max) = _rangeOf(info);
    return '$min–$max';
  }

  String _exampleValue(WordingName info) => switch (info.kind) {
    WordingNameKind.choices when info.values.isNotEmpty =>
      info.values.first.word,
    WordingNameKind.number => _exampleNumber(info),
    _ => '…',
  };

  /// Every value of [info] written at [at], with where each ends: more than
  /// one when one value's words begin another's ("next" and "next
  /// neighbors"). Null when none is.
  List<({Object value, int end})>? _valueAt(WordingName info, int at) {
    final found = <({Object value, int end})>[];
    final seen = <String>{};
    for (final v in info.values) {
      for (final word in [v.word, ...v.alsoWords]) {
        final end = _matchWords(at, word);
        if (end != null && seen.add('${v.value}@$end')) {
          found.add((value: v.value, end: end));
        }
      }
    }
    return found.isEmpty ? null : found;
  }

  /// The list of values from the `(` at [open], in a test of [info] whose
  /// `is` clause starts at [k].
  List<_Reading> _list(
    WordingName info,
    bool negated,
    int nameStart,
    int k,
    int open,
  ) {
    if (info.kind == WordingNameKind.flag) {
      _flagCompare(info, k);
      return const [];
    }
    if (info.kind == WordingNameKind.text ||
        info.kind == WordingNameKind.slot) {
      _failAt(k, 3, WordingIssueCode.presenceOnly, nameStart, k, {
        'name': info.name,
      });
      return const [];
    }
    final first = _skipSpace(open + 1);
    if (first < text.length && text[first] == ')') {
      _failAt(first, 2, WordingIssueCode.emptyList, open, first + 1, {
        'example': '${info.name} is in (${_exampleValue(info)})',
      });
      return const [];
    }
    final results = <_Reading>[];
    final frontier = <({List<Object> values, int at})>[(values: [], at: first)];
    // As in a chain ([_condition]): at most two lists reach each place.
    final seen = <String>{};
    final atPlace = <int, int>{};
    while (frontier.isNotEmpty) {
      final state = frontier.removeLast();
      final valueAt = _skipSpace(state.at);
      final ends = <({Object value, int end})>[];
      // A value is looked for first: its words may begin with "then" or
      // "and", or hold a comma.
      final words = info.kind == WordingNameKind.choices
          ? _valueAt(info, valueAt)
          : null;
      if (words == null &&
          (valueAt >= text.length ||
              text[valueAt] == ')' ||
              text[valueAt] == ']' ||
              _structuralWords.any((w) => _keyword(valueAt, w) != null))) {
        _failAt(
          valueAt,
          2,
          WordingIssueCode.expectedValue,
          nameStart,
          valueAt,
          {
            'before': text.substring(nameStart, valueAt).trim(),
            'name': info.name,
            'example': _exampleValue(info),
            'values': _valueList(info),
          },
        );
        continue;
      }
      if (info.kind == WordingNameKind.number) {
        final number = _numberAt(info, valueAt, 'is in');
        if (number != null) ends.add(number);
      } else {
        final values = words;
        if (values == null) {
          _unknownValue(
            info,
            valueAt,
            text.substring(nameStart, k).trim(),
            listOpen: open,
          );
        } else {
          ends.addAll(values);
        }
      }
      for (final value in ends) {
        final values = [...state.values, value.value];
        final next = _skipSpace(value.end);
        if (next < text.length && text[next] == ',') {
          final key = '${next + 1}|${values.join('|')}';
          final count = atPlace.update(
            next + 1,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
          if (seen.add(key) && count <= 2) {
            frontier.add((values: values, at: next + 1));
          }
          continue;
        }
        if (next < text.length && text[next] == ')') {
          // A list of one is that one value: `is in (x)` and `is x` are
          // stored alike, so writing either keeps what is stored.
          final op = values.length == 1
              ? (negated ? WordingTestOp.notEquals : WordingTestOp.equals)
              : (negated ? WordingTestOp.notInList : WordingTestOp.inList);
          results.add((
            condition: WordingTest(info.name, op, values),
            end: next + 1,
          ));
          continue;
        }
        if (next >= text.length ||
            text[next] == ']' ||
            _keyword(next, 'then') != null) {
          _failAt(next, 2, WordingIssueCode.unclosedParen, open, open + 1, {
            'context': _context(open),
            'before': text.substring(open, value.end).trim(),
          });
          continue;
        }
        final found = _wordAt(next);
        _failAt(
          next,
          1,
          WordingIssueCode.expectedListSeparator,
          next,
          next + found.length,
          {'found': found, 'before': text.substring(open, value.end).trim()},
        );
      }
    }
    return results;
  }

  /// The number of [info] written at [at] after [op], or null with why not.
  ({Object value, int end})? _numberAt(WordingName info, int at, String op) {
    for (final word in info.values) {
      for (final w in [word.word, ...word.alsoWords]) {
        final end = _matchWords(at, w);
        if (end != null) return (value: word.value, end: end);
      }
    }
    final match = _number.matchAsPrefix(text, at);
    if (match == null || !_boundaryAfter(match.end)) {
      final found = _runAt(at);
      _failAt(at, 2, WordingIssueCode.expectedNumber, at, at + found.length, {
        'op': op,
        'found': found,
        'example': _exampleNumber(info),
        'name': info.name,
      });
      return null;
    }
    // A decimal comma ("1,5"), outside a list where a comma separates.
    if (op != 'is in' &&
        match.end + 1 < text.length &&
        text[match.end] == ',' &&
        _isDigit(text[match.end + 1])) {
      var end = match.end + 1;
      while (end < text.length && _isDigit(text[end])) {
        end++;
      }
      final found = text.substring(at, end);
      _failAt(at, 4, WordingIssueCode.expectedNumber, at, end, {
        'op': op,
        'found': found,
        'example': found.replaceFirst(',', '.'),
        'name': info.name,
      });
      return null;
    }
    num value;
    if (match[3] != null) {
      value = _fractionGlyphs[match[3]!]!;
    } else {
      value = num.parse(match[1]!);
      if (match[2] != null) {
        if (match[1]!.contains('.')) {
          _failAt(at, 2, WordingIssueCode.expectedNumber, at, match.end, {
            'op': op,
            'found': match[0]!,
            'example': _exampleNumber(info),
            'name': info.name,
          });
          return null;
        }
        value += _fractionGlyphs[match[2]!]!;
      }
    }
    final found = match[0]!;
    final kind = info.spec!.kind;
    if (kind != ParamKind.rotation && value != value.roundToDouble()) {
      _failAt(at, 4, WordingIssueCode.numberNotWhole, at, match.end, {
        'name': info.name,
        'found': found,
      });
      return null;
    }
    if (kind == ParamKind.rotation && (value * 4) % 1 != 0) {
      _failAt(at, 4, WordingIssueCode.numberNotQuarter, at, match.end, {
        'name': info.name,
        'found': found,
      });
      return null;
    }
    final (min, max) = _rangeOf(info);
    if (value < min || value > max) {
      _failAt(at, 4, WordingIssueCode.numberOutOfRange, at, match.end, {
        'name': info.name,
        'found': found,
        'min': _storedNumber(min),
        'max': _storedNumber(max),
      });
      return null;
    }
    if (kind != ParamKind.rotation) value = value.toInt();
    return (value: value, end: match.end);
  }

  (num, num) _rangeOf(WordingName info) => switch (info.spec?.kind) {
    ParamKind.rotation => (0.25, 2.5),
    ParamKind.places => (1, 10),
    _ => (0, 64),
  };

  /// Warns where `is empty` tests a name one of whose values is the word
  /// "empty": the test means no value, not that one.
  void _warnEmptyLabel(WordingCondition condition, int start, int end) {
    for (final test in _tests(condition)) {
      if (test.op != WordingTestOp.empty && test.op != WordingTestOp.notEmpty) {
        continue;
      }
      final info = vocabulary[test.name];
      final hasEmptyValue =
          info?.values.any(
            (v) => [
              v.word,
              ...v.alsoWords,
            ].any((w) => w.trim().toLowerCase() == 'empty'),
          ) ??
          false;
      if (hasEmptyValue) {
        warnings.add(
          WordingIssue(WordingIssueCode.emptyMeansNoValue, start, end, {
            'name': info!.name,
            'fix':
                '${info.name} is ${test.op == WordingTestOp.notEmpty ? 'not ' : ''}in (empty)',
          }),
        );
      }
    }
  }

  Iterable<WordingTest> _tests(WordingCondition condition) sync* {
    switch (condition) {
      case WordingTest():
        yield condition;
      case WordingNot(:final inner):
        yield* _tests(inner);
      case WordingAll(:final parts) || WordingAny(:final parts):
        for (final part in parts) {
          yield* _tests(part);
        }
    }
  }
}

const Map<String, num> _fractionGlyphs = {'¼': 0.25, '½': 0.5, '¾': 0.75};

/// The closest of [candidates] to [found], or null when none is close: the
/// "Did you mean …?" of a message.
String? _suggest(String found, Iterable<String> candidates) {
  final target = found.toLowerCase().trim();
  if (target.isEmpty) return null;
  String? best;
  var bestDistance = 1 << 30;
  for (final candidate in candidates) {
    final c = candidate.toLowerCase();
    if (c == target) continue;
    final distance = _editDistance(target, c);
    final limit = target.length <= 4 ? 1 : (target.length <= 8 ? 2 : 3);
    final prefix = c.startsWith(target) || target.startsWith(c);
    if ((distance <= limit || (prefix && target.length >= 3)) &&
        distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

/// The edits between [a] and [b], counting two swapped neighbours ("hnad"
/// for "hand") as one.
int _editDistance(String a, String b) {
  final d = [
    for (var x = 0; x <= a.length; x++)
      [for (var y = 0; y <= b.length; y++) x == 0 ? y : (y == 0 ? x : 0)],
  ];
  for (var x = 1; x <= a.length; x++) {
    for (var y = 1; y <= b.length; y++) {
      final cost = a[x - 1] == b[y - 1] ? 0 : 1;
      var best = d[x - 1][y] + 1;
      if (d[x][y - 1] + 1 < best) best = d[x][y - 1] + 1;
      if (d[x - 1][y - 1] + cost < best) best = d[x - 1][y - 1] + cost;
      if (x > 1 &&
          y > 1 &&
          a[x - 1] == b[y - 2] &&
          a[x - 2] == b[y - 1] &&
          d[x - 2][y - 2] + 1 < best) {
        best = d[x - 2][y - 2] + 1;
      }
      d[x][y] = best;
    }
  }
  return d[a.length][b.length];
}
