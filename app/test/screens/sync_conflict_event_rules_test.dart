// A sync conflict on an event rule, or on the rules a program applies, reads
// in words (#2340): the quantifier and scope as the rule editor says them,
// the saved search by its name, and the applied rules by their names or
// sentences, never the stored values.
import 'package:compendium_app/src/screens/sync_conflict_details.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

SyncConflictGroup _group(
  SyncRecordKind kind,
  Map<String, Object?> local,
  Map<String, Object?> theirs,
) => SyncConflictGroup(
  kind: kind,
  recordId: 'x',
  localBody: local,
  candidates: syncConflictGroupFor(
    SyncConflictReconsideration(
      kind: kind,
      recordId: 'x',
      before: null,
      offered: [
        SyncRecordBlob(
          kind: kind,
          id: 'x',
          updatedAt: DateTime.utc(2026, 9, 30),
          deletedAt: null,
          existenceAt: DateTime.utc(2026, 9, 30),
          body: theirs,
        ),
      ],
      writtenWireHash: 'written',
      writtenAt: DateTime.utc(2026, 9, 30),
    ),
  ).candidates,
);

Future<void> _pump(
  WidgetTester tester,
  SyncConflictGroup group,
  SyncConflictLookups lookups,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SyncConflictComparison(group: group, lookups: lookups),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a rule shows its quantifier and scope in words and its saved '
      'search by name, or as not on this device', (tester) async {
    Map<String, Object?> rule(String q, String scope, String search) => {
      'id': 'x',
      'savedSearchId': search,
      'quantifier': q,
      'count': 1,
      'scope': scope,
      'position': 0,
    };
    await _pump(
      tester,
      _group(
        SyncRecordKind.eventRule,
        rule('atMost', 'wholeProgram', 's1'),
        rule('atLeast', 'neighbouring', 's-gone'),
      ),
      const SyncConflictLookups(savedSearches: {'s1': 'Becket'}),
    );
    for (final text in [
      'At most',
      'At least',
      'The whole program',
      'Any two neighboring dances',
      'Becket',
      'Not on this device',
    ]) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    for (final raw in ['atMost', 'atLeast', 'wholeProgram', 'neighbouring']) {
      expect(find.textContaining(raw), findsNothing, reason: raw);
    }
  });

  testWidgets('a value a newer build wrote is shown as it came', (
    tester,
  ) async {
    Map<String, Object?> rule(String q) => {
      'id': 'x',
      'savedSearchId': 's1',
      'quantifier': q,
      'count': 1,
      'scope': 'wholeProgram',
      'position': 0,
    };
    await _pump(
      tester,
      _group(SyncRecordKind.eventRule, rule('atMost'), rule('exactly')),
      const SyncConflictLookups(),
    );
    expect(find.textContaining('exactly'), findsOneWidget);
  });

  testWidgets("a program's applied rules are named, by name or sentence, and "
      'a rule not here is not on this device', (tester) async {
    Map<String, Object?> program(List<String> rules) => {
      'id': 'x',
      'title': 'Night',
      'status': 'draft',
      'notes': '',
      'hideAlternates': false,
      'slots': const <Object?>[],
      'eventRuleIds': rules,
      'createdAt': '2026-09-01T00:00:00.000Z',
    };
    await _pump(
      tester,
      _group(
        SyncRecordKind.program,
        program(['r1']),
        program(['r1', 'r2', 'r-gone']),
      ),
      SyncConflictLookups(
        savedSearches: const {'s1': 'Becket'},
        eventRules: {
          'r1': EventRule.of(
            id: 'r1',
            savedSearchId: 's1',
            quantifier: EventRuleQuantifier.none,
            scope: EventRuleScope.afterFirstBreak,
          ),
          'r2': EventRule.of(
            id: 'r2',
            savedSearchId: 's1',
            quantifier: EventRuleQuantifier.atMost,
            count: 1,
            scope: EventRuleScope.neighbouring,
            nickname: 'No two Beckets',
          ),
        },
      ),
    );
    expect(
      find.textContaining('No dance matching "Becket" after the first break'),
      findsWidgets,
    );
    expect(find.textContaining('No two Beckets'), findsOneWidget);
    expect(find.textContaining('Not on this device'), findsOneWidget);
    expect(find.textContaining('r-gone'), findsNothing);
  });
}
