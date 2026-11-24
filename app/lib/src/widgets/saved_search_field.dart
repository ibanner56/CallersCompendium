import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../theme/app_spacing.dart';

/// One row of the search field's dropdown.
sealed class _Option {}

/// The first row: search for what is typed, as Enter does.
final class _SearchFor extends _Option {}

/// A saved search to load.
final class _Saved extends _Option {
  _Saved(this.search);

  final SavedSearch search;
}

/// Builds the search field itself, given what to call when it is submitted.
typedef SavedSearchFieldBuilder =
    Widget Function(BuildContext context, VoidCallback onSubmitted);

/// The search field with a dropdown of saved searches under it (#2325), for
/// the Collection and the collection picker.
///
/// With the field focused, a popover lists the saved searches by name, and
/// typing narrows it to the names that contain what is typed. While there is
/// text, the first row is **Search for "…"**. Choosing that row, pressing
/// Enter on it, or leaving the field does what the field always did: the
/// search runs as it is typed (the host's own debounce) and on Enter
/// ([onSubmitted]). Choosing a saved search calls [onLoad]; the field's text is
/// never replaced by a row's label. Arrow keys move through the rows and
/// Escape closes the popover ([RawAutocomplete]); the highlighted row is
/// announced, as in the command palette.
///
/// No dropdown while [enabled] is false (online search), or while there are
/// no saved searches. A saved search this version cannot read is not listed:
/// it can only be seen, and deleted, in Settings ▸ Collection.
class SavedSearchField extends StatefulWidget {
  const SavedSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onLoad,
    required this.onSubmitted,
    required this.fieldBuilder,
    this.revision = 0,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// False while online search is on.
  final bool enabled;

  /// Loads a chosen saved search into the host.
  final ValueChanged<SavedSearch> onLoad;

  /// What Enter did before there was a dropdown: run the search now.
  final VoidCallback onSubmitted;

  /// The field. It must use [controller] and [focusNode], and call the
  /// callback it is given from its `onSubmitted`.
  final SavedSearchFieldBuilder fieldBuilder;

  /// Bumped by the host after it saves, renames or deletes a saved search, so
  /// the list is read again.
  final int revision;

  @override
  State<SavedSearchField> createState() => _SavedSearchFieldState();
}

class _SavedSearchFieldState extends State<SavedSearchField> {
  List<SavedSearch> _saved = const [];
  int _readSeq = 0;

  /// Set when a row was chosen while handling Enter, so the plain search is
  /// not run as well.
  bool _choseOnSubmit = false;

  /// Whether the arrow keys have moved the highlight since the text last
  /// changed. With nothing typed there is no Search for row, so the
  /// highlighted row is a saved search; Enter loads it only once the user
  /// has moved onto it, and otherwise searches as it always did.
  bool _movedHighlight = false;
  String _lastText = '';

