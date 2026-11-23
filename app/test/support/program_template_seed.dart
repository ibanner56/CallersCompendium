import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_core/compendium_core.dart';

/// The text of the one slot [seedDefaultProgramTemplate]'s template holds, so
/// a test can say a program did not take it.
const String kSeededTemplateSlotText = 'From the default template';

/// Makes a Default template with one text slot, [kSeededTemplateSlotText],
/// for tests that show a creation path keeps its own slots (#2337).
Future<void> seedDefaultProgramTemplate(CompendiumRepositories repos) async {
  await saveProgramTemplate(
    repos.settings,
    const ProgramTemplate(
      id: 'seeded',
      name: 'Seeded',
      entries: [ProgramTemplateEntry(text: kSeededTemplateSlotText)],
    ),
  );
  await saveProgramTemplateOrder(repos.settings, const ['seeded']);
  await saveProgramTemplateDefault(repos.settings, 'seeded');
}

/// Whether any slot of [program] came from the seeded template.
bool hasSeededTemplateSlot(Program program) =>
    program.slots.any((slot) => slot.text == kSeededTemplateSlotText);
