import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for the CC `InsertCall` → shorthand-candidate builder (issue #562):
/// [buildInsertCallShorthandCandidates] and [partitionInsertCallCandidates].
///
/// All fixtures use OWN generic contra phrasing (common calls like "neighbor
/// balance and swing") — never a transcription of CC's proprietary shipped
/// button set — and exercise the real free-text fan-out against [contraTaxonomy]
/// so the candidate figures are genuinely structured, matching production.
void main() {
  List<ShorthandSeedCandidate> build(List<CcInsertCall> buttons) =>
      buildInsertCallShorthandCandidates(buttons, taxonomy: contraTaxonomy);

  group('buildInsertCallShorthandCandidates — parsing', () {
    test(
      'a button whose text structures becomes a candidate (label→figure)',
      () {
        final candidates = build([
          CcInsertCall(
            label: 'B&S-N',
            text: 'neighbor balance and swing',
            beats: 16,
          ),
        ]);
        expect(candidates, hasLength(1));
        final c = candidates.single;
        expect(c.token, 'B&S-N');
        expect(c.figures, isNotEmpty);
        expect(c.figures.any((f) => f.isCustom), isFalse);
        expect(c.figures.first.move, 'swing');
        expect(c.hasAlt, isFalse);
      },
    );

    test('primary beats flow into the parsed expansion', () {
      final candidate = build([
        CcInsertCall(label: 'Sw-N', text: 'neighbor swing', beats: 8),
      ]).single;
      expect(candidate.figures.single.move, 'swing');
      expect(candidate.figures.single.params['beats'], 8);
    });

    test('a button that only parses to custom yields NO candidate', () {
      // Deliberately unstructurable gibberish → custom → dropped (no raw-text
      // shorthand is seeded in v1).
      final candidates = build([
        CcInsertCall(
          label: 'Zzz',
          text: 'qwxz not a real contra call zzzq',
          beats: 8,
        ),
      ]);
      expect(candidates, isEmpty);
    });

    test('a multi-figure button expands to multiple ordered figures', () {
      final candidate = build([
        CcInsertCall(
          label: 'Combo',
          text: 'circle left 3/4; neighbor swing',
          beats: 16,
        ),
      ]).single;
      expect(candidate.figures.length, 2);
      expect(candidate.figures[0].move, 'circle');
      expect(candidate.figures[1].move, 'swing');
    });
  });

  group('buildInsertCallShorthandCandidates — alt form', () {
    test('a distinct, parseable alt is attached for the same token', () {
      final candidate = build([
        CcInsertCall(
          label: 'Chain',
          text: 'ladies chain',
          beats: 8,
          altText: 'gents chain',
          altBeats: 8,
        ),
      ]).single;
      expect(candidate.token, 'Chain');
      expect(candidate.hasAlt, isTrue);
      expect(candidate.altFigures, isNotNull);
      expect(candidate.altFigures!.any((f) => f.isCustom), isFalse);
      // Both mappings share the one token — never two mappings for one label.
      expect(candidate.toPrimaryMapping().token, 'Chain');
      expect(candidate.toAltMapping().token, 'Chain');
    });

    test('an alt equal to the primary text is not attached', () {
      final candidate = build([
        CcInsertCall(
          label: 'Sw',
          text: 'neighbor swing',
          beats: 8,
          altText: '  neighbor swing  ',
          altBeats: 8,
        ),
      ]).single;
      expect(candidate.hasAlt, isFalse);
    });

    test('an alt that only parses to custom is dropped, primary kept', () {
      final candidate = build([
        CcInsertCall(
          label: 'Sw',
          text: 'neighbor swing',
          beats: 8,
          altText: 'qwxz nonsense zzzq',
          altBeats: 8,
        ),
      ]).single;
      expect(candidate.figures.single.move, 'swing');
      expect(candidate.hasAlt, isFalse);
    });

    test('toAltMapping throws when there is no alt', () {
      final candidate = build([
        CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
      ]).single;
      expect(candidate.hasAlt, isFalse);
      expect(candidate.toAltMapping, throwsStateError);
    });
  });

  group('buildInsertCallShorthandCandidates — bounds & dedupe', () {
    test('an empty label is skipped', () {
      expect(
        build([CcInsertCall(label: '   ', text: 'neighbor swing', beats: 8)]),
        isEmpty,
      );
    });

    test('a token longer than the max length is skipped', () {
      final tooLong = 'x' * (maxShorthandTokenLength + 1);
      expect(
        build([CcInsertCall(label: tooLong, text: 'neighbor swing', beats: 8)]),
        isEmpty,
      );
    });

    test('a token exactly at the max length is kept', () {
      final atLimit = 'x' * maxShorthandTokenLength;
      final candidates = build([
        CcInsertCall(label: atLimit, text: 'neighbor swing', beats: 8),
      ]);
      expect(candidates.single.token, atLimit);
    });

    test(
      'duplicate labels dedupe on the normalized token, keeping the first',
      () {
        final candidates = build([
          CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
          CcInsertCall(label: ' sw ', text: 'partner swing', beats: 16),
        ]);
        expect(candidates, hasLength(1));
        // First writer wins: neighbor/8, not partner/16.
        expect(candidates.single.figures.single.params['who'], 'neighbors');
        expect(candidates.single.figures.single.params['beats'], 8);
      },
    );

    test(
      'a non-seeding (custom) first button does not block a later real one',
      () {
        // The custom button yields no candidate, so it must not claim the token.
        final candidates = build([
          CcInsertCall(label: 'Sw', text: 'qwxz nonsense zzzq', beats: 8),
          CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
        ]);
        expect(candidates, hasLength(1));
        expect(candidates.single.figures.single.move, 'swing');
      },
    );
  });

  group('partitionInsertCallCandidates — conflicts', () {
    List<ShorthandSeedCandidate> sample() => build([
      CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
      CcInsertCall(label: 'Circle', text: 'circle left 3/4', beats: 8),
    ]);

    test('no existing tokens ⇒ everything is seedable', () {
      final partition = partitionInsertCallCandidates(sample(), <String>{});
      expect(partition.seedable, hasLength(2));
      expect(partition.conflicting, isEmpty);
    });

    test(
      'a matching normalized token is routed to conflicting (not seedable)',
      () {
        final partition = partitionInsertCallCandidates(sample(), {'sw'});
        expect(partition.conflicting.map((c) => c.token), ['Sw']);
        expect(partition.seedable.map((c) => c.token), ['Circle']);
      },
    );

    test('conflict detection is case-insensitive on the token', () {
      final partition = partitionInsertCallCandidates(sample(), {'circle'});
      expect(partition.conflicting.map((c) => c.token), ['Circle']);
    });
  });
}
