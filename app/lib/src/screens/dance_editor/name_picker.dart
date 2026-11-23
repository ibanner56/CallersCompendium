import 'dart:math' as math;

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_breakpoints.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';

typedef NameOption = ({String id, String name});

/// A multi-select dropdown of named entities (authors, interpreters, tags):
/// a field that reads the chosen names as text, and opens a list of every
/// option with a checkbox, a search box that narrows it, and a row that
/// creates a new entity from the typed name (`docs/design/ux.md` §3).
///
/// On a wide window the list drops down under the field; on a phone, or a
/// short window, it is a bottom sheet padded above the keyboard, so typing
/// never hides it (issue #716).
///
/// The list reads [selectedIds], [namesById] and [options] live: a check runs
/// [onAdd] or [onRemove], and the boxes follow once the owner rebuilds this
/// widget with the new selection.
class NamePicker extends StatefulWidget {
  const NamePicker({
    super.key,
    required this.fieldKey,
    required this.selectedIds,
    required this.namesById,
    required this.options,
    required this.onAdd,
    required this.onRemove,
    required this.onCreate,
    this.onEdit,
    this.sheetSemanticLabel,
  });

  final String fieldKey;
  final List<String> selectedIds;
  final Map<String, String> namesById;
  final List<NameOption> options;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  /// Returns the id the entity actually occupies, or `null` when the
  /// create did not happen and the caller has already told the user why
  /// (see `dance_editor_screen._createChoreographer`). `null` skips
  /// [onAdd] and leaves the typed text in place.
  final Future<String?> Function(String name) onCreate;

  /// When non-null, each row of the open list has an edit button that closes
  /// the list and invokes [onEdit] with the id: used by the Authors and
  /// Interpreted by pickers to edit the shared person record. When null (the
  /// Tags picker), rows have no edit button.
  final ValueChanged<String>? onEdit;

  /// The field's name for screen readers, and the announced name of the open
  /// list (e.g. "Authors" or "Tags"), matching the [FieldLabel] shown above
  /// this picker.
  final String? sheetSemanticLabel;

  @override
  State<NamePicker> createState() => _NamePickerState();
}

class _NamePickerState extends State<NamePicker> {
  /// The open list's view of this widget, updated on every rebuild so the
  /// list shows the owner's current selection and names.
  late final ValueNotifier<NamePicker> _live = ValueNotifier(widget);

  /// The open list's route, while it is open.
  Route<String>? _route;

  /// The closed field's focus. Taken when the list opens, so closing it hands
  /// focus back here, not to a text field elsewhere in the form, which would
  /// scroll the form back to that field.
  final FocusNode _fieldFocus = FocusNode();

  /// The window size when the drop-down opened, to close it on a resize.
  Size? _openedAt;

  @override
  void didUpdateWidget(covariant NamePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // After this frame: the open list is in another route, so it cannot be
    // marked for rebuild while this one is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _live.value = widget;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A drop-down is placed under the field, so a resized window, which moves
    // the field, closes it, as a menu closes.
    final size = MediaQuery.sizeOf(context);
    if (_route is _DropDownRoute && _openedAt != null && size != _openedAt) {
      _closeList();
    }
  }

