import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_dropdown_field.dart';

/// An English dance's phrases as the caller names them (Hudson, 20 November
/// 2026): one row for each of A, B and C, with its bars, its beats to the bar
/// (a tune that changes meter has a different count in each phrase, #2303) and
/// whether it plays once or twice, its repeat straight after it. It writes the phrase
/// structure as named components ([PhraseStructure.named]), so the figure
/// list's section labels read `A`, `A1`/`A2`, `B`, `C`.
///
/// With no named phrases yet, it offers to name them, starting from the
/// dance's current structure ([namedPhrasesFrom]).
class NamedPhrasesEditor extends StatefulWidget {
  const NamedPhrasesEditor({
    super.key,
    required this.structure,
    required this.beatsPerBar,
    required this.onChanged,
  });

  /// The dance's phrase structure as it now reads, or null while the text
  /// holds one that does not parse.
  final PhraseStructure? structure;

  /// The beats in a bar the dance's Meter states, or null when it states
  /// none. A new phrase counts its bars by it.
  final int? beatsPerBar;

  /// The new phrase structure text, when the rows make a valid one. [typed]
  /// is true for a bar count being typed, and false for a single action
  /// (naming, adding, removing, renaming, Once or Twice), which is its own
  /// undo step.
  final void Function(String raw, {required bool typed}) onChanged;

  @override
  State<NamedPhrasesEditor> createState() => _NamedPhrasesEditorState();
}

/// The named phrases a caller starts from for [structure]: its own names when
/// it has them; else its paired labels grouped by letter (`A1 A2 B1 B2` of 8
/// bars is A and B, each 8 bars played twice) when that gives at most three
/// letters, each played once or twice at one length; else A and B, each 8
/// bars played twice. Each phrase keeps its part's bars, and its beats per
/// bar are [beatsPerBar], or the part's own when that is null: so the
/// standard structure in 4/4 is A and B of 8 bars, as an import gives it
/// (`4*8*4`), not 4 bars of the standard's 2/2 beats.
List<NamedPhrase> namedPhrasesFrom(
  PhraseStructure structure, {
  int? beatsPerBar,
}) {
  final named = structure.namedPhrases;
  if (named != null) return named;
  final fallbackPerBar = beatsPerBar ?? structure.components.first.beatsPerBar;
  final fallback = [
    NamedPhrase(name: 'A', plays: 2, bars: 8, beatsPerBar: fallbackPerBar),
    NamedPhrase(name: 'B', plays: 2, bars: 8, beatsPerBar: fallbackPerBar),
  ];
  final labels = structure.labels;
  final groups = <({String letter, int plays, int bars, int perBar})>[];
  var beat = 0;
  for (final label in labels) {
    final component = structure.componentAtBeat(beat);
    beat += component.beatsPerPhrase;
    final perBar = beatsPerBar ?? component.beatsPerBar;
    final bars = component.bars;
    final letter = label.substring(0, 1);
    if (groups.isNotEmpty && groups.last.letter == letter) {
      final last = groups.removeLast();
      if (last.bars != bars || last.perBar != perBar) return fallback;
      groups.add((
        letter: letter,
        plays: last.plays + 1,
        bars: bars,
        perBar: perBar,
      ));
    } else {
      groups.add((letter: letter, plays: 1, bars: bars, perBar: perBar));
    }
  }
  if (groups.length > PhraseStructure.phraseNames.length ||
      groups.any((g) => g.plays > PhraseStructure.maxNamedPlays) ||
      groups.any((g) => !PhraseStructure.phraseNames.contains(g.letter))) {
    return fallback;
  }
  return [
    for (final g in groups)
      NamedPhrase(
        name: g.letter,
        plays: g.plays,
        bars: g.bars,
        beatsPerBar: g.perBar,
      ),
  ];
}

class _Row {
  _Row(NamedPhrase phrase)
    : name = phrase.name,
      plays = phrase.plays,
      bars = TextEditingController(text: '${phrase.bars}'),
      beats = TextEditingController(text: '${phrase.beatsPerBar}');

  String name;
  int plays;
  final TextEditingController bars;

  /// The beats in each of the phrase's bars, as typed.
  final TextEditingController beats;

  /// The bars typed, or null when they are not a whole number from 1 to
  /// [PhraseStructure.maxComponentNumber].
  int? get barCount => _count(bars);

  /// The beats to the bar typed, or null when they are not a whole number from
  /// 1 to [PhraseStructure.maxComponentNumber].
  int? get beatsPerBar => _count(beats);

  static int? _count(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null ||
            value < 1 ||
            value > PhraseStructure.maxComponentNumber
        ? null
        : value;
  }

  void dispose() {
    bars.dispose();
    beats.dispose();
  }
}

class _NamedPhrasesEditorState extends State<NamedPhrasesEditor> {
  final List<_Row> _rows = [];

  /// The text this editor last wrote, so a structure it wrote itself does
  /// not rebuild the rows under the caller's cursor.
  String? _written;

  /// Whether the rows, as typed, make no valid structure (a bar count left
  /// empty, or a structure past its bounds).
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void didUpdateWidget(NamedPhrasesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final raw = widget.structure?.raw;
    if (raw != null && raw != _written && raw != oldWidget.structure?.raw) {
      _loadRows();
    }
  }

  void _loadRows() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll([
        for (final phrase
            in widget.structure?.namedPhrases ?? const <NamedPhrase>[])
          _Row(phrase),
      ]);
    _written = widget.structure?.raw;
    _invalid = false;
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  int get _newRowBeatsPerBar =>
      widget.beatsPerBar ??
      (_rows.isNotEmpty
          ? _rows.first.beatsPerBar ?? 2
          : widget.structure?.components.first.beatsPerBar ?? 2);

