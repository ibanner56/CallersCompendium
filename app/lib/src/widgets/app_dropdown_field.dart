import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'app_shortcuts.dart';

/// A list at least this long lets the user type to narrow it
/// ([AppDropdownField.filterable]), for a field whose list length varies.
const int appDropdownFilterFrom = 12;

/// One choice in an [AppDropdownField].
@immutable
class AppDropdownEntry<T> {
  const AppDropdownEntry({
    required this.value,
    required this.label,
    this.key,
    this.leadingIcon,
    this.enabled = true,
  });

  final T value;

  /// The text shown in the open menu and, once chosen, in the closed field.
  final String label;

  /// Key on the entry's label in the open menu, for tests that pick it.
  final Key? key;

  /// Shown before the label in the menu and, while this entry is the one
  /// chosen, at the start of the closed field.
  final Widget? leadingIcon;

  /// A disabled entry is listed but cannot be chosen.
  final bool enabled;
}

/// The app's form dropdown: a [DropdownMenu] that fills its slot, reads as a
/// filled text field, and takes part in an enclosing [Form] as a [FormField].
///
/// Used instead of Flutter's DropdownButtonFormField, whose menu is painted
/// with a fixed decoration and no hook for a border, so in High contrast it was
/// the one menu without an outline. [DropdownMenu]'s menu takes the theme's
/// `dropdownMenuTheme`, which High contrast outlines, and its closed field takes
/// the theme's `inputDecorationTheme` (see `component_themes.dart`).
///
/// [value] is the current choice. It is read again whenever the parent rebuilds
/// with a different one, so the field follows its owner's state; a value not
/// among [entries] shows an empty field. [onChanged] runs when the user picks
/// an entry other than the current one; a null [onChanged] disables the field.
///
/// By default the field is select-only: tapping opens the menu and never
/// raises the on-screen keyboard. Set [filterable] for a long or user-grown
/// list: the field then takes focus on tap and typing narrows the menu. Only
/// a pick (a tap, or Enter on a highlighted entry) changes the value: typed
/// text, even text that names an entry exactly, is put back to the current
/// choice when the menu closes or focus leaves the field.
///
/// Esc closes an open menu; with the menu closed, the go-back keys (Esc,
/// Ctrl/Cmd-W) reach whatever is around the field, as from any other control:
/// an inline editor that closes on Esc, or the app's go-back.
///
/// Set [compact] for a list row's own control (a Settings row's trailing
/// control, a match picker inside a sentence): no filled box, only the value,
/// an arrow and a thin underline, 48 dp tall as a row's control is, while the
/// open menu is the same outlined menu as every other field's.
///
/// With [fillWidth] off the field is as wide as its widest entry (or hint, or
/// label) needs at the current text size, measured with the text style the
/// closed field draws with, so the value is never cut off. Where its parent
/// bounds the width (a Wrap or a Column) and that is narrower, it takes the
/// whole width; a parent that does not bound it (a Row's fixed child) gets
/// the measured width.
class AppDropdownField<T> extends FormField<T> {
  AppDropdownField({
    super.key,
    required T value,
    required this.entries,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.filterable = false,
    this.fillWidth = true,
    this.compact = false,
    this.clearsAfterPick = false,
    this.widthFits = const [],
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    bool enabled = true,
  }) : super(
         initialValue: value,
         enabled: enabled && onChanged != null,
         builder: (field) => (field as _AppDropdownFieldState<T>)._buildField(),
       );

  final List<AppDropdownEntry<T>> entries;
  final ValueChanged<T>? onChanged;

  /// Label, helper, hint and density, as for a text field. The suffix arrow and
  /// any validation error are added here.
  final InputDecoration decoration;

  /// Whether typing filters the menu. Off for short, fixed lists.
  final bool filterable;

  /// Whether the field fills the width it is given, as a text field does.
  /// When false it is as wide as its longest entry needs, but no wider than
  /// its parent allows: for a short list beside a field that should take the
  /// rest of the row, or a row's trailing control. The closed field cannot
  /// ellipsize, so a fixed narrow width would cut its value off.
  final bool fillWidth;

