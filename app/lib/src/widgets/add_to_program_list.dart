import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../data/venue_label.dart';
import 'program_status_chip.dart';

/// The program count above which [AddToProgramList] shows its search field
/// (`docs/design/add-to-program-sheet.md` §4.1: "above about 8"). At roughly
/// 56 px a row, about eight rows fit on a phone beside the pinned New row and a
/// title bar, so a shorter list has little to search. A UI tuning value, not a
/// data rule.
const kAddToProgramSearchThreshold = 8;

/// The programs an add-to-program list offers, split into the two groups it
/// shows (`docs/design/add-to-program-sheet.md` §4.2).
typedef AddToProgramGroups = ({List<Program> open, List<Program> performed});

/// Splits [programs] into the open group and the Performed group, each in the
/// order the sheet shows it.
///
/// * **Open** (Draft and Finalized): programs dated [today] or later first,
///   soonest at the top; then everything else (undated, or dated earlier and not
///   Performed) by `updatedAt`, newest first (N3-2).
/// * **Performed:** event date newest first, then undated programs by
///   `updatedAt`, newest first. The most recent gig is the likeliest
///   forgotten-dance target.
///
/// Status is the grouping signal because it is the only one the user sets;
/// `eventDate` is optional and date-only, so "before today" depends on the
/// device's day (§4.2, option D, rejected). [today] is a local calendar day;
/// only its year, month and day are read.
AddToProgramGroups groupProgramsForAdd(
  Iterable<Program> programs, {
  required DateTime today,
}) {
  final todayKey = _dayKey(today);
  final open = <Program>[];
  final performed = <Program>[];
  for (final program in programs) {
    (program.status == ProgramStatus.performed ? performed : open).add(program);
  }
  int newestEdit(Program a, Program b) {
    final byEdit = b.updatedAt.compareTo(a.updatedAt);
    return byEdit != 0 ? byEdit : a.id.compareTo(b.id);
  }

  bool upcoming(Program p) =>
      p.eventDate != null && _dayKey(p.eventDate!) >= todayKey;
  open.sort((a, b) {
    final aUpcoming = upcoming(a);
    if (aUpcoming != upcoming(b)) return aUpcoming ? -1 : 1;
    if (aUpcoming) {
      final byDate = _dayKey(a.eventDate!).compareTo(_dayKey(b.eventDate!));
      if (byDate != 0) return byDate;
    }
    return newestEdit(a, b);
  });
  performed.sort((a, b) {
    final aDated = a.eventDate != null;
    if (aDated != (b.eventDate != null)) return aDated ? -1 : 1;
    if (aDated) {
      final byDate = _dayKey(b.eventDate!).compareTo(_dayKey(a.eventDate!));
      if (byDate != 0) return byDate;
    }
    return newestEdit(a, b);
  });
  return (open: open, performed: performed);
}

/// A sortable key for a calendar day. Event dates are stored date-only, so the
/// date's own year, month and day are the day, whatever zone the value carries.
int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// The programs a search [query] keeps: those whose title or resolved venue
/// label contains it, folded with [foldForTitleMatch] so "ecole" finds "École".
///
/// The same folding the command palette uses on program titles, so the sheet
/// adds no further matcher. A blank query keeps everything. Match rank is not
/// used: with a handful of matches the grouped order is more useful than
/// "exact first" (§4.1).
List<Program> filterProgramsForAdd(
  List<Program> programs,
  String query, {
  required Map<String, Venue> venuesById,
}) {
  final needle = foldForTitleMatch(query.trim());
  if (needle.isEmpty) return programs;
  return [
    for (final program in programs)
      if (foldForTitleMatch(program.title).contains(needle) ||
          foldForTitleMatch(resolveVenueLabel(program, venuesById) ?? '')
              .contains(needle))
        program,
  ];
}

/// The scrolling program list of the add-to-program sheet: grouped (open first,
/// Performed collapsed beneath), searchable above [kAddToProgramSearchThreshold]
/// programs, with a status on every row and an "In this program" marker for
/// programs that already hold the dance
/// (`docs/design/add-to-program-sheet.md` §4.1–§4.3).
///
/// It is the part of the sheet the batch version reuses (§4.8), so it knows
/// nothing about what a tap does: [onSelect] gets the program and how many slots
/// already hold the dance, and the caller decides whether to ask, add or
/// something else. The pinned "New program" row and the empty state stay with
/// the caller, outside this widget.
///
/// The search query and whether the Performed group is expanded are session
/// state: they live in this widget's `State` and are never persisted (§4.6).
class AddToProgramList extends StatefulWidget {
  const AddToProgramList({
    super.key,
    required this.programs,
    required this.venuesById,
    required this.danceId,
    required this.danceTitle,
    required this.onSelect,
    this.today,
  });

  /// Every program the sheet may add to, in any order; the widget orders them.
  final List<Program> programs;

  /// Linked venues by id, to resolve each row's venue label and to match a
  /// search against it. A program with no linked venue falls back to its
  /// free-text venue, so an empty map is valid.
  final Map<String, Venue> venuesById;

  /// The dance whose presence marks a row ([Program.danceSlotCount]).
  final String danceId;

