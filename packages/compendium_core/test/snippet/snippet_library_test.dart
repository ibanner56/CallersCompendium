import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('WalkthroughSnippetLibrary', () {
    test('withSnippet stores and resolves by signature', () {
      final lib = WalkthroughSnippetLibrary.empty.withSnippet(
        'swing(who=partners)',
        'Swing your partner.',
      );
      expect(lib.resolve('swing(who=partners)'), 'Swing your partner.');
      expect(lib.resolve('unknown'), isNull);
      expect(lib.resolve(null), isNull);
    });

    test('blank text removes the entry', () {
      final lib = WalkthroughSnippetLibrary.empty
          .withSnippet('a', 'text')
          .withSnippet('a', '   ');
      expect(lib.contains('a'), isFalse);
      expect(lib.isEmpty, isTrue);
    });

    test('soft-clamps overly long snippet text', () {
      final long = 'x' * (kMaxWalkthroughSnippetLength + 500);
      final lib = WalkthroughSnippetLibrary.empty.withSnippet('a', long);
      expect(lib.resolve('a')!.length, kMaxWalkthroughSnippetLength);
    });

    test('is immutable — withSnippet returns a new instance', () {
      final base = WalkthroughSnippetLibrary.empty;
      final next = base.withSnippet('a', 'text');
      expect(base.isEmpty, isTrue);
      expect(next.contains('a'), isTrue);
      expect(identical(base, next), isFalse);
    });

    test('caps entry count on ingest, keeping first sorted keys', () {
      final raw = <String, String>{
        for (var i = 0; i < kMaxSnippetLibraryEntries + 10; i++)
          i.toString().padLeft(6, '0'): 'snippet $i',
      };
      final lib = WalkthroughSnippetLibrary.fromJson({'snippets': raw});
      expect(lib.length, kMaxSnippetLibraryEntries);
      expect(lib.contains('000000'), isTrue);
    });

    test('withSnippet ignores a new key past the cap but allows updates', () {
      final raw = <String, String>{
        for (var i = 0; i < kMaxSnippetLibraryEntries; i++)
          i.toString().padLeft(6, '0'): 'snippet $i',
      };
      final full = WalkthroughSnippetLibrary.fromJson({'snippets': raw});
      final withNew = full.withSnippet('zzz-new', 'text');
      expect(withNew.contains('zzz-new'), isFalse);
      expect(withNew.length, kMaxSnippetLibraryEntries);
      final updated = full.withSnippet('000000', 'changed');
      expect(updated.resolve('000000'), 'changed');
    });

    test('JSON round-trip preserves entries', () {
      final lib = WalkthroughSnippetLibrary.empty
          .withSnippet('swing(who=partners)', 'Swing your partner.')
          .withSnippet('allemande(hand=left,turn=1.5,who=neighbors)', 'Alle.');
      final restored = WalkthroughSnippetLibrary.fromJson(lib.toJson());
      expect(restored, lib);
    });

    test('fromJson is tolerant of malformed input', () {
      expect(WalkthroughSnippetLibrary.fromJson({}), isEmpty);
      expect(
        WalkthroughSnippetLibrary.fromJson({'snippets': 'not a map'}),
        isEmpty,
      );
      final lib = WalkthroughSnippetLibrary.fromJson({
        'snippets': {'a': 'ok', 'b': 42, 'c': '  ', 'd': null},
      });
      expect(lib.length, 1);
      expect(lib.resolve('a'), 'ok');
    });

    test('sanitizes control/bidi spoofing chars on ingest (OWASP)', () {
      // A hostile backup blob with an embedded control byte + RLO override.
      final lib = WalkthroughSnippetLibrary.fromJson({
        'snippets': {'swing(who=partners)': 'Swing\u0007 them.\u202E'},
      });
      expect(lib.resolve('swing(who=partners)'), 'Swing them.');
      // Legitimate newlines survive.
      final multiline = WalkthroughSnippetLibrary.empty.withSnippet(
        'a',
        'line1\nline2',
      );
      expect(multiline.resolve('a'), 'line1\nline2');
      // A snippet that is nothing but spoofing chars is dropped entirely.
      final blanked = WalkthroughSnippetLibrary.empty.withSnippet(
        'b',
        '\u202E\u200B',
      );
      expect(blanked.contains('b'), isFalse);
    });
  });
}