  /// Whether the field is a list row's own control rather than a form field:
  /// no fill and no box, the value in the weight a row's control uses, and a
  /// compact arrow. It is 48 dp tall at every density, and as tall as one
  /// line of its value once the text is large enough that the line is taller.
  final bool compact;

  /// Whether a pick is an action, not a choice: [onChanged] runs and the field
  /// goes back to showing [value] (usually nothing, with a hint such as
  /// "Add…"), so the next pick starts from the same place.
  final bool clearsAfterPick;

  /// Further text a field that does not [fillWidth] makes room for, in its
  /// hint style: a hint shown only at times, so the field keeps one width
  /// whether it shows a value or the hint.
  final List<String> widthFits;

  @override
  FormFieldState<T> createState() => _AppDropdownFieldState<T>();
}

/// [DropdownMenu]'s padding on each side of its arrow button.
const double _arrowPadding = 4;

/// A compact field's arrow, as wide as a plain dropdown's.
const double _compactArrow = 24;

/// A compact field's room before its value.
const double _compactStartPadding = 8;

/// The widest horizontal padding Material gives a text field with none set.
const double _defaultHorizontalPadding = 16;

/// The gap a text field leaves between its text and a suffix icon, in place
/// of its end padding.
const double _suffixGap = 4;

/// Room the text field keeps beside its text for the caret (its width and its
/// gap), plus a pixel against rounding.
const double _caretRoom = 4;

