import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import 'link_draft.dart';
import 'name_picker.dart';

class LinksEditor extends StatelessWidget {
  const LinksEditor({
    super.key,
    required this.links,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<LinkDraft> links;

  final VoidCallback onAdd;
  final ValueChanged<LinkDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Related dances have their own dedicated subsection; the generic links
    // list handles only URL-bearing kinds (source/video/other).
    final urlLinks = [
      for (final draft in links)
        if (draft.kind != LinkKind.relatedDance) draft,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final draft in urlLinks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<LinkKind>(
                    key: ValueKey('link-kind-${draft.id}'),
                    initialValue: draft.kind,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: LinkKind.source,
                        child: Text(l10n.danceEditorLinkKindSource),
                      ),
                      DropdownMenuItem(
                        value: LinkKind.video,
                        child: Text(l10n.danceEditorLinkKindVideo),
                      ),
                      DropdownMenuItem(
                        value: LinkKind.other,
                        child: Text(l10n.danceEditorLinkKindOther),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        draft.kind = value;
                        onChanged();
                      }
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        key: ValueKey('link-url-${draft.id}'),
                        controller: draft.urlController,
                        decoration: InputDecoration(
                          labelText: l10n.danceEditorUrlLabel,
                          isDense: true,
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      TextField(
                        key: ValueKey('link-label-${draft.id}'),
                        controller: draft.labelController,
                        decoration: InputDecoration(
                          labelText: l10n.danceEditorLabelOptional,
                          isDense: true,
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('link-remove-${draft.id}'),
                  tooltip: l10n.danceEditorRemoveLinkTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(draft),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('link-add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(l10n.danceEditorAddLink),
          ),
        ),
      ],
    );
  }
}

/// Callers-Companion-style "Related dances" subsection. Distinct from the
/// generic [LinksEditor]: it lets the user pick another dance from the
/// collection and attach an optional free-text note.
///
/// Operates on the shared `_links` list, filtered to
/// [LinkKind.relatedDance] drafts, so save/load/undo wiring is unchanged. The
/// note reuses [DanceLink.label] — no schema change is required.
class RelatedDancesEditor extends StatelessWidget {
  const RelatedDancesEditor({
    super.key,
    required this.links,
    required this.danceOptions,
    required this.danceNamesById,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<LinkDraft> links;

  /// Non-deleted dances eligible for selection (self excluded).
  final List<NameOption> danceOptions;

  /// Title lookup for resolving a [LinkDraft.targetDanceId] to its display
  /// name. A missing entry means the target dance was deleted/purged.
  final Map<String, String> danceNamesById;

  final VoidCallback onAdd;
  final ValueChanged<LinkDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final relatedDrafts = [
      for (final draft in links)
        if (draft.kind == LinkKind.relatedDance) draft,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final draft in relatedDrafts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _RelatedDancePicker(
                        key: ValueKey(
                          'related-dance-picker-${draft.id}-'
                          '${draft.targetDanceId ?? 'null'}',
                        ),
                        initialTitle: draft.targetDanceId == null
                            ? ''
                            : (danceNamesById[draft.targetDanceId!] ??
                                  l10n.danceEditorMissingDance),
                        danceOptions: danceOptions,
                        onSelected: (id) {
                          draft.targetDanceId = id;
                          onChanged();
                        },
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      TextField(
                        key: ValueKey('related-dance-note-${draft.id}'),
                        controller: draft.labelController,
                        decoration: InputDecoration(
                          labelText: l10n.danceEditorNoteOptionalLabel,
                          isDense: true,
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('related-dance-remove-${draft.id}'),
                  tooltip: l10n.danceEditorRemoveRelatedDanceTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(draft),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('related-dance-add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(l10n.danceEditorAddRelatedDance),
          ),
        ),
      ],
    );
  }
}

/// Dance type-ahead for selecting a related dance in a link row.
///
/// Keyed externally on `draft.id + targetDanceId` so it is recreated (and
/// [initialTitle] applied) whenever the selection changes via undo/redo.
class _RelatedDancePicker extends StatelessWidget {
  const _RelatedDancePicker({
    super.key,
    required this.initialTitle,
    required this.danceOptions,
    required this.onSelected,
  });

  final String initialTitle;
  final List<NameOption> danceOptions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Autocomplete<NameOption>(
      initialValue: TextEditingValue(text: initialTitle),
      displayStringForOption: (opt) => opt.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<NameOption>.empty();
        return danceOptions.where((o) => o.name.toLowerCase().contains(q));
      },
      onSelected: (choice) => onSelected(choice.id),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: l10n.danceEditorRelatedDanceLabel,
            hintText: l10n.danceEditorTypeToSearchHint,
            isDense: true,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, choices) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final choice in choices)
                    ListTile(
                      key: ValueKey('link-dance-option-${choice.id}'),
                      dense: true,
                      leading: const Icon(Icons.link, size: 18),
                      title: Text(choice.name),
                      onTap: () => onSelected(choice),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
