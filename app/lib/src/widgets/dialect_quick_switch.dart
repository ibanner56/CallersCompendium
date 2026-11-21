import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/dialect_library_scope.dart';

/// A compact app-bar control for switching the active dialect of one dance
/// form mid-session (`docs/design/ux.md` §6 — per-gig quick switching). Lists
/// every dialect in [form]'s library (shipped presets + custom) with the
/// active one checked, and calls [DialectLibraryController.setActive] on
/// selection so every dance of that form re-renders live through the
/// `ActiveDialectScope` bridge. Each form has its own dialects (ADR-006 §9.1,
/// point 1), so the control offers those of the dance on screen.
///
/// Factored into one widget so the dance-detail and perform screens share an
/// identical control. Read-only over the library; it never mutates dialect
/// contents, only which one is active.
///
/// **Session-local mode.** Pass both [selectedName] and [onSelected] and the
/// control no longer touches the application dialect: the checkmark follows
/// [selectedName] and a selection is reported through [onSelected] instead of
/// [DialectLibraryController.setActive]. Program Perform uses this while the
/// program has its own dialect, so a mid-performance switch stays inside that
/// Perform session (issue #1554). With neither, behaviour is unchanged.
class DialectQuickSwitch extends StatelessWidget {
  const DialectQuickSwitch({
    super.key,
    required this.form,
    this.selectedName,
    this.onSelected,
  }) : assert(
         (selectedName == null) == (onSelected == null),
         'selectedName and onSelected must be given together',
       );

  /// The dance form whose dialects are offered.
  final DanceForm form;

  /// The checked dialect name in session-local mode; `null` otherwise.
  final String? selectedName;

  /// Receives the chosen dialect name in session-local mode; `null` otherwise.
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final controller = DialectLibraryScope.maybeOf(context)?.forForm(form);
    // Optional affordance: render nothing outside a library-scoped tree (the
    // scope is always mounted in the running app via main.dart).
    if (controller == null) return const SizedBox.shrink();
    final active =
        selectedName ?? controller.activeName ?? controller.active.name;
    final sessionLocal = onSelected;
    final dialects = controller.all;

    return PopupMenuButton<String>(
      key: const ValueKey('dialect-quick-switch'),
      icon: const Icon(Icons.groups_outlined),
      tooltip: AppLocalizations.of(context).commonSwitchDialectTooltip,
      onSelected: (name) => sessionLocal != null
          ? sessionLocal(name)
          : controller.setActive(name),
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
