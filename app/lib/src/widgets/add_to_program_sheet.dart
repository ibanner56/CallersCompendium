import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../utils/undo_snack_bar.dart';

/// Opens a modal bottom sheet listing existing (non-deleted) programs so the
/// user can append the dance identified by [danceId] as a new slot at the end
/// of one of them (`docs/design/ux.md` §2 add-to-program). Programs are ordered
/// most-recently-updated first. When there are no programs yet, a teaching
/// empty state offers to create a new program seeded with this dance.
///
/// Extracted from `DanceDetailScreen` so the Collection list's row action menu
/// ([DanceListTile]) and the detail screen share the exact same flow (identical
/// snackbars/keys), rather than duplicating the modal in two places.
///
/// The confirmation snackbar is shown on the [ScaffoldMessenger] resolved from
/// [context] (captured up-front so it survives the sheet closing — e.g. it
/// appears in the detail pane in split-pane mode).
Future<void> showAddToProgramSheet(
  BuildContext context, {
  required CompendiumRepositories repositories,
  required String danceId,
  required String danceTitle,
}) async {
  final programs = await repositories.programs.listAll();
  if (!context.mounted) return;
  programs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.7;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.commonAddToProgram,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              Expanded(
                child: programs.isEmpty
                    ? _buildEmptyPrograms(
                        sheetContext,
                        sheetContext,
                        repositories: repositories,
                        danceId: danceId,
                        danceTitle: danceTitle,
                        messenger: messenger,
                        l10n: l10n,
                      )
                    : ListView.builder(
                        itemCount: programs.length,
                        itemBuilder: (context, index) => _buildProgramPickRow(
                          context,
                          sheetContext,
                          programs[index],
                          repositories: repositories,
                          danceId: danceId,
                          danceTitle: danceTitle,
                          messenger: messenger,
                          accessibleNavigation: accessibleNavigation,
                          l10n: l10n,
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// One selectable program row: a single merged-semantics button exposing the
/// program's title, event date (if any), and slot count.
Widget _buildProgramPickRow(
  BuildContext context,
  BuildContext sheetContext,
  Program program, {
  required CompendiumRepositories repositories,
  required String danceId,
  required String danceTitle,
  required ScaffoldMessengerState messenger,
  required bool accessibleNavigation,
  required AppLocalizations l10n,
}) {
  final slotCount = program.slots.length;
  final dateLabel = program.eventDate == null
      ? null
      : formatEventDate(
          program.eventDate!,
          DateFormatScope.of(context),
          MaterialLocalizations.of(context),
          l10n,
        );
  final countLabel = l10n.collectionDanceCount(slotCount);
  final subtitleParts = [?dateLabel, countLabel];
  return MergeSemantics(
    child: Semantics(
      button: true,
      label: l10n.programsAddDanceToProgramSemantic(
        danceTitle,
        program.title,
        subtitleParts.join(', '),
      ),
      child: ListTile(
        key: ValueKey('program-pick-${program.id}'),
        title: ExcludeSemantics(child: Text(program.title)),
        subtitle: ExcludeSemantics(child: Text(subtitleParts.join(' · '))),
        onTap: () => _selectProgram(
          sheetContext,
          program,
          repositories: repositories,
          danceId: danceId,
          danceTitle: danceTitle,
          messenger: messenger,
          accessibleNavigation: accessibleNavigation,
          l10n: l10n,
        ),
      ),
    ),
  );
}

/// Teaching empty state shown when no programs exist yet, with an affordance
/// to create a brand-new program seeded with this dance.
Widget _buildEmptyPrograms(
  BuildContext context,
  BuildContext sheetContext, {
  required CompendiumRepositories repositories,
  required String danceId,
  required String danceTitle,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) {
  final theme = Theme.of(context);
  return ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 16),
      Text(
        l10n.programsEmptyTitle,
        key: const ValueKey('add-to-program-empty'),
        style: theme.textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        l10n.programsAddToProgramEmptyBody,
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      Center(
        child: FilledButton.icon(
          key: const ValueKey('add-to-program-create'),
          onPressed: () => _createProgramWith(
            sheetContext,
            repositories: repositories,
            danceId: danceId,
            danceTitle: danceTitle,
            messenger: messenger,
            l10n: l10n,
          ),
          icon: const Icon(Icons.add),
          label: Text(l10n.programsCreateWithDance),
        ),
      ),
    ],
  );
}

/// Appends this dance as a new slot at the end of [program], persists it,
/// closes the sheet, and confirms with an Undo snackbar that restores the
/// program's previous slot list (soft/undoable per project convention).
Future<void> _selectProgram(
  BuildContext sheetContext,
  Program program, {
  required CompendiumRepositories repositories,
  required String danceId,
  required String danceTitle,
  required ScaffoldMessengerState messenger,
  required bool accessibleNavigation,
  required AppLocalizations l10n,
}) async {
  // Re-load fresh so we append onto the latest persisted slot list.
  final fresh = await repositories.programs.getById(program.id);
  if (fresh == null) {
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    return;
  }
  final previousSlots = fresh.slots.toList();
  final now = DateTime.now().toUtc();
  final newSlot = ProgramSlot(
    id: uuidV4(),
    position: fresh.slots.length,
    danceId: danceId,
  );
  await repositories.programs.update(
    fresh.copyWith(slots: [...fresh.slots, newSlot], updatedAt: now),
  );
  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  showUndoSnackBar(
    messenger,
    key: const ValueKey('added-to-program-snackbar'),
    message: l10n.programsAddedToProgramSnack(danceTitle, fresh.title),
    undoLabel: l10n.commonUndo,
    accessibleNavigation: accessibleNavigation,
    onUndo: () async {
      final current = await repositories.programs.getById(fresh.id);
      if (current == null) return;
      await repositories.programs.update(
        current.copyWith(
          slots: previousSlots,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    },
  );
}

/// Creates a new draft program seeded with this dance as its only slot, then
/// closes the sheet and confirms with a snackbar. (No Undo: the new program
/// is itself the artifact and can be deleted from the programs list.)
Future<void> _createProgramWith(
  BuildContext sheetContext, {
  required CompendiumRepositories repositories,
  required String danceId,
  required String danceTitle,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) async {
  final now = DateTime.now().toUtc();
  final program = Program(
    id: uuidV4(),
    title: l10n.programsNewProgram,
    slots: [ProgramSlot(id: uuidV4(), position: 0, danceId: danceId)],
    createdAt: now,
    updatedAt: now,
  );
  await repositories.programs.create(program);
  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  messenger.showSnackBar(
    SnackBar(
      key: const ValueKey('created-program-snackbar'),
      content: Text(
        l10n.programsCreatedProgramSnack(program.title, danceTitle),
      ),
    ),
  );
}
