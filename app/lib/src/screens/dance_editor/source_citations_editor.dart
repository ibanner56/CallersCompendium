import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import 'source_citation_draft.dart';

/// A short bibliographic subtitle ("Author, Year") for a source, or `null`
/// when it has neither an author nor a year.
String? _sourceSubtitle(PublishedSource s) {
  final parts = <String>[
    if (s.author != null) s.author!,
    if (s.year != null) s.year!.toString(),
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

/// The per-dance source-citation section: a list of cited-source rows (each an
/// editable chip + freeform page/number) plus a type-ahead to attach an
/// existing source or create a new one inline. Mirrors `LinksEditor` and the
/// `NamePicker` create/attach precedent.
class SourceCitationsEditor extends StatelessWidget {
  const SourceCitationsEditor({
    super.key,
    required this.citations,
    required this.sourcesById,
    required this.sourceOptions,
    required this.onAttach,
    required this.onCreate,
    required this.onEditSource,
    required this.onRemove,
    required this.onChanged,
  });

  final List<SourceCitationDraft> citations;
  final Map<String, PublishedSource> sourcesById;
  final List<PublishedSource> sourceOptions;

  /// Attaches an existing source by id.
  final ValueChanged<String> onAttach;

  /// Creates a new source with the typed title; resolves to its id, or `null`
  /// if the user cancels the create dialog.
  final Future<String?> Function(String title) onCreate;

  /// Opens the shared-source details dialog for the given source id.
  final ValueChanged<String> onEditSource;

  final ValueChanged<SourceCitationDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final citedIds = {for (final c in citations) c.sourceId};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final draft in citations)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: _buildRow(context, draft),
          ),
        _AddSourceAutocomplete(
          citedIds: citedIds,
          options: sourceOptions,
          onAttach: onAttach,
          onCreate: onCreate,
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, SourceCitationDraft draft) {
    final l10n = AppLocalizations.of(context);
    final source = sourcesById[draft.sourceId];
    final title = source?.title ?? l10n.danceEditorUnknownSource;
    final subtitle = source == null ? null : _sourceSubtitle(source);
    final chipLabel = subtitle == null ? title : '$title — $subtitle';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  key: ValueKey('source-chip-${draft.sourceId}'),
                  avatar: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(chipLabel, overflow: TextOverflow.ellipsis),
                  tooltip: l10n.danceEditorEditItemTooltip(title),
                  onPressed: () => onEditSource(draft.sourceId),
                  onDeleted: () => onRemove(draft),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xxs,
            left: AppSpacing.xs,
            right: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('source-page-${draft.sourceId}'),
                  controller: draft.pageController,
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorPageOptionalLabel,
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: TextField(
                  key: ValueKey('source-number-${draft.sourceId}'),
                  controller: draft.numberController,
                  decoration: InputDecoration(
                    labelText: l10n.danceEditorNumberOptionalLabel,
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddSourceAutocomplete extends StatelessWidget {
  const _AddSourceAutocomplete({
    required this.citedIds,
    required this.options,
    required this.onAttach,
    required this.onCreate,
  });

  final Set<String> citedIds;
  final List<PublishedSource> options;
  final ValueChanged<String> onAttach;
  final Future<String?> Function(String title) onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Autocomplete<_SourceChoice>(
      key: const ValueKey('source-autocomplete'),
      displayStringForOption: (choice) => choice.label,
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (q.isEmpty) return const Iterable<_SourceChoice>.empty();
        final lower = q.toLowerCase();
        final matches = options
            .where(
              (o) =>
                  !citedIds.contains(o.id) &&
                  (o.title.toLowerCase().contains(lower) ||
                      (o.author?.toLowerCase().contains(lower) ?? false)),
            )
            .map((o) => _SourceChoice.existing(o.id, o.title, o.author))
            .toList();
        final exact = options.any((o) => o.title.toLowerCase() == lower);
        if (!exact) matches.add(_SourceChoice.create(q));
        return matches;
      },
      onSelected: (choice) async {
        if (choice.isCreate) {
          final id = await onCreate(choice.title);
          if (id != null) onAttach(id);
        } else {
          onAttach(choice.id!);
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          key: const ValueKey('source-input'),
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: l10n.danceEditorCiteSourceHint,
            isDense: true,
          ),
          onSubmitted: (_) => onSubmit(),
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
                      key: ValueKey('source-option-${choice.optionKey}'),
                      dense: true,
                      leading: Icon(
                        choice.isCreate ? Icons.add : Icons.menu_book_outlined,
                        size: 18,
                      ),
                      title: Text(
                        choice.isCreate
                            ? l10n.danceEditorCreateQuotedName(choice.title)
                            : choice.title,
                      ),
                      subtitle: choice.author == null
                          ? null
                          : Text(choice.author!),
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

class _SourceChoice {
  _SourceChoice.existing(this.id, this.title, this.author) : isCreate = false;
  _SourceChoice.create(this.title) : id = null, author = null, isCreate = true;

  final String? id;
  final String title;
  final String? author;
  final bool isCreate;

  /// Text shown in the field when this option is selected.
  String get label => title;

  /// Stable widget key for the option row: existing items by id, the sole
  /// "create" row by its typed title.
  String get optionKey => isCreate ? 'create:$title' : id!;
}
