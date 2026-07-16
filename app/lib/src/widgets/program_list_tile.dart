import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import 'program_status_chip.dart';

/// One Programs list row: title, event date, venue, slot count, and a status
/// chip (icon+text). Tapping calls [onTap]; [selected] highlights the row in
/// split-pane mode. Mirrors `DanceListTile` (`docs/design/ux.md` §4).
class ProgramListTile extends StatelessWidget {
  const ProgramListTile({
    super.key,
    required this.program,
    this.onTap,
    this.selected = false,
  });

  final Program program;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slotCount = program.slots.length;
    final eventDate = program.eventDate;
    final dateLabel = eventDate == null
        ? null
        : formatEventDate(
            eventDate,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
          );

    final venue = program.venue?.trim();
    final subtitleParts = <String>[
      ?dateLabel,
      if (venue != null && venue.isNotEmpty) venue,
      '$slotCount ${slotCount == 1 ? 'slot' : 'slots'}',
    ];

    return ListTile(
      selected: selected,
      title: Text(program.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitleParts.join(' · '), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            ProgramStatusChip(status: program.status),
          ],
        ),
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }
}
