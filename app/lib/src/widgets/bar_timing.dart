import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Timing in bars for the figures below it (ADR-006 §5.5): an English dance
/// is timed in bars, so its editor shows and takes a figure's count in bars
/// and stores beats, converting with the tune's [beatsPerBar].
///
/// Absent, figures are timed in beats, as contra's are.
class BarTimingScope extends InheritedWidget {
  const BarTimingScope({
    super.key,
    required this.beatsPerBar,
    this.allowsUntimed = false,
    required super.child,
  });

  /// Beats in one bar of the tune.
  final int beatsPerBar;

  /// Whether a count may be left empty, for a step of a sequence that states
  /// its own span ("A, B and C in bars 1–4"): the step then has no timing of
  /// its own.
  final bool allowsUntimed;

  /// The bar timing of a dance of [form] set to [structure] in [meter], or
  /// null where it is timed in beats: any form but ECD, and a tune whose parts
  /// differ in beats per bar, where one count of bars would mean different
  /// beats in different parts. A bar holds the beats [meter] states (Hudson,
  /// 19 November 2026: "the meter is the rule"), or with none the beats per
  /// bar of [structure] ([ecdMeterForBars]), as a typed bar range counts them.
  static int? beatsPerBarFor(
    DanceForm form,
    PhraseStructure structure, {
    String meter = '',
  }) {
    if (form != DanceForm.ecd) return null;
    final perBar = {for (final c in structure.components) c.beatsPerBar};
    if (perBar.length != 1) return null;
    return ecdBeatsPerBar(ecdMeterForBars(meter, structure)).beatsPerBar;
  }

  /// [child] under the bar timing of [dance], or as it is where the dance
  /// is timed in beats ([beatsPerBarFor]).
  static Widget forDance(Dance dance, {required Widget child}) {
    final beatsPerBar = beatsPerBarFor(
      dance.form,
      dance.phraseStructure,
      meter: dance.meter,
    );
    return beatsPerBar == null
        ? child
        : BarTimingScope(beatsPerBar: beatsPerBar, child: child);
  }

  static BarTimingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarTimingScope>();

  /// This scope with [allowsUntimed] as given.
  BarTimingScope withUntimed(bool allowsUntimed, {required Widget child}) =>
      BarTimingScope(
        beatsPerBar: beatsPerBar,
        allowsUntimed: allowsUntimed,
        child: child,
      );

  @override
  bool updateShouldNotify(BarTimingScope oldWidget) =>
      beatsPerBar != oldWidget.beatsPerBar ||
      allowsUntimed != oldWidget.allowsUntimed;
}

/// [beats] as a count of bars of [beatsPerBar] beats, such as "4" or "1½",
/// or null when it is not a whole number of half bars.
String? barsText(int beats, int beatsPerBar) {
  final doubled = beats * 2;
  if (doubled % beatsPerBar != 0) return null;
  final halfBars = doubled ~/ beatsPerBar;
  final whole = halfBars ~/ 2;
  if (halfBars.isEven) return '$whole';
  return whole == 0 ? '½' : '$whole½';
}

final RegExp _barsPattern = RegExp(r'^(\d{0,3})(\.5|,5|½|1/2)?$');

/// The number of half bars [text] names, or null when it names none: a whole
/// number ("4"), or one with a half written as ".5", ",5", "½" or " 1/2".
int? parseHalfBars(String text) {
  final t = text.trim().replaceAll(' ', '');
  final match = _barsPattern.firstMatch(t);
  if (match == null) return null;
  final wholeText = match.group(1)!;
  final half = match.group(2) != null;
  if (wholeText.isEmpty && !half) return null;
  final whole = wholeText.isEmpty ? 0 : int.parse(wholeText);
  return whole * 2 + (half ? 1 : 0);
}

