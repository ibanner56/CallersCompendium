import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../data/display_defaults.dart';

/// The text a person reads for [slot]'s own text: a break
/// ([ProgramSlot.isBreak]) reads as the translated break label, and any other
/// slot as its stored text.
///
/// A break is stored as the English token [Program.breakSlotText] in every
/// language, and that token is what the database, backups, sync, data exports
/// and the event rules read; only what a person reads is translated (the
/// maintainer's decision, 2026-11-27). Use this wherever a slot's text is
/// shown or printed, never where it is stored or matched.
String? slotDisplayText(AppLocalizations l10n, ProgramSlot slot) =>
    slot.isBreak ? l10n.programsBreakSlotLabel : slot.text;

/// [slotDisplayText] for a template entry's text, which has no
/// [ProgramSlot] yet: the break token reads as the translated label.
String? templateEntryDisplayText(AppLocalizations l10n, String? text) =>
    isProgramTemplateBreakText(text) ? l10n.programsBreakSlotLabel : text;

/// The stored text for [shown], text edited in a field that opened with
/// [slotDisplayText]: a break whose label the person left as it was keeps its
/// stored token, so editing a break's other fields can't turn it into a note
/// reading "Pause".
String storedSlotText(
  AppLocalizations l10n, {
  required String? stored,
  required String shown,
}) {
  if (isProgramTemplateBreakText(stored) &&
      shown.trim().toLowerCase() ==
          l10n.programsBreakSlotLabel.trim().toLowerCase()) {
    return stored!;
  }
  return shown;
}
