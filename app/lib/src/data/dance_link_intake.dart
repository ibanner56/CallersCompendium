/// Opening a dance link (#2335): the `ccdance://` link a dance's QR code holds
/// (#2334), handed to the app by a phone's camera app, or pasted into Import.
///
/// A link is untrusted input: any web page or app can open one. It is read in
/// two steps, the same for every way in:
///
/// 1. [decodeDanceLink] caps its length, then inflates it with an output cap
///    well below the cap on an opened file, and refuses anything that is not a
///    version-1 link to a JSON object, with a [DanceLinkException].
/// 2. The JSON is then checked exactly as an opened file's bytes are, by
///    [ArchiveIntakeService.validateBytes]. Like a file, an archive from a
///    newer schema is not refused there.
///
/// Both steps run on a short-lived worker isolate, not the UI isolate: a link
/// of a few hundred characters can inflate to the full cap of tiny JSON values,
/// and validating those took about a second on a desktop, during which the
/// interface would not respond.
///
/// Nothing is written: a validated link opens the normal import review, which
/// writes only when the user commits. No network is involved.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../l10n/app_localizations.dart';
import '../export/dance_code.dart';
import 'archive_intake_service.dart';

/// Whether [text], trimmed, is meant as a dance link: it starts with the
/// `ccdance:` scheme, in any case. Says nothing about whether it can be read;
/// [validateDanceLink] decides that. Used to route a link to dance intake
/// instead of to the web-page importers.
bool looksLikeDanceLink(String text) {
  final trimmed = text.trimLeft();
  const scheme = 'ccdance:';
  return trimmed.length >= scheme.length &&
      trimmed.substring(0, scheme.length).toLowerCase() == scheme;
}

/// Runs [work] somewhere and completes with its result, or its error.
typedef DanceLinkWorkRunner =
    Future<ArchiveIntakeValidation> Function(
      Future<ArchiveIntakeValidation> Function() work,
    );

/// Where [validateDanceLink] does its work: a worker isolate ([Isolate.run]),
/// which exits with its result. A widget test runs under fake time, where a
/// worker's reply never arrives, so it sets this to a runner that calls the
/// work in place, and puts it back when done.
@visibleForTesting
DanceLinkWorkRunner danceLinkWorkRunner = runDanceLinkWorkOnWorker;

/// The production [danceLinkWorkRunner].
Future<ArchiveIntakeValidation> runDanceLinkWorkOnWorker(
  Future<ArchiveIntakeValidation> Function() work,
) => Isolate.run(work);

/// Reads [link] and checks the archive it carries. Completes with a
/// [DanceLinkException] error when the link itself cannot be read; otherwise
/// returns the intake result, which may still be a rejection (for example, an
/// archive with no dances).
///
/// The reading and checking run off the UI isolate ([danceLinkWorkRunner]).
/// Surrounding whitespace is ignored, as a pasted or shared link often has
/// some. [maxLinkLength] and [maxInflatedBytes] are for tests.
Future<ArchiveIntakeValidation> validateDanceLink(
  String link, {
  ArchiveIntakeService? intake,
  int maxLinkLength = kMaxDanceLinkLength,
  int maxInflatedBytes = kMaxDanceInflatedBytes,
}) {
  final trimmed = link.trim();
  final service = intake ?? ArchiveIntakeService();
  return danceLinkWorkRunner(() async {
    final json = decodeDanceLink(
      trimmed,
      maxLinkLength: maxLinkLength,
      maxInflatedBytes: maxInflatedBytes,
    );
    return service.validateBytes(Uint8List.fromList(utf8.encode(json)));
  });
}

/// What to tell the user about a link [decodeDanceLink] refused. A link from a
/// newer format version asks them to update; anything else is damaged or cut
/// short. Generic prose: never the link or any part of it.
String danceLinkRefusalMessage(
  AppLocalizations l10n,
  DanceLinkFailure failure,
) => switch (failure) {
  DanceLinkFailure.unknownVersion => l10n.danceLinkRefusedNewerVersion,
  DanceLinkFailure.tooLong ||
  DanceLinkFailure.notADanceLink ||
  DanceLinkFailure.malformedBase64 ||
  DanceLinkFailure.inflateFailed ||
  DanceLinkFailure.tooLarge ||
  DanceLinkFailure.empty ||
  DanceLinkFailure.notUtf8 ||
  DanceLinkFailure.notAJsonObject => l10n.danceLinkRefusedDamaged,
};

/// What to tell the user when a link reads correctly but intake refuses the
/// archive it carries. Worded for a code, not a file: the file messages would
/// tell someone who scanned a code that "that file" is wrong. A size, read or
/// empty refusal cannot follow a successful [decodeDanceLink] (its caps and
/// checks come first), so those say the code is damaged.
String danceLinkIntakeRejectionMessage(
  AppLocalizations l10n,
  ArchiveIntakeRejectionReason reason,
) => switch (reason) {
  ArchiveIntakeRejectionReason.notArchive ||
  ArchiveIntakeRejectionReason.backup => l10n.danceLinkRefusedNotADance,
  ArchiveIntakeRejectionReason.noContent => l10n.danceLinkRefusedNoContent,
  ArchiveIntakeRejectionReason.tooLarge ||
  ArchiveIntakeRejectionReason.unreadable ||
  ArchiveIntakeRejectionReason.empty => l10n.danceLinkRefusedDamaged,
};
