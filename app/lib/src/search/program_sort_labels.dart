import '../../l10n/app_localizations.dart';
import 'program_sort.dart';

/// Localized label for a [ProgramSort] option shown in the Programs list sort
/// menu and the Settings ▸ Defaults picker (issue #895). Mirrors the L2
/// `collection_query_labels.dart` pattern so the display text is translatable
/// without baking a locale into the enum.
String programSortLabel(AppLocalizations l10n, ProgramSort sort) =>
    switch (sort) {
      ProgramSort.title => l10n.programsSortTitle,
      ProgramSort.recentlyUpdated => l10n.programsSortRecentlyUpdated,
      ProgramSort.eventDate => l10n.programsSortEventDate,
    };
