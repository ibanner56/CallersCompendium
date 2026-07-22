import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/dialect_library_scope.dart';

/// A compact app-bar control for switching the active dialect mid-session
/// (`docs/design/ux.md` §6 — per-gig quick switching). Lists every dialect in
/// [DialectLibraryScope.of]'s library (shipped presets + custom) with the active
/// one checked, and calls [DialectLibraryController.setActive] on selection so
/// the whole app re-renders live through the existing `ActiveDialectScope`
/// bridge.
///
/// Factored into one widget so the dance-detail and perform screens share an
/// identical control. Read-only over the library; it never mutates dialect
/// contents, only which one is active.
class DialectQuickSwitch extends StatelessWidget {
  const DialectQuickSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DialectLibraryScope.maybeOf(context);
    // Optional affordance: render nothing outside a library-scoped tree (the
    // scope is always mounted in the running app via main.dart).
    if (controller == null) return const SizedBox.shrink();
    final active = controller.activeName ?? controller.active.name;
    final dialects = controller.all;

    return PopupMenuButton<String>(
      key: const ValueKey('dialect-quick-switch'),
      icon: const Icon(Icons.groups_outlined),
      tooltip: AppLocalizations.of(context).commonSwitchDialectTooltip,
      onSelected: (name) => controller.setActive(name),
      itemBuilder: (context) => [
        for (final dialect in dialects)
          CheckedPopupMenuItem<String>(
            key: ValueKey('dialect-quick-switch-${dialect.name}'),
            value: dialect.name,
            checked: dialect.name == active,
            child: Text(dialect.name),
          ),
      ],
    );
  }
}
