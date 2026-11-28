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
//
// The hosts are discovered, not listed: every file under lib/ that makes one
// of those calls is checked, so a new host is checked from its first call.
import 'package:flutter_test/flutter_test.dart';

import '../support/source_scan.dart';

/// Hosts that take today from a `SearchClock` of their own making
/// (`const SearchClock().today()`) instead of the one they were given, by
/// path, with how many such calls each holds and why. Such a day is the
/// caller's calendar day, so it is right in use, but a test cannot pin it to a
/// fixed instant and zone. The count is exact, so a new such call in a listed
/// file fails as it would anywhere else, and one fewer means the entry needs
/// updating.
const _ownClockHosts = <String, (int, String)>{
  'lib/src/screens/perform_swap_sheet.dart': (
    1,
    'reads event-rule contexts with today from const SearchClock(); found '
        'when this scan began discovering hosts, not yet given an injected '
        'clock',
  ),
  'lib/src/screens/program_editor_screen.dart': (
    1,
    'reads event-rule contexts with today from const SearchClock(); found '
        'when this scan began discovering hosts, not yet given an injected '
        'clock',
  ),
};

/// A local or field holding a `SearchClock` the host made itself
/// (`final clock = SearchClock();`, `final SearchClock _clock = const
/// SearchClock();`), which `clock.today()` would then read as if it were the
/// one the host was given. A parameter's default (`this.clock = const
/// SearchClock()`) is not one: a test passes its own.
final _ownClockField = RegExp(
  r'\b(?:final|var|late|static)\s+(?:SearchClock\s+)?_?clock\s*=\s*'
  r'(?:const\s+)?SearchClock\s*\(',
);

final _todayCall = RegExp(
  r'\b(buildCollectionFilter|readSavedSearchContext|SavedSearchSpec\s*\.\s*fromPanelState)\s*\(',
);

/// The calls in [code] (from [codeOnly]) that take a day: each
/// `buildCollectionFilter(`, `readSavedSearchContext(` and
/// `SavedSearchSpec.fromPanelState(` that is a call, not the declaration of
/// the function (which a body or `=>` follows).
List<RegExpMatch> todayCalls(String code) => [
  for (final m in _todayCall.allMatches(code))
    if (!RegExp(
      r'^\s*(?:async\b|\{|=>)',
    ).hasMatch(code.substring(closingDelimiter(code, m.end - 1) + 1)))
      m,
];

/// What is wrong with [source]'s "today", one line each; empty when nothing.
List<String> todayProblems(String source) {
  final code = codeOnly(source);
  final problems = <String>[];
  final now = RegExp(r'DateTime\s*\.\s*now\b');

  // Every call that counts a window back from a day takes today from the
  // host's clock: `today: _today()`, or `today: clock.today()` from a clock
  // the host was given.
  for (final call in todayCalls(code)) {
    final args = code.substring(
      call.end - 1,
      closingDelimiter(code, call.end - 1) + 1,
    );
    final name = call.group(1)!.replaceAll(RegExp(r'\s'), '');
    final today = namedArgs(source, call.end - 1, code: code)['today'];
    final compact = today?.replaceAll(RegExp(r'\s'), '');
    if (compact == 'constSearchClock().today()' ||
        compact == 'SearchClock().today()') {
      problems.add('$name(...) takes today from a new SearchClock');
    } else if (compact == null ||
        !RegExp(
          r'^(?:_today\(\)|(?:widget\.)?_?clock\.today\(\))$',
        ).hasMatch(compact)) {
      problems.add('$name(...) does not pass today from its clock');
    }
    if (now.hasMatch(args)) problems.add('$name(...) reads DateTime.now');
  }

  if (_ownClockField.hasMatch(code)) {
    problems.add('keeps a SearchClock of its own making as its clock');
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
      body = code.substring(def.end, closingDelimiter(code, def.end) + 1);
    }
    if (now.hasMatch(body)) problems.add('_today() reads DateTime.now');
    // The day comes from the host's SearchClock: its own `today()` (which is
    // `calendarDayAt` of one reading), or a reading turned into a day with
    // `calendarDayAt`. A subclass that overrides `today()` (a test clock) is
    // honoured only by the first form.
    final fromToday = RegExp(r'\bclock\s*\.\s*today\s*\(').hasMatch(body);
    final fromReading =
        RegExp(r'\bclock\s*\.\s*read\s*\(').hasMatch(body) &&
        body.contains('calendarDayAt');
    if (!fromToday && !fromReading) {
      problems.add('_today() does not take its day from its clock');
    }
  }
  return problems;
}

