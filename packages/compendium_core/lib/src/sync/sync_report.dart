import 'sync_record_kind.dart';

/// The non-fatal reasons a sync pass may leave one record unresolved.
///
/// All but one name something about an *inbound* record or about the pass as a
/// whole. [withheldUnreadableRecord] is the exception and is documented as one,
/// so a future addition does not read the enum as uniformly inbound.
enum SyncReportCode {
  equalUpdatedAt,
  unseenLocalCreation,
  malformedRecord,
  nonCanonicalWireBody,
  invalidClassification,
  unresolvedBlob,
  blobIdentityMismatch,
  unresolvedReference,
  concurrentLocalChange,
  quarantinedRecord,
  clockSuspect,

  /// A peer has published at least twice since this device published a
  /// record, and its manifest still does not carry that record's hash (spec
  /// §6.9). Judged per peer, so a report always carries `peerId` — the peer
  /// that is not taking it — with `kind` and `recordId`. A peer that has not
  /// published since is merely asleep and raises nothing.
  unreflectedPublication,

  /// A record on *this* device was withheld from publication and from matching
  /// because its stored content could not be decoded (spec §6.9, #1347).
  ///
  /// Deliberately not [malformedRecord]. That code is raised for a record
  /// received from a peer, and the notice it maps to tells the user to check
  /// their *other* device's app version — advice that is false here, where the
  /// unreadable row is on this device and no peer is involved. The same
  /// this-device/other-device distinction is already drawn for
  /// [quarantinedRecord], which splits on a null `peerId`; this condition gets
  /// a code of its own instead, because it shares nothing else with a
  /// malformed inbound body.
  ///
  /// Unlike quarantine it is not a derived predicate over timestamps, it has no
  /// fallback wire hash, and no later pass clears it: the device simply cannot
  /// read the row it would otherwise speak for. Reports carry `kind` and
  /// `recordId`, and always a null `peerId`.
  withheldUnreadableRecord,

  /// A peer's manifest or record blob was written in an envelope version newer
  /// than this build understands (`SyncNewerWireVersionException`): another
  /// device runs a newer version of the app.
  ///
  /// Deliberately not [malformedRecord], whose notice cannot say which side
  /// has to act. Here it is always this device: nothing is wrong with the
  /// record, and updating the app is the whole remedy. A blob's report carries
  /// `kind` and `recordId`; a manifest's carries only `peerId`, because a
  /// manifest this build cannot read does not say what it lists.
  newerWireVersion,
}

/// A structured, non-blocking diagnostic produced by a sync pass.
class SyncReport {
  const SyncReport({
    required this.code,
    required this.message,
    this.kind,
    this.recordId,
    this.peerId,
    this.httpStatus,
  });

  final SyncReportCode code;
  final String message;
  final SyncRecordKind? kind;
  final String? recordId;
  final String? peerId;

  /// The HTTP status the server answered the request behind this report with,
  /// when a response is what raised it — a blob or manifest the store would
  /// not serve. Null for everything else, a blob whose bytes did not match
  /// its hash included.
  ///
  /// Kept apart from [message] so the diagnostics export can say which status
  /// a report came from without printing the message, which is a maintainer
  /// diagnostic and may name wire paths. Not part of [coalescingKey]: the
  /// same record failing twice in one pass is one condition.
  final int? httpStatus;

  String get coalescingKey =>
      '${code.name}:${kind?.name ?? ''}:${recordId ?? ''}:${peerId ?? ''}';
}

/// Coalesces identical reports for the lifetime of one sync session.
class SyncReportSink {
  final _reports = <SyncReport>[];
  final _keys = <String>{};

  void add(SyncReport report) {
    if (_keys.add(report.coalescingKey)) {
      _reports.add(report);
    }
  }

  void addAll(Iterable<SyncReport> reports) {
    for (final report in reports) {
      add(report);
    }
  }

  List<SyncReport> get reports => List.unmodifiable(_reports);
}
