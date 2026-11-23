import '../imports/ecd_bars.dart';
import 'bar_timing.dart';
import 'enums.dart';
import 'phrase_structure.dart';

/// The beats in one bar of a dance of [form] set to [structure] in [meter],
/// when its figures are counted in bars, or null where they are counted in
/// beats (ADR-006 §5.5): any form but ECD, and a tune whose parts differ in
/// beats per bar, where one count of bars would mean different beats in
/// different parts. A bar holds the beats [meter] states (Hudson, 19 November
/// 2026: "the meter is the rule"), or with none the beats per bar of
/// [structure], as a typed bar range counts them ([ecdBeatsPerBar]). A typed
/// bar range in a tune whose parts differ is counted by [BarTiming.byPhrase],
/// phrase by phrase (#2303); the figures are shown in beats until the editor
/// and exports show them so.
///
/// The editor, Perform and every export count a dance's bars by this one
/// rule, so a figure reads "4 bars" on screen and on paper alike.
int? danceBeatsPerBar(
  DanceForm form,
  PhraseStructure structure, {
  String meter = '',
}) {
  if (form != DanceForm.ecd) return null;
  final perBar = {for (final c in structure.components) c.beatsPerBar};
  if (perBar.length != 1) return null;
  final stated = ecdBeatsPerBar(meter);
  return stated.stated ? stated.beatsPerBar : perBar.single;
}

/// How a dance of [form] set to [structure] in [meter] counts its figures in
/// bars, or null where they are counted in beats: [danceBeatsPerBar]'s one bar
/// length where the phrases agree (so a dance in one meter reads as ever), and
/// each phrase's own where they differ (#2303), whatever [meter] states.
BarTiming? barTimingFor(
  DanceForm form,
  PhraseStructure structure, {
  String meter = '',
}) {
  // Red-run stub: the old rule, which counts a tune whose parts differ in
  // beats.
  final perBar = danceBeatsPerBar(form, structure, meter: meter);
  return perBar == null ? null : BarTiming.fixed(perBar);
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