void main() {
  group('the checker itself', () {
    test('a host that takes its day from clock.today() is clean, so a test '
        'clock that overrides today() is honoured', () {
      const source = '''
DateTime _today() => widget.clock.today();
void run() {
  buildCollectionFilter(ftsText: f(x), today: _today());
}
''';
      expect(todayProblems(source), isEmpty);
    });

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
          'buildCollectionFilter(...) does not pass today from its clock',
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
        'buildCollectionFilter(...) does not pass today from its clock',
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
          '_today() does not take its day from its clock',
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
    test('a host given a clock, rather than defining _today(), is clean', () {
      const source = '''
Future<void> f(SearchClock clock) => readSavedSearchContext(
  repos,
  today: clock.today(),
  taxonomy: t,
);
''';
      expect(todayProblems(source), isEmpty);
    });

    test('positive control: a new SearchClock in place of the host\'s is '
        'found', () {
      const source = '''
void run() {
  readSavedSearchContext(repos, today: const SearchClock().today());
}
''';
      expect(todayProblems(source), [
        'readSavedSearchContext(...) takes today from a new SearchClock',
      ]);
    });

    test('positive control: a clock the host made itself is found, a '
        "parameter's default is not", () {
      const own = '''
final clock = SearchClock();
void run() {
  buildCollectionFilter(ftsText: f(x), today: clock.today());
}
''';
      expect(todayProblems(own), [
        'keeps a SearchClock of its own making as its clock',
      ]);
      const field = '''
final SearchClock _clock = const SearchClock();
''';
      expect(todayProblems(field), [
        'keeps a SearchClock of its own making as its clock',
      ]);
      const given = '''
class Host {
  const Host({this.clock = const SearchClock()});
  final SearchClock clock;
}
Future<void> f({SearchClock clock = const SearchClock()}) =>
    readSavedSearchContext(repos, today: clock.today());
''';
      expect(todayProblems(given), isEmpty);
    });

    test('the declaration of a function is not a call to it', () {
      const source = '''
Future<SavedSearchContext> readSavedSearchContext(
  CompendiumRepositories repos, {
  required DateTime today,
}) async {
  return SavedSearchContext(today: today);
}
''';
      expect(todayCalls(codeOnly(source)), isEmpty);
      expect(todayProblems(source), isEmpty);
    });
  });

  final hosts = {
    for (final (path, source) in dartSources('lib'))
      if (todayCalls(codeOnly(source)).isNotEmpty) path: source,
  };

  test('the hosts are discovered', () {
    // Positive control: the hosts this test once listed by hand are found.
    expect(
      hosts.keys,
      containsAll([
        'lib/src/screens/dance_list_screen.dart',
        'lib/src/widgets/collection_picker.dart',
        'lib/src/widgets/saved_search_actions.dart',
      ]),
    );
  });

  for (final MapEntry(key: path, value: source) in hosts.entries) {
    test('$path takes today only from its SearchClock', () {
      final problems = todayProblems(source);
      bool ownClock(String p) =>
          p.endsWith('takes today from a new SearchClock');
      final allowed = _ownClockHosts[path]?.$1 ?? 0;
      if (allowed == 0) {
        expect(problems, isEmpty);
      } else {
        expect(problems.where((p) => !ownClock(p)), isEmpty);
        expect(
          problems.where(ownClock).length,
          allowed,
          reason: "update $path's _ownClockHosts count (or remove the entry)",
        );
      }
    });
  }

  test('every _ownClockHosts entry is a host', () {
    for (final path in _ownClockHosts.keys) {
      expect(hosts.keys, contains(path), reason: 'remove the stale entry');
    }
  });
}
