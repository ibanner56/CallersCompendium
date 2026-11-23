/// The failure report (`lib/src/io/failure_report.dart`): diagnostics the
/// harness writes with `--report`. None of it changes an outcome, so these
/// tests pin what the report *says* about a failure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart' as core;
import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// The Caller's Box #14948 fixture the integration test also reads. It
/// compiles as published, with its progression on the last figure.
Map<String, Object?> _fixture() =>
    jsonDecode(
          File(
            'test/io/callersbox/once_more_with_feeling.json',
          ).readAsStringSync().replaceFirst('﻿', ''),
        )
        as Map<String, Object?>;

Future<core.StructuredDraft> _draft(Map<String, Object?> record) async {
  final adapter = core.CallersBoxAdapter();
  final discovered = await adapter.discover(
    core.ImportRequest(payload: jsonEncode(record)),
  );
  return adapter.parse(await adapter.fetch(discovered.single));
}

/// [draft]'s bridge with the progression assumed on figure [k] instead.
BridgedDance _flaggedAt(core.StructuredDraft draft, int k) =>
    withProgressionAt(bridgeCoreDance(draft.dance), k);

/// A mismatch verdict for [draft] with the progression assumed on figure 2.
DanceRun _mismatchRun(core.StructuredDraft draft) => DanceRun(
  title: draft.dance.title,
  outcome: DanceOutcome.mismatch,
  sourceId: '14948',
  label: 't',
  assumedProgressionAt: 1,
);

DanceRun _run(String detail) => DanceRun(
  title: 't',
  outcome: DanceOutcome.figureRefused,
  sourceId: '1',
  label: 't',
  detail: detail,
);

