import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/plaintext_program_import.dart';
import 'package:compendium_app/src/export/export_labels_l10n.dart';
import 'package:compendium_core/compendium_core.dart';
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

  group('ParsedProgramLine invariants', () {
    test('matched without a danceId throws', () {
      expect(
        () => ParsedProgramLine(
          text: 'x',
          resolution: PlaintextLineResolution.matched,
          matchCount: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('note resolution carrying a danceId throws', () {
      expect(
        () => ParsedProgramLine(
          text: 'x',
          resolution: PlaintextLineResolution.unmatched,
          danceId: 'd1',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('ambiguous with matchCount <= 1 throws', () {
      expect(
        () => ParsedProgramLine(
          text: 'x',
          resolution: PlaintextLineResolution.ambiguous,
          matchCount: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // A shared or printed set list shows a break as the translated label
  // (#2580). Pasting that list back must give the break back, in every
  // language the app ships, and recognise no other word as one (the
  // maintainer's answer to question 44 of the pre-release audit's decision
  // sheet, 2026-11-27).
  group('pasted break labels', () {
    List<ProgramSlot> paste(String text) => buildProgramSlots(
      parsePlaintextProgram(text, collection: const []),
      newSlotId: _seqIds(),
    );

    for (final locale in AppLocalizations.supportedLocales) {
      test('a list shared as text in "$locale" pastes back with its break', () {
        final l10n = lookupAppLocalizations(locale);
        final epoch = DateTime.utc(2026);
        final program = Program(
          id: 'p1',
          title: 'Dance',
          createdAt: epoch,
          updatedAt: epoch,
          slots: [
            ProgramSlot(id: 'a', position: 0, text: 'Welcome'),
            ProgramSlot(id: 'b', position: 1, text: Program.breakSlotText),
            ProgramSlot(id: 'c', position: 2, text: 'Last waltz'),
          ],
        );
        final shared = programToPlainText(
          program,
          titleFor: (_) => null,
          labels: programExportLabels(l10n),
          includeTitle: false,
          includeCallerBand: false,
          includeDateVenue: false,
        );
        expect(shared, contains(l10n.programsBreakSlotLabel));

        final slots = paste(shared);

        expect(slots.map((s) => s.isBreak), [false, true, false]);
        expect(slots[1].text, Program.breakSlotText);
      });
    }

    test('any case and surrounding space, in every language', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final label = lookupAppLocalizations(locale).programsBreakSlotLabel;
        final slots = paste(
          '  ${label.toUpperCase()}  \n${label.toLowerCase()}',
        );
        expect(slots.map((s) => s.text), [
          Program.breakSlotText,
          Program.breakSlotText,
        ], reason: '$locale');
      }
    });

    test('a parsed line knows it is a break only when unmatched', () {
      final lines = parsePlaintextProgram(
        'Pause\nPauses\nBreak',
        collection: const [(id: 'd9', title: 'Break')],
      );
      expect(lines.map((l) => l.isBreak), [true, false, false]);
    });

    test('a near-miss word stays a note', () {
      const nearMisses = ['Pauses', 'Breaks', 'Pause!', 'Pause café', 'Pauzes'];
      final slots = paste(nearMisses.join('\n'));
      expect(slots.map((s) => s.isBreak), everyElement(isFalse));
      expect(slots.map((s) => s.text), nearMisses);
    });

    test('a dance titled like a break label stays that dance', () {
      final slots = buildProgramSlots(
        parsePlaintextProgram(
          'Pause',
          collection: const [(id: 'd9', title: 'Pause')],
        ),
        newSlotId: _seqIds(),
      );
      expect(slots.single.danceId, 'd9');
      expect(slots.single.text, isNull);
    });
  });
}
