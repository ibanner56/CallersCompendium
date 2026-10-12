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
  /// record, and updating the app is the whole remedy. From the client's peer
  /// download, a blob's report carries `kind` and `recordId`; a manifest's
  /// carries only `peerId`, because a manifest this build cannot read does not
  /// say what it lists. `SyncApplyEngine.applyJson` has neither a peer nor a
  /// decoded envelope, so its report carries none of the three.
  newerWireVersion,

  /// A peer's record blob carried a part a newer version of the app added
  /// that this build can neither apply nor keep in place
  /// (`SyncNewerFieldException`), so it was refused whole (spec §6.7, §6.9).
  /// Every other field this build does not sync is kept, not refused, and
  /// raises [keptNewerFields] instead. Also raised when versions tied on
  /// `updatedAt` differ only in kept parts, which this build leaves to a
  /// device that understands them.
  ///
  /// Its own code rather than [malformedRecord] for the reason
  /// [newerWireVersion] has one: the remedy is updating the app on *this*
  /// device, and the generic skipped-record notice cannot say so. It is shown
  /// with [newerWireVersion], which has the same remedy. From the client's
  /// peer download it always carries `kind`, `recordId` and `peerId`;
  /// `SyncApplyEngine.applyJson` has no peer or decoded envelope, so its
  /// report carries none of them.
  ///
  /// It does not distinguish a newer sender from a defective one that put a
  /// private field on the wire. Decided by Isaac (maintainer) in review of
  /// #1728: the app's releases are under the maintainer's control, so a
  /// version difference is the case worth naming (spec §6.9).
  newerRecordFields,

  /// A peer's record was refused because a newer version of the app added
  /// something inside a dance's figures (spec §6.7): figures are positional,
  /// so this build could neither apply nor keep it. Its own code, beside
  /// [newerRecordFields], so the notice can say what this build does not
  /// understand rather than only that it is out of date. Shown with
  /// [newerWireVersion]; same remedy.
  newerFigures,

  /// A record on *this* device carries details a newer version of the app
  /// added, which this build keeps and shares back unchanged but cannot show
  /// (spec §6.7). Information only: the record syncs, nothing is wrong, and
  /// updating the app is what would show those details. Raised by every
  /// snapshot for as long as the parts are kept, with `kind` and `recordId`
  /// and a null `peerId`.
  keptNewerFields,
}

/// A structured, non-blocking diagnostic produced by a sync pass.
class SyncReport {
  const SyncReport({
    required this.code,
    required this.message,
    this.kind,
    this.recordId,
    this.peerId,
  });

  final SyncReportCode code;
  final String message;
  final SyncRecordKind? kind;
  final String? recordId;
  final String? peerId;

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
