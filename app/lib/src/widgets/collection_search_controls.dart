import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/collection_query_labels.dart';
import '../theme/app_spacing.dart';
import 'app_dropdown_field.dart';

// The Collection's search controls, shared with the program picker so the two
// offer the same Search in and sort (FIND-7, maintainer decision 2026-10-29
// "picker-parity" = full parity). Each widget is stateless about the query: the
// host owns the scope, sort and direction and decides what a change re-runs, so
// a later host (a history-filter chip row, a bulk-selection bar) can mount the
// same controls without taking on either screen's search state.

/// The **Search in** dropdown: All fields, Title, Author or Figure.
///
/// While [online] it offers only Title, Author and Figure, the scopes the
/// online sources accept (see [onlineFullTextScope]). [fieldKey] goes on the
/// dropdown itself so each host keeps its own test key.
class SearchScopeField extends StatelessWidget {
  const SearchScopeField({
    super.key,
    required this.fieldKey,
    required this.scope,
    required this.online,
    required this.onChanged,
    this.border,
  });

  final Key fieldKey;
  final FullTextScope scope;
  final bool online;
  final ValueChanged<FullTextScope?> onChanged;

  /// The field's border, so it matches the search box beside it. `null` keeps
  /// the theme's default, as the Collection does.
  final InputBorder? border;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The field follows [scope], so a change made from outside (turning
    // online search on maps All fields to Title) shows at once.
    return AppDropdownField<FullTextScope>(
      key: fieldKey,
      value: scope,
      decoration: InputDecoration(
        labelText: l10n.collectionSearchScopeLabel,
        isDense: true,
        border: border,
      ),
      entries: [
        if (!online)
          AppDropdownEntry(
            value: FullTextScope.omni,
            label: l10n.collectionSearchScopeOmni,
          ),
        AppDropdownEntry(
          value: FullTextScope.title,
          label: l10n.collectionSearchScopeTitle,
        ),
        AppDropdownEntry(
          value: FullTextScope.author,
          label: l10n.collectionSearchScopeAuthor,
        ),
        AppDropdownEntry(
          value: FullTextScope.figure,
          label: l10n.collectionSearchScopeFigure,
        ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A search box with **Search in** beside it whenever the pane is at least
/// 300 logical pixels wide at the current text size, or stacked above it when
/// narrower.
///
/// Both children keep the same element across the switch between one row and
/// two (a rotation, a window resize, a pane resize), so a focused field keeps
/// focus and the keyboard stays up.
class SearchFieldWithScope extends StatefulWidget {
  const SearchFieldWithScope({
    super.key,
    required this.searchField,
    required this.scopeField,
  });

  final Widget searchField;
  final Widget scopeField;

  @override
  State<SearchFieldWithScope> createState() => _SearchFieldWithScopeState();
}

class _SearchFieldWithScopeState extends State<SearchFieldWithScope> {
  final _searchFieldKey = GlobalKey();
  final _scopeFieldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final searchField = KeyedSubtree(
          key: _searchFieldKey,
          child: widget.searchField,
        );
        final scopeField = KeyedSubtree(
          key: _scopeFieldKey,
          child: widget.scopeField,
        );
        if (constraints.maxWidth >= 300 * textScale) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: searchField),
              const SizedBox(width: AppSpacing.xs),
              Expanded(flex: 2, child: scopeField),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            scopeField,
            const SizedBox(height: AppSpacing.xs),
            searchField,
          ],
        );
      },
    );
  }
}

/// The sort menu: one entry per [sorts] (see [availableCollectionSorts]), with
/// [sort] marked as current.
class CollectionSortMenuButton extends StatelessWidget {
  const CollectionSortMenuButton({
    super.key,
    required this.sort,
    required this.sorts,
    required this.onSelected,
  });

  final CollectionSort sort;
  final List<CollectionSort> sorts;
  final ValueChanged<CollectionSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<CollectionSort>(
      tooltip: l10n.collectionSortByTooltip(collectionSortLabel(l10n, sort)),
      initialValue: sort,
      icon: const Icon(Icons.sort),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in sorts)
          PopupMenuItem(
            value: option,
            child: Text(collectionSortLabel(l10n, option)),
          ),
      ],
    );
  }
}

/// The ascending / descending toggle beside [CollectionSortMenuButton].
class SortDirectionButton extends StatelessWidget {
  const SortDirectionButton({
    super.key,
    this.buttonKey,
    required this.direction,
    required this.onPressed,
  });

  /// Goes on the [IconButton] itself, so a host's test key finds the button.
  final Key? buttonKey;
  final SortDirection direction;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ascending = direction == SortDirection.ascending;
    return IconButton(
      key: buttonKey,
      tooltip: ascending
          ? l10n.collectionSortAscendingTooltip
          : l10n.collectionSortDescendingTooltip,
      icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward),
      onPressed: onPressed,
    );
  }
}
