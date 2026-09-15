import 'package:meta/meta.dart';

/// The reasons an operation can refuse to run (`docs/taxonomy.md`, D12).
///
/// These are **dance-level** failures: the figure list asks for something the
/// current arrangement cannot support. They are not compiler defects.
///
/// > **Naming note.** The D12 table in `docs/taxonomy.md` mixes casing —
/// > `whoMismatch` / `notAdjacent` are camelCase while
/// > `UnresolvableDancerSet` / `UnsupportedParam` are PascalCase. Dart enum
/// > values are camelCase, so all are normalized here. [key] preserves the
/// > canonical wire spelling so serialization is not at the mercy of that
/// > choice.
///
/// > **Removed: `invalidFacing`.** Facing is never fatal — a figure danced
/// > from the wrong facing runs and reports
/// > [WarningKind.facingPrecondition] instead. The kind is gone rather than
/// > kept as an unreachable value, so that nothing here describes an outcome
/// > the compiler can no longer produce.
enum ErrorKind {
  /// A `who` relation is not standing where the figure needs it — e.g. a
  /// `sides` swing whose column-mate is not the stated relation.
  whoMismatch('whoMismatch', 'the stated `who` relation is not in position'),

  /// A trade figure needs its two dancers **adjacent** — sharing a row or a
  /// column — but they are diagonal, so neither can give the other a hand.
  /// E.g. `box_the_gnat`.
  ///
  /// This is a question of *where the dancers stand*, not of which way they
  /// face, which is why it survived the ruling that made facing non-fatal: no
  /// turn on the spot puts a hand within reach across a diagonal.
  ///
  /// > **Renamed from `notFacing`.** The old name described the symptom a
  /// > caller sees — two dancers who cannot take hands — but named the wrong
  /// > cause, and once facing stopped being fatal it read as the one surviving
  /// > exception to that ruling rather than as the unrelated check it is. The
  /// > wire spelling moved with it: this kind has never been serialized to
  /// > anything outside this repository.
  notAdjacent(
    'notAdjacent',
    'the interacting dancers are diagonal, not adjacent',
  ),

  /// A `who` or pair selection cannot be resolved in the current arrangement —
  /// e.g. `turn_as_couples` when the pair is not standing together, or
  /// `down_the_hall` when the column pairs are incomplete.
  unresolvableDancerSet(
    'UnresolvableDancerSet',
    'the dancer set for this figure cannot be resolved from the current state',
  ),

  /// A parameter value that is legal in the baseline taxonomy but
  /// **deliberately not implemented** — the Held-table cases (quarter-turn
  /// `allemande` / `gate`, `down_the_hall` `moving: center`, the held hall
  /// `ender`s).
  ///
  /// Distinct from a malformed parameter: this says "valid, but out of scope",
  /// which is why it is worth reporting rather than silently ignoring.
  unsupportedParam(
    'UnsupportedParam',
    'this parameter value is recognized but deliberately not implemented',
  ),

  /// A dance declares a progression that none of its figures performs.
  ///
  /// The only **dance-level** error kind: it is a fact about the figure list as
  /// a whole rather than about any one transition, so it carries no `opIndex`.
  ///
  /// Progression is never inferred from matrix state (§10.1), so a dance with
  /// nothing flagged cannot advance. Reported up front rather than as the
  /// mismatch it would otherwise become, because a mismatch would point at the
  /// choreography when the fault is the missing flag.
  unperformedProgression(
    'UnperformedProgression',
    'the dance claims a progression that none of its figures performs',
  );

  const ErrorKind(this.key, this.description);

  /// The canonical spelling used in `docs/taxonomy.md` and on the wire.
  final String key;

  /// A human-readable gloss, used to build default error messages.
  final String description;
}

/// A single operation's refusal to run, with the context needed to explain it.
@immutable
class OpError {
  const OpError(this.kind, [this.detail]);

  final ErrorKind kind;

  /// A specific explanation, when the figure has one to add.
  final String? detail;

  /// The specific explanation, falling back to the kind's generic gloss.
  String get message => detail ?? kind.description;

  @override
  bool operator ==(Object other) =>
      other is OpError && other.kind == kind && other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => '${kind.key}: $message';
}

/// The non-fatal diagnostics a compile can emit (`docs/taxonomy.md`, D12
/// Warnings).
enum WarningKind {
  /// A dance contains a `down_the_hall` without a matching `up_the_hall`, or
  /// vice versa.
  ///
  /// Non-fatal because the two need not be adjacent, and not raised when
  /// `facing: forwardThenBackward` completes the round trip inside one figure.
  ///
  /// This is a **dance-level lint** evaluated over the whole figure list — the
  /// first diagnostic in the taxonomy that is not a single state transition —
  /// so it is raised by the engine's pre-scan, never by an operation's own
  /// precondition check.
  oneSidedHall(
    'oneSidedHall',
    'a hall figure has no matching return; the set may be left off-balance',
  ),

