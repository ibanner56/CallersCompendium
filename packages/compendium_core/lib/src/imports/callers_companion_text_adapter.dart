import '../model/enums.dart';
import 'author_tokenizer.dart';
import 'callers_companion_mapping.dart';
import 'import_error.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// A [SourceAdapter] that migrates Caller's Companion (CC) dances from CC's
/// **"copy formatted dance" clipboard/text** export — the *fallback* migration
/// path of `docs/design/imports.md` §2 ("worst case we parse those text
/// formats"; see also `docs/research/callers-companion.md` §Migration
/// implications). This is the first of two Phase 6.5 deliverables; the binary
/// FileMaker-12 `.USR` parser (the primary path) is a separate follow-up PR
/// that will **reuse** the [mapCallersCompanionDance] mapping this adapter
/// feeds, so all CC→model interpretation lives in `callers_companion_mapping.
/// dart`, and this file owns only the *text* parsing.
///
/// ## Assumed text format (documented assumption — no real fixture exists)
///
/// No canonical sample of CC's "copy formatted dance" clipboard output was
/// available, so the format below is **assumed** from the CC feature/schema
/// survey (`docs/research/callers-companion.md`: per-dance fields Name, Author,
/// Type, Formation, Level, Progression, Music, DateComposed/DateRevised; a
/// free-text body entered via "Insert Call" buttons that expand to lines like
/// `(16) Partner balance and swing`, grouped into sections A1/A2/B1/B2/C1/C2).
/// The shape is intentionally forgiving; unrecognized header lines and any body
/// line are tolerated rather than rejected.
///
/// ```
/// Simplicity Swing
/// by Becky Hill
/// Type: Contra
/// Formation: Improper
/// Level: Intermediate
/// Progression: Single
/// Music: any good 32-bar reels
/// Composed: 2004
///
/// A1   (8) Neighbor balance and swing
///      (8) Circle left 3/4
/// A2   (16) Partner balance and swing
/// B1   (8) Long lines forward and back
///      (8) Ladies chain
/// B2   (16) Hey for four
/// ```
///
/// Parsing rules:
/// - The **first non-empty line** is the dance title.
/// - An author line is `by <names>` or `Author: <names>`; the names part is
///   carried verbatim into [CcDanceRecord.authors] and split by the shared
///   canonical [splitAuthorNames] tokenizer (#685) in the mapping layer, so
///   this adapter and the `.usr` reader tokenize identically.
/// - Header lines of the form `Key: Value` populate Type / Formation / Level /
///   Progression / Music / Composed / Revised (keys are case-insensitive). One
///   field per line. Unrecognized `Key: Value` lines are ignored.
/// - A body line consisting solely of a section label (`A1`/`A2`/`B1`/`B2`/
///   `C1`/`C2`, optionally with trailing inline content) opens/labels a
///   section; following `(N) text` lines belong to it.
/// - A `(N) text` line has `N` beats; a body line with no `(N)` prefix has
///   beats 0. Malformed prefixes are treated as plain text (beats 0). **Body
///   parsing never fails** — every line becomes a `custom` figure.
/// - **Multiple dances** may be pasted at once, separated by a form-feed
///   character (`\f`, U+000C) — a page-break-per-record convention. A paste
///   with no form-feed is exactly one dance. (Blank lines cannot delimit
///   dances because a blank line optionally separates a dance's header from its
///   body.)
///
/// ## Identity & dedupe
///
/// CC's clipboard text carries **no stable per-record id**, so every
/// [RawRecord] has a `null` `externalId`. Dedupe therefore uses the framework's
/// fuzzy title+author path (`docs/design/imports.md` "dedupe"): re-pasting the
/// same dance surfaces an `ambiguous` verdict the user resolves
/// (link/duplicate/skip) rather than a silent auto-reimport. A content-derived
/// id was deliberately rejected — it would give false precision (any whitespace
/// edit would read as a brand-new dance).
///
/// ## Contract
/// - [discover] splits [ImportRequest.payload] into dance blocks and emits one
///   [DiscoveredRecord] per block (label = parsed title). A missing/empty
///   payload throws a discover [ImportError] (no usable source), mirroring
///   `GenericJsonAdapter`; a payload with usable blocks yields those blocks
///   even if some are blank (blank blocks are dropped).
/// - [fetch] returns a self-contained single-dance `text/plain` [RawRecord]
///   whose payload is that block's text, so [parse] never depends on
///   [discover] state.
/// - [parse] maps one block to a [StructuredDraft] via
///   [mapCallersCompanionDance]. It throws a parse [ImportError] only when the
///   block is not a recognizable CC dance at all (empty, or no title *and* no
///   body lines); it never throws on figure/body content.
class CallersCompanionTextAdapter implements SourceAdapter {
  CallersCompanionTextAdapter();

  /// Version tag stamped onto each [RawRecord.sourceVersion] and echoed to
  /// provenance, identifying this text-format reader (distinct from the future
  /// `.USR` binary reader).
  static const String sourceVersion = 'cc-text-1';

