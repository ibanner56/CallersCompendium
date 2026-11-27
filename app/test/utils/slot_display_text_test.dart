import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/utils/slot_display_text.dart';
import 'package:compendium_app/src/widgets/program_slot_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A break is stored as the English token in every language, and reads as the
/// translated label wherever a person sees it (the maintainer's answer to
/// question 23 of the pre-release audit's decision sheet, 2026-11-27).
void main() {
  final de = lookupAppLocalizations(const Locale('de'));
  final en = lookupAppLocalizations(const Locale('en'));
  final breakSlot = ProgramSlot(id: 's1', position: 0, text: 'Break');
  final typedBreak = ProgramSlot(id: 's2', position: 1, text: ' break ');
  final note = ProgramSlot(id: 's3', position: 2, text: 'Waltz');

  test('a break reads as the translated label; a note as its text', () {
    expect(de.programsBreakSlotLabel, isNot(Program.breakSlotText));
    expect(slotDisplayText(de, breakSlot), de.programsBreakSlotLabel);
    expect(slotDisplayText(de, typedBreak), de.programsBreakSlotLabel);
    expect(slotDisplayText(de, note), 'Waltz');
    expect(slotDisplayText(en, breakSlot), 'Break');
  });

  test('a template entry with the break token reads as the label', () {
    expect(templateEntryDisplayText(de, 'Break'), de.programsBreakSlotLabel);
    expect(templateEntryDisplayText(de, 'Waltz'), 'Waltz');
    expect(templateEntryDisplayText(de, null), isNull);
  });

  test('the builder row names a break by the translated label', () {
    expect(
      programSlotTitle(
        de,
        breakSlot,
        danceTitles: (_) => null,
        dialect: null,
        canonicalizeDiscouragedTerms: false,
      ),
      de.programsBreakSlotLabel,
    );
  });

  group('storedSlotText', () {
    test('an untouched break label keeps the stored token', () {
      expect(
        storedSlotText(de, stored: 'Break', shown: de.programsBreakSlotLabel),
        'Break',
      );
      expect(storedSlotText(de, stored: ' break ', shown: 'PAUSE'), ' break ');
    });

    test(
      'an edited break, or a note reading the label, stores what is shown',
      () {
        expect(storedSlotText(de, stored: 'Break', shown: 'Tea'), 'Tea');
        // A note that merely reads "Pause" was never a break: it stays a note.
        expect(storedSlotText(de, stored: 'Waltz', shown: 'Pause'), 'Pause');
      },
    );
  });
}