/// A figure's count, in the bars of [BarTimingScope], or in beats outside it:
/// "4 bars", "1½ bars", or "8 beats" where the count is not a whole number of
/// half bars. [untimed] reads "no timing of its own".
String timingLabel(BuildContext context, int beats, {bool untimed = false}) {
  final l10n = AppLocalizations.of(context);
  if (untimed) return l10n.danceEditorStepUntimed;
  final scope = BarTimingScope.maybeOf(context);
  final bars = scope == null ? null : barsText(beats, scope.beatsPerBar);
  return bars == null
      ? l10n.danceFigureBeats(beats)
      : l10n.danceFigureBars(bars, beats * 2 ~/ scope!.beatsPerBar);
}

/// The count field of a figure timed in bars: shows its beats as bars and
/// reports what is typed as beats. Half a bar is taken only where it is a
/// whole number of beats, so not in triple time (ADR-006 Q16); otherwise, as
/// for a count out of range or an empty field, the field says so and reports
/// nothing. With [allowsUntimed], an empty field reports null instead: no
/// timing of its own.
class BarsField extends StatefulWidget {
  const BarsField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.beats,
    required this.beatsPerBar,
    required this.onChanged,
    this.allowsUntimed = false,
    this.emptyHint,
    this.maxBeats = 64,
  });

  final String fieldKey;
  final String label;

  /// The stored count, or null for none ([allowsUntimed]).
  final int? beats;
  final int beatsPerBar;
  final ValueChanged<int?> onChanged;
  final bool allowsUntimed;

  /// What an empty field says, with [allowsUntimed]; "no timing of its own"
  /// when null.
  final String? emptyHint;

  /// The largest count the field takes, in beats.
  final int maxBeats;

  @override
  State<BarsField> createState() => _BarsFieldState();
}

class _BarsFieldState extends State<BarsField> {
  late final TextEditingController _controller;

  /// Why the text in the field is not reported, or null when it is.
  String? _error;

  String _textOf(int? beats) => beats == null
      ? ''
      // A count that is not a whole number of half bars (entered in beats
      // before, or imported) shows as beats, and is kept until changed.
      : barsText(beats, widget.beatsPerBar) ?? '';

  int? _beatsOf(String text) {
    final halfBars = parseHalfBars(text);
    if (halfBars == null) return null;
    final doubled = halfBars * widget.beatsPerBar;
    return doubled.isEven ? doubled ~/ 2 : null;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textOf(widget.beats));
  }

  @override
  void didUpdateWidget(BarsField old) {
    super.didUpdateWidget(old);
    if ((widget.beats != old.beats || widget.beatsPerBar != old.beatsPerBar) &&
        _beatsOf(_controller.text) != widget.beats) {
      _controller.text = _textOf(widget.beats);
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final beats = widget.beats;
    final unconverted =
        beats != null && barsText(beats, widget.beatsPerBar) == null;
    return SizedBox(
      width: 120,
      child: TextField(
        key: ValueKey(widget.fieldKey),
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          floatingLabelBehavior: widget.allowsUntimed || unconverted
              ? FloatingLabelBehavior.always
              : null,
          hintText: unconverted
              ? l10n.danceFigureBeats(beats)
              : widget.allowsUntimed
              ? widget.emptyHint ?? l10n.danceEditorStepUntimed
              : null,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          hintMaxLines: 2,
          errorText: _error,
          errorMaxLines: 4,
        ),
        onChanged: (text) {
          final trimmed = text.trim();
          String? error;
          if (trimmed.isEmpty) {
            if (widget.allowsUntimed) {
              widget.onChanged(null);
            } else {
              // An empty field would keep the last count while showing none.
              error = l10n.danceEditorBarsRangeError(
                widget.maxBeats ~/ widget.beatsPerBar,
              );
            }
          } else {
            final halfBars = parseHalfBars(trimmed);
            final beats = _beatsOf(trimmed);
            if (halfBars == null ||
                halfBars * widget.beatsPerBar > widget.maxBeats * 2) {
              error = l10n.danceEditorBarsRangeError(
                widget.maxBeats ~/ widget.beatsPerBar,
              );
            } else if (beats == null) {
              error = l10n.danceEditorHalfBarRefused(widget.beatsPerBar);
            } else {
              widget.onChanged(beats);
            }
          }
          if (error != _error) setState(() => _error = error);
        },
      ),
    );
  }
}
