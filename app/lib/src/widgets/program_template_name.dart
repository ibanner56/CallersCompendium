import '../../l10n/app_localizations.dart';
import '../data/program_templates.dart';

/// The name shown for [template]: its own name, or, when that is empty, the
/// localized "Starting program" for the template copied from the Starting
/// program (stored unnamed so every device writes the same value) and
/// "Untitled template" for any other.
String programTemplateDisplayName(
  AppLocalizations l10n,
  ProgramTemplate template,
) {
  if (template.name.trim().isNotEmpty) return template.name;
  return template.id == kMigratedStartingProgramTemplateId
      ? l10n.settingsProgramTemplatesMigratedName
      : l10n.programTemplateUntitled;
}

/// The text a name field starts with for [template]: its own name, or the
/// localized "Starting program" for the unnamed template copied from the
/// Starting program, so saving keeps the name the user sees.
String programTemplateInitialName(
  AppLocalizations l10n,
  ProgramTemplate template,
) =>
    template.name.trim().isEmpty &&
        template.id == kMigratedStartingProgramTemplateId
    ? l10n.settingsProgramTemplatesMigratedName
    : template.name;