  @override
  void dispose() {
    // The list belongs to this field: a create still in flight must not add
    // to an owner that has gone (the editor closed under it).
    _closeList();
    _live.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  /// Closes the open list, after this frame, since it can be called while
  /// the tree is building or being torn down.
  void _closeList() {
    final route = _route;
    if (route == null) return;
    _route = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  String _nameOf(String id) => widget.namesById[id] ?? id;

  Future<void> _open() async {
    if (_route != null) return;
    _fieldFocus.requestFocus();
    // Chosen first, in their order, then everyone else by name. Fixed while
    // the list is open, so a row does not jump when it is checked.
    final selected = widget.selectedIds.toSet();
    // Each sort key is worked out once: a long people list would otherwise
    // normalise every name many times over.
    final rest = [
      for (final o in widget.options)
        if (!selected.contains(o.id))
          (key: naturalKeyMatchKey(o.name), id: o.id),
    ]..sort((a, b) => a.key.compareTo(b.key));
    final order = [...widget.selectedIds, for (final o in rest) o.id];

    final navigator = Navigator.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.width < AppBreakpoints.compact || AppBreakpoints.isShort(context);
    final Route<String> route;
    if (compact) {
      route = ModalBottomSheetRoute<String>(
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        sheetAnimationStyle: AppMotion.styleFor(context),
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        barrierLabel: MaterialLocalizations.of(
          context,
        ).scrimOnTapHint(MaterialLocalizations.of(context).bottomSheetLabel),
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (_, scrollController) => _NamePickerPanel(
              owner: this,
              live: _live,
              order: order,
              scrollController: scrollController,
              // The keyboard would cover half the list on a phone; the
              // search box is one tap away.
              autofocus: false,
            ),
          ),
        ),
      );
    } else {
      final box = context.findRenderObject()! as RenderBox;
      final anchor = box.localToGlobal(Offset.zero) & box.size;
      route = _DropDownRoute<String>(
        anchor: anchor,
        textDirection: Directionality.of(context),
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        child: _NamePickerPanel(
          owner: this,
          live: _live,
          order: order,
          autofocus: true,
        ),
      );
    }
    _route = route;
    _openedAt = size;
    final editId = await navigator.push(route);
    if (!mounted) return;
    if (identical(_route, route)) _route = null;
    if (editId != null) widget.onEdit?.call(editId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final names = widget.selectedIds.map(_nameOf).join(', ');
    // One node: the field's name, the chosen names as its value, and the
    // ink well's tap and focus. The hint and names drawn inside are left out
    // so they are not read twice.
    return Semantics(
      button: true,
      label: widget.sheetSemanticLabel,
      value: names,
      child: InkWell(
        key: ValueKey('${widget.fieldKey}-field'),
        focusNode: _fieldFocus,
        onTap: _open,
        borderRadius: AppShapes.borderRadiusSmall,
        child: ExcludeSemantics(
          child: InputDecorator(
            isEmpty: names.isEmpty,
            decoration: InputDecoration(
              hintText: l10n.danceEditorChooseHint,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(names, key: ValueKey('${widget.fieldKey}-names')),
          ),
        ),
      ),
    );
  }
}

/// The open list: a search box, a checkbox row per option in [order], and a
/// create row for a typed name nobody has.
class _NamePickerPanel extends StatefulWidget {
  const _NamePickerPanel({
    required this.owner,
    required this.live,
    required this.order,
    required this.autofocus,
    this.scrollController,
  });

  /// The field this list belongs to. Once it is gone (the editor closed
  /// under the list), a create still in flight adds nothing.
  final State<NamePicker> owner;
  final ValueNotifier<NamePicker> live;
  final List<String> order;
  final bool autofocus;
  final ScrollController? scrollController;

  @override
  State<_NamePickerPanel> createState() => _NamePickerPanelState();
}

class _NamePickerPanelState extends State<_NamePickerPanel> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  /// [_NamePickerPanel.order], plus anything created while the list is open.
  late final List<String> _order = [...widget.order];

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// Rows for [picker] matching the typed text, in list order, then the
  /// create row when the typed name matches nobody exactly.
  List<_Row> _rows(NamePicker picker) {
    final q = _query.text.trim();
    // `naturalKeyMatchKey`, not `toLowerCase()`, for the filter and the exact
    // test alike: the repositories look an incumbent up by
    // `normalizeShareableText`, so comparing case-folded raw text would offer
    // a create that the repository then refuses as a duplicate (found in
    // review on #1410).
    final wanted = naturalKeyMatchKey(q);
    final names = {
      for (final o in picker.options) o.id: o.name,
      ...picker.namesById,
    };
    final known = {..._order};
    final ids = [
      ..._order,
      // Options that arrived while the list was open (another device's sync).
      for (final o in picker.options)
        if (!known.contains(o.id)) o.id,
    ];
    final rows = [
      for (final id in ids)
        if (names[id] case final name?)
          if (wanted.isEmpty || naturalKeyMatchKey(name).contains(wanted))
            _Row.existing(id, name),
    ];
    if (q.isNotEmpty &&
        !picker.options.any((o) => naturalKeyMatchKey(o.name) == wanted)) {
      rows.add(_Row.create(q));
    }
    return rows;
  }

  void _toggle(NamePicker picker, String id) {
    if (picker.selectedIds.contains(id)) {
      picker.onRemove(id);
      return;
    }
    picker.onAdd(id);
    // A name found by typing is added; the search box empties and keeps
    // focus, so the next name can be typed straight away (issue #402).
    if (_query.text.isNotEmpty) {
      _query.clear();
      _queryFocus.requestFocus();
    }
  }

  Future<void> _create(NamePicker picker, String name) async {
    final id = await picker.onCreate(name);
    // `null` is "the create did not happen, and the user has been told": the
    // typed name stays, so the next step is to pick the row it collided with.
    if (!mounted || !widget.owner.mounted || id == null) return;
    // Listed after the names already chosen, where a checked name sits.
    final chosen = picker.selectedIds.toSet();
    final at = _order.takeWhile(chosen.contains).length;
    picker.onAdd(id);
    setState(() {
      if (!_order.contains(id)) _order.insert(at, id);
    });
    _query.clear();
    _queryFocus.requestFocus();
  }

  /// Enter in the search box: checks the first match not yet chosen, or
  /// creates the typed name when it matches nobody, then clears the box for
  /// the next name. With nothing left to check or create, Enter does nothing
  /// and the typed text stays.
  void _submit(NamePicker picker) {
    if (_query.text.trim().isEmpty) return;
    final chosen = picker.selectedIds.toSet();
    final rows = _rows(picker);
    final first = rows
        .where((r) => r.isCreate || !chosen.contains(r.id))
        .firstOrNull;
    if (first == null) return;
    if (first.isCreate) {
      _create(picker, first.name);
      return;
    }
    picker.onAdd(first.id!);
    _query.clear();
    _queryFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<NamePicker>(
      valueListenable: widget.live,
      builder: (context, picker, _) {
        final rows = _rows(picker);
        final selected = picker.selectedIds.toSet();
        return Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: picker.sheetSemanticLabel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: TextField(
                  key: ValueKey('${picker.fieldKey}-input'),
                  controller: _query,
                  focusNode: _queryFocus,
                  autofocus: widget.autofocus,
                  decoration: InputDecoration(
                    hintText: l10n.danceEditorTypeToAddOrCreateHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submit(picker),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  key: ValueKey('${picker.fieldKey}-options'),
                  controller: widget.scrollController,
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row.isCreate) {
                      return ListTile(
                        key: ValueKey(
                          '${picker.fieldKey}-option-create:${row.name}',
                        ),
                        dense: true,
                        leading: const Icon(Icons.add),
                        title: Text(l10n.danceEditorCreateQuotedName(row.name)),
                        onTap: () => _create(picker, row.name),
                      );
                    }
                    final id = row.id!;
                    return CheckboxListTile(
                      key: ValueKey('${picker.fieldKey}-option-$id'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected.contains(id),
                      title: Text(row.name),
                      onChanged: (_) => _toggle(picker, id),
                      secondary: picker.onEdit == null
                          ? null
                          : IconButton(
                              key: ValueKey('${picker.fieldKey}-edit-$id'),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: l10n.danceEditorEditItemTooltip(
                                row.name,
                              ),
                              onPressed: () => Navigator.of(context).pop(id),
                            ),
                    );
                  },
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: TextButton(
                    key: ValueKey('${picker.fieldKey}-done'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonDone),
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

class _Row {
  _Row.existing(this.id, this.name) : isCreate = false;
  _Row.create(this.name) : id = null, isCreate = true;

  final String? id;
  final String name;
  final bool isCreate;
}

/// Shows [child] in a card dropped down under [anchor] (or above it, when
/// there is more room there), as wide as the field and at least 280.
/// A tap outside or Esc closes it.
class _DropDownRoute<T> extends PopupRoute<T> {
  _DropDownRoute({
    required this.anchor,
    required this.textDirection,
    required this.child,
    required this.barrierLabel,
  });

  final Rect anchor;

  /// The field's text direction, which the list lines up with.
  final TextDirection textDirection;

  final Widget child;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final padding = MediaQuery.paddingOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    return CustomSingleChildLayout(
      delegate: _DropDownLayout(
        anchor: anchor,
        textDirection: textDirection,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.sm,
          padding.top + AppSpacing.sm,
          AppSpacing.sm,
          math.max(padding.bottom, insets.bottom) + AppSpacing.sm,
        ),
      ),
      child: FadeTransition(
        opacity: animation,
        // The popup menus' shape: their radius, and in High contrast their
        // outline.
        child: Material(
          elevation: 3,
          shape:
              PopupMenuTheme.of(context).shape ??
              const RoundedRectangleBorder(
                borderRadius: AppShapes.borderRadiusSmall,
              ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _DropDownLayout extends SingleChildLayoutDelegate {
  _DropDownLayout({
    required this.anchor,
    required this.padding,
    required this.textDirection,
  });

  final Rect anchor;

  /// The list lines up with the field's start edge: its right edge in a
  /// right-to-left language.
  final TextDirection textDirection;
  final EdgeInsets padding;

  static const double _maxHeight = 400;
  static const double _minWidth = 280;

  double _below(Size size) => size.height - padding.bottom - anchor.bottom;
  double _above() => anchor.top - padding.top;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final width = math.min(
      math.max(anchor.width, _minWidth),
      size.width - padding.horizontal,
    );
    final room = math.max(_below(size), _above());
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0, math.min(_maxHeight, room)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final start = textDirection == TextDirection.rtl
        ? anchor.right - childSize.width
        : anchor.left;
    final double left = math.min(
      math.max(start, padding.left),
      math.max(padding.left, size.width - padding.right - childSize.width),
    );
    final top = childSize.height <= _below(size) || _below(size) >= _above()
        ? anchor.bottom
        : anchor.top - childSize.height;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_DropDownLayout old) =>
      anchor != old.anchor ||
      padding != old.padding ||
      textDirection != old.textDirection;
}
