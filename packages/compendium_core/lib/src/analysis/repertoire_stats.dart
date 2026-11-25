import 'package:meta/meta.dart';

import '../model/enums.dart';
import '../model/formation.dart' show FormationShape;
import '../search/filter.dart' show VenueKey;
import '../storage/calling_history_scope.dart' show CallingHistoryTracking;

/// What a repertoire summary counts (#2357): the calling-history settings the
/// Collection's "called ×N" and Called filter run under, a recency window, and
/// a dance type.
///
/// [performedOnly], [requireEventDate], [callerFilter] and [tracking] mean
/// exactly what they mean on a `CalledFilter`, so a dance's count here is the
/// count its Collection row shows, and a window here selects the calls a
/// `CalledFilter.since` of the same date selects.
@immutable
class RepertoireScope {
  const RepertoireScope({
    this.performedOnly = false,
    this.requireEventDate = false,
    this.callerFilter,
    this.tracking = CallingHistoryTracking.defaults,
    this.since,
    this.form,
  });

  /// "Require mark performed": only slots marked performed count.
  final bool performedOnly;

  /// "Require an event date": programs with no event date count nowhere.
  final bool requireEventDate;

  /// The host-caller scope, or null (or blank) for every caller.
  final String? callerFilter;

  /// Which slots a recency window can date; see [CallingHistoryTracking].
  final CallingHistoryTracking tracking;

  /// The window's first day: only calls whose recency date is on or after it
  /// count in the call-based sections. Null is all time. A UTC calendar date,
  /// `DateTime.utc(y, m, d)`, as `CalledFilter.since` requires.
  final DateTime? since;

  /// Only dances of this type, or every type when null.
  final DanceForm? form;

  @override
  bool operator ==(Object other) =>
      other is RepertoireScope &&
      other.performedOnly == performedOnly &&
      other.requireEventDate == requireEventDate &&
      other.callerFilter == callerFilter &&
      other.tracking == tracking &&
      other.since == since &&
      other.form == form;

  @override
  int get hashCode => Object.hash(
    performedOnly,
    requireEventDate,
    callerFilter,
    tracking,
    since,
    form,
  );
}

/// One dance and how many counted calls it has in the window.
@immutable
class RepertoireDanceCount {
  const RepertoireDanceCount({
    required this.danceId,
    required this.title,
    required this.count,
  });

  final String danceId;
  final String title;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is RepertoireDanceCount &&
      other.danceId == danceId &&
      other.title == title &&
      other.count == count;

  @override
  int get hashCode => Object.hash(danceId, title, count);

  @override
  String toString() => 'RepertoireDanceCount($title, $count)';
}

/// One move of one dance type: how many dances of that type contain it, and
/// how many calls in the window were of such a dance.
///
/// A dance counts once per move however often the move appears in it, so
/// [danceCount] is at most the type's dance count.
@immutable
class RepertoireFigureCount {
  const RepertoireFigureCount({
    required this.form,
    required this.move,
    required this.danceCount,
    required this.callCount,
  });

  final DanceForm form;

  /// The canonical move id, as a `FigureLeaf` takes it.
  final String move;
  final int danceCount;
  final int callCount;

  @override
  bool operator ==(Object other) =>
      other is RepertoireFigureCount &&
      other.form == form &&
      other.move == move &&
      other.danceCount == danceCount &&
      other.callCount == callCount;

  @override
  int get hashCode => Object.hash(form, move, danceCount, callCount);

  @override
  String toString() =>
      'RepertoireFigureCount(${form.name}/$move, dances: $danceCount, '
      'calls: $callCount)';
}

/// One author and how many counted calls in the window were of their dances.
/// A dance with two authors counts for each.
@immutable
class RepertoireAuthorCount {
  const RepertoireAuthorCount({
    required this.choreographerId,
    required this.name,
    required this.callCount,
  });

  final String choreographerId;
  final String name;
  final int callCount;

  @override
  bool operator ==(Object other) =>
      other is RepertoireAuthorCount &&
      other.choreographerId == choreographerId &&
      other.name == name &&
      other.callCount == callCount;

