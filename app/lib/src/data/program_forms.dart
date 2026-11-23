import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

/// The dance forms in a program, as a label: each form's name in [DanceForm]
/// order, joined by " + ", such as "Contra + English (ECD)". Null for a
/// program with no dances, which has no form to show. The " + " keeps the
/// label one item where a row joins its fields with " · ".
///
/// Shown at the top of a program and on its row in the programs list, and
/// what the list's type filter and the program search match (ADR-006: a
/// caller can see at a glance whether a program is contra, English or both).
String? programFormsLabel(AppLocalizations l10n, Set<DanceForm>? forms) {
  if (forms == null || forms.isEmpty) return null;
  return [
    for (final form in DanceForm.values)
      if (forms.contains(form)) danceFormLabel(l10n, form),
  ].join(' + ');
}

/// The forms of the dances in [slots], resolved through [dancesById]: every
/// slot with a dance, alternates included, as the builder's, the summary's
/// and Perform's mixed-form checks count them. A slot whose dance is not in
/// [dancesById], or is in Recently deleted, counts for nothing, as in
/// [ProgramRepository.formsByProgram].
Set<DanceForm> programSlotForms(
  Iterable<ProgramSlot> slots,
  Map<String, Dance> dancesById,
) => {
  for (final slot in slots)
    if (slot.danceId case final id?)
      if (dancesById[id] case final dance? when !dance.isDeleted) dance.form,
};

/// Whether [forms] is the same set of forms as [selected]: the programs
/// list's type filter under [FormMatch.only], and how it recognises the
/// chosen chip.
bool sameForms(Set<DanceForm>? forms, Set<DanceForm> selected) =>
    forms != null &&
    forms.length == selected.length &&
    forms.containsAll(selected);

/// How the programs list's type filter compares a program's forms with the
/// chosen chip's: [only] keeps a program of exactly those forms, so "Contra"
/// leaves out a program that also has English dances; [includes] keeps a
/// program that has that form, so "Contra" lists every program with a
/// contra dance. Under [includes] each chip is a single form.
enum FormMatch { only, includes }

/// Whether a program of [forms] passes the type filter [selected] under
/// [match]. A program with no dances ([forms] null) passes neither.
bool formsMatch(
  Set<DanceForm>? forms,
  Set<DanceForm> selected,
  FormMatch match,
) => switch (match) {
  FormMatch.only => sameForms(forms, selected),
  FormMatch.includes => forms != null && forms.containsAll(selected),
};
