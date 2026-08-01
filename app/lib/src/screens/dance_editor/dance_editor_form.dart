import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/validation_issue_labels.dart';
import '../../data/walkthrough_snippet_library_controller.dart';
import '../../data/walkthrough_snippet_library_scope.dart';
import '../../editor/figure_draft.dart';
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
    this.shorthandMappings,
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

  /// User-defined shorthand → figure(s) mappings (#420) forwarded to the figure
  /// list editor so a free-text line matching a shorthand expands to the mapped
  /// figures. `null` disables shorthand expansion. Only relevant when
  /// [freeTextEntry] is on.
  final ShorthandMappings? shorthandMappings;
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
    final l10n = AppLocalizations.of(context);
    // Personal walkthrough-snippet library (#411), if scoped in. `maybeOf`
    // registers a rebuild dependency so learned/edited snippets re-render live.
    final snippetLib = WalkthroughSnippetLibraryScope.maybeOf(context);
    return Form(
      key: formKey,
      child: ListView(
        keyboardDismissBehavior: kTextEntryKeyboardDismiss,
        // Section headers carry their own padding; each section's content is
        // wrapped in horizontal AppSpacing.md so headers align with the fields
        // they label. A trailing gap keeps the last section off the bottom edge.
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          SectionHeader(title: l10n.danceEditorDetailsSection),
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
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorTitleRequiredLabel,
                  ),
                  onChanged: (_) => controller.onTextEdited(),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.danceEditorTitleRequired
                      : null,
                ),
                LingoDiscouragedHint(
                  controller: controller.titleController,
                  dialect: dialect,
                  fieldKey: 'title',
                ),
                const SizedBox(height: AppSpacing.md),
                FieldLabel(l10n.danceEditorAuthorsLabel),
                NamePicker(
                  fieldKey: 'author',
                  selectedIds: controller.authorIds,
                  namesById: choreographerNames,
                  options: authorOptions,
                  onAdd: onAddAuthor,
                  onRemove: controller.removeAuthor,
                  onCreate: onCreateChoreographer,
                  onEdit: onEditChoreographer,
                  sheetSemanticLabel: l10n.danceEditorAuthorsLabel,
                ),
                const SizedBox(height: AppSpacing.md),
                FieldLabel(l10n.danceEditorFormationLabel),
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
                        child: Text(formationShapeLabel(l10n, shape)),
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
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorFormationDetailLabel,
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
                        label: l10n.commonProgression,
                        value: controller.progression,
                        values: Progression.values,
                        labelOf: (value) => progressionLabel(l10n, value),
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
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorPhraseStructureLabel,
                    hintText: l10n.danceEditorPhraseStructureHint,
                  ),
                  onChanged: (_) => controller.onPhraseChanged(),
                  validator: (value) {
                    try {
                      PhraseStructure.parse(value ?? '');
                      return null;
                    } on FormatException catch (e) {
                      return phraseStructureErrorMessage(l10n, e);
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
          SectionHeader(title: l10n.danceEditorFiguresSection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.danceEditorFiguresHelp,
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
                  shorthandMappings: shorthandMappings,
                  onAddFreeText: controller.insertFreeTextFigures,
                  onDelete: controller.deleteFigure,
                  onDuplicate: controller.duplicateFigure,
                  onReorder: controller.reorderFigure,
                  onGroupWithNext: controller.groupFigureWithNext,
                  onCollapseMeanwhileGroup: controller.collapseMeanwhileGroup,
                  snippetLibraryDefaultFor: snippetLib == null
                      ? null
                      : (draft) {
                          final figure = draft.toFigure();
                          if (figure == null) return null;
                          return snippetLib.resolve(
                            figureSnippetSignature(figure, taxonomy),
                          );
                        },
                  onSnippetCommitted: snippetLib == null
                      ? null
                      : (draft) => _handleWalkthroughSnippetCommit(
                          context,
                          draft,
                          controller,
                          taxonomy,
                          snippetLib,
                        ),
                ),
                if (controller.warnings.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  WarningsCard(warnings: controller.warnings),
                ],
              ],
            ),
          ),
          SectionHeader(title: l10n.danceEditorNotesSection),
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
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorCallingNotesLabel,
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
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorHookLabel,
                    hintText: l10n.danceEditorHookHint,
                  ),
                  onChanged: (_) => controller.onTextEdited(),
                ),
                LingoDiscouragedHint(
                  controller: controller.hookController,
                  dialect: dialect,
                  fieldKey: 'hook',
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('walkthrough-field'),
                  controller: controller.walkthroughController,
                  minLines: 4,
                  maxLines: 12,
                  maxLength: kMaxWalkthroughLength,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorWalkthroughLabel,
                    helperText: l10n.danceEditorWalkthroughHelper,
                    helperMaxLines: 2,
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => controller.onTextEdited(),
                ),
                LingoDiscouragedHint(
                  controller: controller.walkthroughController,
                  dialect: dialect,
                  fieldKey: 'walkthrough',
                ),
                if (snippetLib != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('fill-walkthrough-from-snippets'),
                      onPressed: () => _fillWalkthroughFromSnippets(
                        context,
                        controller,
                        taxonomy,
                        snippetLib,
                      ),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text(l10n.danceEditorFillWalkthroughFromSnippets),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
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
    final l10n = AppLocalizations.of(context);
    final sectionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: colorScheme.outlineVariant),
    );
    return ExpansionTile(
      key: const ValueKey('more-details-tile'),
      leading: Icon(Icons.tune, color: colorScheme.primary),
      title: Text(
        l10n.danceEditorMoreDetailsTitle,
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
          label: l10n.danceEditorStatusLabel,
          value: controller.status,
          values: DanceStatus.values,
          labelOf: (value) => danceStatusLabel(l10n, value),
          onChanged: controller.setStatus,
        ),
        const SizedBox(height: AppSpacing.md),
        LevelDropdown(value: controller.level, onChanged: controller.setLevel),
        const SizedBox(height: AppSpacing.xs),
        CheckboxListTile(
          key: const ValueKey('mixed-level-field'),
          value: controller.mixedLevel,
          onChanged: (v) => controller.setMixedLevel(v ?? false),
          title: Text(l10n.commonMixedLevel),
          subtitle: Text(l10n.danceEditorMixedLevelSubtitle),
          secondary: const Icon(Icons.swap_vert),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        PartialDateField(
          fieldKey: 'composed-on',
          label: l10n.danceEditorComposedLabel,
          helperText: l10n.danceEditorComposedHelper,
          value: controller.composedOn,
          onChanged: controller.setComposedOn,
        ),
        const SizedBox(height: AppSpacing.md),
        PartialDateField(
          fieldKey: 'revised-on',
          label: l10n.danceEditorRevisedLabel,
          helperText: l10n.danceEditorRevisedHelper,
          value: controller.revisedOn,
          onChanged: controller.setRevisedOn,
        ),
        const SizedBox(height: AppSpacing.md),
        FieldLabel(l10n.danceEditorTagsLabel),
        NamePicker(
          fieldKey: 'tag',
          selectedIds: controller.tagIds,
          namesById: tagNames,
          options: tagOptions,
          onAdd: onAddTag,
          onRemove: controller.removeTag,
          onCreate: onCreateTag,
          sheetSemanticLabel: l10n.danceEditorTagsLabel,
        ),
        const SizedBox(height: AppSpacing.md),
        FieldLabel(l10n.danceEditorTunesLabel),
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
        FieldLabel(l10n.danceEditorLinksLabel),
        LinksEditor(
          links: controller.links,
          onAdd: controller.addLink,
          onRemove: controller.removeLink,
          onChanged: controller.onLinksChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        FieldLabel(l10n.danceEditorPublishedSourcesLabel),
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
        FieldLabel(l10n.danceEditorRelatedDancesLabel),
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
          FieldLabel(l10n.danceEditorCustomFieldsLabel),
          for (final def in controller.fieldDefs)
            CustomFieldEditor(
              def: def,
              dialect: dialect,
              textController: controller.customTextControllers[def.id],
              currentValue: controller.customValues[def.id],
              onTextChanged: controller.onTextEdited,
              onValueChanged: (v) => controller.setCustomValue(def.id, v),
              onAddOption: def.type == CustomFieldType.choice
                  ? (raw) => controller.addChoiceOption(def.id, raw)
                  : null,
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Walkthrough snippet flow (#411)
// ---------------------------------------------------------------------------

/// Resolves a committed per-figure walkthrough snippet edit against the global
/// snippet library (#411), implementing the owner-locked flow:
///
/// - **Custom / unknown figure** (no signature): kept as a per-dance override.
/// - **Cleared text**: drops the per-dance override (the library default, if
///   any, still applies).
/// - **Learn-on-first-entry** (no saved default): the text becomes this
///   figure's default; no override is stored.
/// - **Matches the saved default**: no override, no prompt.
/// - **Differs from the saved default**: prompts the user to *use everywhere*
///   (update the global default) or keep it *just this dance* (a per-dance
///   override). A dismissed prompt keeps it local — the shared default is never
///   silently overwritten.
Future<void> _handleWalkthroughSnippetCommit(
  BuildContext context,
  FigureDraft draft,
  DanceEditorController controller,
  Taxonomy taxonomy,
  WalkthroughSnippetLibraryController snippetLib,
) async {
  final figure = draft.toFigure();
  if (figure == null) return;
  final signature = figureSnippetSignature(figure, taxonomy);
  final text = (draft.walkthroughOverride ?? '').trim();

  if (signature == null) {
    _setOverride(draft, controller, text.isEmpty ? null : text);
    return;
  }

  final existing = snippetLib.resolve(signature);

  if (text.isEmpty) {
    _setOverride(draft, controller, null);
    return;
  }

  if (existing == null) {
    // Learn-on-first-entry: the first snippet for this figure becomes its
    // default, reused wherever the figure appears again.
    await snippetLib.setSnippet(signature, text);
    _setOverride(draft, controller, null);
    return;
  }

  if (existing.trim() == text) {
    _setOverride(draft, controller, null);
    return;
  }

  if (!context.mounted) return;
  final useEverywhere = await _promptSnippetDivergence(context);
  if (useEverywhere == true) {
    await snippetLib.setSnippet(signature, text);
    _setOverride(draft, controller, null);
  } else {
    // Explicit "just this dance" or a dismissed prompt: keep it local; never
    // silently change the shared default.
    _setOverride(draft, controller, text);
  }
}

void _setOverride(
  FigureDraft draft,
  DanceEditorController controller,
  String? value,
) {
  if (draft.walkthroughOverride == value) return;
  draft.walkthroughOverride = value;
  controller.onFiguresChanged();
}

/// Prompts whether a diverging snippet should update the global default
/// (`true`) or stay a per-dance override (`false`); `null` when dismissed.
Future<bool?> _promptSnippetDivergence(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.danceEditorSnippetDivergenceTitle),
      content: Text(l10n.danceEditorSnippetDivergenceBody),
      actions: [
        TextButton(
          key: const ValueKey('snippet-just-this-dance'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.danceEditorSnippetJustThisDance),
        ),
        FilledButton(
          key: const ValueKey('snippet-use-everywhere'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.danceEditorSnippetUseEverywhere),
        ),
      ],
    ),
  );
}

/// Assembles a walkthrough from the dance's per-figure snippets (#411) and
/// fills the walkthrough field. When the field already has text, confirms
/// before replacing it — never silently overwriting the user's manual text.
Future<void> _fillWalkthroughFromSnippets(
  BuildContext context,
  DanceEditorController controller,
  Taxonomy taxonomy,
  WalkthroughSnippetLibraryController snippetLib,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final library = snippetLib.library;
  final figures = [
    for (final draft in controller.figureDrafts) ?draft.toFigure(),
  ];
  final lines = <String>[];
  for (final figure in figures) {
    final text = resolveFigureSnippet(figure, library, taxonomy);
    if (text != null) lines.add(text);
  }
  if (lines.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.danceEditorFillWalkthroughEmpty)),
    );
    return;
  }
  var assembled = lines.join('\n\n');
  if (assembled.length > kMaxWalkthroughLength) {
    assembled = assembled.substring(0, kMaxWalkthroughLength);
  }

  if (controller.walkthroughController.text.trim().isNotEmpty) {
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.danceEditorFillWalkthroughReplaceTitle),
        content: Text(l10n.danceEditorFillWalkthroughReplaceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('fill-walkthrough-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.danceEditorFillWalkthroughReplaceConfirm),
          ),
        ],
      ),
    );
    if (replace != true) return;
  }

  controller.setWalkthroughText(assembled);
}
