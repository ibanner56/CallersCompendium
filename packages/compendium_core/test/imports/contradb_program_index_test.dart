import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for [parseContraDbProgramIndex] against a real, redacted capture of the
/// public ContraDB program index (`GET https://contradb.com/programs`, ~845
/// programs) checked in at `support/contradb/programs_index.html`. No live
/// network is used.
void main() {
  final fixtureHtml = File(
    'test/imports/support/contradb/programs_index.html',
  ).readAsStringSync();

  group('parseContraDbProgramIndex', () {
    test('parses every /programs/{id} anchor from the real index', () {
      final entries = parseContraDbProgramIndex(fixtureHtml);
      // The captured index lists ~845 programs; assert we got them all (the
      // `/programs` nav link and `/programs/new` are correctly skipped).
      expect(entries, hasLength(845));
    });

    test('keeps ids and names verbatim (including internal whitespace)', () {
      final entries = parseContraDbProgramIndex(fixtureHtml);
      final byId = {for (final e in entries) e.id: e.name};

      expect(byId['33'], '01.12.18-Harrisburg, Pa');
      // Verbatim: this entry has a double space in its source link text, which
      // must be preserved exactly (no collapsing / normalization).
      expect(
        byId['671'],
        '01.11.25  Pocatello, ID Contra Dance with Runestone',
      );
    });

    test('skips the /programs and /programs/new nav links', () {
      final entries = parseContraDbProgramIndex(fixtureHtml);
      // Every entry has a purely-numeric id (no "new", no empty id).
      expect(entries.every((e) => RegExp(r'^\d+$').hasMatch(e.id)), isTrue);
      expect(entries.every((e) => e.name.isNotEmpty), isTrue);
    });

    test('tolerates malformed / empty / anchor-less HTML (never throws)', () {
      expect(parseContraDbProgramIndex(''), isEmpty);
      expect(parseContraDbProgramIndex('<html'), isEmpty);
      expect(parseContraDbProgramIndex('not html at all <<<>>>'), isEmpty);
      expect(
        parseContraDbProgramIndex(
          '<html><body><p>no anchors</p></body></html>',
        ),
        isEmpty,
      );
    });

    test('extracts a minimal well-formed anchor', () {
      final entries = parseContraDbProgramIndex(
        '<html><body><a href="/programs/42">My Set List</a></body></html>',
      );
      expect(entries, [
        const ContraDbProgramIndexEntry(id: '42', name: 'My Set List'),
      ]);
    });

    test('skips non-numeric, sub-path, and empty-text program anchors', () {
      final entries = parseContraDbProgramIndex('''
        <html><body>
          <a href="/programs">Programs</a>
          <a href="/programs/new">New</a>
          <a href="/programs/33/edit">Edit</a>
          <a href="/programs/7">   </a>
          <a href="/programs/9">Kept</a>
        </body></html>
      ''');
      expect(entries, [const ContraDbProgramIndexEntry(id: '9', name: 'Kept')]);
    });
  });

  // Security regression guard (mirrors the #314/#336 program-fixture finding):
  // the checked-in source fixture must never ship a live CSRF token, session
  // cookie, or other secret.
  group('programs_index fixture secrecy', () {
    test('csrf-token meta is present but redacted', () {
      final csrf = RegExp(
        r'name="csrf-token" content="([^"]*)"',
      ).firstMatch(fixtureHtml);
      expect(
        csrf,
        isNotNull,
        reason: 'expected a csrf-token meta tag in the fixture',
      );
      expect(csrf!.group(1), 'REDACTED-CSRF-TOKEN');
    });

    test('contains no cookie / session / api-key material', () {
      final lower = fixtureHtml.toLowerCase();
      expect(lower, isNot(contains('set-cookie')));
      expect(lower, isNot(contains('_contradb_session')));
      expect(
        RegExp(r'api[_-]?key', caseSensitive: false).hasMatch(fixtureHtml),
        isFalse,
      );
    });

    test('contains no stray base64 token-like blobs', () {
      // Any >=24-char run containing + / or trailing == would be token-like. The
      // only long digests on this page are hex sprocket asset fingerprints,
      // which contain none of those, so this catches a re-introduced secret
      // without false-positiving on the asset URLs.
      final secretLike = RegExp(r'[A-Za-z0-9+/]{24,}={0,2}');
      final hits = secretLike
          .allMatches(fixtureHtml)
          .map((m) => m.group(0)!)
          .where((s) => s.contains('+') || s.contains('/') || s.endsWith('=='))
          .toList();
      expect(hits, isEmpty, reason: 'possible secret token in fixture: $hits');
    });
  });
}
