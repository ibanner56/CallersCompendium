import 'dart:async';
import 'dart:math' as math;

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

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

class _Move extends Intent {
  const _Move(this.by);

  final int by;
}

/// An action that acts, and consumes its key, only while [open] says so:
/// otherwise the arrow keys reach the field (and an input method's candidate
/// list), and a dismiss goes on to the page (Escape leaves it, as before).
class _WhileOpen<T extends Intent> extends CallbackAction<T> {
  _WhileOpen({required super.onInvoke, required this.open});

  final bool Function() open;

  @override
  bool isEnabled(covariant T intent) => open();

  @override
  bool consumesKey(covariant T intent) => open();
}

/// The search field with a dropdown of saved searches under it (#2325), for
/// the Collection and the collection picker.
///
/// With the field focused, a popover lists the saved searches by name, and
/// typing narrows it to the names that contain what is typed. While there is
/// text, the first row is **Search for "…"**. Choosing that row, pressing
/// Enter on it, or tapping outside does what the field always did: the
/// search runs as it is typed (the host's own debounce) and on Enter
/// ([onSubmitted]). Choosing a saved search calls [onLoad] and takes focus
/// from the field, so the results it shows are not covered by the popover.
/// Nothing here writes to [controller]: what is typed, the cursor and an IME
/// composition are left as they are.
///
/// While there is text, Search for is highlighted, and goes back to being so
/// whenever the text changes. With nothing typed no row is highlighted, so
/// Enter searches as it always did; the first Down highlights the first saved
/// search (Up, the last). The arrow keys move the highlight and Enter chooses
/// the highlighted row; the highlighted row is announced, as in the command
/// palette. While an input method is composing, the arrow keys are left to
/// it. Escape closes the popover while it is open; with it closed, Escape is
/// not handled here, so it leaves the page as it always did. No key is bound
/// to Escape here: the app's Escape reaches this field's dismiss action
/// through the field.
///
/// The popover's visibility is worked out on every build, from the focus, the
/// list and [enabled], so a list that arrives after the field has focus, or
/// Online search turned off while it has focus, opens it at once. No dropdown
/// while [enabled] is false (online search), or while there are no saved
/// searches. A saved search this version cannot read is not listed: it can
/// only be seen, and deleted, in Settings ▸ Collection.
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
  final _overlay = OverlayPortalController(debugLabel: 'saved-search-field');
  final _scroll = ScrollController();
  List<SavedSearch> _saved = const [];
  int _readSeq = 0;
  String _lastText = '';

  /// The highlighted row, the one Enter chooses; null for none (nothing
  /// typed, and no arrow key since).
  int? _highlight;

  /// Set by a change of text, so the popover announces that it opened when
  /// typing opens it, but not on every focus.
  bool _announceOpen = false;

  /// Set by a tap outside the field and the dropdown while the field has
  /// focus: the dropdown closes, though the field keeps its focus (as a text
  /// field does on a phone). Typing, or tapping the field, opens it again.
  bool _closedByTap = false;

  /// Set by Escape; cleared as for [_closedByTap].
  bool _dismissed = false;

  /// Whether the popover was open at the last build, to announce it opening.
  bool _wasOpen = false;

  /// No highlight with nothing typed; otherwise Search for, the first row.
  int? get _startHighlight => widget.controller.text.trim().isEmpty ? null : 0;

  /// Whether an input method is composing, when the arrow keys are its own.
  bool get _composing => widget.controller.value.composing.isValid;

  final Map<int, GlobalKey> _rowKeys = {};

  late final Map<Type, Action<Intent>> _actions = {
    _Move: _WhileOpen<_Move>(open: () => _open && !_composing, onInvoke: _move),
    // Reached by the app's Escape through the field (no key is bound here).
    DismissIntent: _WhileOpen<DismissIntent>(
      open: () => _open && !_composing,
      onInvoke: (_) {
        setState(() => _dismissed = true);
        return null;
      },
    ),
  };

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowDown): _Move(1),
    SingleActivator(LogicalKeyboardKey.arrowUp): _Move(-1),
  };

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
    _lastText = widget.controller.text;
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
    _scroll.dispose();
    super.dispose();
  }

  void _onText() {
    if (widget.controller.text == _lastText) return;
    _lastText = widget.controller.text;
    setState(() {
      _highlight = _startHighlight;
      _announceOpen = true;
      _closedByTap = false;
      _dismissed = false;
    });
  }

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      // Read again on every focus, so a search saved or deleted elsewhere (in
      // Settings, or by sync) is listed as it is now.
      unawaited(_read());
    }
    setState(() {
      _highlight = _startHighlight;
      _announceOpen = false;
      _closedByTap = false;
      _dismissed = false;
    });
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

  /// The rows for what is typed now.
  List<_Option> _rows() {
    if (!widget.enabled || _saved.isEmpty) return const [];
    final typed = widget.controller.text.trim();
    final needle = typed.toLowerCase();
    return [
      if (typed.isNotEmpty) _SearchFor(),
      for (final search in _saved)
        if (search.name.toLowerCase().contains(needle)) _Saved(search),
    ];
  }

  bool get _open =>
      widget.focusNode.hasFocus &&
      !_closedByTap &&
      !_dismissed &&
      _rows().isNotEmpty;

  Object? _move(_Move intent) {
    final count = _rows().length;
    if (count == 0) return null;
    setState(() {
      final from = _highlight;
      // From no highlight, Down lands on the first row and Up on the last.
      var next = from == null
          ? (intent.by > 0 ? 0 : count - 1)
          : (from + intent.by) % count;
      if (next < 0) next += count;
      _highlight = next;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final row = _rowKeys[_highlight]?.currentContext;
      if (row != null) Scrollable.ensureVisible(row, alignment: 0.5);
      _announceHighlighted();
    });
    return null;
  }

  String _label(AppLocalizations l10n, _Option option) => switch (option) {
    _SearchFor() => l10n.savedSearchSearchFor(widget.controller.text.trim()),
    _Saved(:final search) => search.name,
  };

  void _send(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    ).catchError((Object _) {
      // diagnostics: silent — a screen-reader announcement is best-effort.
    });
  }

  void _announceHighlighted() {
    final rows = _rows();
    final at = _highlight;
    if (at == null || at >= rows.length) return;
    final l10n = AppLocalizations.of(context);
    _send(
      l10n.savedSearchHighlightedRow(
        _label(l10n, rows[at]),
        at + 1,
        rows.length,
      ),
    );
  }

  /// Enter: the highlighted row while the popover is open (the first row,
  /// Search for, is the ordinary search; with nothing typed, only a row the
  /// arrow keys moved onto), and otherwise the ordinary search.
  void _submit() {
    final rows = _rows();
    final at = _highlight;
    if (_open && at != null && at < rows.length) {
      _choose(rows[at]);
    } else {
      widget.onSubmitted();
    }
  }

  void _choose(_Option option) {
    switch (option) {
      case _SearchFor():
        setState(() => _dismissed = true);
        widget.onSubmitted();
      case _Saved(:final search):
        // The results are what the user wants to see now: the popover and
        // the keyboard go, and come back when the field is focused again.
        widget.focusNode.unfocus();
        widget.onLoad(search);
    }
  }

  /// Opens or closes the popover to match [open], after this frame.
  void _sync(bool open) {
    if (open == _overlay.isShowing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (open && !_overlay.isShowing) {
        _overlay.show();
      } else if (!open && _overlay.isShowing) {
        _overlay.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final open = _open;
    // Announced when typing opens it, not each time the field gains focus.
    if (open &&
        !_wasOpen &&
        _announceOpen &&
        MediaQuery.supportsAnnounceOf(context)) {
      final found = WidgetsLocalizations.of(context).searchResultsFound;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(found);
      });
    }
    _wasOpen = open;
    _sync(open);
    final rows = _rows();
    if ((_highlight ?? 0) >= rows.length) _highlight = _startHighlight;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: (context, info) =>
          _buildDropdown(context, info, l10n),
      // The field and the dropdown are one tap group, so a tap on a row is
      // not a tap outside.
      child: TapRegion(
        groupId: EditableText,
        onTapInside: (_) {
          if (_closedByTap || _dismissed) {
            setState(() {
              _closedByTap = false;
              _dismissed = false;
            });
          }
        },
        onTapOutside: (_) {
          // Only while focused: a tap elsewhere while the field is not in use
          // must not keep the dropdown shut when focus later arrives by
          // keyboard (Tab, or Ctrl/Cmd-F).
          if (widget.focusNode.hasFocus && !_closedByTap) {
            setState(() => _closedByTap = true);
          }
        },
        child: Shortcuts(
          shortcuts: _shortcuts,
          child: Actions(
            actions: _actions,
            child: widget.fieldBuilder(context, _submit),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    BuildContext context,
    OverlayChildLayoutInfo info,
    AppLocalizations l10n,
  ) {
    final rows = _rows();
    if (!_open || rows.isEmpty || info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    // Under the field, as wide as it, no taller than the room below it.
    final field = info.childSize;
    final origin = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset(0, field.height),
    );
    // The window's own insets: a Scaffold above strips the keyboard's from
    // the MediaQuery here, while the overlay spans the whole window.
    final view = MediaQueryData.fromView(View.of(context));
    final insets = view.viewInsets;
    final padding = view.padding;
    final below =
        info.overlaySize.height - insets.bottom - padding.bottom - origin.dy;
    final maxHeight = math.max(
      kMinInteractiveDimension,
      math.min(320.0, below - AppSpacing.xs),
    );
    final scheme = Theme.of(context).colorScheme;
    return Transform(
      transform: info.childPaintTransform.clone()
        ..translateByDouble(0, field.height, 0, 1),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: field.width,
          child: TextFieldTapRegion(
            // Rows are chosen by tap or by the arrow keys from the field, so they
            // never take focus from it.
            child: ExcludeFocus(
              child: Material(
                key: const ValueKey('saved-search-dropdown'),
                elevation: 4,
                color: scheme.surfaceContainer,
                shape: Theme.of(context).popupMenuTheme.shape,
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  // Every row is built, so the arrow keys can scroll any of them
                  // into view. A list holds at most savedSearchMaxCount rows here.
                  child: SingleChildScrollView(
                    controller: _scroll,
                    // Scrolling the rows must not take focus from the field:
                    // losing focus closes them.
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.manual,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, option) in rows.indexed)
                          ListTile(
                            key: _rowKeys.putIfAbsent(i, GlobalKey.new),
                            dense: true,
                            selected: i == _highlight,
                            selectedTileColor: scheme.secondaryContainer,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            leading: Icon(switch (option) {
                              _SearchFor() => Icons.search,
                              _Saved() => Icons.bookmark_border,
                            }),
                            title: Text(
                              _label(l10n, option),
                              key: switch (option) {
                                _SearchFor() => const ValueKey(
                                  'saved-search-search-for',
                                ),
                                _Saved(:final search) => ValueKey(
                                  'saved-search-row-${search.id}',
                                ),
                              },
                            ),
                            onTap: () => _choose(option),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