class _AppDropdownFieldState<T> extends FormFieldState<T> {
  final TextEditingController _text = TextEditingController();
  // On touch, the arrow is a select-only field's keyboard stop, so it takes
  // the go-back keys as the field does.
  late final FocusNode _arrowFocus = FocusNode(onKeyEvent: _onFieldKey);
  // The text field's own node, so its key handler runs before the menu's.
  late final FocusNode _fieldFocus = FocusNode(onKeyEvent: _onFieldKey);
  // The wrapper's own node: the field's handlers stop here when they pass a
  // key on to the page.
  final FocusNode _ownFocus = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );
  final MenuController _menu = MenuController();
  late final _tapOutside = _KeepFocusForMenuPress(_pressIsInMenu);
  bool _menuWasOpen = false;
  bool _focused = false;
  ScrollPosition? _scroll;
  bool _reopenAfterScroll = false;
  // True for the frames just after the field takes focus: the only time a
  // scroll is the field's own, not the user's.
  bool _justFocused = false;
  List<AppDropdownEntry<T>>? _builtFrom;
  List<DropdownMenuEntry<int>> _menuEntries = const [];

  @override
  AppDropdownField<T> get widget => super.widget as AppDropdownField<T>;

  int _indexOf(T? value) =>
      widget.entries.indexWhere((entry) => entry.value == value);

  AppDropdownEntry<T>? get _current {
    final index = _indexOf(value);
    return index < 0 ? null : widget.entries[index];
  }

  /// Shows the current choice's label, unless it already does.
  void _showCurrent() {
    final label = _current?.label ?? '';
    if (_text.text == label) return;
    _text.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _showCurrent();
  }

  @override
  void didUpdateWidget(AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
    // Also after a relabel (a new locale, a renamed entry). Not while the menu
    // is open, where the text may be the user's filter.
    if (!_menuWasOpen) _showCurrent();
  }

  @override
  void didChange(T? value) {
    super.didChange(value);
    _showCurrent();
  }

  @override
  void reset() {
    super.reset();
    _showCurrent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.isScrollingNotifier.removeListener(_onScrolling);
      _scroll = scroll?..isScrollingNotifier.addListener(_onScrolling);
    }
  }

  @override
  void dispose() {
    _scroll?.isScrollingNotifier.removeListener(_onScrolling);
    _text.dispose();
    _arrowFocus.dispose();
    _fieldFocus.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  /// The menu closes whenever the page scrolls under it. A filterable field
  /// scrolls the page itself as it takes focus (to stay on screen above the
  /// keyboard), which would shut the menu the tap just opened; open it again
  /// once that scroll is over. A scroll the user makes later closes the menu
  /// for good, as it does any menu.
  void _onScrolling() {
    if (!widget.filterable) return;
    if (_scroll!.isScrollingNotifier.value) {
      _reopenAfterScroll =
          _reopenAfterScroll || (_justFocused && _menuWasOpen && _focused);
    } else {
      _maybeReopen();
    }
  }

  /// Reopens a menu a scroll shut, once the scroll is over and the menu has
  /// finished closing (it reads as open for a moment after it is told to
  /// close).
  void _maybeReopen() {
    if (!_reopenAfterScroll || !mounted) return;
    if (_scroll?.isScrollingNotifier.value ?? false) return;
    if (_menu.isOpen) return;
    _reopenAfterScroll = false;
    if (!_focused) return;
    // Not from inside the scroll's own notification, mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focused && !_menu.isOpen) _menu.open();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onFocusChange(bool focused) {
    _focused = focused;
    if (focused) {
      // The scroll that brings a focused field on screen starts in the frame
      // after focus moves; two frames bound it without a timer.
      _justFocused = true;
      SchedulerBinding.instance.endOfFrame
          .then((_) => SchedulerBinding.instance.endOfFrame)
          .then((_) => _justFocused = false);
      return;
    }
    _reopenAfterScroll = false;
    // Tabbing away leaves no menu open over the next field.
    if (_menu.isOpen) _menu.close();
    _showCurrent();
  }

  /// Whether [event] presses inside this field's open menu: its entries, its
  /// padding, its scrollbar.
  ///
  /// The menu is a focus scope of its own under this field's node, laid out
  /// over the panel, so its rect is the panel's. No other scope is under it.
  bool _pressIsInMenu(PointerDownEvent event) =>
      _menu.isOpen &&
      _ownFocus.descendants.any(
        (node) => node is FocusScopeNode && node.rect.contains(event.position),
      );

  /// A go-back key (Esc, Ctrl/Cmd-W) in the field while its menu is closed.
  ///
  /// From inside the field, [DropdownMenu] would take a dismiss and do nothing
  /// with it, though nothing is open. Let go of the focus and offer the key
  /// instead to the key handlers above this field, nearest first, as if the
  /// field were not there: an inline editor that closes on Esc closes, and
  /// otherwise the app goes back, closing a dialog or leaving the page. With
  /// the menu open, Esc is the menu's, and closes it.
  ///
  /// The key is offered from the page's scope, where the focus has gone, so a
  /// shortcut bound between that scope and this field (none is today) would
  /// look up its action from the scope, not from here.
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _menu.isOpen) return KeyEventResult.ignored;
    final goBack = appShortcuts.entries.any(
      (binding) =>
          binding.value is GoBackIntent &&
          binding.key.accepts(event, HardwareKeyboard.instance),
    );
    if (!goBack) return KeyEventResult.ignored;
    _letGo();
    for (final ancestor in _ownFocus.ancestors) {
      final result =
          ancestor.onKeyEvent?.call(ancestor, event) ?? KeyEventResult.ignored;
      if (result != KeyEventResult.ignored) return result;
    }
    return KeyEventResult.handled;
  }

  /// Go back sent as an intent (the menu bar's Close) with the field focused.
  Object? _goBack(GoBackIntent intent) {
    if (_menu.isOpen) {
      _menu.close();
      return null;
    }
    _letGo();
    return Actions.maybeInvoke(context, intent);
  }

  /// Moves the focus off the field at once, so whatever acts next does so
  /// from the page around the field, not from inside the menu's handling.
  void _letGo() {
    if (_ownFocus.hasFocus) FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }

  /// Keeps the focus on the field while its menu is in use.
  ///
  /// [DropdownMenu] puts the focus on a node of its own when its arrow is
  /// clicked (or, on touch, when the field is tapped), and a pick from the
  /// menu then leaves it on the page instead of the field. Esc from either
  /// place misses the field and whatever surrounds it, such as an inline
  /// editor that closes on Esc. So when the menu opens on a desktop, move the
  /// focus to the field; and when the menu closes with the focus still on
  /// that node of the menu's, move it to the field, or on touch to the arrow.
  /// A press in the open menu leaves the field its focus
  /// ([_KeepFocusForMenuPress]), so a mouse pick ends on the field too.
  void _reclaimFocus({required bool opening}) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary == _fieldFocus || primary == _arrowFocus) {
      return;
    }
    final inMenu = primary.ancestors.contains(_ownFocus);
    if (opening && _fieldTakesFocus(context) && _fieldFocus.canRequestFocus) {
      _fieldFocus.requestFocus();
    } else if (inMenu) {
      // On touch, the arrow rather than a filterable field: focusing the
      // field there would raise the keyboard over a menu opened by its arrow.
      if (_fieldTakesFocus(context) && _fieldFocus.canRequestFocus) {
        _fieldFocus.requestFocus();
      } else if (widget.enabled) {
        _arrowFocus.requestFocus();
      }
    }
  }

  /// The menu's entries, rebuilt only when an entry changed: [DropdownMenu]
  /// drops its keyboard highlight whenever it is handed a new list.
  List<DropdownMenuEntry<int>> _entriesForMenu() {
    final from = widget.entries;
    final built = _builtFrom;
    if (built != null && _sameEntries(built, from)) return _menuEntries;
    _builtFrom = from;
    return _menuEntries = [
      for (final (index, entry) in from.indexed)
        DropdownMenuEntry<int>(
          value: index,
          label: entry.label,
          enabled: entry.enabled,
          leadingIcon: entry.leadingIcon,
          labelWidget: KeyedSubtree(key: entry.key, child: Text(entry.label)),
        ),
    ];
  }

  static bool _sameEntries<E>(
    List<AppDropdownEntry<E>> a,
    List<AppDropdownEntry<E>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.value != y.value ||
          x.label != y.label ||
          x.enabled != y.enabled ||
          x.key != y.key ||
          !_sameIcon(x.leadingIcon, y.leadingIcon)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameIcon(Widget? a, Widget? b) {
    if (a is Icon && b is Icon) {
      return a.icon == b.icon && a.size == b.size && a.color == b.color;
    }
    return identical(a, b);
  }

  void _onSelected(int? index) {
    // Null is "nothing matched what was typed", never a choice: entries are
    // addressed by position, so a null value is an index like any other.
    if (index == null) {
      _showCurrent();
      return;
    }
    final picked = widget.entries[index].value;
    if (widget.clearsAfterPick) {
      _showCurrent();
      widget.onChanged?.call(picked);
      return;
    }
    if (picked == value) {
      _showCurrent();
      return;
    }
    didChange(picked);
    widget.onChanged?.call(picked);
  }

  InputDecoration _decorate(BuildContext context, MenuController menu) {
    final open = menu.isOpen;
    if (!_menuWasOpen && open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reclaimFocus(opening: true);
      });
    }
    if (_menuWasOpen && !open) {
      // Closing without a pick (Esc, a tap outside) leaves a highlighted or
      // typed label in the field; put the choice back once the menu is gone.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCurrent();
        _reclaimFocus(opening: false);
        _maybeReopen();
      });
    }
    _menuWasOpen = open;
    var decoration = widget.decoration;
    final icon = _current?.leadingIcon;
    if (icon != null && decoration.prefixIcon == null) {
      decoration = decoration.copyWith(prefixIcon: icon);
    }
    if (errorText != null) {
      decoration = decoration.copyWith(errorText: errorText);
    }
    return decoration;
  }

  /// The closed field's width that shows its widest entry, hint or label in
  /// full: the text at the current text size, plus the field's padding, the
  /// arrow, any leading icon and the caret's room.
  double _contentWidth(
    TextStyle? style,
    InputDecorationThemeData decorationTheme, {
    required double arrowWidth,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widest = 0.0;
    void measure(String? text, TextStyle? textStyle, {double factor = 1}) {
      if (text == null || text.isEmpty) return;
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width * factor);
      painter.dispose();
    }

    for (final entry in widget.entries) {
      measure(entry.label, style);
    }
    final decoration = widget.decoration;
    measure(decoration.hintText, style?.merge(decoration.hintStyle));
    for (final text in widget.widthFits) {
      measure(text, style?.merge(decoration.hintStyle));
    }
    // A floating label is drawn at three quarters of the field's text size.
    measure(decoration.labelText, style, factor: 0.75);
    final padding =
        (decoration.contentPadding ?? decorationTheme.contentPadding)?.resolve(
          Directionality.of(context),
        ) ??
        const EdgeInsets.symmetric(horizontal: _defaultHorizontalPadding);
    final leading = widget.entries.any((e) => e.leadingIcon != null)
        ? kMinInteractiveDimension
        : 0.0;
    // A suffix replaces the end padding with a fixed gap; count whichever is
    // wider.
    final ltr = Directionality.of(context) == TextDirection.ltr;
    final (start, end) = ltr
        ? (padding.left, padding.right)
        : (padding.right, padding.left);
    final horizontal = start + math.max(end, _suffixGap);
    return (widest + horizontal + arrowWidth + leading + _caretRoom)
        .ceilToDouble();
  }

  /// The closed field of a [AppDropdownField.compact] field: no fill or box,
  /// only an underline in the theme's divider (heavier in High contrast), and
  /// the theme's focus ring colour under a focused field.
  static InputDecorationThemeData _compactDecorationTheme(
    ThemeData theme,
    TextStyle? style,
    TextScaler scaler,
  ) {
    final line = BorderSide(
      color: theme.dividerTheme.color ?? theme.colorScheme.outlineVariant,
      width: theme.dividerTheme.thickness ?? 1,
    );
    final focus =
        theme.inputDecorationTheme.focusedBorder?.borderSide ??
        BorderSide(color: theme.colorScheme.primary, width: 2);
    final error = BorderSide(color: theme.colorScheme.error, width: line.width);
    final fontSize = style?.fontSize ?? 16;
    final lineHeight = scaler.scale(fontSize) * (style?.height ?? 1.5);
    // The decorator adds the density's height adjustment (8 dp less at a
    // desktop's compact density) to whatever the padding gives.
    final density = theme.visualDensity.baseSizeAdjustment.dy;
    final vertical = math.max(
      0.0,
      (kMinInteractiveDimension - lineHeight - density) / 2,
    );
    return InputDecorationThemeData(
      filled: false,
      isDense: true,
      // Padding that makes the field 48 dp tall, a row control's height, at
      // any density; once a line of large text is taller than that, the
      // field is one line tall and no more (a list tile's trailing slot is at
      // most 56 dp tall, 48 dp at a desktop's compact density).
      contentPadding: EdgeInsetsDirectional.fromSTEB(
        _compactStartPadding,
        vertical,
        0,
        vertical,
      ),
      // [DropdownMenu] hands these to its arrow button as well as to the
      // decorator, so they are the arrow's own size, not its slot's.
      suffixIconConstraints: const BoxConstraints(
        minWidth: _compactArrow,
        minHeight: _compactArrow,
      ),
      border: UnderlineInputBorder(borderSide: line),
      enabledBorder: UnderlineInputBorder(borderSide: line),
      focusedBorder: UnderlineInputBorder(borderSide: focus),
      errorBorder: UnderlineInputBorder(borderSide: error),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: focus.copyWith(color: theme.colorScheme.error),
      ),
      disabledBorder: UnderlineInputBorder(
        borderSide: line.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
    );
  }

  static bool _fieldTakesFocus(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia => false,
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
      };

  Widget _buildField() {
    final selected = _indexOf(value);
    final filterable = widget.filterable;
    // Where the field itself takes focus, the arrow is part of it, not a
    // second Tab stop beside it. Where it does not (select-only on touch),
    // the arrow is how a hardware keyboard reaches the menu.
    _arrowFocus.skipTraversal = filterable || _fieldTakesFocus(context);
    // With a node of its own, [DropdownMenu] asks the node, not
    // `requestFocusOnTap`, whether a tap focuses the field.
    _fieldFocus.canRequestFocus = filterable || _fieldTakesFocus(context);
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final compact = widget.compact;
    final textStyle = compact
        ? theme.textTheme.titleMedium
        : theme.dropdownMenuTheme.textStyle ?? theme.textTheme.bodyLarge;
    final decorationTheme = compact
        ? _compactDecorationTheme(
            theme,
            textStyle,
            MediaQuery.textScalerOf(context),
          )
        : null;
    final denseArrow =
        (widget.decoration.isDense ?? false) &&
        theme.visualDensity.vertical < 0;
    Widget field = DropdownMenu<int>(
      controller: _text,
      menuController: _menu,
      focusNode: _fieldFocus,
      enabled: widget.enabled,
      initialSelection: selected < 0 ? null : selected,
      // Fill the slot: the text fields' slot, or the width set below.
      expandedInsets: EdgeInsets.zero,
      textStyle: compact ? textStyle : null,
      inputDecorationTheme: decorationTheme,
      decorationBuilder: _decorate,
      trailingIconFocusNode: _arrowFocus,
      onSelected: _onSelected,
      enableFilter: filterable,
      enableSearch: filterable,
      selectOnly: !filterable,
      // A filterable field's arrow is a button of its own beside the field,
      // so it needs a name; a select-only field's arrow is part of the field
      // and [DropdownMenu] leaves it out of the semantics tree.
      trailingIcon: Icon(
        Icons.arrow_drop_down,
        semanticLabel: localizations.showMenuTooltip,
      ),
      selectedTrailingIcon: Icon(
        Icons.arrow_drop_up,
        semanticLabel: localizations.showMenuTooltip,
      ),
      // Unused while [focusNode] is set (see `_fieldFocus.canRequestFocus`,
      // which carries the same rule); kept so the rule reads here too. A
      // filterable field takes focus on tap so it can be typed in. A
      // select-only one takes it only on desktop, where Enter and the arrow
      // keys then work the menu; on touch it never takes focus, so a tap
      // never raises the keyboard.
      requestFocusOnTap: filterable || _fieldTakesFocus(context),
      dropdownMenuEntries: _entriesForMenu(),
    );
    if (!widget.fillWidth) {
      // As wide as the widest entry needs, but no wider than the slot (a box
      // wider than its constraints is clamped to them). Measured here rather
      // than left to [DropdownMenu]: its own measure reads the entries in the
      // menu's smaller label style, so a long value would not fit the field
      // it measured.
      field = SizedBox(
        width: _contentWidth(
          textStyle,
          decorationTheme ?? theme.inputDecorationTheme,
          arrowWidth: compact
              ? _compactArrow + 2 * _arrowPadding
              : (denseArrow ? 32 : kMinInteractiveDimension) +
                    2 * _arrowPadding,
        ),
        child: field,
      );
    }
    if (compact) {
      // The arrow is a row control's arrow, not a full-size button: the whole
      // field is the tap target, 48 dp tall as a row's control is.
      field = IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(_compactArrow),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: field,
      );
    } else if (denseArrow) {
      // A dense field stays dense at a compact (pointer) density: the menu's
      // arrow button would otherwise hold it at a full-size button's height.
      // At a touch density the arrow keeps its full-size target.
      field = IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: field,
      );
    }
    return Focus(
      focusNode: _ownFocus,
      onFocusChange: _onFocusChange,
      child: Actions(
        actions: {
          GoBackIntent: CallbackAction<GoBackIntent>(onInvoke: _goBack),
          EditableTextTapOutsideIntent: _tapOutside,
        },
        child: field,
      ),
    );
  }
}

/// Keeps the text field's focus for a press inside its own open menu.
///
/// A text field drops its focus on a press outside itself: any press on a
/// desktop, a mouse or stylus press on a phone or tablet. [DropdownMenu]'s
/// menu is outside its text field, so a mouse click on an entry would take
/// the field's focus, the field would close its menu on that blur
/// ([_AppDropdownFieldState._onFocusChange]), and the release would find
/// nothing to pick (#2292). A press in the menu that picks nothing (its
/// padding, a right-click) must not strand the focus on the page either,
/// out of reach of Esc and Tab while the menu is still open. So a press in
/// the menu leaves the focus where it is; any other press is the text
/// field's own, as before.
class _KeepFocusForMenuPress
    extends ContextAction<EditableTextTapOutsideIntent> {
  _KeepFocusForMenuPress(this.inMenu);

  final bool Function(PointerDownEvent event) inMenu;

  @override
  Object? invoke(EditableTextTapOutsideIntent intent, [BuildContext? context]) {
    if (inMenu(intent.pointerDownEvent)) return null;
    final standard = callingAction;
    return standard is ContextAction<EditableTextTapOutsideIntent>
        ? standard.invoke(intent, context)
        : standard?.invoke(intent);
  }
}
