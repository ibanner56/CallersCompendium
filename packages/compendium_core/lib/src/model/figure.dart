import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Current figure schema version. Persisted with every figure so old data
/// always parses after taxonomy/schema evolution.
const int figureSchemaVersion = 1;

/// Upper bound on the length of a single figure's walkthrough snippet
/// ([Figure.walkthroughOverride] and each entry of the global snippet library),
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
  /// migration is required. It is a DISPLAY/provenance flag only — it never
  /// changes the canonical (search/dedupe) render, which stays byte-stable.
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

  bool get isCustom => move == customMove;

  /// Duration in beats; 0 when unset (taxonomy defaults apply at a higher
  /// layer) — 0 is also legitimate for formation labels.
  int get beats => (params['beats'] as int?) ?? 0;

  /// Sentinel so [copyWith] can distinguish "leave [walkthroughOverride]
  /// unchanged" (argument omitted) from "clear it to `null`" (explicit `null`).
  static const Object _unchangedOverride = Object();

  Figure copyWith({
    int? schemaVersion,
    String? move,
    Map<String, Object?>? params,
    String? note,
    bool? progression,
    CustomOrigin? customOrigin,
    bool? assumedSubject,
    Object? walkthroughOverride = _unchangedOverride,
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
      other.walkthroughOverride == walkthroughOverride;

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
  );

  @override
  String toString() => 'Figure($move, $params)';
}