  /// A hall figure was danced from a line of four that was already facing the
  /// *other* way along the hall.
  ///
  /// The figure still runs, and facing wins mechanically: the line ends facing
  /// the direction the figure specifies, which means the dancers turn around
  /// on the spot before travelling. That turn is real movement nobody called,
  /// so it is worth reporting — it usually means the figure list is missing a
  /// turn, or names the wrong hall direction.
  ///
  /// **State-dependent**, so unlike [oneSidedHall] this is raised by the
  /// operation itself against the formation it is handed, and stamped with its
  /// index by the engine.
  hallFacingConflict(
    'hallFacingConflict',
    'the line was already facing the other way along the hall; it turns '
        'around before travelling',
  ),

  /// A figure was danced by dancers facing the wrong way for it.
  ///
  /// **Facing is never fatal.** It is the softest thing the matrix holds: the
  /// figures that resolve it are numerous, several of them leave it
  /// deliberately undetermined ([Facing.flexible]), and a record that does not
  /// spell out an intermediate turn is describing a dance that works perfectly
  /// well on a real floor. Refusing a dance over it would reject good
  /// choreography for a detail the notation was never careful about.
  ///
  /// So the figure runs, and it runs as though the dancers had turned to face
  /// the way it needs. The turn that implies is real movement nobody called,
  /// which is worth reporting for the same reason [hallFacingConflict] is.
  ///
  /// **State-dependent**, so it is raised by the operation against the
  /// formation it is handed, and stamped with its index by the engine.
  facingPrecondition(
    'facingPrecondition',
    'the dancers were not facing the way this figure needs; they turn to it '
        'before dancing',
  ),

  /// A **descriptive anchor** contradicts the arrangement the figure produced.
  ///
  /// Some parameters state a fact the figure does not need in order to run.
  /// `form_long_waves` is the type case: `who` alone fixes every facing, and
  /// `whom` / `hand` merely record which dancer you hold and by which hand —
  /// something a reader of the source could already have worked out.
  ///
  /// Those parameters are still worth carrying, for two reasons. They
  /// **disambiguate**: a record that names the hold but not the facing pair
  /// has already said everything needed, and reading it is better than falling
  /// back on a default. And they **corroborate**: once the arrangement is
  /// fixed, the anchor is a claim about that arrangement, so it can be checked
  /// rather than trusted — the same reason `form_short_waves` verifies
  /// `center` and `sides` instead of believing them.
  ///
  /// A contradiction is a **warning**, not a refusal: the figure's outcome
  /// never depended on the anchor, so the dance still runs exactly as it would
  /// have. What is wrong is the description, and the dance is very often fine
  /// while its notation is careless. *(User-ruled.)*
  anchorMismatch(
    'anchorMismatch',
    'a descriptive parameter does not match the arrangement the figure '
        'produced; the figure ran regardless, but the record misdescribes it',
  ),

  /// A record declares a starting formation this compiler does not model.
  ///
  /// Raised at **parse** time rather than by a figure, and carried on the
  /// [Dance] so the compile it belongs to reports it. It is the first
  /// diagnostic that is not an observation about a formation at all.
  ///
  /// Not fatal, because the shape vocabulary is owned upstream and grows, and
  /// because the declared type does less work than its name suggests: it fixes
  /// the starting matrix and never tracks where the dancers stand
  /// (`docs/architecture.md` §3.2). A dance whose own opening figures establish
  /// the arrangement it dances in — long waves, say — is fully determined from
  /// the base formation regardless of what the record called it. *(User-ruled.)*
  unrecognizedFormation(
    'unrecognizedFormation',
    'the declared starting formation is not one this compiler models; the base '
        'formation is used instead',
  ),

  /// An importer had to assume which figure progresses, because its source
  /// never said.
  ///
  /// Raised by an **import bridge**, never by the compiler, and that separation
  /// is the point. The compiler's rule stands untouched: progression is a fact
  /// the record states, never one inferred from the matrix, and a record with
  /// no figure flagged is still refused outright
  /// ([ErrorKind.unperformedProgression]). This warning exists so that a source
  /// whose format simply has no place to *put* that fact can be read at all,
  /// while the assumption stays visible in the output.
  ///
  /// It is raised **whenever the assumption is made**, including when the dance
  /// then compiles. A compile that rests on a guess and one that rests on the
  /// record saying so are not the same result, and they must not read alike.
  /// *(User-ruled.)*
  assumedProgression(
    'assumedProgression',
    'the source did not say which figure progresses, so one was assumed; the '
        'result rests on that assumption',
  );

  const WarningKind(this.key, this.description);

  final String key;
  final String description;
}

/// A non-fatal diagnostic attached to a completed compile.
///
/// Warnings never change the outcome: a dance that mismatches with warnings
/// mismatches for the reason the matrices differ, not because of the warning.
@immutable
class Warning {
  const Warning(this.kind, {this.opIndex, this.detail});

  final WarningKind kind;

  /// The operation this warning points at, when it points at one at all.
  ///
  /// `null` for whole-dance observations that no single figure owns.
  final int? opIndex;

  /// A specific explanation, when the lint has one to add.
  final String? detail;

  String get message => detail ?? kind.description;

  @override
  bool operator ==(Object other) =>
      other is Warning &&
      other.kind == kind &&
      other.opIndex == opIndex &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, opIndex, message);

  @override
  String toString() => opIndex == null
      ? '${kind.key}: $message'
      : '${kind.key} @$opIndex: $message';
}
