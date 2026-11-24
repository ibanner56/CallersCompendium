import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Timing in bars for the figures below it (ADR-006 §5.5): an English dance
/// is timed in bars, so its editor shows and takes a figure's count in bars
/// and stores beats, converting with the tune's [timing]: one bar length, or
/// each phrase's own where the phrases differ in beats per bar (#2303), which
/// read a figure's bars from where it starts ([FigureStartScope]).
///
/// Absent, figures are timed in beats, as contra's are.
class BarTimingScope extends InheritedWidget {
  const BarTimingScope({super.key, required this.timing, required super.child});

  /// How the tune's bars are counted.
  final BarTiming timing;

  /// [child] under the bar timing of [dance], or as it is where the dance
  /// is timed in beats ([barTimingFor]).
  static Widget forDance(Dance dance, {required Widget child}) {
    final timing = barTimingFor(
      dance.form,
      dance.phraseStructure,
      meter: dance.meter,
    );
    return timing == null
        ? child
        : BarTimingScope(timing: timing, child: child);
  }

  static BarTimingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarTimingScope>();

  @override
  bool updateShouldNotify(BarTimingScope oldWidget) =>
      timing != oldWidget.timing;
}

/// Sequences below it may state a span of their own, with steps that carry
/// no timing of their own ([formHasSequenceSpan]): an English dance's ("A, B
/// and C in bars 1–4", ADR-006 §5.5), counted in the bars of
/// [BarTimingScope], and a square's ("forward again and swing the opposite
/// (8)", ADR-007 Q10), counted in beats.
///
/// Absent, a sequence counts its steps, as contra's do.
class SequenceSpanScope extends InheritedWidget {
  const SequenceSpanScope({
    super.key,
    this.allowsUntimed = false,
    required super.child,
  });

  /// Whether a count may be left empty, for a step of a sequence that states
  /// its own span: the step then has no timing of its own.
  final bool allowsUntimed;

  static SequenceSpanScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SequenceSpanScope>();

  /// Whether a count below [context] may be left empty ([allowsUntimed]).
  static bool allowsUntimedOf(BuildContext context) =>
      maybeOf(context)?.allowsUntimed ?? false;

  /// This scope with [allowsUntimed] as given.
  SequenceSpanScope withUntimed(bool allowsUntimed, {required Widget child}) =>
      SequenceSpanScope(allowsUntimed: allowsUntimed, child: child);

  @override
  bool updateShouldNotify(SequenceSpanScope oldWidget) =>
      allowsUntimed != oldWidget.allowsUntimed;
}

/// The beat at which the figure below it starts, from which its bars are read
/// where the tune's phrases differ in beats per bar ([BarTimingScope]).
class FigureStartScope extends InheritedWidget {
  const FigureStartScope({
    super.key,
    required this.startBeat,
    required super.child,
  });

  final int startBeat;

  /// The start of the figure [context] is in, or the start of the dance where
  /// no figure's is given.
  static int startOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FigureStartScope>()
          ?.startBeat ??
      0;

