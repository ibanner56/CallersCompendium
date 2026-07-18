import 'dart:convert';

import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../model/phrase_structure.dart';
import 'figure_parser.dart';
import 'figure_text_scrub.dart';
import 'import_error.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// A [SourceAdapter] that imports dances from **The Caller's Box** (TCB)
/// per-dance JSON, as served by
/// `ibiblio.org/contradance/thecallersbox/dance.php?id=N&format=JSON`
/// (surveyed in `docs/research/callersbox.md`; conventions in
/// `docs/design/imports.md` §"CallersBox" and `docs/design/callersbox-snapshot.md`).
///
/// **Core is I/O-free** — this adapter never fetches the endpoint. It parses a
/// payload *string* that the app layer supplies (a separate PR adds the URL
/// fetch + in-app wiring, at which point ROADMAP 6.2/6.3 tick). The same parse
/// path is reused by the future 6.2 hosted-snapshot NDJSON import.
///
/// ## Scope: figures imported as CUSTOM (dialect-scrubbed text + beats)
/// TCB figure lines are free text of the form `(beats) text` (e.g.
/// `(4) Neighbor balance`). A `(beats) text` → **structured-move** grammar
/// parser is a genuinely separate, large effort and is **deferred to a
/// follow-up** (the same call the ContraDB 6.4 and Caller's Companion 6.5
/// adapters made). Here every figure line is imported as a [customFigure]
/// carrying its beats and its **canonicalized** text, so the headline asks —
/// by-link parsing + gendered-term dialect scrubbing — are fully delivered and
/// `parse` never fails on figure content.
///
/// ## Dialect scrubbing (the headline ask)
/// Each figure line's text is routed through the CORE canonicalization
/// chokepoint [canonicalizeText] with [Dialect.canonical], whose always-on
/// legacy-synonym map rewrites gendered role terms
/// (gents/ladies/larks/robins/ladles/gentlespoons) to canonical role tokens
/// (`role1`/`role2`). Storage is dialect-agnostic; the app renders per the
/// user's active dialect. As a safety net the legacy move term `gypsy` is also
/// substituted to `shoulder round` (TCB already did this globally in Oct 2025).
///
/// ## Permission tiers (honored exactly)
/// - `Permission: full` → phrases/figures imported normally.
/// - anything else (`search`, blank, omitted) → TCB serves only metadata
///   (empty/omitted `phrases`); imported as a **metadata-only** draft (title,
///   formation, notes) with **no** reconstructed figures and a warning issue.
///   Figures are never fabricated for a non-full dance.
///
/// ## Choreographers / metadata
/// Each TCB `Authors[]` name is carried on the draft's `authorNames`; the
/// import pipeline resolves those to real [Choreographer] associations
/// ([Dance.authorIds]) at commit (match-or-create). Author names are no longer
/// folded into [Dance.callingNotes]. `FormationBase`/`FormationDetail` classify
/// to a [FormationShape] best-effort (original kept as [Formation.detail]);
/// `Progression` maps best-effort; `PhraseStructure` empty means the default.
///
/// ## Contract
/// - [discover] decodes the payload once and accepts a single TCB dance object,
///   an array of dances, or an object with a `dances`/`records` array. It
///   throws a discover [ImportError] on a missing/blank/undecodable payload, an
///   empty set, or a payload that is not a TCB dance (no `ID`/`Name`). It emits
///   one [DiscoveredRecord] per dance (`externalId` = TCB `ID`, `label` =
///   `Name`).
/// - [fetch] re-serializes the single dance into a self-contained [RawRecord]
///   (permission + a `sourceVersion` tag carried through) so [parse] never
///   depends on discover state.
/// - [parse] maps one TCB dance JSON → [StructuredDraft]. It throws a parse
///   [ImportError] only when there is no usable dance at all (undecodable / not
///   an object / no `ID` and no `Name`). It never fails on figure content.
class CallersBoxAdapter implements SourceAdapter {
  CallersBoxAdapter();

