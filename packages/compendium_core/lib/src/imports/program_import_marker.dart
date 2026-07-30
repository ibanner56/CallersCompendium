import 'package:meta/meta.dart';

import '../model/enums.dart';
import 'dedupe.dart';

/// Which "already imported?" marker a ContraDB search/preview row should show.
///
/// Two tiers, mirroring the reporter's framing on issue #586:
/// - [imported]: a **strong** signal matched — an existing local program was
///   imported from ContraDB with this exact program id (`(source, externalId)`).
/// - [possiblyImported]: only a **fuzzy** title-only signal matched — a local
///   program already exists with the same normalized title, but no stored
///   ContraDB id ties it to this program (e.g. it was imported before
///   provenance capture, or created by hand).
/// - [none]: no local program matches either signal.
enum ProgramImportMarkerKind { none, imported, possiblyImported }

/// The result of asking [ProgramImportMarkerIndex.markerFor] about one ContraDB
/// program: the [kind] and, for [ProgramImportMarkerKind.imported], the
/// [importedAt] timestamp of the matched local program (for an "Imported on
/// `<date>`" tooltip). Never blocks re-import — this is a display hint only.
@immutable
class ProgramImportMarker {
  const ProgramImportMarker._(this.kind, this.importedAt);

  static const ProgramImportMarker none = ProgramImportMarker._(
    ProgramImportMarkerKind.none,
    null,
  );

  factory ProgramImportMarker.imported({DateTime? importedAt}) =>
      ProgramImportMarker._(ProgramImportMarkerKind.imported, importedAt);

  static const ProgramImportMarker possiblyImported = ProgramImportMarker._(
    ProgramImportMarkerKind.possiblyImported,
    null,
  );

  final ProgramImportMarkerKind kind;

  /// When the matched local program was imported, for
  /// [ProgramImportMarkerKind.imported]. `null` otherwise, or when the matched
  /// program's provenance carried no import timestamp.
  final DateTime? importedAt;

  bool get isImported => kind == ProgramImportMarkerKind.imported;
  bool get isPossiblyImported =>
      kind == ProgramImportMarkerKind.possiblyImported;
  bool get isNone => kind == ProgramImportMarkerKind.none;
}

/// One existing local program as seen by the marker index: just enough to
/// answer "have I already imported this ContraDB program?" without loading the
/// whole `Program`.
@immutable
class ProgramImportMarkerEntry {
  const ProgramImportMarkerEntry({
    required this.title,
    this.source,
    this.externalId,
    this.importedAt,
  });

  /// The local program's title (used for the fuzzy title-only signal).
  final String title;

  /// The program's provenance source, if imported. Only entries whose [source]
  /// matches the index's tracked source participate in the strong id signal.
  final ProvenanceSource? source;

  /// The program's provenance external id, if imported (for ContraDB, the
  /// numeric `/programs/{id}`). Only non-empty ids participate in the strong
  /// signal.
  final String? externalId;

  /// When the program was imported, surfaced on an [ProgramImportMarkerKind.imported]
  /// marker for the tooltip. May be `null`.
  final DateTime? importedAt;
}

/// A pure, in-memory index that answers the two-tier "already imported?"
/// question for ContraDB program search/preview rows (issue #586).
///
/// It does no I/O: the caller builds it from the current local collection (one
/// [ProgramImportMarkerEntry] per program) and reuses it across a search
/// session. Matching is deliberately cheap and **ReDoS-safe** — the strong
/// signal is exact string equality on numeric ids, and the fuzzy signal is
/// equality of [normalizeTitle]-normalized titles (linear, simple char-class
/// regexes only). Untrusted ContraDB ids/names are length-capped before use so
/// a pathological value can't drive unbounded work.
///
/// The marker is only a hint: a false positive or negative can never corrupt
/// data or block a (possibly intentional) re-import.
class ProgramImportMarkerIndex {
  ProgramImportMarkerIndex(
    Iterable<ProgramImportMarkerEntry> entries, {
    this.source = ProvenanceSource.contradb,
  }) {
    for (final e in entries) {
      final title = e.title;
      if (title.length <= _maxTitleLength) {
        final normalized = normalizeTitle(title);
        if (normalized.isNotEmpty) _normalizedTitles.add(normalized);
      }
      final ext = e.externalId;
      if (e.source == source && ext != null && ext.isNotEmpty) {
        // First writer wins is fine: this is a display hint, and any matching
        // program proves the id was imported. Keep the earliest importedAt seen
        // so the tooltip reflects the original import.
        _importedAtByExternalId.putIfAbsent(ext, () => e.importedAt);
      }
    }
  }

  /// The provenance source whose ids drive the strong "Imported" signal.
  final ProvenanceSource source;

  /// Upper bound on a title's length before we bother normalizing it. ContraDB
  /// program names are short; anything longer is untrusted noise and is ignored
  /// for the fuzzy signal (defense against resource exhaustion on hostile input).
  static const int _maxTitleLength = 512;

  /// Upper bound on a candidate external id's length. ContraDB program ids are
  /// short numeric strings; a longer value can't be a real id, so it never
  /// strong-matches.
  static const int _maxExternalIdLength = 64;

  final Map<String, DateTime?> _importedAtByExternalId = {};
  final Set<String> _normalizedTitles = {};

  /// The marker for a ContraDB program identified by [externalId] (its numeric
  /// `/programs/{id}`) and shown as [name].
  ///
  /// Precedence is imported > possiblyImported > none: an exact id match wins
  /// even when the title also matches, so a firm "Imported" is never downgraded
  /// to the softer "Possibly imported".
  ProgramImportMarker markerFor(String externalId, String name) {
    final id = externalId.trim();
    if (id.isNotEmpty &&
        id.length <= _maxExternalIdLength &&
        _importedAtByExternalId.containsKey(id)) {
      return ProgramImportMarker.imported(
        importedAt: _importedAtByExternalId[id],
      );
    }
    if (name.length <= _maxTitleLength) {
      final normalized = normalizeTitle(name);
      if (normalized.isNotEmpty && _normalizedTitles.contains(normalized)) {
        return ProgramImportMarker.possiblyImported;
      }
    }
    return ProgramImportMarker.none;
  }
}