  @override
  bool updateShouldNotify(FigureStartScope oldWidget) =>
      startBeat != oldWidget.startBeat;
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
/// half bars. [untimed] reads "no timing of its own". Bars are read from
/// [startBeat], or the start of the figure [context] is in
/// ([FigureStartScope]); [startBeat] is for a caller that is above the
/// figure's own scope.
String timingLabel(
  BuildContext context,
  int beats, {
  bool untimed = false,
  int? startBeat,
}) {
  final l10n = AppLocalizations.of(context);
  if (untimed) return l10n.danceEditorStepUntimed;
  final scope = BarTimingScope.maybeOf(context);
  final counted = scope?.timing.barsTextAt(
    startBeat ?? FigureStartScope.startOf(context),
    beats,
  );
  return counted == null
      ? l10n.danceFigureBeats(beats)
      : l10n.danceFigureBars(counted.text, counted.halfBars);
}

/// The count field of a figure timed in bars: shows its beats as bars and
/// reports what is typed as beats, counting bars from where the figure starts
/// ([startBeat]) by [timing]. Half a bar is taken only where it is a whole
/// number of beats, so not in triple time (ADR-006 Q16); otherwise, as for a
/// count out of range or an empty field, the field says so and reports
/// nothing. With [allowsUntimed], an empty field reports null instead: no
/// timing of its own.
class BarsField extends StatefulWidget {
  const BarsField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.beats,
    required this.timing,
    this.startBeat = 0,
    required this.onChanged,
    this.allowsUntimed = false,
    this.emptyHint,
    this.maxBeats = 64,
  });

  final String fieldKey;
  final String label;

  /// The stored count, or null for none ([allowsUntimed]).
  final int? beats;
  final BarTiming timing;

  /// Where the figure starts, from which its bars are counted.
  final int startBeat;
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
      : widget.timing.barsTextAt(widget.startBeat, beats)?.text ?? '';

  int? _beatsOf(String text) {
    final halfBars = parseHalfBars(text);
    if (halfBars == null) return null;
    return widget.timing.beatsForHalfBars(widget.startBeat, halfBars);
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textOf(widget.beats));
  }

  @override
  void didUpdateWidget(BarsField old) {
    super.didUpdateWidget(old);
    // A start that moves matters only where bars differ in length: in one
    // bar length the count reads the same, and half-typed text is kept.
    if ((widget.beats != old.beats ||
            widget.timing != old.timing ||
            (widget.startBeat != old.startBeat && !widget.timing.isFixed)) &&
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
        beats != null &&
        widget.timing.barsTextAt(widget.startBeat, beats) == null;
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
          final timing = widget.timing;
          final start = widget.startBeat;
          String? error;
          if (trimmed.isEmpty) {
            if (widget.allowsUntimed) {
              widget.onChanged(null);
            } else {
              // An empty field would keep the last count while showing none.
              error = l10n.danceEditorBarsRangeError(
                timing.maxBarsWithin(start, widget.maxBeats),
              );
            }
          } else {
            final halfBars = parseHalfBars(trimmed);
            if (halfBars == null ||
                timing.doubledBeatsForHalfBars(start, halfBars) >
                    widget.maxBeats * 2) {
              error = l10n.danceEditorBarsRangeError(
                timing.maxBarsWithin(start, widget.maxBeats),
              );
            } else if (timing.beatsForHalfBars(start, halfBars)
                case final beats?) {
              widget.onChanged(beats);
            } else {
              error = l10n.danceEditorHalfBarRefused(
                timing.beatsPerBarOfHalfAt(start, halfBars),
              );
            }
          }
          if (error != _error) setState(() => _error = error);
        },
      ),
    );
  }
}

/// The count field of a figure timed in beats that may be left empty: a step
/// of a square's sequence that states its own span, or that span itself
/// ([SequenceSpanScope], ADR-007 Q10), as [BarsField] is for an English
/// dance's. An empty field reports null: no timing of its own, or no span.
/// A count that is not a whole number from 0 to [maxBeats] is not reported,
/// and the field says so.
class BeatsField extends StatefulWidget {
  const BeatsField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.beats,
    required this.onChanged,
    this.emptyHint,
    this.maxBeats = 64,
  });

  final String fieldKey;
  final String label;

  /// The stored count, or null for none.
  final int? beats;
  final ValueChanged<int?> onChanged;

  /// What an empty field says; "no timing of its own" when null.
  final String? emptyHint;

  /// The largest count the field takes.
  final int maxBeats;

  @override
  State<BeatsField> createState() => _BeatsFieldState();
}

class _BeatsFieldState extends State<BeatsField> {
  late final TextEditingController _controller;

  /// Whether the text in the field is not reported.
  bool _invalid = false;

  /// The count [text] names, or null when it names none in range.
  int? _beatsOf(String text) {
    final n = int.tryParse(text.trim());
    return n != null && n >= 0 && n <= widget.maxBeats ? n : null;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.beats?.toString() ?? '');
  }

  @override
  void didUpdateWidget(BeatsField old) {
    super.didUpdateWidget(old);
    // Only a count set from elsewhere replaces the text, so half-typed text
    // is kept.
    if (widget.beats != old.beats &&
        (_controller.text.trim().isEmpty
            ? widget.beats != null
            : _beatsOf(_controller.text) != widget.beats)) {
      _controller.text = widget.beats?.toString() ?? '';
      _invalid = false;
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
    return SizedBox(
      width: 120,
      child: TextField(
        key: ValueKey(widget.fieldKey),
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          // The label floats while the field is empty so the hint shows.
          floatingLabelBehavior: FloatingLabelBehavior.always,
          hintText: widget.emptyHint ?? l10n.danceEditorStepUntimed,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          hintMaxLines: 2,
          errorText: _invalid
              ? l10n.danceEditorIntParamRangeError(0, widget.maxBeats)
              : null,
          errorMaxLines: 4,
        ),
        onChanged: (text) {
          final trimmed = text.trim();
          final beats = _beatsOf(trimmed);
          final valid = trimmed.isEmpty || beats != null;
          if (valid) widget.onChanged(beats);
          if (_invalid == valid) setState(() => _invalid = !valid);
        },
      ),
    );
  }
}