  void _write({bool typed = false}) {
    final phrases = <NamedPhrase>[];
    for (final row in _rows) {
      final bars = row.barCount;
      final beats = row.beatsPerBar;
      if (bars == null || beats == null) {
        setState(() => _invalid = true);
        return;
      }
      phrases.add(
        NamedPhrase(
          name: row.name,
          plays: row.plays,
          bars: bars,
          beatsPerBar: beats,
        ),
      );
    }
    final String raw;
    try {
      raw = phrases.isEmpty ? _unnamedRaw : PhraseStructure.named(phrases).raw;
    } on FormatException {
      // diagnostics: silent — a structure past its bounds is shown on the
      // rows as invalid; nothing is written until it is fixed.
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    _written = raw;
    widget.onChanged(raw, typed: typed);
  }

  /// With every phrase removed: four 8-bar phrases in the meter's beats, as
  /// an import gives an English dance, or the standard structure in 2/2 or
  /// with no meter stated.
  String get _unnamedRaw {
    final perBar = widget.beatsPerBar;
    return perBar == null || perBar == 2 ? '' : '4*8*$perBar';
  }

  void _start() {
    final structure = widget.structure ?? PhraseStructure.standard;
    setState(() {
      _rows.addAll([
        for (final phrase in namedPhrasesFrom(
          structure,
          beatsPerBar: widget.beatsPerBar,
        ))
          _Row(phrase),
      ]);
    });
    _write();
  }

  void _add() {
    final used = {for (final row in _rows) row.name};
    final name = PhraseStructure.phraseNames.firstWhere(
      (n) => !used.contains(n),
    );
    setState(() {
      _rows.add(
        _Row(
          NamedPhrase(
            name: name,
            plays: 1,
            bars: 8,
            beatsPerBar: _newRowBeatsPerBar,
          ),
        ),
      );
    });
    _write();
  }

  void _remove(int index) {
    setState(() => _rows.removeAt(index).dispose());
    _write();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_rows.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('named-phrases-start'),
          onPressed: _start,
          icon: const Icon(Icons.label_outline),
          label: Text(l10n.danceEditorPhrasesNameThem),
        ),
      );
    }
    return Column(
      key: const ValueKey('named-phrases'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.danceEditorPhrasesTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.danceEditorPhrasesHelp, style: theme.textTheme.bodySmall),
        for (final (index, row) in _rows.indexed) _rowFor(context, index, row),
        if (_invalid)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l10n.danceEditorPhrasesInvalid(
                  PhraseStructure.maxComponentNumber,
                ),
                key: const ValueKey('named-phrases-invalid'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        if (_rows.length < PhraseStructure.phraseNames.length)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('named-phrases-add'),
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(l10n.danceEditorPhrasesAdd),
            ),
          ),
      ],
    );
  }

  Widget _rowFor(BuildContext context, int index, _Row row) {
    final l10n = AppLocalizations.of(context);
    final taken = {
      for (final (i, other) in _rows.indexed)
        if (i != index) other.name,
    };
    final name = AppDropdownField<String>(
      key: ValueKey('named-phrase-$index-name'),
      value: row.name,
      fillWidth: false,
      decoration: InputDecoration(labelText: l10n.danceEditorPhraseNameLabel),
      entries: [
        for (final n in PhraseStructure.phraseNames)
          if (!taken.contains(n)) AppDropdownEntry(value: n, label: n),
      ],
      onChanged: (value) {
        if (value == row.name) return;
        setState(() => row.name = value);
        _write();
      },
    );
    final bars = SizedBox(
      width: 112,
      child: TextField(
        key: ValueKey('named-phrase-$index-bars'),
        controller: row.bars,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(
            '${PhraseStructure.maxComponentNumber}'.length,
          ),
        ],
        decoration: InputDecoration(
          labelText: l10n.danceEditorPhraseBarsLabel(row.name),
          errorText: row.barCount == null
              ? l10n.danceEditorPhraseBarsRange(
                  PhraseStructure.maxComponentNumber,
                )
              : null,
          errorMaxLines: 2,
        ),
        onChanged: (_) => _write(typed: true),
      ),
    );
    final beats = SizedBox(
      width: 112,
      child: TextField(
        key: ValueKey('named-phrase-$index-beats'),
        controller: row.beats,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(
            '${PhraseStructure.maxComponentNumber}'.length,
          ),
        ],
        decoration: InputDecoration(
          labelText: l10n.danceEditorPhraseBeatsPerBarLabel(row.name),
          errorText: row.beatsPerBar == null
              ? l10n.danceEditorPhraseBeatsPerBarRange(
                  PhraseStructure.maxComponentNumber,
                )
              : null,
          errorMaxLines: 2,
        ),
        onChanged: (_) => _write(typed: true),
      ),
    );
    final plays = Semantics(
      label: l10n.danceEditorPhrasePlaysLabel(row.name),
      container: true,
      child: SegmentedButton<int>(
        key: ValueKey('named-phrase-$index-plays'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 1, label: Text(l10n.danceEditorPhrasePlaysOnce)),
          ButtonSegment(
            value: 2,
            label: Text(l10n.danceEditorPhrasePlaysTwice),
          ),
        ],
        selected: {row.plays},
        onSelectionChanged: (value) {
          setState(() => row.plays = value.single);
          _write();
        },
      ),
    );
    final remove = IconButton(
      key: ValueKey('named-phrase-$index-remove'),
      tooltip: l10n.danceEditorPhraseRemove(row.name),
      icon: const Icon(Icons.close),
      onPressed: () => _remove(index),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [name, bars, beats, plays, remove],
      ),
    );
  }
}
