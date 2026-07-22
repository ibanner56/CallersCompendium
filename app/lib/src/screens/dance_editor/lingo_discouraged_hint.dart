import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/lingo_text_editing_controller.dart';

/// Live, accessible "Discouraged: `<terms>`" affordance shown beneath a lingo
/// prose field. The visual strikethrough drawn by [LingoTextEditingController]
/// is a color/decoration-only cue, so this text (and its [Semantics] label)
/// gives an equivalent non-visual signal — mirroring the figure editor's note
/// field. Renders nothing when the active dialect flags no terms. Rebuilds on
/// each keystroke via the controller and on dialect change via its parent.
class LingoDiscouragedHint extends StatelessWidget {
  const LingoDiscouragedHint({
    super.key,
    required this.controller,
    required this.dialect,
    required this.fieldKey,
  });

  final LingoTextEditingController controller;
  final Dialect dialect;
  final String fieldKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final discouraged = canonicalize(controller.text, dialect).discouraged;
        if (discouraged.isEmpty) return const SizedBox.shrink();
        final hint = discouraged.map((s) => s.text).toSet().join(', ');
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          // intentional: 2px optical inset, below the 4px AppSpacing grid
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Icon(Icons.warning_outlined, size: 13, color: scheme.error),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Semantics(
                  label: l10n.danceEditorDiscouragedTermSemantic(hint),
                  child: Text(
                    l10n.danceEditorDiscouragedTermText(hint),
                    key: ValueKey('$fieldKey-lingo-hint'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
