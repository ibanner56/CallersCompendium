import 'package:meta/meta.dart';

import '../model/custom_field.dart';
import '../model/enums.dart';
import '../model/formation.dart';

/// The composable search filter tree (`docs/design/search.md`).
///
/// A search is a single [DanceFilter] value — a sealed tree that the
/// [FilterCompiler] turns into exactly one parameterized `SELECT` over the
/// derived indexes. Sealed so the compiler (and the 3.2c UI) exhaustively
/// switch over it.
///
/// **Naming note.** The design doc names the leaves `And`/`Or`/`Figure`/
/// `Formation`/etc., but several of those collide with exported domain types
/// (`Figure`, `Formation`, `Progression`, `Tag`, `Program`). To keep the AST
/// exportable from `compendium_core` without hiding domain types, every
/// `DanceFilter` node carries a `Filter` suffix. The narrower [FigureQuery]
/// nodes keep their design names (they already have a `Figure` prefix and do
/// not collide).
@immutable
sealed class DanceFilter {
  const DanceFilter();
}

/// Boolean AND of [children]. An empty list matches **everything** (`TRUE`).
@immutable
class AndFilter extends DanceFilter {
  const AndFilter(this.children);

  final List<DanceFilter> children;
}

/// Boolean OR of [children]. An empty list matches **nothing** (`FALSE`).
@immutable
class OrFilter extends DanceFilter {
  const OrFilter(this.children);

  final List<DanceFilter> children;
}

/// Boolean negation: `NOT (<child>)`.
@immutable
class NotFilter extends DanceFilter {
  const NotFilter(this.child);

  final DanceFilter child;
}

/// Full-text search over `dance_fts`. [query] is canonicalized (dialect role
/// terms rewritten) at the compiler boundary and then sanitized into a safe
/// `MATCH` bind: each whitespace-delimited token is wrapped as a quoted FTS5
/// phrase (embedded `"` doubled). This means ordinary punctuated terms like
/// `do-si-do` or `O'Neill` match instead of raising `fts5: syntax error`, but
/// it also **neutralizes** user-typed FTS operators — `AND`/`OR`/`NOT`/`NEAR`,
/// prefix `*`, and explicit `"…"` grouping are treated as literal text, not
/// query syntax. Callers must not rely on advanced FTS expression support here.
@immutable
class FullTextFilter extends DanceFilter {
  const FullTextFilter(this.query);

  final String query;
}

/// Dances authored by the choreographer with id [choreographerId].
@immutable
class AuthorFilter extends DanceFilter {
  const AuthorFilter(this.choreographerId);

  final String choreographerId;
}

/// Dances that cite a [PublishedSource] whose title or bibliographic author
/// contains [query] (case-insensitive substring match).
///
/// A targeted, field-scoped alternative to the bare [FullTextFilter] (which
/// also searches source text via the `dance_fts.sources` column): this leaf
/// restricts the match to the source's `title`/`author` via a subquery over
/// `dance_sources` joined to `published_sources`, mirroring how [AuthorFilter]
/// scopes to a choreographer. [query] is a plain substring (compiled to
/// `LIKE '%' || ? || '%'`), not an FTS expression — so `"` / `*` / `AND` are
/// treated literally.
@immutable
class SourceFilter extends DanceFilter {
  const SourceFilter(this.query);

  final String query;
}

/// Dances that cite the [PublishedSource] with id [sourceId]; the
/// identity-based counterpart to the text [SourceFilter].
///
/// Where [SourceFilter] does a substring match on the cited source's
/// title/author (for full-text / advanced search), this leaf matches by the
/// source's stable id via a subquery over `dance_sources` — the exact analog
/// of [AuthorFilter] scoping to a choreographer id. Used by the Collection
/// source facet, where the user picks a specific source (not free text) and an
/// id match avoids the title/author over-matching a substring query would.
@immutable
class SourceIdFilter extends DanceFilter {
  const SourceIdFilter(this.sourceId);