  @override
  ProvenanceSource get source => ProvenanceSource.callersCompanion;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    final payload = request.payload;
    if (payload == null || payload.trim().isEmpty) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'No Caller\'s Companion text was provided to import.',
      );
    }

    final blocks = _splitBlocks(payload);
    return [
      for (var i = 0; i < blocks.length; i++)
        DiscoveredRecord(
          source: source,
          // No stable CC id → null externalId (dedupe falls to fuzzy match).
          externalId: null,
          label: _peekTitle(blocks[i]),
          locator: {'block': blocks[i]},
        ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final block = record.locator['block'];
    if (block is! String) {
      throw fetchError(
        source,
        'Record locator is missing its dance text; re-run discover.',
      );
    }
    return RawRecord(
      source: source,
      externalId: null,
      sourceVersion: sourceVersion,
      payload: block,
      contentType: 'text/plain',
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final record = _parseBlock(raw.payload);
    if (record == null) {
      throw parseError(
        source,
        'Payload is not a recognizable Caller\'s Companion dance.',
      );
    }
    final mapping = mapCallersCompanionDance(record);
    return StructuredDraft(
      dance: mapping.dance,
      raw: raw,
      issues: mapping.issues,
      authorNames: mapping.authorNames,
    );
  }

  /// Splits a paste into per-dance text blocks on form-feed (`\f`). Blank
  /// blocks (only whitespace) are dropped.
  static List<String> _splitBlocks(String payload) => payload
      .split('\f')
      .where((b) => b.trim().isNotEmpty)
      .toList(growable: false);

  /// The parsed title of a block for a discovery label, or `null`.
  static String? _peekTitle(String block) => _parseBlock(block)?.name;

  /// Parses one dance block into a [CcDanceRecord], or `null` when the block is
  /// not a recognizable CC dance (empty, or no title and no body lines).
  static CcDanceRecord? _parseBlock(String block) {
    final lines = block
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    String? title;
    final authors = <String>[];
    String? type, formation, level, progression, music, composed, revised;
    final sections = <CcBodySection>[];

    String? currentLabel;
    var currentLines = <String>[];
    var inBody = false;

    void flushSection() {
      if (currentLabel != null || currentLines.isNotEmpty) {
        sections.add(CcBodySection(label: currentLabel, lines: currentLines));
      }
      currentLabel = null;
      currentLines = <String>[];
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();

      // Header region: everything before the first body content. A blank line
      // in the header is a separator and is skipped.
      if (!inBody) {
        if (line.isEmpty) continue;

        // A section label or a beats line is body content, never a title —
        // so a paste that opens straight into the transcription has no title
        // (the mapping supplies a placeholder + warning).
        final isBodyStart =
            _sectionLabelOf(line) != null || _looksLikeBodyLine(line);

        if (title == null && !isBodyStart) {
          title = line;
          continue;
        }

        if (isBodyStart) {
          inBody = true;
        } else {
          final author = _parseAuthorLine(line);
          if (author != null) {
            authors.addAll(author);
            continue;
          }
          final field = _parseFieldLine(line);
          if (field != null) {
            final (key, value) = field;
            switch (key) {
              case 'type':
                type = value;
              case 'formation':
                formation = value;
              case 'level':
                level = value;
              case 'progression':
                progression = value;
              case 'music':
                music = value;
              case 'composed':
              case 'datecomposed':
                composed = value;
              case 'revised':
              case 'daterevised':
                revised = value;
            }
            continue;
          }
          // Unrecognized non-field header line — treat as the start of the
          // body so nothing is silently dropped.
          inBody = true;
        }
      }

      // Body region.
      if (inBody) {
        if (line.isEmpty) continue;
        final (label, inlineContent) = _splitSectionLabel(line);
        if (label != null) {
          flushSection();
          currentLabel = label;
          if (inlineContent.isNotEmpty) currentLines.add(inlineContent);
        } else {
          currentLines.add(line);
        }
      }
    }
    flushSection();

    final hasTitle = (title ?? '').trim().isNotEmpty;
    final hasBody = sections.any((s) => s.lines.isNotEmpty);
    if (!hasTitle && !hasBody) return null;

    return CcDanceRecord(
      name: title,
      authors: authors,
      type: type,
      formation: formation,
      level: level,
      progression: progression,
      music: music,
      composed: composed,
      revised: revised,
      body: sections,
    );
  }

  /// The canonical section label (`A1`..`C2`) a line opens with, or `null`.
  static String? _sectionLabelOf(String line) => _splitSectionLabel(line).$1;

  /// Splits a leading section label from any inline content on the same line.
  /// Returns `(null, line)` when the line does not open with a section label.
  static (String?, String) _splitSectionLabel(String line) {
    final match = RegExp(
      r'^([ABC][12])\b[.:)\-]?\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return (null, line);
    return (match.group(1)!.toUpperCase(), match.group(2)!.trim());
  }

  /// Whether a line looks like a transcription body line (`(N) ...`).
  static bool _looksLikeBodyLine(String line) =>
      RegExp(r'^\(\s*\d+\s*\)').hasMatch(line);

  /// Parses an author line (`by X` / `Author: X`). Returns the names part
  /// **verbatim as a single raw field** — splitting multiple names is owned
  /// solely by the shared [splitAuthorNames] tokenizer in the mapping layer
  /// (#685), so this adapter and the `.usr` reader can never tokenize
  /// differently. Returns `null` when the line is not an author line.
  static List<String>? _parseAuthorLine(String line) {
    final byMatch = RegExp(
      r'^by\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    final String namesPart;
    if (byMatch != null) {
      namesPart = byMatch.group(1)!;
    } else {
      final field = _parseFieldLine(line);
      if (field == null || (field.$1 != 'author' && field.$1 != 'authors')) {
        return null;
      }
      namesPart = field.$2;
    }
    final trimmed = namesPart.trim();
    return trimmed.isEmpty ? null : [trimmed];
  }

  /// Parses a `Key: Value` header line into a lowercased key + trimmed value,
  /// or `null` when the line is not a `Key: Value` pair.
  static (String, String)? _parseFieldLine(String line) {
    final idx = line.indexOf(':');
    if (idx <= 0) return null;
    final key = line.substring(0, idx).trim().toLowerCase();
    final value = line.substring(idx + 1).trim();
    if (key.isEmpty || key.contains(' ')) return null;
    return (key, value);
  }
}
