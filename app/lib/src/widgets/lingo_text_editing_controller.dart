import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Lingo-line text editing controller
// ---------------------------------------------------------------------------

/// A [TextEditingController] that overlays "lingo line" decorations on typed
/// text: discouraged terms are struck through, role terms are underlined
/// (solid), and recognized taxonomy move keywords are dotted-underlined.
/// Styles are recomputed from core APIs on every change, so character offsets
/// stay correct across arbitrary edits.
class LingoTextEditingController extends TextEditingController {
  LingoTextEditingController({
    super.text,
    required this.dialect,
    this.taxonomy,
  });

  Dialect dialect;

  /// The active taxonomy used to detect move keywords.  When `null`, no
  /// move-keyword spans are computed (the discouraged-strike and role-underline
  /// are unaffected).
  Taxonomy? taxonomy;

  /// Replaces the active dialect and redraws the styled spans.
  void updateDialect(Dialect newDialect) {
    // `Dialect` implements deep (map/list) equality, so guard the potentially
    // expensive `==` with an identity fast-path for the common same-instance
    // case.
    if (identical(dialect, newDialect) || dialect == newDialect) return;
    dialect = newDialect;
    notifyListeners();
  }

  /// Replaces the active taxonomy and redraws the styled spans.
  void updateTaxonomy(Taxonomy? newTaxonomy) {
    if (identical(taxonomy, newTaxonomy) || taxonomy == newTaxonomy) return;
    taxonomy = newTaxonomy;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final raw = text;
    if (raw.isEmpty) return TextSpan(text: raw, style: style);

    final discSpans = canonicalize(raw, dialect).discouraged;
    final roleSpanList = roleSpans(raw, dialect);
    final tax = taxonomy;
    final moveSpanList = tax == null
        ? const <({String text, int start})>[]
        : moveKeywordSpans(raw, tax);

    // Lingo events: priority controls tie-breaking when two spans share the
    // same start position. 1 = discouraged (highest among lingo), 2 = role,
    // 3 = move keyword (supplementary hint, lowest).
    final events =
        <
          ({
            int start,
            int end,
            TextDecoration decoration,
            TextDecorationStyle? decorationStyle,
            int priority,
          })
        >[];

    for (final s in discSpans) {
      final end = (s.start + s.text.length).clamp(0, raw.length);
      if (s.start < end) {
        events.add((
          start: s.start,
          end: end,
          decoration: TextDecoration.lineThrough,
          decorationStyle: null,
          priority: 1,
        ));
      }
    }
    for (final s in roleSpanList) {
      final end = (s.start + s.text.length).clamp(0, raw.length);
      if (s.start < end) {
        events.add((
          start: s.start,
          end: end,
          decoration: TextDecoration.underline,
          decorationStyle: null,
          priority: 2,
        ));
      }
    }
    for (final s in moveSpanList) {
      final end = (s.start + s.text.length).clamp(0, raw.length);
      if (s.start < end) {
        events.add((
          start: s.start,
          end: end,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          priority: 3,
        ));
      }
    }

    // IME composing region must render within its exact range regardless of
    // any lingo span that began before it.  Fragment any overlapping lingo
    // event into [start, cs) and (ce, end] pieces, then insert the composing
    // event so it is never blocked by a longer preceding span.
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      final cs = value.composing.start.clamp(0, raw.length);
      final ce = value.composing.end.clamp(0, raw.length);
      if (cs < ce) {
        final fragmented =
            <
              ({
                int start,
                int end,
                TextDecoration decoration,
                TextDecorationStyle? decorationStyle,
                int priority,
              })
            >[];
        for (final ev in events) {
          final overlaps = ev.start < ce && ev.end > cs;
          if (!overlaps) {
            fragmented.add(ev);
          } else {
            if (ev.start < cs) {
              fragmented.add((
                start: ev.start,
                end: cs,
                decoration: ev.decoration,
                decorationStyle: ev.decorationStyle,
                priority: ev.priority,
              ));
            }
            if (ev.end > ce) {
              fragmented.add((
                start: ce,
                end: ev.end,
                decoration: ev.decoration,
                decorationStyle: ev.decorationStyle,
                priority: ev.priority,
              ));
            }
          }
        }
        fragmented.add((
          start: cs,
          end: ce,
          decoration: TextDecoration.underline,
          decorationStyle: null,
          priority: 0,
        ));
        events
          ..clear()
          ..addAll(fragmented);
      }
    }

    if (events.isEmpty) return TextSpan(text: raw, style: style);

    // Stable sort: by start position, then by priority (lower = higher
    // precedence), then by length (longer span wins) to ensure determinism
    // when a term is both discouraged and a role term (e.g. "gents").
    events.sort((a, b) {
      final byCmp = a.start.compareTo(b.start);
      if (byCmp != 0) return byCmp;
      final byPri = a.priority.compareTo(b.priority);
      if (byPri != 0) return byPri;
      return b.end.compareTo(a.end); // longer first
    });

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final ev in events) {
      // Trim the event's start to wherever we are (overlapping spans are
      // skipped because the first-encountered span already covers that range).
      final start = ev.start < cursor ? cursor : ev.start;
      final end = ev.end > raw.length ? raw.length : ev.end;
      if (start >= end) continue;

      if (start > cursor) {
        spans.add(TextSpan(text: raw.substring(cursor, start), style: style));
      }
      spans.add(
        TextSpan(
          text: raw.substring(start, end),
          style: (style ?? const TextStyle()).copyWith(
            decoration: ev.decoration,
            decorationStyle: ev.decorationStyle,
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < raw.length) {
      spans.add(TextSpan(text: raw.substring(cursor), style: style));
    }

    return TextSpan(children: spans, style: style);
  }
}
