import 'package:flutter/material.dart';

import 'program_matrix_table.dart' show ProgramMatrixTable;

/// Builds a single option row (e.g. a [ListTile]) for [option]. [onSelected]
/// is pre-bound to that option — the tile just calls it on tap — so callers
/// keep authoring the exact same row widget (icons, subtitles, "create new"
/// styling) they used inside a hand-rolled `Autocomplete.optionsViewBuilder`
/// `ListView`, just factored down to one item.
typedef AutocompleteOptionTileBuilder<T extends Object> =
    Widget Function(BuildContext context, T option, VoidCallback onSelected);

/// Same shape as [AutocompleteOptionsBuilder] but synchronous. Every current
/// call site filters an already-loaded in-memory list, so this widget doesn't
/// need (and doesn't implement) the async/race-handling machinery the
/// framework's `FutureOr`-returning variant implies — a sync function is
/// always assignable where the framework's is expected.
typedef PickerOptionsBuilder<T extends Object> =
    Iterable<T> Function(TextEditingValue textEditingValue);

/// A drop-in replacement for [Autocomplete] that fixes issue #716: on a phone,
/// the software keyboard covers a field-anchored options overlay, and the
/// overlay dismisses if a drag starts outside it (because `Autocomplete` ties
/// the overlay to the field's focus). Net effect: picking an existing option
/// is harder than typing a fresh one, and a focused option can end up fully
/// hidden by the keyboard (WCAG 2.2 SC 2.4.11).
///
/// The fix is responsive, not a rewrite:
/// * **Wide/tall enough** (desktop/tablet): delegates straight to a real
///   [Autocomplete], unchanged — so its native keyboard/AT navigation and
///   focus handling keep working exactly as they do today.
/// * **Narrow or short** (phones, including landscape): the field becomes a
///   read-only "launcher" and options are presented in a keyboard-aware
///   [showModalBottomSheet] (a [DraggableScrollableSheet] padded for
///   `MediaQuery.viewInsets`, mirroring `perform_adjust_sheet.dart` /
///   `venue_editor_sheet.dart` / `custom_fields_screen.dart`). The sheet's own
///   list scrolls independently of any field focus, so a drag anywhere on the
///   sheet — not just inside a tiny fixed-height popover — scrolls it without
///   dismissing.
///
/// Both layouts share the same [optionsBuilder], [fieldViewBuilder], and
/// [optionTileBuilder], so option filtering, free-text/"create new" handling,
/// and every [ValueKey] a call site (or its widget tests) depends on are
/// identical between the two — only the *container* around the options
/// differs.
class ResponsiveAutocomplete<T extends Object> extends StatefulWidget {
  const ResponsiveAutocomplete({
    super.key,
    required this.optionsBuilder,
    required this.displayStringForOption,
    required this.onSelected,
    required this.fieldViewBuilder,
    required this.optionTileBuilder,
    this.initialValue,
    this.textEditingController,
    this.focusNode,
    this.autofocus = false,
    this.sheetSemanticLabel,
    this.overlayConstraints = const BoxConstraints(
      maxHeight: 240,
      maxWidth: 320,
    ),
    this.compactWidthBreakpoint = ProgramMatrixTable.compactBreakpoint,
    this.compactHeightBreakpoint = _defaultCompactHeightBreakpoint,
  }) : assert(
         textEditingController == null || initialValue == null,
         'Provide either initialValue or textEditingController, not both '
         '(mirrors Autocomplete).',
       );

  /// Width (logical pixels) below which the narrow/sheet layout is used,
  /// mirroring [ProgramMatrixTable.compactBreakpoint] (Material 3's compact
  /// window-size-class cutoff) so phones get the sheet and tablets/desktop
  /// keep the fast inline overlay.
  final double compactWidthBreakpoint;

  /// Height (logical pixels) below which the narrow/sheet layout is used even
  /// if [compactWidthBreakpoint] isn't tripped.
  ///
  /// A landscape phone is commonly *wider* than [compactWidthBreakpoint]
  /// (e.g. ~800dp) but only ~360-430dp *tall* — width alone would still route
  /// it to the inline overlay even though the on-screen keyboard occupies a
  /// large fraction of that short height, reproducing the exact occlusion
  /// this widget exists to fix. 480 sits comfortably above real
  /// landscape-phone heights and comfortably below small-tablet-landscape
  /// heights (iPad mini landscape is ~768dp), so tablets aren't
  /// misclassified as compact.
  final double compactHeightBreakpoint;

  static const double _defaultCompactHeightBreakpoint = 480;

  /// Given the current field text, returns the matching options (already
  /// filtered/sorted/capped by the caller — this widget does no filtering of
  /// its own).
  final PickerOptionsBuilder<T> optionsBuilder;

