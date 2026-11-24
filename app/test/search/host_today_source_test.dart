// "Today" for a search comes from the host's SearchClock, never from
// DateTime.now() (#2325, plan trap T19). A calling-history window ("Within 3
// months", or a saved search's "the last 12 months") is counted back from the
// caller's own calendar day. A host that takes it from `DateTime.now()`, or
// leaves `today:` out so `buildCollectionFilter` falls back to it, cannot be
// tested at a fixed instant and zone, and one that takes the UTC day is a day
// early for hours every night far from UTC.
//
// The scan is narrow on purpose: only the `today` computation (each host's
// `_today()`), every `buildCollectionFilter(...)` and
// `readSavedSearchContext(...)` call, and every
// `SavedSearchSpec.fromPanelState(...)` call. Timers and Undo stamps in the
// same files are not "today" and need no allow-list.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The hosts that build a Collection filter or save a search.
const _hosts = [
  'lib/src/screens/dance_list_screen.dart',
  'lib/src/widgets/collection_picker.dart',
  'lib/src/widgets/saved_search_menu.dart',
];

/// [source] with every comment and string literal blanked to spaces (same
/// length, so offsets still line up), so a `(` or `DateTime.now` inside one is
/// not code.
String _codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      while (i < source.length &&
          !(source[i] == '*' &&
              i + 1 < source.length &&
              source[i + 1] == '/')) {
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      out.write('  ');
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final triple =
          i + 2 < source.length && source[i + 1] == c && source[i + 2] == c;
      final quote = triple ? c * 3 : c;
      out.write(' ' * quote.length);
      i += quote.length;
      while (i < source.length && !source.startsWith(quote, i)) {
        if (source[i] == r'\') {
          out.write('  ');
          i += 2;
          continue;
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      out.write(' ' * quote.length);
      i += quote.length;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// The text from [open] (an opening delimiter) to its matching close, walking
/// the delimiters rather than a fixed window of lines.
String _balanced(String code, int open) {
  const pairs = {'(': ')', '{': '}', '[': ']'};
  final stack = <String>[];
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (pairs.containsKey(c)) {
      stack.add(pairs[c]!);
    } else if (stack.isNotEmpty && c == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) return code.substring(open, i + 1);
    }
  }
  throw StateError('unbalanced from offset $open');
}

/// What is wrong with [source]'s "today", one line each; empty when nothing.
List<String> todayProblems(String source) {
  final code = _codeOnly(source);
  final problems = <String>[];
  final now = RegExp(r'DateTime\s*\.\s*now\b');

  // Every call that counts a window back from a day takes `today: _today()`.
  for (final call in RegExp(
    r'\b(buildCollectionFilter|readSavedSearchContext|SavedSearchSpec\s*\.\s*fromPanelState)\s*\(',
  ).allMatches(code)) {
    final args = _balanced(code, call.end - 1);
    final name = call.group(1)!.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'\btoday\s*:\s*_today\s*\(\s*\)').hasMatch(args)) {
      problems.add('$name(...) does not pass today: _today()');
    }
    if (now.hasMatch(args)) problems.add('$name(...) reads DateTime.now');
  }

  // `_today()` reads the injected clock and nothing else.
  for (final def in RegExp(
    r'DateTime\s+_today\s*\(\s*\)\s*',
  ).allMatches(code)) {
    final rest = code.substring(def.end);
    final String body;
    if (rest.startsWith('=>')) {
      body = rest.substring(0, rest.indexOf(';') + 1);
    } else {
      body = _balanced(code, def.end);
    }
    if (now.hasMatch(body)) problems.add('_today() reads DateTime.now');
    if (!body.contains('widget.clock') || !body.contains('calendarDayAt')) {
      problems.add('_today() does not read widget.clock through calendarDayAt');
    }
  }
  return problems;
}

void main() {
  group('the checker itself', () {
    test('a host that passes today from its clock is clean', () {
      const source = '''
DateTime _today() {
  final reading = widget.clock.read();
  return calendarDayAt(reading.instantUtc, reading.offset);
}
void run() {
  // DateTime.now() in a comment is not code.
  final s = 'DateTime.now(';
  buildCollectionFilter(ftsText: f(x), today: _today());
  SavedSearchSpec.fromPanelState(state, today: _today(), text: codec);
  final undoAt = DateTime.now(); // not "today": no rule here
}
''';
      expect(todayProblems(source), isEmpty);
    });

    test('positive control: DateTime.now() in a filter call is found', () {
      const source = '''
void run() {
  buildCollectionFilter(ftsText: f(g(x)), today: DateTime.now());
}
''';
      expect(
        todayProblems(source),
        containsAll([
          'buildCollectionFilter(...) does not pass today: _today()',
          'buildCollectionFilter(...) reads DateTime.now',
        ]),
      );
    });

    test('positive control: a call with no today is found', () {
      const source = '''
void run() {
  buildCollectionFilter(
    ftsText: text,
    tracking: _tracking,
  );
}
''';
      expect(todayProblems(source), [
        'buildCollectionFilter(...) does not pass today: _today()',
      ]);
    });

    test('positive control: a _today() built on DateTime.now() is found', () {
      const source = '''
DateTime _today() {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day);
}
''';
      expect(
        todayProblems(source),
        containsAll([
          '_today() reads DateTime.now',
          '_today() does not read widget.clock through calendarDayAt',
        ]),
      );
    });

    test('positive control: saving a search as of DateTime.now() is found', () {
      const source = '''
void save() {
  SavedSearchSpec.fromPanelState(current(), today: DateTime.now());
}
''';
      expect(
        todayProblems(source),
        contains('SavedSearchSpec.fromPanelState(...) reads DateTime.now'),
      );
    });
  });

  for (final path in _hosts) {
    test('$path takes today only from its SearchClock', () {
      final source = File(path).readAsStringSync();
      final code = _codeOnly(source);
      // The guard must have something to guard: each host defines _today()
      // and makes at least one call that takes it.
      expect(
        RegExp(r'DateTime\s+_today\s*\(').hasMatch(code),
        isTrue,
        reason: '$path defines no _today()',
      );
      expect(
        RegExp(
          r'\b(buildCollectionFilter|readSavedSearchContext|SavedSearchSpec\s*\.\s*fromPanelState)\s*\(',
        ).hasMatch(code),
        isTrue,
        reason: '$path makes no call that takes today',
      );
      expect(todayProblems(source), isEmpty);
    });
  }
}
