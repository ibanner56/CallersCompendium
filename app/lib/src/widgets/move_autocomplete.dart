import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import 'responsive_autocomplete.dart';

/// The kind of entry selected from a [MoveAutocomplete]: a taxonomy move or
/// alias, the structural modifier or sequence, or one of the user's own
/// figures, a
/// compound (#709) or a new figure (#1023), whose [MoveOption.id] is its
/// glossary entry id.
enum MoveOptionKind { move, modifier, sequence, compound, userFigure }

/// One selectable entry in a [MoveAutocomplete]: either a canonical move, an
/// alias, or an enabled structural option. [id] is what gets stored on the
/// figure/query (a move id, an alias id, or a structural move id), so aliases
/// keep their own identity (a "see saw" stays a see saw).
class MoveOption {
  const MoveOption({
    required this.id,
    required this.displayName,
    this.kind = MoveOptionKind.move,
    this.searchTerms = const [],
  });

  final String id;
  final String displayName;
  final MoveOptionKind kind;

  /// One of the user's own figures, listed first and marked as theirs.
  bool get isUsers =>
      kind == MoveOptionKind.compound || kind == MoveOptionKind.userFigure;

  /// Other words that find one of the user's own figures: its keywords.
  final List<String> searchTerms;
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
    this.includeModifier = false,
    this.includeSequence = false,
    this.compoundOptions = const [],
    this.compoundMarkerLabel = 'custom',
    this.includeCustomMove = true,
    this.modifierOptionLabel = 'modifier',
    this.sequenceOptionLabel = 'sequence',
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

  /// Text shown in the field (e.g. the current move's display name). Changes
  /// after mount update the field when it owns its controller.
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

  /// Whether to offer the structural `modifier` option alongside taxonomy
  /// moves. Callers that enable this must handle [MoveOptionKind.modifier] by
  /// creating a container draft rather than storing [modifierMove] as a
  /// leaf move.
  final bool includeModifier;

  /// Whether to offer the structural `sequence` option. As for
  /// [includeModifier], a caller that enables it must handle
  /// [MoveOptionKind.sequence] by creating a container draft.
  final bool includeSequence;

  /// The user's own figures to offer: combinations (#709), each a
  /// [MoveOptionKind.compound] option, and new figures (#1023), each a
  /// [MoveOptionKind.userFigure] option. Matching ones are listed before
  /// every move, within the same cap. Empty (the default) offers none.
  final List<MoveOption> compoundOptions;

  /// What marks one of [compoundOptions] as the user's own, in words.
  final String compoundMarkerLabel;

  /// Whether the taxonomy's own [customMove] is offered. An editor that
  /// cannot hold a custom figure turns it off, as it turns off
  /// [onCustomSubmitted].
  final bool includeCustomMove;

  /// Label shown for the optional structural modifier entry.
  final String modifierOptionLabel;

  /// Label shown for the optional structural sequence entry.
  final String sequenceOptionLabel;

  final String hintText;
  final String labelText;
  final bool autofocus;

  @override
  State<MoveAutocomplete> createState() => _MoveAutocompleteState();
}

class _MoveAutocompleteState extends State<MoveAutocomplete> {
  static String _labelKey(String label) => label.trim().toLowerCase();

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
      for (final c in widget.compoundOptions)
        if (c.displayName.toLowerCase().contains(q) ||
            c.searchTerms.any((k) => k.toLowerCase().contains(q)))
          c,
      if (widget.includeModifier &&
          matches(
            modifierMove,
            widget.modifierOptionLabel,
            widget.modifierOptionLabel,
            const [],
          ))
        MoveOption(
          id: modifierMove,
          displayName: widget.modifierOptionLabel,
          kind: MoveOptionKind.modifier,
        ),
      if (widget.includeSequence &&
          matches(
            sequenceMove,
            widget.sequenceOptionLabel,
            widget.sequenceOptionLabel,
            const [],
          ))
        MoveOption(
          id: sequenceMove,
          displayName: widget.sequenceOptionLabel,
          kind: MoveOptionKind.sequence,
        ),
      for (final m in widget.taxonomy.moves.values)
        if ((widget.includeCustomMove || m.id != customMove) &&
            matches(
              m.id,
              m.displayName,
              renderer.displayMoveName(m.id, dialect),
              m.searchKeywords,
            ))
          MoveOption(
            id: m.id,
            displayName: renderer.displayMoveName(m.id, dialect),
          ),
    ];
    if (widget.includeAliases) {
      // An alias whose label equals one already offered (the v34 "pull by"
      // aliases all read "pull by") is indistinguishable in the list, so it
      // only costs a slot and invites a coin-flip. Drop it; the move, or the
      // earlier alias, already covers that label. Moves are never dropped, so
      // a dialect that gives two moves one term cannot hide either of them.
      final labels = {
        for (final o in options)
          if (!o.isUsers) _labelKey(o.displayName),
      };
      for (final a in widget.taxonomy.aliases.values) {
        final label = renderer.displayMoveName(a.id, dialect);
        if (matches(a.id, a.displayName, label, a.searchKeywords) &&
            labels.add(_labelKey(label))) {
          options.add(MoveOption(id: a.id, displayName: label));
        }
      }
    }
    return options.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAutocomplete<MoveOption>(
      initialValue: TextEditingValue(text: widget.initialText),
      displayStringForOption: (o) => o.displayName,
      // Reuses the field's own label as the sheet's a11y announcement (e.g.
      // "Move") — matches the field the user was just interacting with,
      // rather than introducing a separate string.
      sheetSemanticLabel: widget.labelText,
      autofocus: widget.autofocus,
      overlayConstraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
      optionsBuilder: (value) => _optionsFor(value.text),
      onSelected: widget.onSelected,
      optionTileBuilder: (context, option, onSelected) {
        final compound = option.isUsers;
        return ListTile(
          key: ValueKey(
            '${widget.fieldKey ?? 'move'}-option-'
            '${switch (option.kind) {
              MoveOptionKind.compound => 'compound:',
              MoveOptionKind.userFigure => 'userFigure:',
              _ => '',
            }}${option.id}',
          ),
          dense: true,
          title: Text(option.displayName),
          // Marked in words for assistive technology, not by the icon alone.
          trailing: compound
              ? Tooltip(
                  message: widget.compoundMarkerLabel,
                  // The icon's own label says it; read once.
                  excludeFromSemantics: true,
                  child: Icon(
                    Icons.person_outline,
                    size: 18,
                    semanticLabel: widget.compoundMarkerLabel,
                  ),
                )
              : null,
          onTap: onSelected,
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit, autofocus) {
        return TextField(
          key: widget.fieldKey == null
              ? null
              : ValueKey('${widget.fieldKey}-input'),
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
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