  final String sourceId;
}

/// Dances of a given [DanceForm] (roadmap "Type": contra / ecd / square).
@immutable
class FormFilter extends DanceFilter {
  const FormFilter(this.form);

  final DanceForm form;
}

/// Dances with a given [FormationShape]. Shape only; free-text formation
/// detail is searched via [FullTextFilter].
@immutable
class FormationFilter extends DanceFilter {
  const FormationFilter(this.shape);

  final FormationShape shape;
}

/// Dances with a given [Progression].
@immutable
class ProgressionFilter extends DanceFilter {
  const ProgressionFilter(this.progression);

  final Progression progression;
}

/// Dances with a given [DanceStatus].
@immutable
class StatusFilter extends DanceFilter {
  const StatusFilter(this.status);

  final DanceStatus status;
}

/// Ordered comparison operators for a [LevelFilter]. The [DanceLevel] scale is
/// ordered (enum index = ordinal), so callers can ask for a level exactly
/// ([eq]), "that level or easier" ([lte]), or "that level or harder" ([gte]) —
/// mirroring the numeric operators of [CustomFieldOp] but as a small dedicated
/// vocabulary (`docs/design/search.md` "Future leaves").
enum LevelOp {
  /// `level = ?` (exact difficulty).
  eq,

  /// The dance's difficulty is at or below the given level (easier-or-equal).
  lte,

  /// The dance's difficulty is at or above the given level (harder-or-equal).
  gte,
}

/// Dances at a given [DanceLevel], compared with [op] on the ordered scale.
///
/// Dances with an **unspecified** level (`dances.level IS NULL`) never match an
/// ordered comparison ([LevelOp.lte]/[LevelOp.gte]) — an unspecified difficulty
/// is not a point on the scale. "Mixed level" is a separate axis: see
/// [MixedLevelFilter].
@immutable
class LevelFilter extends DanceFilter {
  const LevelFilter(this.level, [this.op = LevelOp.eq]);

  final DanceLevel level;
  final LevelOp op;
}

/// Dances whose "mixed level" flag equals [mixed] (`dances.mixed_level`).
///
/// A separate boolean leaf rather than a point on the ordered [LevelFilter]
/// scale: a mixed-level event spans the difficulty scale, so it is modelled
/// orthogonally to keep the ordered comparisons total (mirrors
/// [Dance.mixedLevel] being distinct from [Dance.level]).
@immutable
class MixedLevelFilter extends DanceFilter {
  const MixedLevelFilter(this.mixed);

  final bool mixed;
}

/// Dances whose "mixer" flag equals [mixer] (`dances.mixer`).
///
/// A separate boolean leaf for the partner-changing flag added in issue #732.
/// Modelled orthogonally to [FormationShape] — a mixer can be in any shape
/// and not every circle dance is a mixer (see [Dance.mixer]).
///
/// In the UI this filter is only ever constructed with `mixer = true`
/// (the facet is tri-state null / "show mixers only"; "show non-mixers only"
/// is not offered). `false` is valid but unused by the facet panel — the same
/// pattern [MixedLevelFilter] uses for its `mixed` field.
@immutable
class MixerFilter extends DanceFilter {
  const MixerFilter(this.mixer);

  final bool mixer;
}

/// Dances whose curatorial rating is **at least** [minimum] (`rating >= N`) on
/// the closed `1..5` scale.
///
/// A minimum-rating floor (mirrors [LevelFilter]'s ordered `gte`): "show me
/// dances I rated [minimum] stars or better". Unrated dances (`dances.rating
/// IS NULL`) never match — a NULL rating is not a point on the scale, so the
/// SQL `rating >= ?` comparison against NULL is not-true (excluded).
///
/// [minimum] must be on the `1..5` scale (asserted at construction, mirroring
/// how [Dance.rating] validates its own range): an out-of-range floor is
/// meaningless — `0` would match every rated dance and `6` none — so it is a
/// caller bug, not a valid query. The [FilterCompiler] re-checks defensively.
@immutable
class RatingFilter extends DanceFilter {
  const RatingFilter(this.minimum)
    : assert(minimum >= 1 && minimum <= 5, 'RatingFilter.minimum must be 1..5');

