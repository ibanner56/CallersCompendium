import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

/// Icon + text label for a [ProgramStatus]. Pairs an icon with text so status
/// is never conveyed by color alone (`docs/research/accessibility-baseline.md`,
/// `docs/design/ux.md` cross-cutting rule).
({IconData icon, String label}) programStatusPresentation(
  ProgramStatus status,
) => switch (status) {
  ProgramStatus.draft => (icon: Icons.edit_note_outlined, label: 'Draft'),
  ProgramStatus.finalized => (
    icon: Icons.check_circle_outline,
    label: 'Finalized',
  ),
  ProgramStatus.performed => (
    icon: Icons.event_available_outlined,
    label: 'Performed',
  ),
};

/// Compact status chip for a program (icon + text).
class ProgramStatusChip extends StatelessWidget {
  const ProgramStatusChip({super.key, required this.status});

  final ProgramStatus status;

  @override
  Widget build(BuildContext context) {
    final p = programStatusPresentation(status);
    return Chip(
      avatar: Icon(p.icon, size: 16),
      label: Text(p.label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
