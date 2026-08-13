import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Covers [danceTitleFromSlotNote] (issue #881): a program note slot's text
/// is not reliably a bare title, so this must extract a reasonable dance
/// title seed from each of the four shapes producers actually emit — see
/// `program_slot_note.dart`'s doc comment for the shapes and their sources.
void main() {
  group('bare pasted title (title-list / plaintext import)', () {
    test('a plain title passes through trimmed', () {
      expect(danceTitleFromSlotNote('  Petronella  '), 'Petronella');
    });

    test('a title with no surrounding whitespace is unchanged', () {
      expect(danceTitleFromSlotNote('Chorus Jig'), 'Chorus Jig');
    });
  });

  group('ContraDB "<title> — <note>" join — deliberately NOT split', () {
    test('the whole joined string is kept as the seed', () {
      // Isaac decided: do not split ContraDB's ' — ' joiner, so the note
      // half is not silently discarded from the seed's source text. The
      // user reviews/edits the seed in the dance editor before saving.
      expect(
        danceTitleFromSlotNote('Money Musk — called by a guest'),
        'Money Musk — called by a guest',
      );
    });
  });

  group('archive import unresolved-dance marker', () {
    test('marker-only note (no original text) strips to empty', () {
      expect(danceTitleFromSlotNote('Dance not imported (abc123)'), '');
    });

    test(
      'original text + blank line + marker keeps only the original text',
      () {
        expect(
          danceTitleFromSlotNote('Chorus Jig\n\nDance not imported (abc123)'),
          'Chorus Jig',
        );
      },
    );

    test('a marker with a longer numeric-ish id still strips fully', () {
      expect(
        danceTitleFromSlotNote(
          'Dance not imported (01234567-89ab-cdef-0123-456789abcdef)',
        ),
        '',
      );
    });
  });

  group("Caller's Companion unresolved-dance marker", () {
    test('marker-only note strips to empty', () {
      expect(
        danceTitleFromSlotNote(
          "Dance not imported (Caller's Companion dance #42)",
        ),
        '',
      );
    });
  });

  group('hand-typed note / break', () {
    test('an arbitrary announcement passes through trimmed', () {
      expect(
        danceTitleFromSlotNote('  Announcements before intermission  '),
        'Announcements before intermission',
      );
    });

    test('blank lines before the real content are skipped', () {
      expect(danceTitleFromSlotNote('\n\n  Waltz  \n\nmore text'), 'Waltz');
    });

    test('an empty note yields an empty seed', () {
      expect(danceTitleFromSlotNote(''), '');
    });

    test('a whitespace-only note yields an empty seed', () {
      expect(danceTitleFromSlotNote('   \n   \n  '), '');
    });
  });

  group('length cap (untrusted input defense)', () {
    test('a pathologically long note is capped before extraction', () {
      final huge = 'A' * 10000;
      final result = danceTitleFromSlotNote(huge);
      expect(result.length, lessThanOrEqualTo(512));
    });

    test('a long note with a marker past the cap is still bounded', () {
      final huge = '${'A' * 10000}\n\nDance not imported (x)';
      final result = danceTitleFromSlotNote(huge);
      expect(result.length, lessThanOrEqualTo(512));
    });
  });
}