  final int minimum;
}

/// Dances tagged with the tag id [tagId].
@immutable
class TagFilter extends DanceFilter {
  const TagFilter(this.tagId);

  final String tagId;
}

/// Comparison operators for a [CustomFieldFilter], typed by the field's
/// [CustomFieldType]. Illegal `(type, op)` pairings are rejected when the
/// filter is constructed (see [CustomFieldFilter]) and again, defensively,
/// at compile time.
enum CustomFieldOp {
  /// text: `value_text LIKE '%' || ? || '%'`.
  contains,

  /// text: `value_text = ?`.
  equals,

  /// number: `value_num = ?`.
  eq,

  /// number: `value_num < ?`.
  lt,

  /// number: `value_num > ?`.
  gt,

  /// number: `value_num BETWEEN ? AND ?` (inclusive).
  between,

  /// boolean: `value_num = ?` (1/0); choice: `value_text = ?`.
  is_,

  /// choice: `value_text IN (?, ?, …)`.
  in_,
}

/// The operators legal for each [CustomFieldType] (`docs/design/search.md`).
const Map<CustomFieldType, Set<CustomFieldOp>> customFieldOpsByType = {
  CustomFieldType.text: {CustomFieldOp.contains, CustomFieldOp.equals},
  CustomFieldType.number: {
    CustomFieldOp.eq,
    CustomFieldOp.lt,
    CustomFieldOp.gt,
    CustomFieldOp.between,
  },
  CustomFieldType.boolean: {CustomFieldOp.is_},
  CustomFieldType.choice: {CustomFieldOp.is_, CustomFieldOp.in_},
};

/// A custom-field predicate. Built against the field's [CustomFieldDef] so the
/// `(type, op, value)` triple is validated at construction — an illegal
/// operator for the field type, or a value whose shape doesn't match the
/// operator, throws [ArgumentError].
///
/// - `between` requires a two-element `[lo, hi]` list of numbers.
/// - `in_` requires a non-empty `List<String>`.
/// - `is_` on a boolean field requires a `bool`; on a choice field a `String`.
@immutable
class CustomFieldFilter extends DanceFilter {
  CustomFieldFilter(CustomFieldDef def, this.op, Object? value)
    : fieldId = def.id,
      fieldType = def.type,
      // Snapshot list values so a later caller mutation can't slip a
      // different shape past validation into the compiler.
      value = value is List ? List<Object?>.unmodifiable(value) : value {
    final legal = customFieldOpsByType[def.type] ?? const {};
    if (!legal.contains(op)) {
      throw ArgumentError.value(
        op,
        'op',
        'operator ${op.name} is not valid for a ${def.type.name} field '
            '"${def.key}"',
      );
    }
    _validateValueShape(def, op, this.value);
  }

  final String fieldId;
  final CustomFieldType fieldType;
  final CustomFieldOp op;
  final Object? value;

  static void _validateValueShape(
    CustomFieldDef def,
    CustomFieldOp op,
    Object? value,
  ) {
    switch (op) {
      case CustomFieldOp.between:
        if (value is! List ||
            value.length != 2 ||
            value.any((v) => v is! num)) {
          throw ArgumentError.value(
            value,
            'value',
            'between requires a [lo, hi] list of two numbers',
          );
        }
      case CustomFieldOp.in_:
        if (value is! List || value.isEmpty || value.any((v) => v is! String)) {
          throw ArgumentError.value(
            value,
            'value',
            'in requires a non-empty list of choice strings',
          );
        }
      case CustomFieldOp.eq:
      case CustomFieldOp.lt:
      case CustomFieldOp.gt:
        if (value is! num) {
          throw ArgumentError.value(
            value,
            'value',
            '${op.name} requires a number',
          );
        }
      case CustomFieldOp.is_:
        if (def.type == CustomFieldType.boolean && value is! bool) {
          throw ArgumentError.value(
            value,
            'value',
            'is on a boolean field requires a bool',
          );
        }
        if (def.type == CustomFieldType.choice && value is! String) {
          throw ArgumentError.value(
            value,
            'value',
            'is on a choice field requires a String',
          );
        }
      case CustomFieldOp.contains:
      case CustomFieldOp.equals:
        if (value is! String) {
          throw ArgumentError.value(
            value,
            'value',
            '${op.name} requires a String',
          );
        }
    }
  }
}

