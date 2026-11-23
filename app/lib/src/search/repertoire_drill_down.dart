import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// The Repertoire page's period (#2357): all time, the last 1, 3 or 6
/// calendar months, or since a chosen date. The same choices as the Called
/// filter's Within windows ([FacetSelections.historyMonths] and
/// [FacetSelections.historySince]), so a drill-down carries the period into
/// Collection unchanged. Session state only; never persisted.
@immutable
class RepertoirePeriod {
  /// Every call, whenever it was.
  const RepertoirePeriod.allTime() : months = null, since = null;

  /// Calls in the last [months] calendar months; one of [monthPresets].
  const RepertoirePeriod.months(int this.months) : since = null;

  /// Calls on or after [date]'s calendar day.
  RepertoirePeriod.since(DateTime date)
    : months = null,
      since = DateTime.utc(date.year, date.month, date.day);

  /// The month presets, the Within presets'. No 12-month preset (maintainer
  /// decision): a longer season uses [RepertoirePeriod.since].
  static const List<int> monthPresets = [1, 3, 6];

  final int? months;
  final DateTime? since;

  bool get isAllTime => months == null && since == null;

  /// The window's first day as of [today], or null for all time. The same
  /// date [FacetSelections.historyCutoff] gives for the same choice.
  DateTime? cutoff(DateTime today) {
    if (since case final date?) return date;
    if (months case final m?) return calendarMonthsBefore(today, m);
    return null;
  }

  /// Sets this period as [facets]' recency scope.
  void applyTo(FacetSelections facets) {
    if (since case final date?) {
      facets.setHistorySince(date);
    } else {
      facets.setHistoryMonths(months);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RepertoirePeriod &&
      other.months == months &&
      other.since == since;

  @override
  int get hashCode => Object.hash(months, since);
}

/// What a Repertoire row asks Collection to show (#2357), in the Collection's
/// own query vocabulary: facet selections and, for a figure, one Advanced
/// "has figure" row. No new filter leaf.
///
/// Applying one replaces the Collection's search ([applyTo] expects cleared
/// selections), so the list shows the dances the tapped number counts. The
/// page's dance type, when one is chosen, comes along as a Form selection.
@immutable
class RepertoireDrillDown {
  const RepertoireDrillDown._({
    this.form,
    this.called,
    this.period = const RepertoirePeriod.allTime(),
    this.authorId,
    this.formation,
    this.venue,
    this.venueLabel,
    this.move,
  });

  /// Never called: `CalledFilter(called: false)`, with no window.
  const RepertoireDrillDown.neverCalled({DanceForm? form})
    : this._(form: form, called: false);

  /// Not called in [period]: `CalledFilter(called: false, since: …)`.
  const RepertoireDrillDown.notCalledIn(
    RepertoirePeriod period, {
    DanceForm? form,
  }) : this._(form: form, called: false, period: period);

  /// A figure of one dance type: `FormFilter(form)` AND
  /// `FigureFilter(FigureLeaf(move))`.
  const RepertoireDrillDown.figure(String move, {required DanceForm form})
    : this._(form: form, move: move);

  /// A choreographer: `AuthorFilter` AND `CalledFilter` since the period
  /// start.
  const RepertoireDrillDown.author(
    String choreographerId,
    RepertoirePeriod period, {
    DanceForm? form,
  }) : this._(
         form: form,
         called: true,
         period: period,
         authorId: choreographerId,
       );

  /// A formation: `FormationFilter` AND `CalledFilter` since the period
  /// start.
  const RepertoireDrillDown.formation(
    FormationShape shape,
    RepertoirePeriod period, {
    DanceForm? form,
  }) : this._(form: form, called: true, period: period, formation: shape);

  /// A venue: `CalledFilter` with that venue, since the period start.
  const RepertoireDrillDown.venue(
    VenueKey key,
    RepertoirePeriod period, {
    String? label,
    DanceForm? form,
  }) : this._(
         form: form,
         called: true,
         period: period,
         venue: key,
         venueLabel: label,
       );

  final DanceForm? form;

  /// The Called facet's polarity, or null for no calling-history filter.
  final bool? called;

  /// The recency scope, applied only with [called].
  final RepertoirePeriod period;
  final String? authorId;
  final FormationShape? formation;
  final VenueKey? venue;
  final String? venueLabel;
  final String? move;

  /// Writes this drill-down into [facets] and [advanced], which the caller
  /// has just cleared.
  void applyTo(FacetSelections facets, BuilderGroup advanced) {
    if (form case final f?) facets.forms.add(f);
    if (called case final polarity?) {
      facets.callStatuses.add(polarity);
      period.applyTo(facets);
      if (venue case final key?) facets.setHistoryVenue(key, label: venueLabel);
    }
    if (authorId case final id?) facets.authorIds.add(id);
    if (formation case final shape?) facets.formations.add(shape);
    if (move case final m?) advanced.children.add(BuilderFigure(move: m));
  }
}
