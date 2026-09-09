import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Current figure schema version. Persisted with every figure so old data
/// always parses after taxonomy/schema evolution.
const int figureSchemaVersion = 1;

/// Upper bound on the length of a single figure's walkthrough snippet
/// ([Figure.walkthroughOverride], [Figure.wordingOverride], and each entry of
/// the global snippet library),
/// in UTF-16 code units (#411).
///
/// Snippets are per-figure step descriptions — much shorter than a whole-dance
/// [kMaxWalkthroughLength] walkthrough — but they are still untrusted free text
/// that travels through backup / share / import, so they need a defence against
/// unbounded input. Enforcement is **soft**: editors cap input via `maxLength`
/// and deserializers **clamp** (truncate) rather than rejecting, so an oversized
/// snippet can never fail an otherwise-valid import.
const int kMaxWalkthroughSnippetLength = 4000;

/// Canonical move id for the free-text fallback figure.
const String customMove = 'custom';

/// Canonical taxonomy id for the custom move (same value as [customMove]).
const String customMoveId = customMove;

/// Reserved structural move id for the **meanwhile** container figure (#590):
/// a single figure that groups two or more concurrent sub-figures happening in
/// the same beats. Mirrors [customMove] — it is a structural id, not a taxonomy
/// move. Stable/serialized (permanent once written); never renamed.
const String meanwhileMove = 'meanwhile';

/// Reserved structural move id for a **modifier** container: the first child is
/// the core figure and every later child modifies it. Like [meanwhileMove], this
/// is a structural id, not a taxonomy move, and is stable once serialized.
const String modifierMove = 'modifier';

/// Maximum number of children either structural container may hold.
///
/// Real choreography never stacks more than a handful of simultaneous actions,
/// so this is both a UX bound and a **security bound** on the untrusted archive
/// / .ccshare import path: `params['figures']` is untrusted recursive structure,
/// and an unbounded side count would allow a nested-payload DoS. The codec and
/// the archive sanitizer both clamp defensively to this cap (parse-never-fails:
/// clamp, never throw).
const int kMaxMeanwhileSides = 6;

/// Alias for the shared structural-child cap, named for the modifier's ordered
/// children.
const int kMaxModifierFigures = kMaxMeanwhileSides;

/// Maximum structural container depth accepted by the strict model and honored
/// while decoding/sanitizing untrusted `params['figures']`.
///
/// A root container may contain one opposite container, but that child may only
/// contain ordinary figures. Same-kind nesting and deeper alternation are
/// rejected by the model and dropped defensively by tolerant decoders.
const int kMaxContainerDepth = 2;

/// Legacy name retained for callers that only need a defensive recursive bound.
const int kMaxMeanwhileDepth = 4;

const DeepCollectionEquality _paramsEquality = DeepCollectionEquality();

/// How a [customMove] [Figure] came to exist. Only meaningful when
/// [Figure.isCustom]; non-custom figures always carry [userEntered].
///
/// A custom figure can arise two ways that are otherwise indistinguishable:
/// the user deliberately authored it, or an import hit a taxonomy coverage gap
/// and kept the source line verbatim (the parse-never-fails invariant). This
/// discriminator lets the UI flag the parse-gap flavor. It is a passive flag
/// only — it never triggers a re-parse or rewrite (that is a separate concern).
enum CustomOrigin {
  /// The user authored this custom figure (the default for every figure).
  userEntered,

  /// An import parser could not map the source line to a structured move and
  /// kept it verbatim as a custom figure.
  importGap,
}

/// One figure (move instance) in a dance transcription.
///
/// A value object: canonical [move] id from the form's taxonomy plus NAMED
/// [params] (never positional — a ContraDB pitfall). Whether [move] exists
/// in the taxonomy and whether [params] match its parameter schema is
/// validated by the taxonomy engine (roadmap 2.4); this class enforces only
/// structural invariants.
@immutable
class Figure {
  Figure({
    this.schemaVersion = figureSchemaVersion,
    required this.move,
    Map<String, Object?> params = const {},
    this.note,
    this.progression = false,
    this.customOrigin = CustomOrigin.userEntered,
    this.assumedSubject = false,
    this.walkthroughOverride,
    this.wordingOverride,
  }) : params = Map.unmodifiable(params) {
    if (move.trim().isEmpty) {
      throw ArgumentError.value(move, 'move', 'must be non-empty');
    }
    final beats = params['beats'];
    if (beats != null && (beats is! int || beats < 0)) {
      throw ArgumentError.value(
        beats,
        'params[beats]',
        'must be a non-negative integer',
      );
    }
  }