  /// The dance's title, for each row's accessible label.
  final String danceTitle;

  /// Called when a row is tapped, with the program and the number of slots that
  /// already hold [danceId] (0 when none).
  final Future<void> Function(Program program, int heldCount) onSelect;

  /// The current local day, for the "dated today or later" split. Defaults to
  /// the device clock; tests pass a fixed day.
  final DateTime? today;

  @override
  State<AddToProgramList> createState() => _AddToProgramListState();
}

class _AddToProgramListState extends State<AddToProgramList> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Whether the user has flipped the Performed group from its default. The
  /// default is collapsed, except when there is nothing open to show (see
  /// [build]); a new query resets the flip so a search is judged afresh.
  bool _performedFlipped = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = groupProgramsForAdd(
      widget.programs,
      today: widget.today ?? DateTime.now(),
    );
    final open = filterProgramsForAdd(
      groups.open,
      _query,
      venuesById: widget.venuesById,
    );
    final performed = filterProgramsForAdd(
      groups.performed,
      _query,
      venuesById: widget.venuesById,
    );
    // Auto-expand when nothing open is showing: no open program at all, or a
    // search that matches only Performed ones. A caller searching by name must
    // not be told "no results" while a match sits in a collapsed group (§4.2).
    final autoExpand = open.isEmpty;
    final expanded = autoExpand != _performedFlipped;
    final showSearch = widget.programs.length > kAddToProgramSearchThreshold;
    final noMatches = open.isEmpty && performed.isEmpty;

    return Column(
      children: [
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const ValueKey('add-to-program-search'),
              controller: _searchController,
              // No autofocus: on a phone the keyboard would cover the list the
              // caller came to see (§4.1).
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.programsAddToProgramSearchHint,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('add-to-program-search-clear'),
                        icon: const Icon(Icons.clear),
                        tooltip: l10n.programsAddToProgramSearchClear,
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                      ),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              if (noMatches)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.programsAddToProgramNoMatches,
                    key: const ValueKey('add-to-program-no-matches'),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final program in open) _buildRow(context, program, l10n),
              if (performed.isNotEmpty) ...[
                _buildPerformedToggle(
                  context,
                  count: performed.length,
                  expanded: expanded,
                  l10n: l10n,
                ),
                if (expanded)
                  for (final program in performed)
                    _buildRow(context, program, l10n),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _performedFlipped = false;
    });
  }

  Widget _buildPerformedToggle(
    BuildContext context, {
    required int count,
    required bool expanded,
    required AppLocalizations l10n,
  }) {
    final status = programStatusPresentation(ProgramStatus.performed, l10n);
    return Semantics(
      expanded: expanded,
      child: ListTile(
        key: const ValueKey('add-to-program-performed-toggle'),
        leading: Icon(status.icon),
        title: Text(l10n.programsAddToProgramPerformedGroup(count)),
        trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
        onTap: () => setState(() => _performedFlipped = !_performedFlipped),
      ),
    );
  }

  /// One selectable program row: a single merged-semantics button exposing the
  /// program's title, status, event date (if any), venue (if any), planned
  /// dance count and, when it holds the dance, the marker.
  Widget _buildRow(
    BuildContext context,
    Program program,
    AppLocalizations l10n,
  ) {
    final status = programStatusPresentation(program.status, l10n);
    final dateLabel = program.eventDate == null
        ? null
        : formatEventDate(
            program.eventDate!,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
            l10n,
          );
    // The venue is shown because search matches it: a row that appears for text
    // it does not display looks like a wrong result.
    final venueLabel = resolveVenueLabel(program, widget.venuesById);
    final countLabel = l10n.programsDanceCount(program.plannedDanceCount);
    final heldCount = program.danceSlotCount(widget.danceId);
    final heldLabel = heldCount == 0
        ? null
        : heldCount == 1
        ? l10n.programsDanceInThisProgram
        : l10n.programsDanceInThisProgramCount(heldCount);
    final details = [
      status.label,
      ?dateLabel,
      ?venueLabel,
      countLabel,
      ?heldLabel,
    ];
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: l10n.programsAddDanceToProgramSemantic(
          widget.danceTitle,
          program.title,
          details.join(', '),
        ),
        child: ListTile(
          key: ValueKey('program-pick-${program.id}'),
          // Shape as well as words (WCAG 1.4.1): the status label in the
          // subtitle is the text half of this icon.
          leading: ExcludeSemantics(
            child: Icon(
              status.icon,
              color: programStatusColor(program.status, Theme.of(context)),
            ),
          ),
          title: ExcludeSemantics(child: Text(program.title)),
          subtitle: ExcludeSemantics(
            child: Text(
              details.join(' · '),
              key: heldLabel == null
                  ? null
                  : ValueKey('program-pick-held-${program.id}'),
            ),
          ),
          // Shape as well as words, like the builder picker's in-program icon.
          trailing: heldLabel == null
              ? null
              : const ExcludeSemantics(child: Icon(Icons.check_circle_outline)),
          onTap: () => widget.onSelect(program, heldCount),
        ),
      ),
    );
  }
}
