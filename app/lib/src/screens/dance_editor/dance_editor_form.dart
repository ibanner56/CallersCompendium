import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../models/dance_list_entry.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/figure_list_editor.dart';
import '../../widgets/section_header.dart';
import 'custom_field_editor.dart';
import 'dance_editor_controller.dart';
import 'editor_fields.dart';
import 'lingo_discouraged_hint.dart';
import 'links_editor.dart';
import 'name_picker.dart';
import 'source_citations_editor.dart';

/// The dance editor's scrolling metadata form. Presentational only: it reads
/// the working draft from [controller] and routes edits back through the
/// controller's mutation methods (which own undo/autosave), plus a handful of
/// shared-entity callbacks for the inline create/edit dialogs that the
/// coordinating [DanceEditorScreen] owns (it holds the reference-data caches
/// and a [BuildContext] for the dialogs).
class DanceEditorForm extends StatelessWidget {
  const DanceEditorForm({
    super.key,
    required this.controller,
    required this.formKey,
    required this.taxonomy,
    required this.moveParamDefaults,
    this.freeTextEntry = false,
    required this.dialect,
    required this.isNew,
    required this.authorOptions,
    required this.choreographerNames,
    required this.tagOptions,
    required this.tagNames,
    required this.publishedSources,
    required this.sourcesById,
    required this.danceOptions,
    required this.danceNamesById,
    required this.onAddAuthor,
    required this.onAddTag,
    required this.onAttachSource,
    required this.onCreateChoreographer,
    required this.onEditChoreographer,
    required this.onCreateSource,
    required this.onEditSource,
    required this.onCreateTag,
  });

  final DanceEditorController controller;
  final GlobalKey<FormState> formKey;
  final Taxonomy taxonomy;
  final Map<String, Map<String, Object?>> moveParamDefaults;

  /// Whether the opt-in "Free-text entry" toggle is on (#419). Forwarded to the
  /// figure list editor so adding a NEW figure opens a single free-text field
  /// instead of a blank structured draft. Editing existing figures is
  /// unaffected. Defaults to `false` (structured Add).
  final bool freeTextEntry;
  final Dialect dialect;
  final bool isNew;

  // Reference-data caches, owned + kept fresh by the coordinator.
  final List<NameOption> authorOptions;
  final Map<String, String> choreographerNames;
  final List<NameOption> tagOptions;
  final Map<String, String> tagNames;
  final List<PublishedSource> publishedSources;
  final Map<String, PublishedSource> sourcesById;
  final List<NameOption> danceOptions;
  final Map<String, String> danceNamesById;

