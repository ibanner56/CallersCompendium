import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

/// One selectable entry in a [MoveAutocomplete]: either a canonical move or an
/// alias. [id] is what gets stored on the figure/query (a move id or an alias
/// id), so aliases keep their own identity (a "see saw" stays a see saw).
class MoveOption {
  const MoveOption({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// A keyboard-first type-ahead move picker over a [Taxonomy]'s moves (and,
/// optionally, aliases). Typing `sw` offers swing; selecting an option reports
/// it via [onSelected]. Factored out of the search query builder so the dance
/// editor and the "has figure" search row share one move picker
/// (`docs/design/ux.md` §3).
class MoveAutocomplete extends StatefulWidget {
  const MoveAutocomplete({
    super.key,
    required this.taxonomy,
    required this.initialText,
    required this.onSelected,
    this.dialect,
    this.fieldKey,
    this.onCleared,
    this.onCustomSubmitted,
    this.includeAliases = true,
    this.hintText = 'e.g. swing',
    this.labelText = 'Move',
    this.autofocus = false,
  });

  final Taxonomy taxonomy;

  /// Active dialect. When non-null (and non-canonical), option labels and the
  /// resting field text render via the dialect's move substitutions and typing
  /// matches those dialect terms too (e.g. a custom "buzz" for `swing` both
  /// displays and is searchable). Null falls back to canonical taxonomy names.
  final Dialect? dialect;

  /// Text shown initially in the field (e.g. the current move's display name).
  final String initialText;

  /// Called when the user picks a move/alias from the options.
  final ValueChanged<MoveOption> onSelected;

  /// Optional key stem for the inner [TextField] (`<fieldKey>-input`).
  final String? fieldKey;

  /// Called when the field is emptied (clears the current move).
  final VoidCallback? onCleared;

  /// Called when the user submits free text that matches no move — the hook the
  /// editor uses to spin up a custom figure. Null disables custom entry.
  final ValueChanged<String>? onCustomSubmitted;

  final bool includeAliases;
  final String hintText;
  final String labelText;
  final bool autofocus;

  @override
  State<MoveAutocomplete> createState() => _MoveAutocompleteState();
}

class _MoveAutocompleteState extends State<MoveAutocomplete> {
  // Fires once per mount to reliably grab focus on a cold start. Relying on
  // `TextField.autofocus` alone drops the request when the enclosing FocusScope
  // isn't yet active (a freshly opened editor before any manual focus), so we
  // explicitly requestFocus after the first frame, which walks up and activates
  // the ancestor scopes. Because the field remounts on each open (keyed by
  // figure index), this runs on every open — exactly when we want it.
  bool _didRequestAutofocus = false;

  void _scheduleAutofocus(FocusNode focusNode) {
    if (!widget.autofocus || _didRequestAutofocus) return;
    _didRequestAutofocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !focusNode.hasFocus) focusNode.requestFocus();
    });
  }

  List<MoveOption> _optionsFor(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final dialect = widget.dialect ?? Dialect.canonical;
    final renderer = FigureRenderer(widget.taxonomy);
    // Match on canonical name, id, keywords, AND the dialect display term so a
    // user can type a custom substitution (e.g. "buzz" for swing).
    bool matches(
      String id,
      String displayName,
      String dialectName,
      List<String> keywords,
    ) {
      return displayName.toLowerCase().contains(q) ||
          dialectName.toLowerCase().contains(q) ||
          id.toLowerCase().contains(q) ||
          keywords.any((k) => k.toLowerCase().contains(q));
    }

    final options = <MoveOption>[
      for (final m in widget.taxonomy.moves.values)
        if (matches(
          m.id,
          m.displayName,
          renderer.displayMoveName(m.id, dialect),
          m.searchKeywords,
        ))
          MoveOption(
            id: m.id,
            displayName: renderer.displayMoveName(m.id, dialect),
          ),
      if (widget.includeAliases)
        for (final a in widget.taxonomy.aliases.values)
          if (matches(
            a.id,
            a.displayName,
            renderer.displayMoveName(a.id, dialect),
            a.searchKeywords,
          ))
            MoveOption(
              id: a.id,
              displayName: renderer.displayMoveName(a.id, dialect),
            ),
    ];
    return options.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<MoveOption>(
      initialValue: TextEditingValue(text: widget.initialText),
      displayStringForOption: (o) => o.displayName,
      optionsBuilder: (value) => _optionsFor(value.text),
      onSelected: widget.onSelected,
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      key: ValueKey(
                        '${widget.fieldKey ?? 'move'}-option-${option.id}',
                      ),
                      dense: true,
                      title: Text(option.displayName),
                      onTap: () => onSelected(option),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        // Explicitly grab focus on the first frame this field is built so cold
        // starts work; TextField.autofocus stays as a belt-and-suspenders.
        _scheduleAutofocus(focusNode);
        return TextField(
          key: widget.fieldKey == null
              ? null
              : ValueKey('${widget.fieldKey}-input'),
          controller: controller,
          focusNode: focusNode,
          autofocus: widget.autofocus,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (text) {
            if (text.trim().isEmpty) widget.onCleared?.call();
          },
          onSubmitted: (text) {
            final q = text.trim();
            final options = _optionsFor(q);
            if (options.isNotEmpty) {
              widget.onSelected(options.first);
            } else if (q.isNotEmpty) {
              widget.onCustomSubmitted?.call(q);
            }
            onSubmit();
          },
        );
      },
    );
  }
}