  /// Same contract as [RawAutocomplete.displayStringForOption].
  final AutocompleteOptionToString<T> displayStringForOption;

  /// Called when the user picks an option, in either layout.
  final AutocompleteOnSelected<T> onSelected;

  /// Same contract as [RawAutocomplete.fieldViewBuilder]: builds the
  /// interactive text field. Reused verbatim for the wide inline field *and*
  /// for the real field inside the narrow-layout sheet, so `onChanged`/
  /// `onSubmitted` free-text handling behaves identically in both.
  final AutocompleteFieldViewBuilder fieldViewBuilder;

  /// Builds one option row. Used both inside the wide overlay's `ListView`
  /// and the narrow sheet's `ListView.builder`.
  final AutocompleteOptionTileBuilder<T> optionTileBuilder;

  final TextEditingValue? initialValue;
  final TextEditingController? textEditingController;
  final FocusNode? focusNode;

  /// When true, grabs focus (wide) or opens the sheet (narrow) on the first
  /// frame after mount — mirrors `TextField.autofocus`, but on narrow layouts
  /// a read-only launcher field can't itself raise the keyboard, so autofocus
  /// there means "open the picker immediately" instead.
  final bool autofocus;

  /// Announced (as a semantics header) when the narrow-layout sheet opens,
  /// e.g. "Search moves". Ignored on the wide layout.
  final String? sheetSemanticLabel;

  /// Size constraints for the wide layout's floating options popover. Ignored
  /// on the narrow layout (the sheet sizes itself via
  /// [DraggableScrollableSheet]).
  final BoxConstraints overlayConstraints;

  @override
  State<ResponsiveAutocomplete<T>> createState() =>
      _ResponsiveAutocompleteState<T>();
}

