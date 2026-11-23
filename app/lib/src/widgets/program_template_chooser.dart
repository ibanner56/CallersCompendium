import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/program_templates.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../theme/app_motion.dart';
import 'program_template_name.dart';

/// Asks which program template a new program starts from, when there is a
/// choice to make (#2337).
///
/// With two or more templates it shows a short sheet: the templates in the
/// user's order with the Default template first and marked, and Blank
/// program (first and marked when it is the default, else last). With one
/// template or none it asks nothing and returns
/// [ProgramTemplateChoice.useDefault], so New program opens the builder
/// directly, as it did with the single Starting program. Returns `null` when
/// the sheet is dismissed, which cancels New program.
///
/// A failure to read the templates is logged and answered with the default,
/// so New program still opens.
Future<ProgramTemplateChoice?> chooseProgramTemplate(
  BuildContext context,
) async {
  final repos = RepositoriesScope.of(context);
  final ProgramTemplates templates;
  try {
    templates = await loadProgramTemplates(repos.settings);
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'program_template_chooser.load');
    return const ProgramTemplateChoice.useDefault();
  }
  if (templates.templates.length < 2) {
    return const ProgramTemplateChoice.useDefault();
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<ProgramTemplateChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    sheetAnimationStyle: AppMotion.styleFor(context),
    builder: (sheetContext) =>
        ProgramTemplateChooserSheet(templates: templates),
  );
}

/// The New program chooser's sheet body. Pops the chosen
/// [ProgramTemplateChoice].
class ProgramTemplateChooserSheet extends StatelessWidget {
  const ProgramTemplateChooserSheet({super.key, required this.templates});

  final ProgramTemplates templates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final defaultId = templates.defaultId;
    final blank = ListTile(
      key: const ValueKey('program-template-choice-blank'),
      leading: const Icon(Icons.note_add_outlined),
      title: Text(l10n.programTemplateBlankProgram),
      subtitle: defaultId == null
          ? Text(l10n.programTemplateDefaultBadge)
          : null,
      onTap: () =>
          Navigator.of(context).pop(const ProgramTemplateChoice.blank()),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          key: const ValueKey('program-template-chooser'),
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.programTemplateChooserTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // The default comes first: Blank program when it is the default.
            if (defaultId == null) blank,
            for (final template in templates.defaultFirst)
              ListTile(
                key: ValueKey('program-template-choice-${template.id}'),
                leading: const Icon(Icons.article_outlined),
                title: Text(programTemplateDisplayName(l10n, template)),
                subtitle: template.id == defaultId
                    ? Text(l10n.programTemplateDefaultBadge)
                    : null,
                onTap: () => Navigator.of(
                  context,
                ).pop(ProgramTemplateChoice.template(template.id)),
              ),
            if (defaultId != null) blank,
          ],
        ),
      ),
    );
  }
}
