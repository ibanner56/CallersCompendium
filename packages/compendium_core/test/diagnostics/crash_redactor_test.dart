import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('CrashRedactor PII patterns', () {
    final redactor = CrashRedactor();

    test('redacts email addresses', () {
      final out = redactor.scrub('contact caller.jane+tag@example.co.uk now');
      expect(out, isNot(contains('caller.jane+tag@example.co.uk')));
      expect(out, contains(CrashRedactor.emailPlaceholder));
    });

    test('redacts phone numbers in several formats', () {
      const samples = [
        '+1 (555) 123-4567',
        '555-123-4567',
        '555.123.4567',
        '5551234567',
        '+44 20 7946 0958',
      ];
      for (final sample in samples) {
        final out = redactor.scrub('call me at $sample please');
        expect(
          out,
          isNot(contains(RegExp(r'\d{3}'))),
          reason: 'phone not scrubbed: $sample -> $out',
        );
        expect(out, contains(CrashRedactor.phonePlaceholder));
      }
    });

    test('collapses absolute POSIX paths but keeps the basename', () {
      final out = redactor.scrub(
        'opened /Users/isaac/dev/app/lib/main.dart ok',
      );
      expect(out, isNot(contains('/Users/isaac')));
      expect(out, contains('<path>/main.dart'));
    });

    test('collapses file:// URIs', () {
      final out = redactor.scrub('at file:///home/jane/secret/notes.txt end');
      expect(out, isNot(contains('/home/jane')));
      expect(out, contains('<path>/notes.txt'));
    });

    test('collapses Windows paths', () {
      final out = redactor.scrub(r'wrote C:\Users\Jane\Docs\backup.json today');
      expect(out, isNot(contains(r'C:\Users\Jane')));
      expect(out, contains('<path>/backup.json'));
    });

    test('collapses a POSIX path with spaces in a segment', () {
      // The username must not leak because the path contains a space.
      final out = redactor.scrub('read /Users/Jane Doe/project/main.dart ok');
      expect(out, isNot(contains('Jane Doe')));
      expect(out, contains('<path>/main.dart'));
      expect(out, contains('ok'));
    });

    test('collapses Windows forward-slash drive paths', () {
      final out = redactor.scrub('load C:/Users/Jane Doe/app/config.json here');
      expect(out, isNot(contains('Jane Doe')));
      expect(out, isNot(contains('C:/Users')));
      expect(out, contains('<path>/config.json'));
    });

    test('collapses UNC paths, dropping server and share', () {
      final out = redactor.scrub(r'open \\fileserver\team\notes.txt now');
      expect(out, isNot(contains('fileserver')));
      expect(out, isNot(contains('team')));
      expect(out, contains('<path>/notes.txt'));
    });

    test('does not mistake a URL scheme for a Windows drive', () {
      final out = redactor.scrub('see https://example.com/help for details');
      expect(out, contains('https://example.com/help'));
    });
  });

  group('CrashRedactor preserves diagnostic skeleton', () {
    final redactor = CrashRedactor();

    test('keeps package: stack frames and line:col refs', () {
      const frame =
          '#1      _DanceEditorState.build (package:compendium_app/src/screens/'
          'dance_editor_screen.dart:412:9)';
      final out = redactor.scrub(frame);
      expect(out, contains('package:compendium_app/src/screens/'));
      expect(out, contains('dance_editor_screen.dart:412:9'));
    });

    test('does not treat a version string as a phone number', () {
      final out = redactor.scrub('running app v0.1.0+1 on the device');
      expect(out, contains('0.1.0+1'));
      expect(out, isNot(contains(CrashRedactor.phonePlaceholder)));
    });
  });

  group('CrashRedactor user-content terms', () {
    test('redacts each seeded user-content class', () {
      final redactor = CrashRedactor(
        userContentTerms: {
          'Chinquapin Reel', // dance title
          'Autumn Gathering 2025', // program title
          'balance and swing your neighbour', // figure/notes
          'Newcomer Friendly', // tag name
          'commissioned for Sam', // custom-field value
        },
      );
      const raw =
          'Failed rendering "Chinquapin Reel" in program '
          '"Autumn Gathering 2025": note "balance and swing your neighbour", '
          'tag Newcomer Friendly, field "commissioned for Sam".';
      final out = redactor.scrub(raw);
      for (final term in const [
        'Chinquapin Reel',
        'Autumn Gathering 2025',
        'balance and swing your neighbour',
        'Newcomer Friendly',
        'commissioned for Sam',
      ]) {
        expect(out, isNot(contains(term)), reason: 'leaked term: $term');
      }
      expect(out, contains(CrashRedactor.contentPlaceholder));
    });

    test('is case-insensitive and ignores very short terms', () {
      final redactor = CrashRedactor(userContentTerms: {'Reel', 'a'});
      final out = redactor.scrub('the REEL and a note');
      expect(out, isNot(contains(RegExp('reel', caseSensitive: false))));
      // The single-character term must not blank out unrelated text.
      expect(out, contains('note'));
    });

    test('combined scrub removes every class at once', () {
      final redactor = CrashRedactor(userContentTerms: {'Chinquapin Reel'});
      const raw =
          'Chinquapin Reel crashed; email jane@example.com phone 555-123-4567 '
          'at /Users/jane/app/lib/main.dart:10:2';
      final out = redactor.scrub(raw);
      expect(out, isNot(contains('Chinquapin Reel')));
      expect(out, isNot(contains('jane@example.com')));
      expect(out, isNot(contains('555-123-4567')));
      expect(out, isNot(contains('/Users/jane')));
      expect(out, contains('main.dart:10:2'));
    });
  });
}