class _ResponsiveAutocompleteState<T extends Object>
    extends State<ResponsiveAutocomplete<T>> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocusNode;
  bool _didScheduleAutofocus = false;
  bool _sheetOpen = false;
  // Popping the sheet restores focus to whatever previously held it (the
  // launcher field), which would otherwise immediately re-trigger
  // [_handleFocusChange] and reopen the sheet. Set right before the sheet
  // closes so exactly that one restored-focus event is ignored; a genuine
  // later Tab/AT focus still opens it normally.
  bool _ignoreNextFocusGain = false;

  TextEditingController get _controller {
    if (widget.textEditingController != null) {
      return widget.textEditingController!;
    }
    return _ownedController ??= TextEditingController(
      text: widget.initialValue?.text,
    );
  }

  FocusNode get _focusNode {
    if (widget.focusNode != null) return widget.focusNode!;
    return _ownedFocusNode ??= FocusNode();
  }

  bool _isCompact(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < widget.compactWidthBreakpoint ||
        size.height < widget.compactHeightBreakpoint;
  }

  @override
  void initState() {
    super.initState();
    // A single listener (not a second Focus widget — the launcher TextField
    // built by fieldViewBuilder already owns this node) so that focus
    // arriving via Tab/AT traversal (not just a tap) opens the sheet too.
    // Guarded to the compact layout so normal wide-layout typing focus never
    // triggers it.
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!mounted || !_focusNode.hasFocus) return;
    if (_ignoreNextFocusGain) {
      _ignoreNextFocusGain = false;
      return;
    }
    if (_isCompact(context)) _openSheet();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownedController?.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _scheduleAutofocusIfNeeded(bool compact) {
    if (!widget.autofocus || _didScheduleAutofocus) return;
    _didScheduleAutofocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (compact) {
        _openSheet();
      } else if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _openSheet() async {
    if (_sheetOpen) return;
    // Rebuilds the launcher out of the tree (see `build`'s narrow branch) so
    // the sheet's own field — built from the same [fieldViewBuilder] and
    // therefore carrying the same call-site [ValueKey] — is never mounted
    // simultaneously with it.
    setState(() => _sheetOpen = true);
    final l10n = widget.sheetSemanticLabel;
    final picked = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (sheetContext, scrollController) {
              return _AutocompleteSheetContent<T>(
                initialText: _controller.text,
                optionsBuilder: widget.optionsBuilder,
                fieldViewBuilder: widget.fieldViewBuilder,
                optionTileBuilder: widget.optionTileBuilder,
                scrollController: scrollController,
                semanticLabel: l10n,
              );
            },
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    _ignoreNextFocusGain = true;
    if (picked != null) {
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = _isCompact(context);
    _scheduleAutofocusIfNeeded(compact);
    if (!compact) {
      return Autocomplete<T>(
        initialValue: widget.textEditingController == null
            ? widget.initialValue
            : null,
        textEditingController: widget.textEditingController,
        focusNode: widget.focusNode,
        displayStringForOption: widget.displayStringForOption,
        optionsBuilder: widget.optionsBuilder,
        onSelected: widget.onSelected,
        fieldViewBuilder: widget.fieldViewBuilder,
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: AlignmentDirectional.topStart,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: widget.overlayConstraints,
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final option in options)
                      widget.optionTileBuilder(
                        context,
                        option,
                        () => onSelected(option),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // Narrow layout: a read-only "launcher" field that opens the keyboard-safe
    // sheet on tap. Focus arriving via Tab/AT traversal (not just a tap) is
    // handled by the `_focusNode` listener registered in [initState] — NOT a
    // second `Focus` widget here, since the field built by [fieldViewBuilder]
    // already attaches `_focusNode` to its own internal `Focus`, and a
    // `FocusNode` can only be attached to one `Focus` widget at a time.
    // `AbsorbPointer` keeps the field itself from ever taking the tap (and
    // therefore never raising the keyboard); the `GestureDetector` above it
    // handles the tap instead.
    //
    // While the sheet is open, the launcher is collapsed rather than kept
    // mounted: the sheet's own field is built from this same
    // [fieldViewBuilder] and therefore carries the same call-site [ValueKey]
    // (e.g. `move-input`) — mounting both at once would put two widgets with
    // an identical key in the tree, breaking key-based finders in tests (and
    // in spirit, the "one keyed field" contract every call site relies on).
    // The launcher is fully hidden behind the modal barrier regardless, so
    // collapsing it has no visible effect for the user.
    return Semantics(
      button: true,
      hint: widget.sheetSemanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openSheet,
        child: _sheetOpen
            ? const SizedBox.shrink()
            : AbsorbPointer(
                child: widget.fieldViewBuilder(
                  context,
                  _controller,
                  _focusNode,
                  () {},
                ),
              ),
      ),
    );
  }
}

class _AutocompleteSheetContent<T extends Object> extends StatefulWidget {
  const _AutocompleteSheetContent({
    required this.initialText,
    required this.optionsBuilder,
    required this.fieldViewBuilder,
    required this.optionTileBuilder,
    required this.scrollController,
    this.semanticLabel,
  });

  final String initialText;
  final PickerOptionsBuilder<T> optionsBuilder;
  final AutocompleteFieldViewBuilder fieldViewBuilder;
  final AutocompleteOptionTileBuilder<T> optionTileBuilder;
  final ScrollController scrollController;
  final String? semanticLabel;

  @override
  State<_AutocompleteSheetContent<T>> createState() =>
      _AutocompleteSheetContentState<T>();
}

class _AutocompleteSheetContentState<T extends Object>
    extends State<_AutocompleteSheetContent<T>> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final FocusNode _focusNode = FocusNode();
  late Iterable<T> _options = widget.optionsBuilder(
    TextEditingValue(text: widget.initialText),
  );

  @override
  void initState() {
    super.initState();
    // Sheets open already focused so typing can start immediately — matches
    // the keyboard-up state the user was just in before opening the sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _recompute() {
    setState(() {
      _options = widget.optionsBuilder(
        TextEditingValue(text: _controller.text),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = _options.toList();
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _SheetField(
            controller: _controller,
            focusNode: _focusNode,
            fieldViewBuilder: widget.fieldViewBuilder,
            onChanged: _recompute,
            onSubmit: () => Navigator.of(context).maybePop(),
          ),
        ),
        Expanded(
          child: options.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return widget.optionTileBuilder(
                      context,
                      option,
                      () => Navigator.of(context).pop(option),
                    );
                  },
                ),
        ),
      ],
    );
    // A container-level label (rather than a zero-size header node) so
    // screen readers announce the picker's purpose (e.g. "Related dance")
    // as soon as the sheet opens, regardless of geometry.
    return widget.semanticLabel == null
        ? content
        : Semantics(
            container: true,
            label: widget.semanticLabel,
            child: content,
          );
  }
}

/// Wraps the caller's [AutocompleteFieldViewBuilder] so we can observe text
/// changes (to re-run [PickerOptionsBuilder]) without altering the
/// field widget the builder returns.
class _SheetField extends StatefulWidget {
  const _SheetField({
    required this.controller,
    required this.focusNode,
    required this.fieldViewBuilder,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AutocompleteFieldViewBuilder fieldViewBuilder;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  State<_SheetField> createState() => _SheetFieldState();
}

class _SheetFieldState extends State<_SheetField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(widget.onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(widget.onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.fieldViewBuilder(
      context,
      widget.controller,
      widget.focusNode,
      widget.onSubmit,
    );
  }
}
