// How Device Sync names another device to the user: a short tag cut from its
// random identifier, and when it last shared changes rounded to the day. Never
// a name, a nickname or anything about the device itself — two people can
// share a store, so a name one of them typed would be the other's personal
// data, and the server would learn it.
import '../../../l10n/app_localizations.dart';

/// The shortest a device tag is.
const int kSyncDeviceTagLength = 6;

/// A short tag for each of [deviceIds]: the first [kSyncDeviceTagLength]
/// characters of the identifier, lengthened — for every identifier that
/// shares that prefix, not just one of them — until no two tags are equal.
///
/// Identifiers are random base64url, so six characters collide about once in
/// 69 billion pairs, and in practice every tag is six long. A tag is unique
/// only among the identifiers it was computed with, so a surface that shows
/// tags together computes them together.
Map<String, String> syncDeviceTags(Iterable<String> deviceIds) {
  final ids = deviceIds.toSet().toList(growable: false);
  return {
    for (final id in ids)
      id: id.substring(0, _tagLength(id, ids).clamp(0, id.length)),
  };
}

int _tagLength(String id, List<String> ids) {
  var length = kSyncDeviceTagLength;
  for (final other in ids) {
    if (identical(other, id) || other == id) continue;
    final shared = _commonPrefixLength(id, other);
    if (shared >= length) length = shared + 1;
  }
  return length;
}

int _commonPrefixLength(String a, String b) {
  final limit = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < limit && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// Whole calendar days from [writtenAt] to [now], both taken in local time.
///
/// Counted on calendar dates rather than elapsed hours, so a change shared
/// late yesterday reads as yesterday, and through UTC midnights so a daylight
/// saving change cannot shorten a day to 23 hours. A peer whose clock is ahead
/// of this one can report a time after [now]; that reads as today rather than
/// as a negative age.
int syncDaysSince(DateTime writtenAt, DateTime now) {
  DateTime day(DateTime value) {
    final local = value.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  final days = day(now).difference(day(writtenAt)).inDays;
  return days < 0 ? 0 : days;
}

/// "Last shared changes …" for a device whose manifest was written at
/// [writtenAt]: today, a count of days for under two weeks, and a rounded
/// count of weeks after that. Never a time of day — the day is all the user
/// needs to recognise a device, and it is all this shows of when they used it.
String syncLastSharedText(
  AppLocalizations l10n,
  DateTime writtenAt,
  DateTime now,
) {
  final days = syncDaysSince(writtenAt, now);
  if (days == 0) return l10n.settingsSyncDeviceLastSharedToday;
  if (days < 14) return l10n.settingsSyncDeviceLastSharedDays(days);
  return l10n.settingsSyncDeviceLastSharedWeeks((days / 7).round());
}
