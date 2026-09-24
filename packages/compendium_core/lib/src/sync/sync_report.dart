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
