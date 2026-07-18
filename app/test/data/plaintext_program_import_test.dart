import 'package:compendium_app/src/data/plaintext_program_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// A deterministic id minter so slot ids are predictable in assertions.
String Function() _seqIds() {
  var n = 0;
  return () => 'slot-${n++}';
}

void main() {
  group('parsePlaintextProgram', () {
    const collection = <({String id, String title})>[
      (id: 'd1', title: 'Rockin\' Robin'),
      (id: 'd2', title: 'The Nice Combination'),
      // Two dances sharing a title (case-insensitively) → ambiguous.
      (id: 'd3', title: 'Broken Sixpence'),
      (id: 'd4', title: 'broken sixpence'),
    ];

    test('matched titles link to dances (case-insensitive) and keep order', () {
      final lines = parsePlaintextProgram(
        'rockin\' robin\nThe Nice Combination',
        collection: collection,
      );

      expect(lines.map((l) => l.text), [
        'rockin\' robin',
        'The Nice Combination',
      ]);
      expect(lines[0].resolution, PlaintextLineResolution.matched);
      expect(lines[0].danceId, 'd1');
      expect(lines[0].isNote, isFalse);
      expect(lines[1].resolution, PlaintextLineResolution.matched);
      expect(lines[1].danceId, 'd2');
    });

    test('unmatched lines become note lines', () {
      final lines = parsePlaintextProgram(
        'Some Unknown Dance',
        collection: collection,
      );

      expect(lines, hasLength(1));
      expect(lines.single.resolution, PlaintextLineResolution.unmatched);
      expect(lines.single.danceId, isNull);
      expect(lines.single.isNote, isTrue);
      expect(lines.single.matchCount, 0);
    });

    test('ambiguous (multi-match) title becomes a note, not a link', () {
      final lines = parsePlaintextProgram(
        'Broken Sixpence',
        collection: collection,
      );

      expect(lines.single.resolution, PlaintextLineResolution.ambiguous);
      expect(lines.single.danceId, isNull);
      expect(lines.single.isNote, isTrue);
      expect(lines.single.matchCount, 2);
    });

    test('blank and whitespace-only lines are skipped; order intact', () {
      final lines = parsePlaintextProgram(
        'Rockin\' Robin\n\n   \nAnnouncement: welcome\nThe Nice Combination',
        collection: collection,
      );

      expect(lines.map((l) => l.text), [
        'Rockin\' Robin',
        'Announcement: welcome',
        'The Nice Combination',
      ]);
      expect(lines[0].resolution, PlaintextLineResolution.matched);
      expect(lines[1].resolution, PlaintextLineResolution.unmatched);
      expect(lines[2].resolution, PlaintextLineResolution.matched);
    });

    test('empty input yields no lines', () {
      expect(parsePlaintextProgram('', collection: collection), isEmpty);
      expect(parsePlaintextProgram('   \n\n', collection: collection), isEmpty);
    });
  });

  group('buildProgramSlots', () {
    const collection = <({String id, String title})>[
      (id: 'd1', title: 'Rockin\' Robin'),
    ];

    test('builds ordered slots: matched → dance, note → free text', () {
      final lines = parsePlaintextProgram(
        'Rockin\' Robin\nBreak\nUnknown Dance',
        collection: collection,
      );
      final slots = buildProgramSlots(lines, newSlotId: _seqIds());

      expect(slots, hasLength(3));
      expect(slots.map((s) => s.position), [0, 1, 2]);
      expect(slots.map((s) => s.id), ['slot-0', 'slot-1', 'slot-2']);

      // Matched → dance-linked slot, no text.
      expect(slots[0].danceId, 'd1');
      expect(slots[0].text, isNull);

      // Note slots carry the original line text, no dance.
      expect(slots[1].danceId, isNull);
      expect(slots[1].text, 'Break');
      expect(slots[2].danceId, isNull);
      expect(slots[2].text, 'Unknown Dance');
    });

    test('empty lines produce no slots', () {
      expect(buildProgramSlots(const [], newSlotId: _seqIds()), isEmpty);
    });
  });
}