  @override
  ProvenanceSource get source => ProvenanceSource.callersbox;

  /// Raw dance elements from the most recent [discover], in order, so [fetch]
  /// can re-serialize a single dance by index. [parse] never consults this.
  final List<Object?> _records = [];

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    // Reset up front so a failed attempt never leaves stale records fetchable
    // from a prior successful discover on this instance.
    _records.clear();

    final payload = request.payload;
    if (payload == null || payload.trim().isEmpty) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'No Caller\'s Box payload provided to import.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (e) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'Payload is not valid JSON: ${e.message}',
        cause: e,
      );
    }

    final elements = _extractDanceElements(decoded);
    if (elements == null) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'Payload is not a Caller\'s Box dance export: expected a TCB dance '
            'object (with "ID"/"Name"), an array of dances, or an object with '
            'a "dances"/"records" array.',
      );
    }
    // Keep only dance-like elements so a mixed array/wrapper never surfaces a
    // record with a null id/label that would only fail later in parse().
    final dances = elements.where(_looksLikeTcbDance).toList();
    if (dances.isEmpty) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'Payload does not contain a Caller\'s Box dance: no element has an '
            '"ID" or "Name".',
      );
    }

    _records.addAll(dances);
    return [
      for (var i = 0; i < dances.length; i++)
        DiscoveredRecord(
          source: source,
          externalId: _externalIdOf(dances[i]),
          label: _nameOf(dances[i]),
          locator: {'index': i},
        ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final index = record.locator['index'];
    if (index is! int || index < 0 || index >= _records.length) {
      throw fetchError(
        source,
        'Record locator is missing a valid "index"; re-run discover.',
        externalId: record.externalId,
      );
    }
    final element = _records[index];
    return RawRecord(
      source: source,
      externalId: record.externalId,
      sourceVersion: _sourceVersionOf(element),
      payload: jsonEncode(element),
      contentType: 'application/json',
      permission: _permissionOf(element),
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.payload);
    } on FormatException catch (e) {
      throw parseError(
        source,
        'Payload is not valid JSON: ${e.message}',
        externalId: raw.externalId,
        cause: e,
      );
    }
    if (decoded is! Map) {
      throw parseError(
        source,
        'Payload is not a Caller\'s Box dance object.',
        externalId: raw.externalId,
      );
    }
    final dance = Map<String, Object?>.from(decoded);

    final title = _asString(dance['Name'])?.trim();
    final id = _asString(dance['ID'])?.trim();
    if ((title == null || title.isEmpty) && (id == null || id.isEmpty)) {
      throw parseError(
        source,
        'Caller\'s Box record has no "ID" or "Name".',
        externalId: raw.externalId,
      );
    }
    // A dance with an id but no name is still importable (metadata stub).
    final effectiveTitle = (title != null && title.isNotEmpty)
        ? title
        : 'Caller\'s Box dance $id';

    final issues = <ImportIssue>[];
    final formation = _parseFormation(dance, issues);
    final progression = _parseProgression(dance['Progression'], issues);
    final phraseStructure = _parsePhraseStructure(
      dance['PhraseStructure'],
      issues,
    );

    final permission = (_asString(dance['Permission'])?.trim() ?? '')
        .toLowerCase();
    final isFull = permission == 'full';
    final figures = isFull ? _parseFigures(dance['phrases']) : const <Figure>[];
    if (!isFull) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'callersbox_search_tier',
          message: permission.isEmpty
              ? 'Dance has no "full" permission tier; The Caller\'s Box '
                    'serves only metadata (no figures). Imported as a '
                    'metadata-only stub.'
              : 'Dance permission tier is "$permission" (not "full"); The '
                    'Caller\'s Box serves only metadata (no figures). '
                    'Imported as a metadata-only stub.',
        ),
      );
    }

    return StructuredDraft(
      dance: Dance(
        id: 'callersbox-import',
        title: effectiveTitle,
        formation: formation,
        progression: progression,
        phraseStructure: phraseStructure,
        figures: figures,
        callingNotes: _buildNotes(dance),
        tunes: _asStringList(dance['Tunes']),
        // The pipeline attaches provenance at commit, derived from `raw`.
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
      raw: raw,
      issues: issues,
      authorNames: _asStringList(dance['Authors']),
    );
  }

  // --- Figures ---------------------------------------------------------------

  /// TCB `phrases` is an array of `{name, figures:[line, ...]}`. Figures are
  /// concatenated across phrases in order; each line is routed through the
  /// shared [parseFigureLine] — recognised moves become structured figures, the
  /// rest fall back to [customFigure]. Section grouping is NOT embedded in the
  /// figure text (labels derive from cumulative beats), so the phrase `name` is
  /// no longer prefixed. Parse-never-fails: any odd line is still imported as
  /// custom.
  ///
  /// The cross-line merge ([_mergeCrossLineFigures]) runs PER-PHRASE, so a fold
  /// never crosses a section boundary: TCB phrase entries map to the A1/A2/…
  /// sections, and the balance+move / hall+bend pairs it folds are always
  /// written within a single phrase entry.
  List<Figure> _parseFigures(Object? phrases) {
    if (phrases is! List) return const [];
    final figures = <Figure>[];
    for (final phrase in phrases) {
      if (phrase is! Map) continue;
      final lines = phrase['figures'];
      if (lines is! List) continue;
      // Preserve the raw line strings (indentation intact): TCB's compound
      // convention is signalled by leading indentation, which `_parseFigureLine`
      // trims away, so grouping must run on the untrimmed lines first.
      final rawLines = <String>[];
      for (final line in lines) {
        final text = _asString(line);
        if (text == null) continue;
        rawLines.add(text);
      }
      figures.addAll(_mergeCrossLineFigures(_parsePhraseFigures(rawLines)));
    }
    return figures;
  }

  /// Parses one phrase's raw figure lines into figures, collapsing TCB's
  /// compound convention ([_tryParseCompound]) into a single figure and routing
  /// every other line through the per-line parser unchanged.
  List<Figure> _parsePhraseFigures(List<String> rawLines) {
    final out = <Figure>[];
    var i = 0;
    while (i < rawLines.length) {
      final compound = _tryParseCompound(rawLines, i);
      if (compound != null) {
        out.add(compound.figure);
        i = compound.nextIndex;
        continue;
      }
      out.addAll(_parseFigureLine(rawLines[i]));
      i += 1;
    }
    return out;
  }

  /// Attempts to read a TCB **compound figure** starting at [start]: a parent
  /// line `(beats) Name:` (trailing colon) followed by one or more lines with
  /// strictly greater leading indentation whose `(beats)` values sum EXACTLY to
  /// the parent's. This is TCB's convention for expressing a named figure as its
  /// component sub-figures (e.g. `(6) Revolving door:` == `(4) Partner star
  /// promenade ½` + `(2) Women allemande right ½`); the children are the
  /// figure's *definition*, not additional choreography.
  ///
  /// On a confident match returns a single figure carrying the PARENT's beats —
  /// the parent name routed through [parseFigureLines], yielding the structured
  /// taxonomy move when it maps (e.g. `revolving_door`) or a single
  /// [customFigure] otherwise. The children are never emitted as separate
  /// figures; their (scrubbed) decomposition rides along in the figure `note` so
  /// nothing the source stated is dropped. Beats stay accurate: the collapsed
  /// figure contributes exactly the parent's beat count to the section total.
  ///
  /// Returns `null` when [start] is not a compound parent, so the caller parses
  /// the line normally. Tolerant of untrusted input: a missing/non-numeric beat,
  /// no children, a colon with no indented followers, or children that do not
  /// sum to the parent all decline the collapse (safe fallback, never a throw).
  _Compound? _tryParseCompound(List<String> lines, int start) {
    final parent = _compoundParent.firstMatch(lines[start]);
    if (parent == null) return null;
    final parentIndent = parent.group(1)!.length;
    final parentBeats = int.tryParse(parent.group(2)!);
    if (parentBeats == null || parentBeats <= 0) return null;
    final parentText = parent.group(3)!.trim();
    if (parentText.isEmpty) return null;

    // Collect strictly-more-indented `(beats) text` children until the block
    // returns to the parent's column (or a non-beats / non-indented line). We do
    // NOT recurse into deeper nesting — a nested grandchild would double-count
    // and fail the exact-sum guard below, declining the collapse safely.
    final childTexts = <String>[];
    var childBeatsSum = 0;
    var i = start + 1;
    while (i < lines.length) {
      final child = _indentedBeats.firstMatch(lines[i]);
      if (child == null) break;
      final childIndent = child.group(1)!.length;
      if (childIndent <= parentIndent) break;
      final childBeats = int.tryParse(child.group(2)!);
      if (childBeats == null) break;
      childBeatsSum += childBeats;
      childTexts.add('($childBeats) ${child.group(3)!.trim()}');
      i += 1;
    }

    // Confidence guard: at least one child, summing EXACTLY to the parent.
    if (childTexts.isEmpty || childBeatsSum != parentBeats) return null;

    // The parent is a single atomic figure carrying the parent's beats. A
    // recognised parent structures (revolving_door, …); anything else — or a
    // parent that would itself split on `;` — stays one custom figure. Never
    // split into the children.
    final parsed = parseFigureLine(parentText, beats: parentBeats);
    final base =
        parsed != null && !parsed.isCustom && !_hasTopLevelSemicolon(parentText)
        ? parsed
        : customFigure(parentText, beats: parentBeats);

    // Preserve the source decomposition (scrubbed) so the definition is not
    // lost, appending to any note the recognizer already attached.
    final decomposition = childTexts
        .map((c) => _scrubCompoundChild(c))
        .join('; ');
    final note = [
      if (base.note != null && base.note!.trim().isNotEmpty) base.note!.trim(),
      decomposition,
    ].join(' — ');

    return _Compound(base.copyWith(note: note), i);
  }

  /// Scrubs one `(beats) text` child line for storage in a compound's note,
  /// keeping its beat count but routing the prose through the shared
  /// canonicalization chokepoint (gendered terms → role tokens) so the note
  /// reads dialect-agnostically like every other imported figure text.
  static String _scrubCompoundChild(String childLine) {
    final match = _beatsPrefix.firstMatch(childLine);
    if (match == null) return scrubFigureText(childLine);
    final beats = match.group(1)!;
    final scrubbed = scrubFigureText(match.group(2)!);
    return scrubbed.isEmpty ? '($beats)' : '($beats) $scrubbed';
  }

  /// Whether [text] contains a top-level `;` clause separator (outside any
  /// bracketed annotation). Mirrors [parseFigureLines]' split rule so a compound
  /// parent that would fan out into multiple structured clauses is kept as a
  /// single custom figure instead.
  static bool _hasTopLevelSemicolon(String text) {
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x28 || c == 0x5B) {
        depth++;
      } else if (c == 0x29 || c == 0x5D) {
        if (depth > 0) depth--;
      } else if (depth == 0 && c == 0x3B) {
        return true;
      }
    }
    return false;
  }

  /// Parses one TCB figure line `(beats) text` into one or more figures. A
  /// missing prefix or `(0)` means a 0-beat line (a formation label). The
  /// scrubbed dance prose is stored as clean text — section grouping is not
  /// embedded in the text (it derives from beats). Returns an empty list for a
  /// line that is empty after scrubbing (nothing to store).
  ///
  /// A compound line joined by top-level `;` (`do A; then do B`) is split into
  /// one figure per clause by [parseFigureLines], which keeps the whole line
  /// custom unless every clause structures and preserves the source beats total
  /// on the first clause. Single-clause lines behave exactly as before.
  List<Figure> _parseFigureLine(String line) {
    final match = _beatsPrefix.firstMatch(line);
    int beats = 0;
    String text = line.trim();
    if (match != null) {
      beats = int.tryParse(match.group(1)!) ?? 0;
      text = match.group(2)!.trim();
    }
    // Route through the shared parser: recognised moves become structured
    // figures; the rest fall back to custom. Empty when the line is empty
    // after scrubbing.
    return parseFigureLines(text, beats: beats);
  }

  // --- Cross-line merge (PR3b) -----------------------------------------------

  /// Moves a preceding balance LINE folds into (D1). `swing` takes the balance
  /// as its `prefix`; the rest take it as a `balance: true` flag.
  static const _balanceMergeMoves = {
    'swing',
    'petronella',
    'rory_o_more',
    'box_the_gnat',
    'swat_the_flea',
    // v11 balance+twirl-family move: a preceding balance line folds in as
    // `balance: true` and the summed beats (balance 4 + move 4 = 8) supply the
    // balanced beat count — the same single-source-of-truth pattern box_the_gnat
    // uses, which is why it carries no `paramBeats`. (v12: `star_through` was
    // removed from this set — it now mirrors california_twirl with no balance.)
    'box_circulate',
  };

  /// Folds figures that The Caller's Box writes as separate lines into a single
  /// structured move, flipping PR3a's neutral cross-line values to real ones:
  ///  - a balance LINE immediately preceding a swing / petronella /
  ///    rory_o_more / box_the_gnat / swat_the_flea folds into that move (swing →
  ///    `prefix: 'balance'`; the others → `balance: true`, upgrading rory's
  ///    neutral `false`);
  ///  - a bend-the-line LINE immediately following a structured down/up the hall
  ///    folds in as `ender: 'bendTheLine'` (upgrading the neutral `'none'`).
  ///
  /// Adjacency-consume: a single left-to-right walk that advances by two on a
  /// merge, so each line is consumed at most once, only immediately-adjacent
  /// lines fold, and a balance/bend line with no mergeable neighbour is kept as
  /// its own figure (choreography is never dropped). Merged beats are the SUM of
  /// the two consumed lines (source timing preserved). The caller passes one
  /// phrase's figures, so folds never cross a section boundary.
  static List<Figure> _mergeCrossLineFigures(List<Figure> figures) {
    final merged = <Figure>[];
    var i = 0;
    while (i < figures.length) {
      final current = figures[i];
      final next = i + 1 < figures.length ? figures[i + 1] : null;
      if (next != null) {
        // Fold 1: balance line → following mergeable move.
        if (_isBalanceLine(current)) {
          final folded = _foldBalanceIntoMove(current, next);
          if (folded != null) {
            merged.add(folded);
            i += 2;
            continue;
          }
        }
        // Fold 2: structured hall → following bend-the-line line.
        if (_isHall(current) && _isBendLine(next)) {
          merged.add(_foldBendIntoHall(current, next));
          i += 2;
          continue;
        }
      }
      merged.add(current);
      i += 1;
    }
    return merged;
  }

  /// A balance line: the structured `balance` / `balance_the_ring` moves, or a
  /// custom figure whose scrubbed text leads with "balance" (the varied
  /// non-dancer forms `Balance diamond` / `Balance long wave` /
  /// `Balance wave of four`; `X balance`, `Balance ring` and `X balance (hand)`
  /// already recognise as structured balance / balance_the_ring).
  static bool _isBalanceLine(Figure f) {
    if (f.move == 'balance' || f.move == 'balance_the_ring') return true;
    if (!f.isCustom) return false;
    final words = _figureWords(f);
    return words.isNotEmpty && words.first == 'balance';
  }

  /// A bend-the-line line: a custom figure whose scrubbed text is "bend the
  /// line" (or the bare "bend" / "bend line" shorthands). Bend never recognises
  /// as a structured move, so it is always custom here.
  static bool _isBendLine(Figure f) {
    if (!f.isCustom) return false;
    final words = _figureWords(f);
    if (words.isEmpty || words.first != 'bend') return false;
    return words.length == 1 ||
        (words.length == 2 && words[1] == 'line') ||
        (words.length == 3 && words[1] == 'the' && words[2] == 'line');
  }

  static bool _isHall(Figure f) =>
      f.move == 'down_the_hall' || f.move == 'up_the_hall';

  /// Returns [move] with the preceding [balance] folded in, or `null` when
  /// [move] is not a mergeable target (leaving both as separate figures) or
  /// already carries the balance (guarding against a double-fold of a
  /// single-line "balance and swing" / meltdown swing / already-balanced move).
  static Figure? _foldBalanceIntoMove(Figure balance, Figure move) {
    if (!_balanceMergeMoves.contains(move.move)) return null;
    // Mismatched-who guard: a structured balance line carries its own `who`
    // (e.g. "Neighbor balance" → who: neighbors). Only fold when the dancers
    // agree — if BOTH the balance and the move name an explicit, DIFFERING
    // `who`, they are distinct figures ("Neighbor balance" then "Partner
    // swing"), so merging would silently drop the balance's choreography.
    // Either side without a `who` (custom balance forms, balance_the_ring,
    // petronella) still merges.
    final balanceWho = balance.params['who'];
    final moveWho = move.params['who'];
    if (balanceWho != null && moveWho != null && balanceWho != moveWho) {
      return null;
    }
    final beats = _sumBeats(balance, move);
    if (move.move == 'swing') {
      final prefix = move.params['prefix'];
      if (prefix != null && prefix != 'none') return null;
      return move.copyWith(
        params: {...move.params, 'prefix': 'balance', 'beats': ?beats},
      );
    }
    if (move.params['balance'] == true) return null;
    return move.copyWith(
      params: {...move.params, 'balance': true, 'beats': ?beats},
    );
  }

  static Figure _foldBendIntoHall(Figure hall, Figure bend) {
    final beats = _sumBeats(hall, bend);
    return hall.copyWith(
      params: {...hall.params, 'ender': 'bendTheLine', 'beats': ?beats},
    );
  }

  /// Sum of the two figures' beats, or `null` when neither carries beats (so a
  /// merged beats-free pair does not gain a spurious `0`).
  static int? _sumBeats(Figure a, Figure b) {
    final total = a.beats + b.beats;
    return total > 0 ? total : null;
  }

  /// The lowercased, punctuation-split words of a custom figure's stored text
  /// (empty for a structured figure, which has no `text` param).
  static List<String> _figureWords(Figure f) {
    final text = f.params['text'];
    if (text is! String) return const [];
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[(){}\[\]]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  // --- Formation -------------------------------------------------------------

  Formation _parseFormation(
    Map<String, Object?> dance,
    List<ImportIssue> issues,
  ) {
    final base = _asString(dance['FormationBase'])?.trim() ?? '';
    final extra = _asString(dance['FormationDetail'])?.trim() ?? '';
    final combined = [base, extra].where((s) => s.isNotEmpty).join(' — ');
    final detail = combined.isEmpty ? null : combined;

    if (base.isEmpty && extra.isEmpty) {
      return const Formation(FormationShape.dupleImproper);
    }

    final lower = '$base $extra'.toLowerCase();
    FormationShape? shape;
    if (lower.contains('becket')) {
      shape = _becketShape(dance['Direction'], lower, issues);
    } else if (lower.contains('improper')) {
      shape = FormationShape.dupleImproper;
    } else if (lower.contains('indecent')) {
      shape = FormationShape.dupleIndecent;
    } else if (lower.contains('proper')) {
      shape = FormationShape.dupleProper;
    } else if (lower.contains('triple')) {
      shape = FormationShape.tripleMinor;
    } else if (lower.contains('triplet')) {
      shape = FormationShape.triplet;
    } else if (lower.contains('four facing four') ||
        lower.contains('four face four')) {
      shape = FormationShape.fourFaceFour;
    } else if (lower.contains('three facing three') ||
        lower.contains('three face three')) {
      shape = FormationShape.threeFaceThree;
    } else if (lower.contains('sicilian')) {
      shape = FormationShape.sicilianCircle;
    } else if (lower.contains('scatter')) {
      shape = FormationShape.scatterMixer;
    } else if (lower.contains('grid')) {
      shape = FormationShape.grid;
    } else if (lower.contains('circle')) {
      shape = FormationShape.circleMixer;
    } else if (lower.contains('longways')) {
      shape = FormationShape.longways;
    }

    if (shape == null) {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'callersbox_formation_unclassified',
          message:
              'Formation "${detail ?? base}" did not classify to a known '
              'shape; kept as detail on "other".',
        ),
      );
      return Formation(FormationShape.other, detail: detail);
    }
    return Formation(shape, detail: detail);
  }

  /// Resolves Becket rotation. The CW/CCW indicator lives in the separate
  /// top-level `Direction` JSON field, so prefer it when present; fall back to
  /// scanning the formation text for feeds that inline the direction; default
  /// to [FormationShape.becketCw] when neither says otherwise.
  static FormationShape _becketShape(
    Object? direction,
    String lower,
    List<ImportIssue> issues,
  ) {
    final dir = _asString(direction)?.trim();
    if (dir != null && dir.isNotEmpty) {
      switch (dir.toLowerCase()) {
        case 'ccw':
          return FormationShape.becketCcw;
        case 'cw':
          return FormationShape.becketCw;
      }
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.info,
          code: 'callersbox_direction_unmapped',
          message:
              'Direction "$dir" is not "CW" or "CCW"; defaulted Becket to '
              'clockwise.',
        ),
      );
    }
    return (lower.contains('ccw') || lower.contains('counter'))
        ? FormationShape.becketCcw
        : FormationShape.becketCw;
  }

  Progression _parseProgression(Object? raw, List<ImportIssue> issues) {
    final text = _asString(raw)?.trim();
    if (text == null || text.isEmpty) return Progression.single;
    switch (text.toLowerCase()) {
      case 'none':
        return Progression.none;
      case 'single':
        return Progression.single;
      case 'double':
        return Progression.double;
      case 'triple':
        return Progression.triple;
      case 'quadruple':
        return Progression.quadruple;
    }
    issues.add(
      ImportIssue(
        severity: ImportIssueSeverity.info,
        code: 'callersbox_progression_unmapped',
        message:
            'Progression "$text" is not a standard tier; recorded as "other".',
      ),
    );
    return Progression.other;
  }

  // --- Phrase structure ------------------------------------------------------

  String _parsePhraseStructure(Object? raw, List<ImportIssue> issues) {
    final text = _asString(raw)?.trim();
    if (text == null || text.isEmpty) return '';
    try {
      // Validate against the model's grammar; keep the raw form when valid.
      PhraseStructure.parse(text);
      return text;
    } on FormatException {
      issues.add(
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'callersbox_phrase_structure_unreadable',
          message:
              'PhraseStructure "$text" is not "phrases*bars*beatsPerBar"; '
              'default structure used.',
        ),
      );
      return '';
    }
  }

  // --- Notes -----------------------------------------------------------------

  String _buildNotes(Map<String, Object?> dance) {
    final parts = <String>[];

    // Author names are resolved to Choreographer associations by the import
    // pipeline (Dance.authorIds); they are carried on the draft's authorNames
    // and deliberately NOT folded into the notes here.
    final interpretedBy = _asStringList(dance['InterpretedBy']);
    if (interpretedBy.isNotEmpty) {
      parts.add('Interpreted by: ${interpretedBy.join(', ')}');
    }

    final callingNotes = _asStringList(dance['CallingNotes']);
    if (callingNotes.isNotEmpty) {
      parts.add(callingNotes.join('\n'));
    }

    final otherNames = _asStringList(dance['OtherNames']);
    if (otherNames.isNotEmpty) {
      parts.add('Other names: ${otherNames.join(', ')}');
    }

    final music = _asStringList(dance['Music']);
    if (music.isNotEmpty) {
      parts.add('Music: ${music.join(', ')}');
    }

    final appearances = _formatAppearances(dance['Appearances']);
    if (appearances.isNotEmpty) {
      parts.add('Appears in: $appearances');
    }

    parts.add('Imported from The Caller\'s Box.');
    return parts.join('\n\n');
  }

  String _formatAppearances(Object? raw) {
    if (raw is! List) return '';
    final entries = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final source = _asString(item['source'])?.trim();
      if (source == null || source.isEmpty) continue;
      final page = _asString(item['p'])?.trim();
      entries.add(
        page != null && page.isNotEmpty ? '$source (p. $page)' : source,
      );
    }
    return entries.join('; ');
  }

  // --- Top-level shape helpers ----------------------------------------------

  /// Normalizes the decoded payload to a flat list of dance elements, or `null`
  /// when the root is not a recognizable Caller's Box shape.
  static List<Object?>? _extractDanceElements(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final dances = decoded['dances'];
      if (dances is List) return dances;
      final records = decoded['records'];
      if (records is List) return records;
      // A bare object is a single dance only when it looks like a TCB dance.
      if (_looksLikeTcbDance(decoded)) return [decoded];
      return null;
    }
    return null;
  }

  static bool _looksLikeTcbDance(Object? element) {
    if (element is! Map) return false;
    final id = _asString(element['ID'])?.trim();
    final name = _asString(element['Name'])?.trim();
    return (id != null && id.isNotEmpty) || (name != null && name.isNotEmpty);
  }

  static String? _externalIdOf(Object? element) {
    if (element is! Map) return null;
    final id = _asString(element['ID'])?.trim();
    if (id != null && id.isNotEmpty) return id;
    final name = _asString(element['Name'])?.trim();
    if (name != null && name.isNotEmpty) {
      return 'name:${name.toLowerCase()}';
    }
    return null;
  }

  static String? _nameOf(Object? element) {
    if (element is! Map) return null;
    return _asString(element['Name'])?.trim();
  }

  static String? _permissionOf(Object? element) {
    if (element is! Map) return null;
    return _asString(element['Permission'])?.trim();
  }

  static String _sourceVersionOf(Object? element) {
    if (element is Map) {
      final downloaded = _asString(element['download_date'])?.trim();
      if (downloaded != null && downloaded.isNotEmpty) return downloaded;
    }
    return 'thecallersbox-json';
  }

  static String? _asString(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final item in value) {
      final s = _asString(item)?.trim();
      if (s != null && s.isNotEmpty) out.add(s);
    }
    return out;
  }

  static final RegExp _beatsPrefix = RegExp(
    r'^\s*\((\d+)\)\s*(.*)$',
    dotAll: true,
  );

  /// A TCB compound-figure PARENT line: `(beats) Name:` with a trailing colon.
  /// Group 1 is the leading indentation (used to scope the children), group 2
  /// the beat count, group 3 the figure name (colon and surrounding space
  /// stripped). Single-line (no `dotAll`) so the trailing-colon anchor is exact.
  static final RegExp _compoundParent = RegExp(
    r'^(\s*)\((\d+)\)\s*(\S.*?):\s*$',
  );

  /// A `(beats) text` line with its leading indentation captured (group 1), used
  /// to detect a compound's indented CHILD lines. Group 2 is the beat count,
  /// group 3 the prose.
  static final RegExp _indentedBeats = RegExp(
    r'^(\s*)\((\d+)\)\s*(.*)$',
    dotAll: true,
  );

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
}

/// The result of collapsing a TCB compound figure: the single [figure] the
/// parent + its indented children map to, and [nextIndex] — the index of the
/// first line AFTER the consumed block, so the caller resumes there.
class _Compound {
  const _Compound(this.figure, this.nextIndex);

  final Figure figure;
  final int nextIndex;
}
