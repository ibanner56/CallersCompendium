import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Unit tests for [splitAuthorNames] — the single canonical multi-author
/// splitter every import adapter routes through (issue #685).
void main() {
  group('single delimiter', () {
    test('slash', () {
      expect(splitAuthorNames(['Alice Smith / Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });

    test('ampersand', () {
      expect(splitAuthorNames(['Alice Smith & Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });

    test('plus', () {
      expect(splitAuthorNames(['Alice Smith + Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });

    test('comma', () {
      expect(splitAuthorNames(['Alice Smith, Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });

    test('semicolon', () {
      expect(splitAuthorNames(['Alice Smith; Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });

    test('word "and"', () {
      expect(splitAuthorNames(['Alice Smith and Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });

    test('word "with"', () {
      expect(splitAuthorNames(['Alice Smith with Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });

    test('is case-insensitive', () {
      expect(splitAuthorNames(['Alice Smith AND Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
      expect(splitAuthorNames(['Alice Smith WITH Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });
  });

  test('mixed delimiters split into all names', () {
    expect(
      splitAuthorNames(['Alice Smith & Bob Jones, Carol Lee and Dave Kim']),
      ['Alice Smith', 'Bob Jones', 'Carol Lee', 'Dave Kim'],
    );
  });

  group('word-boundary protection', () {
    test('"and"/"with" as a word does not split names containing them', () {
      expect(splitAuthorNames(['Andy Davis']), ['Andy Davis']);
      expect(splitAuthorNames(['Ann Withers']), ['Ann Withers']);
      expect(splitAuthorNames(['Withington Jones']), ['Withington Jones']);
    });
  });

  group('name-suffix protection', () {
    test('a trailing Jr./Sr./II/III/IV suffix stays attached', () {
      expect(splitAuthorNames(['Jane Doe, Jr.']), ['Jane Doe, Jr.']);
      expect(splitAuthorNames(['Jane Doe, Sr.']), ['Jane Doe, Sr.']);
      expect(splitAuthorNames(['Jane Doe, II']), ['Jane Doe, II']);
      expect(splitAuthorNames(['Jane Doe, III']), ['Jane Doe, III']);
      expect(splitAuthorNames(['Jane Doe, IV']), ['Jane Doe, IV']);
    });

    test('suffix without a trailing period still attaches', () {
      expect(splitAuthorNames(['Jane Doe, Jr']), ['Jane Doe, Jr']);
    });

    test('a compound suffix + further author still splits the remainder', () {
      expect(splitAuthorNames(['Jane Doe, Jr. and Bob Smith']), [
        'Jane Doe, Jr.',
        'Bob Smith',
      ]);
    });

    test('an ordinary comma-separated second name is NOT treated as a '
        'suffix', () {
      expect(splitAuthorNames(['Smith, Jones']), ['Smith', 'Jones']);
    });
  });

  group('cross-source equivalence (acceptance criterion)', () {
    test('a combined-string field and an array-of-fields field normalize to '
        'the same author set', () {
      final fromContraDbStyle = splitAuthorNames([
        'Alice Smith and Bob Jones',
      ]).map(normalizeAuthor).toSet();
      final fromCallersBoxStyle = splitAuthorNames([
        'Alice Smith',
        'Bob Jones',
      ]).map(normalizeAuthor).toSet();
      expect(fromContraDbStyle, fromCallersBoxStyle);
    });
  });

  group('blank/empty handling', () {
    test('null, empty and whitespace-only fields are dropped', () {
      expect(splitAuthorNames([null, '', '   ']), isEmpty);
    });

    test('empty fragments from delimiters are dropped', () {
      expect(splitAuthorNames(['Alice Smith, , Bob Jones']), [
        'Alice Smith',
        'Bob Jones',
      ]);
    });
  });

  group('de-duplication', () {
    test('a name repeated within one call collapses to one entry', () {
      expect(splitAuthorNames(['Alice Smith and Alice Smith']), [
        'Alice Smith',
      ]);
    });

    test(
      'de-duplication is case/whitespace-insensitive, first casing wins',
      () {
        expect(splitAuthorNames(['Alice Smith and ALICE   SMITH']), [
          'Alice Smith',
        ]);
      },
    );

    test('de-duplication applies across multiple raw fields', () {
      expect(splitAuthorNames(['Alice Smith', 'alice smith']), ['Alice Smith']);
    });
  });

  group('caps (OWASP length/count limits, never throw)', () {
    test('an over-long field is truncated and reported', () {
      final issues = <ImportIssue>[];
      final result = splitAuthorNames(
        ['A' * 1000],
        issues: issues,
        limits: const AuthorSplitLimits(maxFieldLength: 500),
      );
      expect(result.single.length, 500);
      expect(issues.map((i) => i.code), contains('author_field_truncated'));
    });

    test('more authors than the per-record cap are dropped and reported', () {
      final issues = <ImportIssue>[];
      final many = List.generate(50, (i) => 'Author Number $i').join(' and ');
      final result = splitAuthorNames(
        [many],
        issues: issues,
        limits: const AuthorSplitLimits(maxAuthorsPerRecord: 20),
      );
      expect(result.length, 20);
      expect(issues.map((i) => i.code), contains('author_count_capped'));
    });

    test('caps never throw on hostile input', () {
      final pathological = '${List.filled(5000, 'and').join(' ')}${',' * 2000}';
      expect(() => splitAuthorNames([pathological]), returnsNormally);
    });
  });

  group('ReDoS safety', () {
    test('pathological repeated-delimiter input completes quickly', () {
      final pathological =
          '${List.filled(20000, 'and & , ; / + with').join(' ')}!';
      final stopwatch = Stopwatch()..start();
      splitAuthorNames([pathological]);
      stopwatch.stop();
      // A linear-time splitter processes this near-instantly; a backtracking
      // regex on adversarial input would blow well past this bound.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('no issues sink provided', () {
    test('truncation still applies without an issues list', () {
      final result = splitAuthorNames([
        'A' * 1000,
      ], limits: const AuthorSplitLimits(maxFieldLength: 10));
      expect(result.single.length, 10);
    });
  });
}
