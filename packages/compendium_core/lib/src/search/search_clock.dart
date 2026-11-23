import 'collection_search_state.dart';

/// The calendar day an [instantUtc] is in, for a zone [utcOffset] from UTC, as
/// the `DateTime.utc(y, m, d)` that [calendarMonthsBefore] and
/// `CalledFilter.since` use.
///
/// "Today" for a relative search window is the caller's own calendar day, not
/// the UTC one: just after local midnight in a zone far ahead of UTC it is
/// already tomorrow, and a window counted back from the UTC day would start a
/// day early.
DateTime calendarDayAt(DateTime instantUtc, Duration utcOffset) {
  final local = instantUtc.toUtc().add(utcOffset);
  return DateTime.utc(local.year, local.month, local.day);
}

/// The clock a search host reads "today" from. It yields the instant **and**
/// the zone offset together, from one reading, so a test can fix both.
///
/// Hosts take `today` from [today] and never call `DateTime.now()` for it.
class SearchClock {
  const SearchClock();

  /// The current instant in UTC and the offset of the caller's zone then.
  ({DateTime instantUtc, Duration offset}) read() {
    final now = DateTime.now();
    return (instantUtc: now.toUtc(), offset: now.timeZoneOffset);
  }

  /// The caller's calendar day now.
  DateTime today() {
    final reading = read();
    return calendarDayAt(reading.instantUtc, reading.offset);
  }
}

/// A [SearchClock] that always reads the instant and offset it was given.
class FixedSearchClock extends SearchClock {
  const FixedSearchClock(this.instantUtc, this.offset);

  final DateTime instantUtc;
  final Duration offset;

  @override
  ({DateTime instantUtc, Duration offset}) read() =>
      (instantUtc: instantUtc, offset: offset);
}

/// How many whole calendar months back from [today] a chosen [since] date is,
/// for saving a "since a date" window as a distance.
///
/// The largest whole number of months N whose window
/// (`calendarMonthsBefore(today, N)`) does not start before [since], and at
/// least 1: "since three weeks ago" is saved as 1 month, never as "today
/// only", and a date in the future is also 1. (Floor rather than round, so the
/// saved window is never wider than the date picked, except for that minimum.)
int monthsBackFromDate(DateTime since, DateTime today) {
  final day = DateTime.utc(since.year, since.month, since.day);
  var months = (today.year - day.year) * 12 + today.month - day.month;
  // The month gap is an upper bound on N: a window of one month more starts
  // in the month before [since]'s, so before it. At most one step back is
  // needed, when the day of month is earlier than [since]'s.
  while (months > 1 && calendarMonthsBefore(today, months).isBefore(day)) {
    months--;
  }
  return months < 1 ? 1 : months;
}