  /// Builds a **meanwhile** container figure (#590): [figures] concurrent sides
  /// sharing a single [beats] count (the authoritative beat total for section
  /// math — a sub-figure's own `beats` is display-only and never counted).
  ///
  /// Enforces the structural caps for **programmatic** construction. A meanwhile
  /// may contain ordinary figures or modifier containers, but never another
  /// meanwhile and never a container below that nested modifier.
  factory Figure.meanwhile({
    required List<Figure> figures,
    required int beats,
    String? note,
    bool progression = false,
    Map<String, Object?> extraParams = const {},
    String? wordingOverride,
  }) {
    _validateContainer(
      containerMove: meanwhileMove,
      figures: figures,
      beats: beats,
    );
    return _container(
      move: meanwhileMove,
      figures: figures,
      beats: beats,
      note: note,
      progression: progression,
      extraParams: extraParams,
      wordingOverride: wordingOverride,
    );
  }

  /// Builds a **modifier** container: [figures.first] is the core figure and
  /// later figures are ordered modifiers sharing the container's beat count.
  ///
  /// A modifier may contain ordinary figures or a meanwhile container, but not
  /// another modifier and never a deeper container.
  factory Figure.modifier({
    required List<Figure> figures,
    required int beats,
    String? note,
    bool progression = false,
    Map<String, Object?> extraParams = const {},
    String? wordingOverride,
  }) {
    _validateContainer(
      containerMove: modifierMove,
      figures: figures,
      beats: beats,
    );
    return _container(
      move: modifierMove,
      figures: figures,
      beats: beats,
      note: note,
      progression: progression,
      extraParams: extraParams,
      wordingOverride: wordingOverride,
    );
  }

  static Figure _container({
    required String move,
    required List<Figure> figures,
    required int beats,
    String? note,
    required bool progression,
    required Map<String, Object?> extraParams,
    String? wordingOverride,
  }) => Figure(
    move: move,
    params: {
      ...extraParams,
      'beats': beats,
      'figures': List<Figure>.unmodifiable(figures),
    },
    note: note,
    progression: progression,
    wordingOverride: wordingOverride,
  );

  static void _validateContainer({
    required String containerMove,
    required List<Figure> figures,
    required int beats,
  }) {
    if (figures.length < 2) {
      throw ArgumentError.value(
        figures.length,
        'figures',
        '$containerMove needs at least 2 children',
      );
    }
    if (figures.length > kMaxMeanwhileSides) {
      throw ArgumentError.value(
        figures.length,
        'figures',
        '$containerMove allows at most $kMaxMeanwhileSides children',
      );
    }
    if (beats < 0) {
      throw ArgumentError.value(beats, 'beats', 'must be non-negative');
    }
    for (final child in figures) {
      if (!child.isContainer) continue;
      if (child.move == containerMove) {
        throw ArgumentError.value(
          child.move,
          'figures',
          '$containerMove may not nest itself',
        );
      }
      if (child.subFigures.any((grandchild) => grandchild.isContainer)) {
        throw ArgumentError.value(
          child.move,
          'figures',
          'container nesting may not exceed $kMaxContainerDepth levels',
        );
      }
    }
  }

  final int schemaVersion;

  /// Canonical snake_case move id (e.g. `shoulder_round`), or [customMove].
  final String move;

  /// Named parameters (e.g. `{who: 'partners', beats: 16}`). Unmodifiable.
  final Map<String, Object?> params;

  /// Optional dialect-aware free-text note ("scoop them up").
  final String? note;

  /// Marks a progression point in the dance.
  final bool progression;

  /// How this custom figure originated (see [CustomOrigin]). Only meaningful
  /// when [isCustom]; defaults to [CustomOrigin.userEntered] so plain-built and
  /// non-custom figures — and existing stored data lacking the key — are
  /// unaffected.
  final CustomOrigin customOrigin;

  /// Whether this figure's dancer/subject (`params['who']`) was ASSUMED by the
  /// import parser rather than STATED by the source.
  ///
  /// A free-text line that omits the subject (e.g. `Allemande left 1½`,
  /// `Balance and swing`) is still recognised as a structured move, but the
  /// recognizer has to fall back to the taxonomy default subject
  /// (`neighbors`/`partners`). Marking that fallback here lets every display
  /// surface render the subject as a NON-authoritative assumption (a
  /// `(assumed)` marker) instead of asserting fabricated choreography as fact —
  /// a provenance-integrity guarantee for untrusted imported input (#460).
  ///
  /// Additive and backward compatible: defaults to `false`, is written to JSON
  /// only when `true`, and absent/legacy data decodes as `false`, so no schema
  /// migration is required. It remains a DISPLAY/provenance flag and never
  /// changes the canonical (search/dedupe) render. Taxonomy v34 also uses this
  /// provenance bit at the repository write boundary to normalize legacy
  /// assumed `mad_robin` subjects before persistence; the bit itself still
  /// does not participate in canonical rendering.
  final bool assumedSubject;

