import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'baby_rose_seed_generator.dart';
import '../test_package_root.dart';

void main() {
  group('Baby Rose seed asset', () {
    late String _fixturePath;
    late String _assetPath;
    late String fixtureHtml;

    setUpAll(() async {
      final repoRoot = p.normalize(
        p.join(await packageRootPath(), '..', '..'),
      );
      _fixturePath = p.join(
        repoRoot,
        'tools',
        'seed',
        'fixtures',
        'contradb_dance_8.html',
      );
      _assetPath = p.join(
        repoRoot,
        'app',
        'assets',
        'seed',
        'baby_rose.json',
      );
      fixtureHtml = File(_fixturePath).readAsStringSync();
    });

    // Drift guard: the checked-in asset must be exactly what the generator
    // produces from the checked-in source fixture, so the seed can never
    // silently diverge from its authoritative source (mirrors the user-docs
    // sync drift check). Regenerate with:
    //   dart run test/seed/generate_baby_rose_seed.dart
    test('checked-in asset matches freshly generated output', () async {
      final generated = await buildBabyRoseSeedArchiveJson(fixtureHtml);
      final onDisk = File(_assetPath).readAsStringSync();
      expect(
        onDisk,
        '$generated\n',
        reason:
            'app/assets/seed/baby_rose.json is stale. Regenerate it with '
            '`dart run test/seed/generate_baby_rose_seed.dart`.',
      );
    });

    // Fidelity: the shipped asset decodes, through the app's real decode path,
    // to the authoritative definition of "The Baby Rose" (David Kaynor,
    // improper) with the exact figure/beat sequence transcribed at
    // https://contradb.com/dances/8.
    test('decodes to the faithful sourced definition', () {
      final result = decodeArchive(File(_assetPath).readAsStringSync());
      expect(result.hasErrors, isFalse, reason: '${result.errors}');

      final archive = result.archive;
      expect(archive.dances, hasLength(1));
      final dance = archive.dances.single;

      expect(dance.title, 'The Baby Rose');
      expect(dance.formation.shape, FormationShape.dupleImproper);
      expect(dance.provenance?.source, ProvenanceSource.contradb);
      expect(dance.provenance?.externalId, '8');

      // Author resolves to a single David Kaynor choreographer.
      expect(dance.authorIds, hasLength(1));
      final author = archive.choreographers.singleWhere(
        (c) => c.id == dance.authorIds.single,
      );
      expect(author.name, 'David Kaynor');

      // Verbatim choreography from the source page (improper):
      //   A1 (16) neighbors balance & swing
      //   A2 (8)  circle left 3 places
      //   A2 (8)  partners do si do once
      //   B1 (16) partners balance & swing
      //   B2 (8)  ladles chain
      //   B2 (8)  star left 4 places to new neighbors  (progression)
      final figures = dance.figures;
      expect(figures, hasLength(6));

      expect(figures[0].move, 'swing');
      expect(figures[0].params['who'], 'neighbors');
      expect(figures[0].params['prefix'], 'balance');
      expect(figures[0].params['beats'], 16);

      expect(figures[1].move, 'circle');
      expect(figures[1].params['turn'], 'left');
      expect(figures[1].params['places'], 3);
      expect(figures[1].params['beats'], 8);

      expect(figures[2].move, 'do_si_do');
      expect(figures[2].params['who'], 'partners');
      expect(figures[2].params['beats'], 8);

      expect(figures[3].move, 'swing');
      expect(figures[3].params['who'], 'partners');
      expect(figures[3].params['prefix'], 'balance');
      expect(figures[3].params['beats'], 16);

      expect(figures[4].move, 'chain');
      expect(figures[4].params['beats'], 8);

      expect(figures[5].params['beats'], 8);
      expect(figures[5].progression, isTrue);

      // Total beats make one full 64-beat contra time (A1+A2+B1+B2).
      final totalBeats = figures.fold<int>(
        0,
        (sum, f) => sum + (f.params['beats'] as int),
      );
      expect(totalBeats, 64);
    });

    // Security regression guard (mirrors the #314 program-fixture finding): the
    // checked-in source fixture must never ship a live CSRF token, session
    // cookie, or other secret, and the generated asset must embed no scraped
    // source markup at all. The seed generator used to strip
    // `provenance.rawPayload` to achieve that; schema v21 removed the column
    // outright (#781), so the guarantee now comes from there being nowhere to
    // put a page. The assertions below are kept exactly as they were — the
    // property they pin is unchanged, and they now also catch a reintroduction
    // of the column.
    test('source fixture and asset contain no live secrets', () {
      // The csrf-token meta must be present but redacted to a fixed placeholder.
      final csrf = RegExp(
        r'name="csrf-token" content="([^"]*)"',
      ).firstMatch(fixtureHtml);
      expect(
        csrf,
        isNotNull,
        reason: 'expected a csrf-token meta tag in the fixture',
      );
      expect(csrf!.group(1), 'REDACTED-CSRF-TOKEN');

      // No cookie / session / api-key material anywhere in the fixture.
      final lower = fixtureHtml.toLowerCase();
      expect(lower, isNot(contains('set-cookie')));
      expect(lower, isNot(contains('_contradb_session')));
      expect(
        RegExp(r'api[_-]?key', caseSensitive: false).hasMatch(fixtureHtml),
        isFalse,
      );

      // No stray base64 token-like blobs (>=24 chars containing + / or ==) in
      // the fixture. The only long digests on this page are hex sprocket
      // fingerprints, which contain none of those, so this catches a
      // re-introduced secret without false-positiving on the asset URLs.
      final secretLike = RegExp(r'[A-Za-z0-9+/]{24,}={0,2}');
      final fixtureHits = secretLike
          .allMatches(fixtureHtml)
          .map((m) => m.group(0)!)
          .where((s) => s.contains('+') || s.contains('/') || s.endsWith('=='))
          .toList();
      expect(
        fixtureHits,
        isEmpty,
        reason: 'possible secret token in fixture: $fixtureHits',
      );

      // The shipped asset embeds NO source markup — no raw HTML payload — so it
      // can never carry a page secret, defensively, independent of the fixture.
      final asset = File(_assetPath).readAsStringSync();
      expect(asset, isNot(contains('rawPayload')));
      expect(asset, isNot(contains('DOCTYPE')));
      expect(asset, isNot(contains('<meta')));
    });

    // Proves the asset is independent of any secret in the source page: even if
    // the fixture carried a live CSRF token, the generated asset is byte-for-byte
    // identical, because the generator strips the raw payload and only the
    // scraped figure breakdown feeds the archive. This is the invariant that
    // makes fixture redaction safe by construction.
    test(
      'a token in the source page cannot change the generated asset',
      () async {
        final withToken = fixtureHtml.replaceAll(
          'content="REDACTED-CSRF-TOKEN"',
          'content="AAAAliveTOKENvalue+with/slashes=="',
        );
        expect(
          withToken,
          isNot(equals(fixtureHtml)),
          reason: 'the replacement should have injected a token',
        );

        final fromRedacted = await buildBabyRoseSeedArchiveJson(fixtureHtml);
        final fromTokened = await buildBabyRoseSeedArchiveJson(withToken);
        expect(fromTokened, fromRedacted);
      },
    );
  });
}
