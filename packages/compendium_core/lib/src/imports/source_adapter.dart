import 'package:meta/meta.dart';

import '../model/enums.dart';
import 'raw_record.dart';
import 'structured_draft.dart';

/// Input to an adapter's `discover` step: whatever the user supplied to start
/// an import (a picked file's bytes, a pasted blob, a URL, a snapshot handle).
///
/// The framework is transport-agnostic — it never performs I/O itself — so
/// this is a small, open envelope. Adapters read the fields they understand;
/// [payload] carries inline text (e.g. a pasted dance JSON), [uri] a location
/// to fetch, and [options] any source-specific knobs.
@immutable
class ImportRequest {
  const ImportRequest({this.payload, this.uri, this.options = const {}});

  /// Inline text content, if the user pasted/loaded it directly.
  final String? payload;

  /// A location the adapter may fetch from (file path or URL). The framework
  /// does not dereference it — the adapter owns all I/O.
  final String? uri;

  /// Source-specific options (e.g. a permission override, a field mapping).
  final Map<String, Object?> options;
}

/// One record an adapter has discovered and can [SourceAdapter.fetch]. It is a
/// lightweight handle (id + display label) — the verbatim payload is only
/// obtained on fetch, so `discover` can list a large snapshot cheaply.
@immutable
class DiscoveredRecord {
  const DiscoveredRecord({
    required this.source,
    this.externalId,
    this.label,
    this.locator = const {},
  });

  final ProvenanceSource source;

  /// Stable source-native id, if any (feeds the dedupe key and provenance).
  final String? externalId;

  /// Human-readable label for review UIs (e.g. a dance title). Optional.
  final String? label;

  /// Opaque adapter-internal data needed to fetch this record (e.g. a byte
  /// offset into a snapshot, a sub-path). The framework treats it as a blob.
  final Map<String, Object?> locator;

  @override
  String toString() =>
      'DiscoveredRecord(${source.name}, $externalId${label == null ? '' : ', $label'})';
}

/// The small interface every source adapter implements (`docs/design/
/// imports.md`): `discover` → `fetch` → `parse`. Adapters live in the pure-Dart
/// core and are unit-tested against fixture files; the [ImportPipeline] drives
/// them through the full `fetch → RawRecord → parse → StructuredDraft →
/// dedupe → commit` flow.
///
/// Contract:
/// - [discover] enumerates the records available from an [ImportRequest]
///   without necessarily fetching their full payloads.
/// - [fetch] obtains one record's payload verbatim as a [RawRecord].
/// - [parse] maps a [RawRecord] to a [StructuredDraft]. **It must never throw
///   because a figure line is unparseable** — such lines become [customFigure]s
///   (the parse-never-fails invariant). Throwing is reserved for a payload that
///   is not a valid record of this source at all (surfaced as a parse
///   [ImportError] by the pipeline).
abstract interface class SourceAdapter {
  /// The source this adapter imports from.
  ProvenanceSource get source;

  /// Enumerates the records available for [request].
  Future<List<DiscoveredRecord>> discover(ImportRequest request);

  /// Fetches the verbatim payload for one [record].
  Future<RawRecord> fetch(DiscoveredRecord record);

  /// Parses one [raw] record into a draft. Never fails a dance on figure
  /// content; unparseable figures fall back to custom.
  StructuredDraft parse(RawRecord raw);
}