  /// A per-dance, per-figure-instance **walkthrough snippet override** (#411):
  /// the step-description text to use for THIS occurrence of the figure in THIS
  /// dance, taking precedence over the user's global snippet library default
  /// (keyed by figure signature). `null` means "no override" — the figure falls
  /// back to the library default (or nothing) when a walkthrough is assembled.
  ///
  /// Untrusted free text (authored locally, but round-trips through backup /
  /// share / import): soft-clamped at [kMaxWalkthroughSnippetLength] on ingest
  /// and rendered ONLY through the dialect renderer's `renderFreeText` path
  /// (role substitution; no markup/injection), exactly like [Dance.walkthrough].
  ///
  /// Additive and backward compatible: defaults to `null`, is written to JSON
  /// only when non-null/non-empty, and absent/legacy data decodes as `null`, so
  /// no schema migration is required (it rides the authoritative `figures_json`
  /// JSON, like [customOrigin]/[assumedSubject]). A DISPLAY/authoring field
  /// only — it never changes the canonical (search/dedupe) render.
  final String? walkthroughOverride;

  /// A per-dance, per-figure-instance **wording override**: display text to
  /// use for THIS occurrence of the figure in THIS dance. It is rendered
  /// through the dialect renderer's `renderFreeText` path, so role terms still
  /// follow the active dialect. `null` means "use the renderer's wording".
  ///
  /// Additive and backward compatible: defaults to `null`, is written to JSON
  /// only when non-null/non-empty, and absent/legacy data decodes as `null`, so
  /// no schema migration is required. This is a DISPLAY/authoring field only —
  /// it never changes the canonical (search/dedupe) render.
  final String? wordingOverride;

  bool get isCustom => move == customMove;

  /// Whether this is a **meanwhile** container figure (#590) — a group of
  /// concurrent sub-figures sharing one beat count. Mirrors [isCustom].
  bool get isMeanwhile => move == meanwhileMove;

  /// Whether this is a **modifier** container whose first child is the core
  /// figure and later children are modifiers.
  bool get isModifier => move == modifierMove;

  /// Whether this is either structural container kind.
  bool get isContainer => isMeanwhile || isModifier;

  /// The ordered children of a structural container, or empty for an ordinary
  /// figure. Downstream surfaces read this instead of hand-parsing
  /// `params['figures']`.
  ///
  /// The children are authoritative; their individual `beats` are display-only
  /// and MUST NOT be summed into section totals — the container's own [beats]
  /// (`params['beats']`) is the single shared count.
  List<Figure> get subFigures {
    final raw = params['figures'];
    if (raw is List) {
      return List<Figure>.unmodifiable([
        for (final f in raw)
          if (f is Figure) f,
      ]);
    }
    return const [];
  }

  /// Duration in beats; 0 when unset (taxonomy defaults apply at a higher
  /// layer) — 0 is also legitimate for formation labels.
  int get beats => (params['beats'] as int?) ?? 0;

  /// Sentinel so [copyWith] can distinguish "leave [walkthroughOverride]
  /// unchanged" (argument omitted) from "clear it to `null`" (explicit `null`).
  static const Object _unchangedOverride = Object();
  static const Object _unchangedWordingOverride = Object();

  Figure copyWith({
    int? schemaVersion,
    String? move,
    Map<String, Object?>? params,
    String? note,
    bool? progression,
    CustomOrigin? customOrigin,
    bool? assumedSubject,
    Object? walkthroughOverride = _unchangedOverride,
    Object? wordingOverride = _unchangedWordingOverride,
  }) => Figure(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    move: move ?? this.move,
    params: params ?? this.params,
    note: note ?? this.note,
    progression: progression ?? this.progression,
    customOrigin: customOrigin ?? this.customOrigin,
    assumedSubject: assumedSubject ?? this.assumedSubject,
    walkthroughOverride: identical(walkthroughOverride, _unchangedOverride)
        ? this.walkthroughOverride
        : walkthroughOverride as String?,
    wordingOverride: identical(wordingOverride, _unchangedWordingOverride)
        ? this.wordingOverride
        : wordingOverride as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Figure &&
      other.schemaVersion == schemaVersion &&
      other.move == move &&
      _paramsEquality.equals(other.params, params) &&
      other.note == note &&
      other.progression == progression &&
      other.customOrigin == customOrigin &&
      other.assumedSubject == assumedSubject &&
      other.walkthroughOverride == walkthroughOverride &&
      other.wordingOverride == wordingOverride;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    move,
    _paramsEquality.hash(params),
    note,
    progression,
    customOrigin,
    assumedSubject,
    walkthroughOverride,
    wordingOverride,
  );

  @override
  String toString() => 'Figure($move, $params)';
}
