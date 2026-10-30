import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../editor/program_slot_rebase.dart';
import '../utils/undo_snack_bar.dart';
import 'add_to_program_list.dart';

/// Opens a modal bottom sheet listing existing (non-deleted) programs so the
/// user can append the dance identified by [danceId] as a new slot at the end
/// of one of them (`docs/design/ux.md` §2 add-to-program). A pinned first row
/// creates a new program seeded with this dance, in every state; when there are
/// no programs yet, a teaching empty state sits beneath it.
///
/// The programs are an [AddToProgramList]: open programs first, soonest event
/// first, Performed ones collapsed beneath, a status on each row and a search
/// field once the list is long (`docs/design/add-to-program-sheet.md`
/// §4.1–§4.2). A program that already holds the dance, as a primary or an
/// alternate ([Program.danceSlotCount]), shows an "In this program" marker, and
/// tapping it asks before adding the dance again (§4.3).
///
/// The sheet is sized from the height the screen has left once the on-screen
/// keyboard is up, so at normal text sizes the pinned row, the search field and
/// a few rows stay visible while the caller types. At large text sizes the title
/// and the pinned row scroll in place within 45% of the sheet, so the search
/// field and the list keep their room (§4.5, "As built").
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
  // Venue labels are resolved beside the rows, as on the Programs list, and the
  // search matches them. The catalogue is read only when a program links one;
  // the sheet reads once on open and does not follow later edits (§4.6).
  final venuesById = programs.any((p) => p.venueId != null)
      ? {for (final v in await repositories.venues.listAll()) v.id: v}
      : const <String, Venue>{};
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
  // Captured up-front, like the messenger above: this sheet pops before its
  // undo callback runs, so none of these can be resolved from a context by
  // then. A refresh notifier used to be captured here for the same reason and
  // no longer is — the undo is a write, and every view of it watches the
  // database (issue #768).
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // With the keyboard up the sheet may take all the height above it, which
    // would reach under the status bar or a notch without this.
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      // The route does not lift a sheet above the keyboard, so pad by its inset
      // and the sheet gets the height left above it, below the status bar
      // (`useSafeArea`). With the keyboard up the sheet takes all of that
      // rather than 70% of the screen, since 70% of what a 640 px phone has
      // left fits too little (§4.5); the padding is what bounds it.
      final keyboard = media.viewInsets.bottom;
      final maxHeight = keyboard > 0
          ? double.infinity
          : media.size.height * 0.7;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  // The title and the pinned New row, capped so that a large text
                  // scale with the keyboard up cannot push the list and search
                  // field out of the sheet: past the cap they scroll in place.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.45,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.commonAddToProgram,
                                style: Theme.of(
                                  sheetContext,
                                ).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          _buildCreateRow(
                            sheetContext,
                            repositories: repositories,
                            danceId: danceId,
                            danceTitle: danceTitle,
                            messenger: messenger,
                            l10n: l10n,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: programs.isEmpty
                        ? _buildEmptyPrograms(sheetContext, l10n: l10n)
                        : AddToProgramList(
                            programs: programs,
                            venuesById: venuesById,
                            danceId: danceId,
                            danceTitle: danceTitle,
                            onSelect: (program, heldCount) async {
                              if (heldCount > 0 &&
                                  !await _confirmAddAgain(
                                    sheetContext,
                                    danceTitle: danceTitle,
                                    programTitle: program.title,
                                    count: heldCount,
                                    l10n: l10n,
                                  )) {
                                return;
                              }
                              if (!sheetContext.mounted) return;
                              await _selectProgram(
                                sheetContext,
                                program,
                                repositories: repositories,
                                danceId: danceId,
                                danceTitle: danceTitle,
                                messenger: messenger,
                                accessibleNavigation: accessibleNavigation,
                                l10n: l10n,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The pinned first row, outside the scrolling list so it stays in reach with a
/// long list or the keyboard up at normal text sizes (N3-5; at large text it
/// scrolls in place with the title, see [showAddToProgramSheet]): creates a new program seeded with this
/// dance.
Widget _buildCreateRow(
  BuildContext sheetContext, {
  required CompendiumRepositories repositories,
  required String danceId,
  required String danceTitle,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) {
  return ListTile(
    key: const ValueKey('add-to-program-create'),
    leading: const Icon(Icons.add),
    title: Text(l10n.programsCreateWithDance),
    onTap: () => _createProgramWith(
      sheetContext,
      repositories: repositories,
      danceId: danceId,
      danceTitle: danceTitle,
      messenger: messenger,
      l10n: l10n,
    ),
  );
}

/// Teaching empty state shown when no programs exist yet, beneath the pinned
/// create row.
Widget _buildEmptyPrograms(
  BuildContext context, {
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
    ],
  );
}

/// Asks whether to add a dance a program already holds. **Add again** is the
/// primary button; **Cancel** (and a dismissal) returns false and leaves the
/// sheet open so the caller can pick another program. Adding a dance is
/// undoable, so this is a named exception to the confirm-only-without-Undo rule
/// (`docs/design/ux.md` §1), not a destructive confirm.
Future<bool> _confirmAddAgain(
  BuildContext sheetContext, {
  required String danceTitle,
  required String programTitle,
  required int count,
  required AppLocalizations l10n,
}) async {
  final again = await showDialog<bool>(
    context: sheetContext,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('add-again-dialog'),
      title: Text(l10n.programsAddAgainTitle),
      content: Text(l10n.programsAddAgainBody(danceTitle, programTitle, count)),
      actions: [
        TextButton(
          key: const ValueKey('add-again-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('add-again-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.programsAddAgain),
        ),
      ],
    ),
  );
  return again ?? false;
}

/// Appends this dance as a new slot at the end of [program], persists it,
/// closes the sheet, and confirms with an Undo snackbar that takes the added
/// slot back out (soft/undoable per project convention).
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
  final addedSlots = [...fresh.slots, newSlot];
  await repositories.programs.update(
    fresh.copyWith(slots: addedSlots, updatedAt: now),
  );
  // The dance's calling history and its "called N times" badge are both derived
  // from program slots (issue #768, gaps 1 and 2). Neither this write nor its
  // Undo broadcasts: both views watch `program_slots` directly, so the write is
  // the whole notification.
  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  showUndoSnackBar(
    messenger,
    key: const ValueKey('added-to-program-snackbar'),
    message: l10n.programsAddedToProgramSnack(danceTitle, fresh.title),
    undoLabel: l10n.commonUndo,
    undoFailedMessage: l10n.commonUndoFailed,
    accessibleNavigation: accessibleNavigation,
    // The prompt can stay up indefinitely with accessible navigation, so the
    // program may have been edited since (GIG-19). The Undo takes out only the
    // slot it added, and writes as a compare-and-replace against the program
    // it read, so an edit made in between, or landing during the Undo, is
    // kept rather than overwritten with the slot list from before the add.
    onUndo: () async {
      for (var attempt = 0; attempt < 5; attempt++) {
        final current = await repositories.programs.getById(fresh.id);
        if (current == null) return;
        final replaced = await repositories.programs.replaceIfUnchanged(
          expected: current,
          replacement: current.copyWith(
            slots: renumberSlots(
              rebaseSlotEdits(
                before: addedSlots,
                after: previousSlots,
                onto: current.slots,
              ),
            ),
          ),
          updatedAt: DateTime.now().toUtc(),
        );
        if (replaced) return;
      }
      // Reported by showUndoSnackBar as a failed Undo.
      throw StateError('program "${fresh.id}" kept changing during the Undo');
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
