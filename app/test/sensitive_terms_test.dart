import 'package:compendium_app/src/diagnostics/sensitive_terms.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'package:compendium_core/testing.dart';

/// Repository-backed tests for [collectSensitiveTerms] (issue #458). These pin
/// down the security-critical contract for the *scrubbed* export: every promised
/// user-content source is collected, and — crucially — collection is
/// fail-closed so a read error can never silently leave content un-redacted.
void main() {
  test('collects every promised user-content source', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);

    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'cf1',
        key: 'commission',
        label: 'Commission Notes',
        type: CustomFieldType.text,
      ),
    );
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'cf2',
        key: 'tier',
        label: 'Skill Tier Label',
        type: CustomFieldType.choice,
        choices: const ['bespoke tier choice'],
      ),
    );

    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Chinquapin Reel',
        hook: 'a swingy delight',
        callingNotes: 'watch the timing on B2',
        tunes: const ['Whiskey Before Breakfast'],
        figures: [
          testFigure(
            move: customMove,
            params: const {'text': 'gypsy meltdown with Robin', 'beats': 8},
          ),
          Figure(move: 'swing', note: 'scoop them up gently'),
        ],
        customFields: [
          CustomFieldValue(fieldId: 'cf1', value: 'commissioned for Sam'),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Autumn Gathering 2025',
        notes: 'remember the raffle at the break',
        band: 'The Syncopaths',
        caller: 'Nils Fredland',
        venue: 'Guiding Star Grange',
        dancerLevel: 'welcoming beginners',
        slots: [
          ProgramSlot(
            id: 's1',
            position: 0,
            text: 'waltz to send them home',
            guestCaller: 'Mary Wesley',
          ),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    await repos.tags.upsert(Tag(id: 't1', name: 'Newcomer Friendly'));

    final terms = await collectSensitiveTerms(repos);

    for (final expected in const [
      // Dance free text.
      'Chinquapin Reel',
      'a swingy delight',
      'watch the timing on B2',
      'Whiskey Before Breakfast',
      'gypsy meltdown with Robin', // custom figure params['text']
      'scoop them up gently', // figure note
      'commissioned for Sam', // custom-field value
      // Custom-field definitions.
      'Commission Notes',
      'Skill Tier Label',
      'bespoke tier choice',
      // Program free text.
      'Autumn Gathering 2025',
      'remember the raffle at the break',
      'The Syncopaths',
      'Nils Fredland',
      'Guiding Star Grange',
      'welcoming beginners',
      'waltz to send them home', // slot text
      'Mary Wesley', // slot guest caller
      // Tag.
      'Newcomer Friendly',
    ]) {
      expect(terms, contains(expected), reason: 'missing source: $expected');
    }
  });

  test('is fail-closed: a source read error propagates', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    // Drop the first source table so its read throws a real SQLite error. The
    // gather MUST fail rather than return a partial set (which the export would
    // then treat as a complete "scrubbed" term list and leak the rest).
    await repos.db.customStatement('DROP TABLE dances');

    await expectLater(collectSensitiveTerms(repos), throwsA(anything));
  });
}