  /// Set by a tap outside the field and the dropdown: the dropdown closes,
  /// though the field keeps its focus (as a text field does on a phone).
  /// Typing, or tapping the field, opens it again.
  bool _closedByTap = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
    _lastText = widget.controller.text;
  }

  void _onText() {
    if (widget.controller.text == _lastText) return;
    _lastText = widget.controller.text;
    _movedHighlight = false;
    if (_closedByTap) setState(() => _closedByTap = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readSeq == 0) unawaited(_read());
  }

  @override
  void didUpdateWidget(SavedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (oldWidget.revision != widget.revision) unawaited(_read());
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onFocus() {
    // Read again on every focus, so a search saved or deleted elsewhere (in
    // Settings, or by sync) is listed as it is now.
    if (widget.focusNode.hasFocus) {
      unawaited(_read());
    } else {
      // Reset on the way out, not on the way in: the dropdown decides whether
      // to open as focus arrives, possibly before this listener runs.
      _closedByTap = false;
    }
  }

  Future<void> _read() async {
    final seq = ++_readSeq;
    try {
      final stored = await RepositoriesScope.of(context).savedSearches.list();
      if (!mounted || seq != _readSeq) return;
      setState(() => _saved = [for (final s in stored) ?s.search]);
    } catch (error, stackTrace) {
      // The field still searches; only the list of saved searches is missing.
      logCaughtError(error, stackTrace, source: 'saved_search_field._read');
    }
  }

  /// The rows, read when they are shown rather than when the text last
  /// changed, so a list read after focus, or online search turned on, is what
  /// the popover shows. Fresh objects on each read, so choosing the same
  /// saved search twice in a row still loads it.
  Iterable<_Option> _options() sync* {
    if (!widget.enabled || _closedByTap || _saved.isEmpty) return;
    final typed = widget.controller.text.trim();
    if (typed.isNotEmpty) yield _SearchFor();
    final needle = typed.toLowerCase();
    for (final search in _saved) {
      if (search.name.toLowerCase().contains(needle)) yield _Saved(search);
    }
  }

  void _onSelected(_Option option) {
    _choseOnSubmit = true;
    switch (option) {
      case _SearchFor():
        widget.onSubmitted();
      case _Saved(:final search):
        widget.onLoad(search);
    }
  }

  void _announce(String label, int index, int count) {
    _movedHighlight = true;
    final l10n = AppLocalizations.of(context);
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.savedSearchHighlightedRow(label, index + 1, count),
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    ).catchError((Object _) {
      // diagnostics: silent — a screen-reader announcement is best-effort.
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The dropdown is in the field's tap group, so a tap on a row is not a
    // tap outside.
    return TapRegion(
      groupId: EditableText,
      onTapInside: (_) {
        if (_closedByTap) setState(() => _closedByTap = false);
      },
      onTapOutside: (_) {
        if (!_closedByTap) setState(() => _closedByTap = true);
      },
      child: _autocomplete(l10n),
    );
  }

  Widget _autocomplete(AppLocalizations l10n) {
    return RawAutocomplete<_Option>(
      textEditingController: widget.controller,
      focusNode: widget.focusNode,
      // Choosing a row never changes what is typed.
      displayStringForOption: (_) => widget.controller.text,
      optionsBuilder: (_) => _options(),
      onSelected: _onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          widget.fieldBuilder(context, () {
            // Enter picks the highlighted row while the popover is open (the
            // first row, Search for, is the ordinary search), and otherwise
            // searches, as before.
            _choseOnSubmit = false;
            if (widget.controller.text.trim().isNotEmpty || _movedHighlight) {
              onFieldSubmitted();
            }
            _movedHighlight = false;
            if (!_choseOnSubmit) widget.onSubmitted();
          }),
      optionsViewBuilder: (context, onSelected, options) {
        final rows = options.toList();
        if (rows.isEmpty) return const SizedBox.shrink();
        String label(_Option o) => switch (o) {
          _SearchFor() => l10n.savedSearchSearchFor(
            widget.controller.text.trim(),
          ),
          _Saved(:final search) => search.name,
        };
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            key: const ValueKey('saved-search-dropdown'),
            elevation: 4,
            color: Theme.of(context).colorScheme.surfaceContainer,
            shape: Theme.of(context).popupMenuTheme.shape,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                // Scrolling the rows must not take focus from the field:
                // losing focus closes them.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final (i, option) in rows.indexed)
                    _Row(
                      key: switch (option) {
                        _SearchFor() => const ValueKey(
                          'saved-search-search-for',
                        ),
                        _Saved(:final search) => ValueKey(
                          'saved-search-row-${search.id}',
                        ),
                      },
                      index: i,
                      icon: switch (option) {
                        _SearchFor() => Icons.search,
                        _Saved() => Icons.bookmark_border,
                      },
                      label: label(option),
                      onTap: () => onSelected(option),
                      onHighlighted: () =>
                          _announce(label(option), i, rows.length),
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

/// A dropdown row: highlighted while it is the one Enter would choose, and
/// announced when the arrow keys move onto it.
class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.index,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.onHighlighted,
  });

  final int index;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onHighlighted;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool? _wasHighlighted;

  @override
  Widget build(BuildContext context) {
    final highlighted =
        AutocompleteHighlightedOption.of(context) == widget.index;
    // Announce a move onto this row, not the first build (where row 0 is
    // highlighted before any key was pressed).
    if (_wasHighlighted == false && highlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onHighlighted();
        Scrollable.ensureVisible(context, alignment: 0.5);
      });
    }
    _wasHighlighted = highlighted;
    return ListTile(
      dense: true,
      selected: highlighted,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      leading: Icon(widget.icon),
      title: Text(widget.label),
      onTap: widget.onTap,
    );
  }
}