void main() {
  group('failureSignature', () {
    test('groups the same cause across dancers, figures and counts', () {
      final a = failureSignature(
        _run(
          'figure 3 (swing) whoMismatch: L-B and R-A are in swing position '
          'in column 0 but are not ones',
        ),
      );
      final b = failureSignature(
        _run(
          'figure 11 (swing) whoMismatch: R1-D and L2-C are in swing '
          'position in column 4 but are not ones',
        ),
      );
      expect(a, b);
      expect(
        a,
        '(swing) whoMismatch: X and X are in swing position in column # '
        'but are not ones',
      );
    });

    test('keeps different causes apart', () {
      expect(
        failureSignature(
          _run('figure 3 (swing) whoMismatch: X but are not ones'),
        ),
        isNot(
          failureSignature(
            _run('figure 3 (swing) whoMismatch: X but are not partners'),
          ),
        ),
      );
    });

    test('strips the bare couple letters of a distance-set message', () {
      expect(
        failureSignature(
          _run(
            'figure 2 (swing) whoMismatch: swing names nextNeighbors, but B '
            'and C started 2 grouping(s) apart',
          ),
        ),
        '(swing) whoMismatch: swing names nextNeighbors, but X and X '
        'started # grouping(s) apart',
      );
    });
  });

  group('classifyMismatch', () {
    late Dance dance;
    late Formation input;

    setUpAll(() async {
      final bridged = bridgeCoreDance((await _draft(_fixture())).dance);
      dance = (parseDance(bridged.record) as Ok<Dance, DanceParseError>).value;
      input = dance.instantiate();
    });

    Mismatch landing(Formation actual) =>
        Mismatch(actual: actual, expected: dance.success.expected(input));

    test('a set that ends where it started did not progress', () {
      expect(
        classifyMismatch(dance, landing(input)),
        MismatchClass.noNetProgression,
      );
    });

    test('a set two progressions on progressed once too many', () {
      expect(
        classifyMismatch(
          dance,
          landing(const ProgressionCriterion(count: 2).expected(input)),
        ),
        MismatchClass.oneProgressionTooMany,
      );
    });

    test('a double progression that progressed once is one short', () {
      final double = Dance(
        formation: dance.formation,
        success: const ProgressionCriterion(count: 2),
        figures: dance.figures,
      );
      final start = double.instantiate();
      expect(
        classifyMismatch(
          double,
          Mismatch(
            actual: const ProgressionCriterion().expected(start),
            expected: double.success.expected(start),
          ),
        ),
        MismatchClass.oneProgressionShort,
      );
    });

    test('two dancers in each other\'s places is elsewhere', () {
      final expected = dance.success.expected(input);
      final [a, b, ...] = expected.dancers.keys.toList();
      final swapped = expected.withUpdates({
        a: expected.stateOf(a).copyWith(position: expected.stateOf(b).position),
        b: expected.stateOf(b).copyWith(position: expected.stateOf(a).position),
      });
      expect(
        classifyMismatch(dance, landing(swapped)),
        MismatchClass.elsewhere,
      );
    });

    test('right places with the wrong numbers is numbersOnly', () {
      final expected = dance.success.expected(input);
      final flipped = expected.withUpdates({
        for (final entry in expected.dancers.entries)
          entry.key: entry.value.copyWith(
            number: entry.value.number == CoupleNumber.one
                ? CoupleNumber.two
                : CoupleNumber.one,
          ),
      });
      expect(
        classifyMismatch(dance, landing(flipped)),
        MismatchClass.numbersOnly,
      );
    });
  });

  group('diagnoseFailure', () {
    test('a misplaced progression is traced, classified and hinted', () async {
      final draft = await _draft(_fixture());
      final bridged = _flaggedAt(draft, 1);
      final run = _mismatchRun(draft);
      final diagnosis = diagnoseFailure(draft, run, bridged: bridged);
      final last = diagnosis.figures.length - 1;

      // Moved off figure 2, the progression compiles again on the last
      // figure, where the published dance has it.
      expect(diagnosis.placementHint, contains(last));

      // Every figure ran: the start plus one step each.
      expect(diagnosis.trace, hasLength(diagnosis.figures.length + 1));
      expect(diagnosis.trace.first.index, isNull);
      expect(diagnosis.trace.last.index, last);
      expect(diagnosis.failedAt, isNull);

      expect(diagnosis.mismatchClass, isNotNull);
      expect(diagnosis.signature, 'mismatch: ${diagnosis.mismatchClass!.name}');
      expect(diagnosis.expected, isNot(diagnosis.actual));
      expect(diagnosis.offDancers, isNotEmpty);

      // The source lines come through exactly as written.
      expect(diagnosis.phrases.map((p) => p.$1), ['A1', 'A2', 'B1', 'B2']);
      expect(diagnosis.phrases.first.$2.first, '(4) Neighbor balance (RH)');
    });

    test('a refusal is traced up to the refusing figure', () async {
      // Rotated so it opens with a partner swing from the improper start,
      // which refuses at the first figure.
      final record = _fixture();
      final phrases = (record['phrases']! as List).toList();
      record['phrases'] = [...phrases.skip(1), phrases.first];
      final diagnosed = await diagnoseCallersBoxPayload(jsonEncode(record));
      final (run, diagnosis) = diagnosed.single;
      expect(run.outcome, DanceOutcome.figureRefused);
      expect(diagnosis!.failedAt, 0);
      expect(diagnosis.trace, hasLength(1));
      expect(diagnosis.signature, startsWith('(swing) whoMismatch: X and X'));
    });

    test('the report never changes the verdict', () async {
      final record = _fixture();
      final phrases = (record['phrases']! as List).toList();
      record['phrases'] = [...phrases.skip(1), phrases.first];
      final plain = await runCallersBoxPayload(jsonEncode(record));
      final diagnosed = await diagnoseCallersBoxPayload(jsonEncode(record));
      expect(diagnosed.map((r) => r.$1.outcome), plain.map((r) => r.outcome));
      expect(diagnosed.map((r) => r.$1.detail), plain.map((r) => r.detail));
    });

    test('a dance that compiles gets no diagnosis', () async {
      final diagnosed = await diagnoseCallersBoxPayload(jsonEncode(_fixture()));
      expect(diagnosed.single.$1.outcome, DanceOutcome.compiled);
      expect(diagnosed.single.$2, isNull);
    });
  });

  test('a phrase with no figure list is skipped, as the adapter skips it', () {
    final record = _fixture();
    record['phrases'] = [
      ...(record['phrases']! as List),
      {'name': 'X', 'figures': 'not a list'},
    ];
    expect(sourcePhrases(jsonEncode(record)).map((p) => p.$1), [
      'A1',
      'A2',
      'B1',
      'B2',
    ]);
  });

  test('the summary groups by cause and counts the focus set', () {
    FailureDiagnosis refusal(String id, String detail) => FailureDiagnosis(
      run: DanceRun(
        title: id,
        outcome: DanceOutcome.figureRefused,
        sourceId: id,
        label: id,
        detail: detail,
        assumedProgressionAt: 3,
      ),
      signature: failureSignature(_run(detail)),
      figures: const ['a', 'b', 'c', 'd'],
      placementHint: id == '1' ? const [1, 2] : const [],
    );
    final summary = summarizeFailures(
      [
        refusal('1', 'figure 2 (swing) whoMismatch: L-A and R-B are not ones'),
        refusal('2', 'figure 4 (swing) whoMismatch: L-C and R-D are not ones'),
        refusal('3', 'figure 1 (hey) whoMismatch: X is elsewhere'),
      ],
      coreIds: {'2'},
    );
    expect(
      summary,
      contains(
        '| 2 | 1 | 1 | (swing) whoMismatch: X and X are not ones | 1, 2 |',
      ),
    );
    expect(
      summary,
      contains('| 1 | 0 | 0 | (hey) whoMismatch: X is elsewhere | 3 |'),
    );
    expect(summary, contains('1 of 3 in-scope failures that parsed'));
    expect(summary, contains('- 1 on a middle figure'));
  });

  test('report.js is one global holding valid JSON', () async {
    final draft = await _draft(_fixture());
    final diagnosis = diagnoseFailure(
      draft,
      _mismatchRun(draft),
      bridged: _flaggedAt(draft, 1),
    );
    final script = failureReportScript(
      [diagnosis],
      coreIds: {'14948'},
      headline: 'h',
    );
    const prefix = 'window.RUBRIC_REPORT = ';
    expect(script, startsWith(prefix));
    final data =
        jsonDecode(
              script
                  .substring(prefix.length)
                  .trim()
                  .replaceFirst(RegExp(r';$'), ''),
            )
            as Map<String, Object?>;
    final dance = (data['dances']! as List).single as Map<String, Object?>;
    expect(dance['id'], '14948');
    expect(dance['core'], isTrue);
  });
}
