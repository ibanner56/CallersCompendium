import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The "possible match" tier (#1907): titles written differently enough that
/// the fuzzy tier misses them (`A-1 Reel {variant}` against `A1 Reel (Imp
/// Var)`), offered to a user and never acted on by anything unattended.
void main() {
  group('dedupeCoreTitleKey', () {
    test("reduces the #1907 reporter's four titles to one key", () {
      // Caller's Box spells it `A-1 Reel`, the reporter's Caller's Companion
      // copy `A1 Reel`, and each has a variant suffixed in its own style.
      for (final title in [
        'A-1 Reel',
        'A1 Reel',
        'A-1 Reel {variant}',
        'A1 Reel (Imp Var)',
      ]) {
        expect(dedupeCoreTitleKey(title), 'a1reel', reason: title);
      }
    });

    test('drops a leading article only before a word', () {
      expect(dedupeCoreTitleKey('A Fine Romance'), 'fineromance');
      expect(dedupeCoreTitleKey('Fine Romance'), 'fineromance');
      expect(dedupeCoreTitleKey('The Nice Combination!'), 'nicecombination');
      expect(dedupeCoreTitleKey('Café Béguine'), 'cafebeguine');
      expect(dedupeCoreTitleKey('A-Reel'), 'reel');
      // `A 1` is `A-1` written with a space, not the article.
      expect(dedupeCoreTitleKey('A 1 Reel'), 'a1reel');
      expect(dedupeCoreTitleKey('A 1 Reel'), dedupeCoreTitleKey('A-1 Reel'));
    });

    test('strips more than one trailing annotation, of every bracket kind', () {
      expect(dedupeCoreTitleKey('Aback {2/2013 version}'), 'aback');
      expect(dedupeCoreTitleKey('Aback [alt] (Imp Var) {x}'), 'aback');
    });

    test('only strips annotations set off at the end', () {
      expect(
        dedupeCoreTitleKey('Chinook (Wind not Salmon) Reel'),
        'chinookwindnotsalmonreel',
      );
      // A bracket inside a word is part of the title, not an annotation.
      expect(dedupeCoreTitleKey("Al's Berlin Trip(let)"), 'alsberlintriplet');
      expect(dedupeCoreTitleKey('Reel(2)'), 'reel2');
    });

    test('keeps the bracket when the rest is a placeholder title', () {
      // ContraDB: one choreographer titles dances `New Dance (Real Name)`.
      expect(dedupeCoreTitleKey('New Dance ( Velvet )'), 'newdancevelvet');
      expect(
        dedupeCoreTitleKey('New Dance (Velvet)'),
        isNot(dedupeCoreTitleKey('New Dance      (    Embrace  )')),
      );
      expect(dedupeCoreTitleKey('New Dance'), 'newdance');
    });

    test('keeps a bracket that is only a part number, and stops there', () {
      // The one Caller's Box false positive in a 60-pair sample: No. 1 and
      // No. 2 are different traditional dances.
      expect(
        dedupeCoreTitleKey("Rickett's Hornpipe {#2}"),
        isNot(dedupeCoreTitleKey("Rickett's Hornpipe {No. 1, alternate 2}")),
      );
      expect(
        dedupeCoreTitleKey("Rickett's Hornpipe {#2}"),
        'rickettshornpipe2',
      );
      expect(
        dedupeCoreTitleKey('Waving at the Stars (1)'),
        isNot(dedupeCoreTitleKey('Waving at the Stars (2)')),
      );
      expect(dedupeCoreTitleKey('Reel (No. 3)'), 'reelno3');
      expect(dedupeCoreTitleKey('Reel {alt} (Part 2)'), 'reelaltpart2');
      // A number among other words is still an annotation.
      expect(dedupeCoreTitleKey('Reel {alternate 2}'), 'reel');
    });

    test('carries no signal for annotation-only or non-Latin titles', () {
      expect(dedupeCoreTitleKey('{variant}'), '');
      expect(dedupeCoreTitleKey('(Imp Var)'), '');
      expect(dedupeCoreTitleKey('花'), '');
      expect(dedupeCoreTitleKey(''), '');
      expect(dedupeCoreTitleKey(')'), '');
    });

    test('leaves unbalanced or nested brackets in place rather than eating '
        'the title', () {
      // A real ContraDB title.
      expect(
        dedupeCoreTitleKey('New Dance            [ Rumble }'),
        'newdancerumble',
      );
      expect(dedupeCoreTitleKey('Reel (a (b))'), 'reelab');
    });

    test('is bounded on hostile input', () {
      final hostile = 'Reel${' {x}' * 10000}';
      // Four annotations come off; the rest stay as text.
      expect(dedupeCoreTitleKey(hostile), startsWith('reelx'));
    });
  });

  test('normalizeTitle is unchanged by the core key: it is the sync key', () {
    // `normalizeTitle` is the normative "normalized title" of
    // docs/design/sync-spec.md, and fresh-attach dedupe merges on it silently,
    // so "fixing" it to read `A-1` as `a1` would make two devices on different
    // versions disagree about how many dances exist. #1907 put that fix in
    // `dedupeCoreTitleKey` instead; this pins the original behaviour.
    expect(normalizeTitle('A-1 Reel'), '1 reel');
    expect(normalizeTitle('A1 Reel'), 'a1 reel');
    expect(normalizeTitle('A-1 Reel {variant}'), '1 reel variant');
  });

  group('possibleMatchIds', () {
    DedupeIndex reporterCollection({
      List<String> authors = const ['Chris Weiler'],
    }) => DedupeIndex([
      DedupeEntry(danceId: 'base', title: 'A1 Reel', authorNames: authors),
      DedupeEntry(
        danceId: 'variant',
        title: 'A1 Reel (Imp Var)',
        authorNames: authors,
      ),
      DedupeEntry(danceId: 'other', title: 'Rory O More', authorNames: authors),
    ]);

    test(
      "offers both of the reporter's dances without changing the verdict",
      () {
        final verdict = reporterCollection().verdictFor(
          source: ProvenanceSource.callersbox,
          externalId: '1606',
          title: 'A-1 Reel {variant}',
          authorNames: const ['Chris Weiler'],
        );
        // The fuzzy tier misses both, so the verdict stays new: every caller
        // that branches on kind or candidates behaves exactly as before.
        expect(verdict.kind, DedupeKind.isNew);
        expect(verdict.candidates, isEmpty);
        expect(verdict.hasConfidentMatch, isFalse);
        expect(verdict.possibleMatchIds, ['base', 'variant']);
      },
    );

    test('rides alongside an ambiguous verdict and may overlap a fuzzy, never '
        'a confident, candidate', () {
      final verdict = reporterCollection().verdictFor(
        source: ProvenanceSource.callersbox,
        externalId: '1605',
        title: 'A-1 Reel',
        authorNames: const ['Chris Weiler'],
      );
      expect(verdict.kind, DedupeKind.ambiguous);
      expect(verdict.candidates.map((c) => c.danceId), contains('base'));
      expect(verdict.hasConfidentMatch, isFalse);
      expect(verdict.possibleMatchIds, ['base', 'variant']);
    });

    test('never repeats a confident candidate', () {
      final verdict = reporterCollection().verdictFor(
        source: ProvenanceSource.callersbox,
        title: 'A1 Reel',
        authorNames: const ['Chris Weiler'],
      );
      expect(verdict.hasConfidentMatch, isTrue);
      expect(verdict.possibleMatchIds, ['variant']);
    });

    test('requires a shared author on both sides', () {
      final index = reporterCollection();
      for (final incoming in [
        const <String>[],
        const ['Someone Else'],
      ]) {
        expect(
          index
              .verdictFor(
                source: ProvenanceSource.callersbox,
                title: 'A-1 Reel {variant}',
                authorNames: incoming,
              )
              .possibleMatchIds,
          isEmpty,
          reason: '$incoming',
        );
      }
      expect(
        reporterCollection(authors: const [])
            .verdictFor(
              source: ProvenanceSource.callersbox,
              title: 'A-1 Reel {variant}',
              authorNames: const ['Chris Weiler'],
            )
            .possibleMatchIds,
        isEmpty,
      );
    });

    test('is empty on a re-import', () {
      final index = DedupeIndex([
        DedupeEntry(
          danceId: 'base',
          title: 'A1 Reel',
          authorNames: const ['Chris Weiler'],
          source: ProvenanceSource.callersbox,
          externalId: '1605',
        ),
        DedupeEntry(
          danceId: 'variant',
          title: 'A1 Reel (Imp Var)',
          authorNames: const ['Chris Weiler'],
        ),
      ]);
      final verdict = index.verdictFor(
        source: ProvenanceSource.callersbox,
        externalId: '1605',
        title: 'A-1 Reel',
        authorNames: const ['Chris Weiler'],
      );
      expect(verdict.isReimport, isTrue);
      expect(verdict.possibleMatchIds, isEmpty);
    });

    test('never matches through an empty core title', () {
      final index = DedupeIndex([
        DedupeEntry(
          danceId: 'blank',
          title: '{variant}',
          authorNames: const ['Chris Weiler'],
        ),
      ]);
      expect(
        index.possibleTitleMatches('(Imp Var)', const ['Chris Weiler']),
        isEmpty,
      );
    });

    test('does not pair placeholder-titled dances through their brackets', () {
      final index = DedupeIndex([
        DedupeEntry(
          danceId: 'velvet',
          title: 'New Dance ( Velvet )',
          authorNames: const ['Don Flaherty'],
        ),
        DedupeEntry(
          danceId: 'plain',
          title: 'New Dance',
          authorNames: const ['Don Flaherty'],
        ),
      ]);
      expect(
        index.possibleTitleMatches('New Dance (Embrace)', const [
          'Don Flaherty',
        ]),
        isEmpty,
      );
    });

    test('is ignored by the score threshold', () {
      final index = reporterCollection();
      for (final threshold in [0.0, 0.72, 1.0]) {
        expect(
          index
              .verdictFor(
                source: ProvenanceSource.callersbox,
                title: 'A-1 Reel {variant}',
                authorNames: const ['Chris Weiler'],
                threshold: threshold,
              )
              .possibleMatchIds,
          ['base', 'variant'],
          reason: '$threshold',
        );
      }
    });
  });
}