  @override
  int get hashCode => Object.hash(choreographerId, name, callCount);
}

/// One formation shape and how many counted calls in the window were of a
/// dance in it. Shape only, the column a `FormationFilter` reads.
@immutable
class RepertoireFormationCount {
  const RepertoireFormationCount({
    required this.shape,
    required this.callCount,
  });

  final FormationShape shape;
  final int callCount;

  @override
  bool operator ==(Object other) =>
      other is RepertoireFormationCount &&
      other.shape == shape &&
      other.callCount == callCount;

  @override
  int get hashCode => Object.hash(shape, callCount);
}

/// One venue with a counted call in the window, and the dances called there
/// more than once in it.
///
/// The app labels a record [key] from its venue catalogue and falls back to
/// [latestVenueText], as the At venue chooser does.
@immutable
class RepertoireVenueRepeats {
  const RepertoireVenueRepeats({
    required this.key,
    required this.latestVenueText,
    required this.repeats,
  });

  /// The venue, as a `CalledFilter.venue` scope keys it.
  final VenueKey key;

  /// The venue as typed on its most recent counted program that has typed
  /// text, trimmed and whitespace-collapsed; null when none has.
  final String? latestVenueText;

  /// Dances called here more than once in the window, most calls first.
  final List<RepertoireDanceCount> repeats;
}

/// Everything the Repertoire page shows (#2357), computed in one read.
///
/// The call-based figures ([mostCalled], [leastCalled], [totalCalls],
/// [figures]' `callCount`, [authors], [formations], [venues],
/// [notCalledInWindowCount]) honor the scope's window; the collection-based
/// ones ([danceCount], [neverCalledCount], [figures]' `danceCount`) do not.
@immutable
class RepertoireStats {
  const RepertoireStats({
    required this.formsPresent,
    required this.danceCount,
    required this.danceCountsByForm,
    required this.totalCalls,
    required this.calledDanceCount,
    required this.callCounts,
    required this.mostCalled,
    required this.leastCalled,
    required this.neverCalledCount,
    required this.neverCalledSample,
    required this.notCalledInWindowCount,
    required this.notCalledInWindowSample,
    required this.figures,
    required this.authorCount,
    required this.authors,
    required this.formations,
    required this.venues,
  });

  /// Every dance type the collection holds, whatever the scope's type.
  final Set<DanceForm> formsPresent;

  /// Live dances in scope (of the scope's type, or every type).
  final int danceCount;

  /// Live dances per type, in scope, for figure-frequency denominators.
  final Map<DanceForm, int> danceCountsByForm;

  /// Counted calls in the window.
  final int totalCalls;

  /// Dances with at least one counted call in the window.
  final int calledDanceCount;

  /// Dance id → counted calls in the window, for every dance with one.
  final Map<String, int> callCounts;

  /// The most-called dances, most calls first, then by title.
  final List<RepertoireDanceCount> mostCalled;

  /// The least-called dances among those called in the window, fewest first,
  /// then by title. Never repeats a dance in [mostCalled].
  final List<RepertoireDanceCount> leastCalled;

  /// Dances with no counted call at all, ever: what the Not called filter
  /// lists with no window.
  final int neverCalledCount;

  /// The first of those, by title.
  final List<RepertoireDanceCount> neverCalledSample;

  /// Dances with no counted call in the window, never-called ones included:
  /// what the Not called filter lists with the same window. Null for all time.
  final int? notCalledInWindowCount;

  /// The first of those, by title; empty for all time.
  final List<RepertoireDanceCount> notCalledInWindowSample;

  /// Figure frequency, per type, most dances first, then by move id.
  final List<RepertoireFigureCount> figures;

  /// Distinct authors with a counted call in the window.
  final int authorCount;

  /// Authors by calls in the window, most first, then by name.
  final List<RepertoireAuthorCount> authors;

  /// Calls in the window by formation shape, most first.
  final List<RepertoireFormationCount> formations;

  /// Venues with a counted call in the window, newest call first.
  final List<RepertoireVenueRepeats> venues;
}
