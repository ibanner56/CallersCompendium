import 'sync_record_kind.dart';

/// The non-fatal reasons a sync pass may leave one record unresolved.
enum SyncReportCode {
  equalUpdatedAt,
  unseenLocalCreation,
  malformedRecord,
  invalidClassification,
  unresolvedBlob,
  blobIdentityMismatch,
  unresolvedReference,
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
