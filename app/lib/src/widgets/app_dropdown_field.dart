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
class AppDropdownField<T> extends FormField<T> {
  AppDropdownField({
    super.key,
    required T value,
    required this.entries,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.filterable = false,
    this.fillWidth = true,
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
  /// When false it is as wide as its longest entry, for a short list beside a
  /// field that should take the rest of the row: the closed field cannot
  /// ellipsize, so a fixed narrow width would cut its value off.
  final bool fillWidth;

  @override
  FormFieldState<T> createState() => _AppDropdownFieldState<T>();
}

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
  bool _menuWasOpen = false;
  bool _focused = false;
  ScrollPosition? _scroll;
  bool _reopenAfterScroll = false;
  // True for the frames just after the field takes focus: the only time a
  // scroll is the field's own, not the user's.
  bool _justFocused = false;
  // Whether a pick returns the focus to the field (on a desktop), set when the
  // menu opens; and whether an entry was picked since then.
  bool _focusBackOnClose = false;
  bool _pickedSinceOpen = false;
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
  /// finished closing (it animates shut, and reads as open until then).
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
  /// focus to the field, and give it back to the field if the menu closes
  /// with the focus dropped to the page; and when the menu closes with the
  /// focus still on that node of the menu's, move it to the field, or on
  /// touch to the arrow.
  void _reclaimFocus({required bool opening}) {
    final primary = FocusManager.instance.primaryFocus;
    if (opening) {
      _focusBackOnClose = _fieldTakesFocus(context);
      _pickedSinceOpen = false;
    }
    if (primary == null || primary == _fieldFocus || primary == _arrowFocus) {
      return;
    }
    final inMenu = primary.ancestors.contains(_ownFocus);
    // A mouse pick from the menu takes the focus off the field, back to the
    // page's scope; return it, as a menu returns it to its button.
    final dropped =
        primary is FocusScopeNode && _ownFocus.ancestors.contains(primary);
    // Only after a pick: a click elsewhere that dismissed the menu keeps the
    // focus where that click left it.
    final backOnClose = _focusBackOnClose && _pickedSinceOpen;
    if (!opening) _focusBackOnClose = _pickedSinceOpen = false;
    if (opening && _fieldTakesFocus(context) && _fieldFocus.canRequestFocus) {
      _fieldFocus.requestFocus();
    } else if (!opening && dropped && backOnClose) {
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
    if (index != null) _pickedSinceOpen = true;
    // Null is "nothing matched what was typed", never a choice: entries are
    // addressed by position, so a null value is an index like any other.
    if (index == null) {
      _showCurrent();
      return;
    }
    final picked = widget.entries[index].value;
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
    Widget field = DropdownMenu<int>(
      // A field sized to its widest entry measures the entries once; measure
      // again when their labels change (another language, say).
      key: widget.fillWidth
          ? null
          : ValueKey(Object.hashAll(widget.entries.map((e) => e.label))),
      controller: _text,
      menuController: _menu,
      focusNode: _fieldFocus,
      enabled: widget.enabled,
      initialSelection: selected < 0 ? null : selected,
      // Fill the slot, as the text fields beside it do, unless asked to size
      // to the widest entry.
      expandedInsets: widget.fillWidth ? EdgeInsets.zero : null,
      decorationBuilder: _decorate,
      trailingIconFocusNode: _arrowFocus,
      onSelected: _onSelected,
      enableFilter: filterable,
      enableSearch: filterable,
      selectOnly: !filterable,
      // Unused while [focusNode] is set (see `_fieldFocus.canRequestFocus`,
      // which carries the same rule); kept so the rule reads here too. A
      // filterable field takes focus on tap so it can be typed in. A
      // select-only one takes it only on desktop, where Enter and the arrow
      // keys then work the menu; on touch it never takes focus, so a tap
      // never raises the keyboard.
      requestFocusOnTap: filterable || _fieldTakesFocus(context),
      dropdownMenuEntries: _entriesForMenu(),
    );
    if ((widget.decoration.isDense ?? false) &&
        Theme.of(context).visualDensity.vertical < 0) {
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
        },
        child: field,
      ),
    );
  }
}