  // Inline shared-entity flows (need the coordinator's context + `mounted`).
  final ValueChanged<String> onAddAuthor;
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onAttachSource;
  final Future<String> Function(String name) onCreateChoreographer;
  final ValueChanged<String> onEditChoreographer;
  final Future<String?> Function(String title) onCreateSource;
  final ValueChanged<String> onEditSource;
  final Future<String> Function(String name) onCreateTag;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        keyboardDismissBehavior: kTextEntryKeyboardDismiss,
        // Section headers carry their own padding; each section's content is
        // wrapped in horizontal AppSpacing.md so headers align with the fields
        // they label. A trailing gap keeps the last section off the bottom edge.
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          const SectionHeader(title: 'Details'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('title-field'),
                  controller: controller.titleController,
                  autofocus: isNew,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  onChanged: (_) => controller.onTextEdited(),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Title is required'
                      : null,
                ),
                LingoDiscouragedHint(
                  controller: controller.titleController,
                  dialect: dialect,
                  fieldKey: 'title',
                ),
                const SizedBox(height: AppSpacing.md),
                const FieldLabel('Authors'),
                NamePicker(
                  fieldKey: 'author',
                  selectedIds: controller.authorIds,
                  namesById: choreographerNames,
                  options: authorOptions,
                  onAdd: onAddAuthor,
                  onRemove: controller.removeAuthor,
                  onCreate: onCreateChoreographer,
                  onEdit: onEditChoreographer,
                ),
                const SizedBox(height: AppSpacing.md),
                const FieldLabel('Formation'),
                // Key includes the value so an undo/redo that changes
                // formationShape forces the DropdownButtonFormField to rebuild
                // with the new state.
                DropdownButtonFormField<FormationShape>(
                  key: ValueKey(
                    'formation-field-${controller.formationShape.name}',
                  ),
                  initialValue: controller.formationShape,
                  items: [
                    for (final shape in FormationShape.values)
                      DropdownMenuItem(
                        value: shape,
                        child: Text(formationShapeLabel(shape)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.setFormationShape(value);
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  key: const ValueKey('formation-detail-field'),
                  controller: controller.formationDetailController,
                  decoration: const InputDecoration(
                    labelText: 'Formation detail (optional)',
                  ),
                  onChanged: (_) => controller.onTextEdited(),
                ),
                LingoDiscouragedHint(
                  controller: controller.formationDetailController,
                  dialect: dialect,
                  fieldKey: 'formation-detail',
                ),
                const SizedBox(height: AppSpacing.md),
                // Progression and Rating share one line.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: EnumDropdown<Progression>(
                        fieldKey: 'progression',
                        label: 'Progression',
                        value: controller.progression,
                        values: Progression.values,
                        labelOf: progressionLabel,
                        onChanged: controller.setProgression,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: RatingField(
                        value: controller.rating,
                        onChanged: controller.setRating,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('phrase-field'),
                  controller: controller.phraseController,
                  decoration: const InputDecoration(
                    labelText: 'Phrase structure',
                    hintText: 'Blank = standard A1 A2 B1 B2; else e.g. 6*8*2',
                  ),
                  onChanged: (_) => controller.onPhraseChanged(),
                  validator: (value) {
                    try {
                      PhraseStructure.parse(value ?? '');
                      return null;
                    } on FormatException catch (e) {
                      return e.message;
                    }
                  },
                ),
                LingoDiscouragedHint(
                  controller: controller.phraseController,
                  dialect: dialect,
                  fieldKey: 'phrase',
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Figures'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Type a move (e.g. "sw" → swing) and press Enter to add it with '
                  'default params; unmatched text becomes a custom figure.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                FigureListEditor(
                  drafts: controller.figureDrafts,
                  taxonomy: taxonomy,
                  phraseStructure: controller.phraseStructure,
                  dialect: dialect,
                  moveParamDefaults: moveParamDefaults,
                  onChanged: controller.onFiguresChanged,
                  onAdd: controller.addFigure,
                  freeTextEntry: freeTextEntry,
                  onAddFreeText: controller.insertFreeTextFigures,
                  onDelete: controller.deleteFigure,
                  onDuplicate: controller.duplicateFigure,
                  onReorder: controller.reorderFigure,
                ),
                if (controller.warnings.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  WarningsCard(warnings: controller.warnings),
                ],
              ],
            ),
          ),
          const SectionHeader(title: 'Notes'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('notes-field'),
                  controller: controller.notesController,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Calling notes',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => controller.onTextEdited(),
                ),
                LingoDiscouragedHint(
                  controller: controller.notesController,
                  dialect: dialect,
                  fieldKey: 'notes',
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('hook-field'),
                  controller: controller.hookController,
                  decoration: const InputDecoration(
                    labelText: 'Hook',
                    hintText: 'One-line "why call this"',
                  ),
                  onChanged: (_) => controller.onTextEdited(),
                ),
                LingoDiscouragedHint(
                  controller: controller.hookController,
                  dialect: dialect,
                  fieldKey: 'hook',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _buildMoreDetails(context),
          ),
        ],
      ),
    );
  }

  /// The collapsible "More details" drawer (Tier 2). Holds the less-frequently
  /// used metadata; collapsed by default so the always-visible Tier 1 fields
  /// stay above the fold. While collapsed the children are removed from the
  /// tree (the default `ExpansionTile` behavior); no edits are lost because
  /// every value lives in the [DanceEditorController] — text controllers,
  /// links, custom values, and the enum/date fields — and is re-seeded into the
  /// child widgets when the section is expanded again.
  Widget _buildMoreDetails(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sectionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: colorScheme.outlineVariant),
    );
    return ExpansionTile(
      key: const ValueKey('more-details-tile'),
      leading: Icon(Icons.tune, color: colorScheme.primary),
      title: Text(
        'More details',
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      initiallyExpanded: false,
      backgroundColor: colorScheme.surfaceContainerHighest,
      collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
      shape: sectionShape,
      collapsedShape: sectionShape,
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnumDropdown<DanceStatus>(
          fieldKey: 'status',
          label: 'Status',
          value: controller.status,
          values: DanceStatus.values,
          labelOf: danceStatusLabel,
          onChanged: controller.setStatus,
        ),
        const SizedBox(height: AppSpacing.md),
        LevelDropdown(value: controller.level, onChanged: controller.setLevel),
        const SizedBox(height: AppSpacing.xs),
        CheckboxListTile(
          key: const ValueKey('mixed-level-field'),
          value: controller.mixedLevel,
          onChanged: (v) => controller.setMixedLevel(v ?? false),
          title: const Text('Mixed level'),
          subtitle: const Text('Spans the difficulty scale'),
          secondary: const Icon(Icons.swap_vert),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        PartialDateField(
          fieldKey: 'composed-on',
          label: 'Composed',
          helperText: 'When the dance was composed (year, or add month/day)',
          value: controller.composedOn,
          onChanged: controller.setComposedOn,
        ),
        const SizedBox(height: AppSpacing.md),
        PartialDateField(
          fieldKey: 'revised-on',
          label: 'Revised',
          helperText: 'When the dance was last revised by its author',
          value: controller.revisedOn,
          onChanged: controller.setRevisedOn,
        ),
        const SizedBox(height: AppSpacing.md),
        const FieldLabel('Tags'),
        NamePicker(
          fieldKey: 'tag',
          selectedIds: controller.tagIds,
          namesById: tagNames,
          options: tagOptions,
          onAdd: onAddTag,
          onRemove: controller.removeTag,
          onCreate: onCreateTag,
        ),
        const SizedBox(height: AppSpacing.md),
        const FieldLabel('Tunes'),
        TuneEditor(
          tunes: controller.tunes,
          controller: controller.tuneController,
          onAdd: controller.addTune,
          onRemove: controller.removeTune,
        ),
        LingoDiscouragedHint(
          controller: controller.tuneController,
          dialect: dialect,
          fieldKey: 'tune',
        ),
        const SizedBox(height: AppSpacing.md),
        const FieldLabel('Links'),
        LinksEditor(
          links: controller.links,
          onAdd: controller.addLink,
          onRemove: controller.removeLink,
          onChanged: controller.onLinksChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        const FieldLabel('Published sources'),
        SourceCitationsEditor(
          citations: controller.sourceCitations,
          sourcesById: sourcesById,
          sourceOptions: publishedSources,
          onAttach: onAttachSource,
          onCreate: onCreateSource,
          onEditSource: onEditSource,
          onRemove: controller.removeSourceCitation,
          onChanged: controller.onSourceCitationsChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        const FieldLabel('Related dances'),
        RelatedDancesEditor(
          links: controller.links,
          danceOptions: danceOptions,
          danceNamesById: danceNamesById,
          onAdd: controller.addRelatedDance,
          onRemove: controller.removeLink,
          onChanged: controller.onLinksChanged,
        ),
        if (controller.fieldDefs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const FieldLabel('Custom fields'),
          for (final def in controller.fieldDefs)
            CustomFieldEditor(
              def: def,
              dialect: dialect,
              textController: controller.customTextControllers[def.id],
              currentValue: controller.customValues[def.id],
              onTextChanged: controller.onTextEdited,
              onValueChanged: (v) => controller.setCustomValue(def.id, v),
            ),
        ],
      ],
    );
  }
}
