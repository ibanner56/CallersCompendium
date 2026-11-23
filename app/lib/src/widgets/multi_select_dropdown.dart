import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_motion.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';

/// Where an open [MultiSelectDropdown] list is shown, for its
/// [MultiSelectDropdown.panelBuilder].
typedef MultiSelectPanelPlacement = ({
  /// Whether the list's search box takes focus as it opens: in a drop-down,
  /// not in a bottom sheet, where the keyboard would cover half the list.
  bool autofocus,

  /// The bottom sheet's scroll controller, for the list to scroll with the
  /// sheet; `null` in a drop-down.
  ScrollController? scrollController,
});

/// A field that reads its choices as text and opens a list to pick from, for
/// a value that holds any number of choices: the people of a dance's credits,
/// its tags, or the dancers a figure names (`docs/design/ux.md` §3).
///
/// On a wide window the list drops down under the field, as a menu does; on a
/// phone, or a short window, it is a bottom sheet padded above the keyboard,
/// so typing in its search box never hides it (issue #716). A tap outside or
/// Esc closes it, as they close a menu, and so does a resized window, which
/// moves the field the drop-down hangs from.
///
/// The list is built by [panelBuilder], again whenever the owner rebuilds this
/// widget, so it follows the owner's selection while it is open.
class MultiSelectDropdown extends StatefulWidget {
  const MultiSelectDropdown({
    super.key,
    required this.fieldKey,
    required this.valueText,
    required this.decoration,
    required this.panelBuilder,
    this.semanticLabel,
    this.onClosed,
  });

  /// Keys the closed field as `'$fieldKey-field'` and its text as
  /// `'$fieldKey-names'`.
  final String fieldKey;

  /// The choices, as the closed field reads them. Empty shows the
  /// [decoration]'s hint.
  final String valueText;

  /// The closed field's decoration. A drop-down arrow is added as its suffix
  /// when it has none.
  final InputDecoration decoration;

  final Widget Function(
    BuildContext context,
    MultiSelectPanelPlacement placement,
  )
  panelBuilder;

  /// The field's name for screen readers, and the announced name of the open
  /// list. Leave it null where [decoration] has a label, which names both.
  final String? semanticLabel;

  /// Called with the value the list was closed with (`Navigator.pop`), or
  /// `null` when it was dismissed, once it has closed.
  final ValueChanged<Object?>? onClosed;

  @override
  State<MultiSelectDropdown> createState() => _MultiSelectDropdownState();
}

class _MultiSelectDropdownState extends State<MultiSelectDropdown> {
  /// The open list's view of this widget, updated on every rebuild so the
  /// list shows the owner's current selection.
  late final ValueNotifier<MultiSelectDropdown> _live = ValueNotifier(widget);

  /// The open list's route, while it is open.
  Route<Object?>? _route;

  /// The closed field's focus. Taken when the list opens, so closing it hands
  /// focus back here, not to a text field elsewhere in the form, which would
  /// scroll the form back to that field.
  final FocusNode _fieldFocus = FocusNode();

  /// The window size when the drop-down opened, to close it on a resize.
  Size? _openedAt;

  @override
  void didUpdateWidget(covariant MultiSelectDropdown oldWidget) {
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
    // The list belongs to this field: once the field has gone (the editor
    // closed under it), nothing in the list may still act for it.
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

  Widget _panel(MultiSelectPanelPlacement placement) =>
      ValueListenableBuilder<MultiSelectDropdown>(
        valueListenable: _live,
        builder: (context, live, _) => Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: live.semanticLabel ?? live.decoration.labelText,
          child: live.panelBuilder(context, placement),
        ),
      );

  Future<void> _open() async {
    if (_route != null) return;
    _fieldFocus.requestFocus();
    final navigator = Navigator.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.width < AppBreakpoints.compact || AppBreakpoints.isShort(context);
    final Route<Object?> route;
    if (compact) {
      route = ModalBottomSheetRoute<Object?>(
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
            builder: (_, scrollController) =>
                _panel((autofocus: false, scrollController: scrollController)),
          ),
        ),
      );
    } else {
      final box = context.findRenderObject()! as RenderBox;
      final anchor = box.localToGlobal(Offset.zero) & box.size;
      route = _DropDownRoute<Object?>(
        anchor: anchor,
        textDirection: Directionality.of(context),
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        child: _panel((autofocus: true, scrollController: null)),
      );
    }
    _route = route;
    _openedAt = size;
    final result = await navigator.push(route);
    if (!mounted) return;
    if (identical(_route, route)) _route = null;
    widget.onClosed?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final decoration = widget.decoration.suffixIcon == null
        ? widget.decoration.copyWith(
            suffixIcon: const Icon(Icons.arrow_drop_down),
          )
        : widget.decoration;
    // One node: the field's name, the choices as its value, and the ink
    // well's tap and focus. The text drawn inside is left out so it is not
    // read twice.
    return Semantics(
      button: true,
      label: widget.semanticLabel ?? widget.decoration.labelText,
      // An empty field reads as its hint ("not stated", "Choose…"), as it
      // shows.
      value: widget.valueText.isEmpty
          ? widget.decoration.hintText
          : widget.valueText,
      child: InkWell(
        key: ValueKey('${widget.fieldKey}-field'),
        focusNode: _fieldFocus,
        onTap: _open,
        borderRadius: AppShapes.borderRadiusSmall,
        child: ExcludeSemantics(
          child: InputDecorator(
            isEmpty: widget.valueText.isEmpty,
            decoration: decoration,
            child: Text(
              widget.valueText,
              key: ValueKey('${widget.fieldKey}-names'),
            ),
          ),
        ),
      ),
    );
  }
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
