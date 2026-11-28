// Shared parsing for the source-scan tests: tests that read app/lib as text
// to hold a convention no type or lint can (a style on every destructive
// confirm button, a token for every radius). Each scan walks delimiters
// rather than matching a window of lines, so a call written across lines, or
// with its arguments in another order, is read the same as one written on a
// single line.
import 'dart:io';

/// [source] with every comment and the text of every string literal blanked
/// to spaces. Newlines are kept and the length is unchanged, so an offset in
/// the result is the same offset in [source], and a `(`, a `//` or a call
/// named inside a string or a comment is not mistaken for code.
///
/// Handles `//` and nested `/* */` comments, single, double and triple
/// quotes, raw strings (`r'...'`, where `\` is not an escape), and
/// interpolation: the code inside `${...}` is kept, as it runs.
String codeOnly(String source) {
  final out = List<String>.of(source.split(''));
  // The two walkers call each other (a string holds `${code}`, code holds
  // strings), so one is declared ahead of its body.
  late final int Function(int start, {String? closer}) code;
  void blank(int from, int to) {
    for (var k = from; k < to && k < out.length; k++) {
      if (out[k] != '\n') out[k] = ' ';
    }
  }

  // Skips a string literal whose opening quote starts at [start]; returns the
  // offset just past it. Interpolated code is left as code.
  int string(int start, {required bool raw}) {
    final c = source[start];
    final triple = source.startsWith(c * 3, start);
    final quote = triple ? c * 3 : c;
    var j = start + quote.length;
    var textFrom = j;
    while (j < source.length && !source.startsWith(quote, j)) {
      if (!triple && source[j] == '\n') break; // unterminated: stop at the line
      if (!raw && source[j] == r'\') {
        j += 2;
        continue;
      }
      if (!raw && source.startsWith(r'${', j)) {
        blank(textFrom, j);
        j = code(j + 2, closer: '}');
        textFrom = j;
        continue;
      }
      j++;
    }
    blank(textFrom, j);
    return j + quote.length;
  }

  // Walks code from [start] until an unmatched [closer] (or the end); returns
  // the offset just past it.
  code = (int start, {String? closer}) {
    var depth = 0;
    var j = start;
    while (j < source.length) {
      final c = source[j];
      if (source.startsWith('//', j)) {
        final end = source.indexOf('\n', j);
        blank(j, end < 0 ? source.length : end);
        j = end < 0 ? source.length : end;
        continue;
      }
      if (source.startsWith('/*', j)) {
        var nest = 0;
        var k = j;
        while (k < source.length) {
          if (source.startsWith('/*', k)) {
            nest++;
            k += 2;
          } else if (source.startsWith('*/', k)) {
            nest--;
            k += 2;
            if (nest == 0) break;
          } else {
            k++;
          }
        }
        blank(j, k);
        j = k;
        continue;
      }
      if (c == "'" || c == '"') {
        final raw =
            j > 0 &&
            source[j - 1] == 'r' &&
            (j < 2 || !RegExp(r'\w').hasMatch(source[j - 2]));
        j = string(j, raw: raw);
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        if (depth == 0 && closer == '}') return j + 1;
        depth--;
      }
      j++;
    }
    return j;
  };

  code(0);
  return out.join();
}

/// The offset of the delimiter that closes the one at [open] in [code] (which
/// should come from [codeOnly], so delimiters in strings and comments are
/// already blank). Throws when [open] is never closed.
int closingDelimiter(String code, int open) {
  const pairs = {'(': ')', '[': ']', '{': '}'};
  final stack = <String>[];
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (pairs.containsKey(c)) {
      stack.add(pairs[c]!);
    } else if (c == ')' || c == ']' || c == '}') {
      if (stack.isEmpty || stack.removeLast() != c) {
        throw StateError('mismatched $c at $i');
      }
      if (stack.isEmpty) return i;
    }
  }
  throw StateError('unbalanced from offset $open');
}

/// One argument of a call: its name (null for a positional one) and its
/// source text, trimmed, with its offsets in the file.
typedef CallArg = ({String? name, String text, int start, int end});

/// The arguments of the call whose `(` is at [open] in [source], at the
/// call's own depth only, so a nested call's arguments are not its own.
/// [code] is [codeOnly] of [source] and is computed when not given. The text
/// of each argument is from [source] (string literals intact).
List<CallArg> callArgs(String source, int open, {String? code}) {
  code ??= codeOnly(source);
  final close = closingDelimiter(code, open);
  final args = <CallArg>[];
  const openers = '([{';
  const closers = ')]}';
  var depth = 0;
  var from = open + 1;
  void finish(int to) {
    final raw = code!.substring(from, to);
    if (raw.trim().isEmpty) return;
    final lead = raw.length - raw.trimLeft().length;
    final start = from + lead;
    final end = from + raw.trimRight().length;
    final named = RegExp(
      r'^(\w+)\s*:(?!:)\s*',
    ).firstMatch(code.substring(start, end));
    if (named != null) {
      args.add((
        name: named.group(1),
        text: source.substring(start + named.end, end),
        start: start + named.end,
        end: end,
      ));
    } else {
      args.add((
        name: null,
        text: source.substring(start, end),
        start: start,
        end: end,
      ));
    }
  }

  for (var i = open + 1; i < close; i++) {
    final c = code[i];
    if (openers.contains(c)) {
      depth++;
    } else if (closers.contains(c)) {
      depth--;
    } else if (c == '<' && depth == 0) {
      // A type argument's `,` (`<String, int>{}`, `f<A, B>()`) is not an
      // argument separator: skip a `<...>` of type-like text that a literal,
      // a call or a member access follows.
      final m = RegExp(r'<[\w\s,<>?.]*>(?=[(\[{.])').matchAsPrefix(code, i);
      if (m != null) i = m.end - 1;
    } else if (c == ',' && depth == 0) {
      finish(i);
      from = i + 1;
    }
  }
  finish(close);
  return args;
}

/// The named arguments of the call at [open], by name. See [callArgs].
Map<String, String> namedArgs(String source, int open, {String? code}) => {
  for (final a in callArgs(source, open, code: code))
    if (a.name != null) a.name!: a.text,
};

/// The 1-based line of [offset] in [source].
int lineAt(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// Every `.dart` file under [root] (relative to the app directory the tests
/// run in), with `/` separators, sorted so a failure lists files in a stable
/// order.
List<(String, String)> dartSources(String root) {
  final files = [
    for (final e in Directory(root).listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart'))
        (e.path.replaceAll(r'\', '/'), e.readAsStringSync()),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return files;
}