/// A structural predicate: the dance has a figure matching [query]
/// ("some `dance_figures` row of the dance satisfies this figure query").
///
/// Sugar for the common case is [FigureFilter.leaf]. When [query] is a
/// top-level [FigureNot], the predicate compiles to
/// `id NOT IN (SELECT dance_id FROM dance_figures …)` — "the dance has **no**
/// figure matching" — per the confirmed `Not` semantics. (`NOT IN` is safe
/// here because `dance_figures.dance_id` is `NOT NULL`, part of the primary
/// key, so the subquery never yields a NULL to trip up `NOT IN`.)
@immutable
class FigureFilter extends DanceFilter {
  const FigureFilter(this.query);

  /// Convenience for a single [FigureLeaf].
  FigureFilter.leaf(
    String move, {
    Map<String, Object?> params = const {},
    String? section,
  }) : query = FigureLeaf(move, params: params, section: section);

  final FigureQuery query;
}

/// Sequence: a figure matching [before] occurs **earlier** in the dance than
/// a figure matching [after] (strict `a.group_idx < b.group_idx`, so two
/// concurrent sides of one `meanwhile` container — which share a group — are
/// not treated as one-before-the-other; #748). Operands are [FigureQuery] only
/// — metadata leaves and nested [ThenFilter] have no per-position meaning and
/// are excluded by the type.
@immutable
class ThenFilter extends DanceFilter {
  const ThenFilter(this.before, this.after);

  final FigureQuery before;
  final FigureQuery after;
}

/// The operand grammar for [ThenFilter] and the reusable shape of a
/// structural predicate. Deliberately narrower than [DanceFilter]: it only
/// composes constraints evaluated **per `dance_figures` row**.
@immutable
sealed class FigureQuery {
  const FigureQuery();
}

/// A single figure constraint: a figure whose canonical [move] matches, with
/// optional [params] (compared via `json_extract` natural typing) and an
/// optional derived phrase [section] label (e.g. `'B1'`).
///
/// Param keys must be well-formed identifiers (`^[A-Za-z_][A-Za-z0-9_]*$`) —
/// they are interpolated into the JSON path and so cannot be bound; an
/// invalid key throws [ArgumentError] at construction.
@immutable
class FigureLeaf extends FigureQuery {
  FigureLeaf(this.move, {Map<String, Object?> params = const {}, this.section})
    : params = Map.unmodifiable(params) {
    for (final key in this.params.keys) {
      if (!_paramKeyPattern.hasMatch(key)) {
        throw ArgumentError.value(
          key,
          'params key',
          'must match ${_paramKeyPattern.pattern}',
        );
      }
    }
  }

  static final RegExp _paramKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  final String move;
  final Map<String, Object?> params;
  final String? section;
}

/// All of [children] match the **same** figure row (`AND` of clauses).
@immutable
class FigureAnd extends FigureQuery {
  const FigureAnd(this.children);

  final List<FigureQuery> children;
}

/// Any of [children] matches the **same** figure row (`OR` of clauses).
@immutable
class FigureOr extends FigureQuery {
  const FigureOr(this.children);

  final List<FigureQuery> children;
}

/// This figure row does **not** match [child] (`NOT` of a clause).
@immutable
class FigureNot extends FigureQuery {
  const FigureNot(this.child);

  final FigureQuery child;
}
