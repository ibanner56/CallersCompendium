import '../model/figure.dart';
import '../taxonomy/gate_facing.dart';
import '../taxonomy/move_def.dart';
import '../taxonomy/param_types.dart';
import '../taxonomy/taxonomy.dart';
import 'dialect.dart';
import 'substitution.dart';

/// The canonical role tokens recognized specially everywhere (rendering and
/// canonicalization). Singular and plural forms of the two contra roles.
const Set<String> roleTokens = {'role1', 'role2', 'role1s', 'role2s'};

final RegExp _placeholder = RegExp(r'\{(\w+)\}');
final RegExp _camelBoundary = RegExp(r'(?<=[a-z])(?=[A-Z])');

/// Shape of the single-dancer identity tokens ([ParamVocab.singleDancers]) —
/// one couple (`ones`/`twos`) × one role. Unlike [roleTokens] these are
/// COMPOUND, so a whole-token membership test never matches them and the
/// embedded role would never be substituted (issue #832).
final RegExp _singleDancerShape = RegExp(r'^(ones|twos)(Role[12])$');

/// Signature of a DISPLAY-ONLY base-line renderer (see
/// [FigureRenderer._displayBaseRenderers]). Rebuilds the whole terse line for a
/// move that adopts ContraDB's `words()` sentence structure verbatim, using the
/// already-resolved effective [params] and the active [dialect]. Never invoked
/// for the canonical render (which keeps expanding `renderTemplate`).
typedef _DisplayBaseRenderer =
    String Function(
      FigureRenderer r,
      MoveDef def,
      Map<String, Object?> params,
      Dialect dialect,
      bool verbose,
      bool decimals,
    );

/// Where a move's `balance` flag renders relative to the terse base line, per
/// ContraDB `libfigure` word order. [leading] prepends the "balance &" prefix
/// to the whole line (ContraDB emits the balance token before any subject);
/// [afterWho] splices it in front of the move name (ContraDB emits the subject,
/// then balance, then the move).
enum _BalancePlacement { leading, afterWho }

/// Renders figures to text in two flavors: canonical (dialect-free, feeds
/// search/FTS) and display (a chosen [Dialect] applied). Pure functions —
/// golden-tested.
class FigureRenderer {
  FigureRenderer(this.taxonomy);

  final Taxonomy taxonomy;

  /// Canonical text for [figure]: role tokens stay as `role1`/`role2`, no
  /// dialect. Used to build the search index.
  ///
  /// This is the ONE invariant: its output is persisted to
  /// `dance_figures.canonicalText` / `dance_fts` and is the dedupe key, so it
  /// must stay byte-for-byte stable. It passes `forCanonical: true`, which
  /// bypasses every display-only polish (silenced defaults, subject omission,
  /// dancer-set singularization, shoulder injection) that [render] /
  /// [renderSummary] apply. As a result `render(figure, Dialect.canonical)`
  /// legitimately diverges from `renderCanonical(figure)`.
  String renderCanonical(Figure figure) =>
      _render(figure, Dialect.canonical, forCanonical: true);

  /// Display text for [figure] under [dialect] (roles + move names mapped).
  ///
  /// DISPLAY-ONLY [decimals]: renders turn amounts as decimals (`0.75`) instead
  /// of fraction glyphs (`¾`) — the opt-in "Show turns as decimals" preference
  /// (#368). Never applied to [renderCanonical], so canonical text stays stable.
  String render(Figure figure, Dialect dialect, {bool decimals = false}) =>
      _render(figure, dialect, decimals: decimals);

  /// A verbose, spoken-friendly rendering of [figure] under [dialect] for
  /// assistive tech (accessibility baseline "Robust"; figure-taxonomy.md §5.4).
  ///
  /// Distinct from [render]: it expands compressed notation glyphs into
  /// spelled-out words so a screen reader announces figures cleanly (e.g.
  /// `neighbors allemande left 1½` becomes `neighbors allemande left one and a
  /// half times`). Move names, roles/dancers, hands, places, directions and
  /// free text already read as words, so they render exactly as in [render] —
  /// keeping the verbose form dialect-aware and identical in wording except for
  /// the glyph-free counts. This is surfaced only via `Semantics` labels; the
  /// visible on-screen text stays terse.
  String renderVerbose(Figure figure, Dialect dialect) =>
      _render(figure, dialect, verbose: true);

  /// Display summary for [figure] under [dialect]: the terse [render] (or
  /// [renderVerbose], when [verbose]) text plus the ContraDB-parity secondary
  /// modifiers the terse `renderTemplate` deliberately omits — down/up-the-hall
  /// and zig-zag `ender`, hey `length`, the `balance` flag (a "balance &"
  /// prefix), and long-lines `goBack`. These params otherwise render as nothing
  /// (enders, balance) or drop information (hey length, hall direction), so a
  /// caller reading the summary loses information ContraDB's params→description
  /// rendering surfaces.
  ///
  /// This is a display-only path layered on top of [_render]; [renderCanonical]
  /// (which feeds storage/search/dedupe) never calls it and stays byte-for-byte
  /// unchanged. The appended wording is copied verbatim from ContraDB's
  /// `libfigure` (`param.js`/`figure.js`), except `bendTheLine` — a
  /// CallersBox-origin ender not present in ContraDB — which uses CallersBox's
  /// own "bend the line" phrasing (see `docs/research/callersbox.md`). The
  /// modifier phrases are fixed structural vocabulary (not role/move tokens),
  /// so they are dialect-independent; the dialect-aware part is the [_render]
  /// base, which already maps roles and move names under [dialect].
  String renderSummary(
    Figure figure,
    Dialect dialect, {
    bool verbose = false,
    bool decimals = false,
  }) {
    final base = _render(figure, dialect, verbose: verbose, decimals: decimals);
    if (figure.isCustom) return base;
    final def = taxonomy.resolve(figure.move);
    if (def == null) return base;
    final params = taxonomy.effectiveParams(figure);
    var out = base;
    // Balance flag → a "balance &" (visual) / "balance and" (verbose) prefix,
    // positioned per ContraDB's per-move word order (see [_balancePlacement]).
    // box_circulate is special (ratified decision): ContraDB models it with a
    // default-TRUE balance (`balance_true`), so its summary shows the balance
    // prefix BY DEFAULT. We keep the taxonomy default false (canonical stays
    // byte-stable) and instead treat an *unset* balance as shown here, checking
    // the raw `figure.params` so an explicit `balance:false` still suppresses.
    final showBalance =
        params['balance'] == true ||
        (figure.move == 'box_circulate' &&
            !figure.params.containsKey('balance'));
    if (showBalance) {
      final placement = _balancePlacement[figure.move];
      if (placement != null) {
        final connective = _renderPrefix('balance', verbose);
        if (placement == _BalancePlacement.leading) {
          // ContraDB emits the balance token first (before any subject).
          out = '$connective $out';
        } else {
          // after-who: the balance token follows the subject and immediately
          // precedes the move name, so splice it in front of the move token.
          // The move name is normalized the same way [_render] normalizes the
          // base line (`_collapseSpaces`) so a dialect substitution with stray
          // double spaces still matches; if it somehow can't be located we fall
          // back to the leading form rather than silently dropping the balance.
          final alias = taxonomy.aliases[figure.move];
          final displayName = alias?.displayName ?? def.displayName;
          final moveName = _collapseSpaces(
            _renderMoveName(def.id, displayName, params, dialect),
          );
          out = out.contains(moveName)
              ? out.replaceFirst(moveName, '$connective $moveName')
              : '$connective $out';
        }
      }
    }
    final suffix = _summarySuffix(figure.move, params, verbose);
    return suffix.isEmpty ? out : '$out$suffix';
  }

  /// The trailing secondary-modifier clause (connective included) appended by
  /// [renderSummary] for [moveId], or the empty string when nothing is
  /// surfaced. Only non-`none` enders and set hey lengths produce a clause.
  /// For hey `half`/`full`, the visible path shows a compact parenthetical and
  /// the spoken [verbose] path expands to ContraDB's "half hey"/"full hey"
  /// comma clause (avoiding a "hey … hey" repetition on screen).
  String _summarySuffix(
    String moveId,
    Map<String, Object?> params,
    bool verbose,
  ) {
    switch (moveId) {
      case 'down_the_hall':
      case 'up_the_hall':
        // ContraDB `upOrDownTheHallWords`: `words(..., sfacing, "and", sender)`.
        final ender = params['ender'];
        final label = ender is String ? _hallEnderLabels[ender] : null;
        return label == null ? '' : ' and $label';
      case 'zig_zag':
        // ContraDB `zigZagWords`: a comma precedes the allemande ender only.
        final ender = params['ender'];
        if (ender == 'ring') return ' into a ring';
        if (ender == 'allemande') return ', trailing two catching hands';
        return '';
      case 'long_lines':
        // ContraDB `longLinesWords` always renders the direction: `forward`
        // when `goBack` is false, else `forward & back` (spoken "and"). The
        // param is always shown by ContraDB, so parity surfaces it in both the
        // default and non-default case.
        return params['goBack'] == false
            ? ' forward'
            : (verbose ? ' forward and back' : ' forward & back');
      case 'hey':
        // The hey display base line (see [_displayBaseRenderers]) already
        // carries the length — the "half"/"full" word inline and the partial
        // lengths' "until someone meets…" clause — mirroring ContraDB
        // `heyWords`. Appending anything here would duplicate it, so (like
        // `revolving_door`) no extra summary clause is added.
        return '';
      case 'revolving_door':
        // The revolving_door display base line (see [_displayBaseRenderers])
        // already renders ContraDB's full "…and drop off <whom> on other side"
        // outcome, so no extra summary clause is appended (it would duplicate).
        return '';
      default:
        return '';
    }
  }

  /// Renders [figure]. When [forCanonical] is true (only [renderCanonical]),
  /// every display-only polish is bypassed so the search/dedupe text stays
  /// stable; when false ([render]/[renderVerbose]/[renderSummary]) the
  /// ContraDB-parity display transforms — silenced default direction/facing,
  /// omitted default subject, singularized positional dancer sets, and the
  /// shoulder_round shoulder injection — are applied.
  String _render(
    Figure figure,
    Dialect dialect, {
    bool verbose = false,
    bool decimals = false,
    bool forCanonical = false,
  }) {
    if (figure.isCustom) {
      final text = (figure.params['text'] as String?)?.trim() ?? '';
      return text.isEmpty ? customMove : renderFreeText(text, dialect);
    }
    if (figure.isMeanwhile) {
      // A meanwhile container (#590) renders its concurrent sides joined by a
      // fixed structural separator. `renderCanonical` (forCanonical) MUST stay
      // byte-stable across runs — it is the dedupe/FTS key — so it always
      // joins with the structural move id (`' meanwhile '`), side order
      // preserved, never varying with `dialect`.
      //
      // The human-facing display renders (`render`/`renderVerbose`/
      // `renderSummary`, i.e. `!forCanonical`) instead use the caller-facing
      // "A while B" idiom (#594) — the Caller's Box / ContraDB convention for
      // simultaneity. 3+ sides chain the same separator ("A while B while
      // C"): simple, deterministic, and matches the 2-side form.
      final sides = figure.subFigures;
      if (sides.isEmpty) return meanwhileMove;
      final rendered = sides.map(
        (side) => _render(
          side,
          dialect,
          verbose: verbose,
          decimals: decimals,
          forCanonical: forCanonical,
        ),
      );
      return rendered.join(forCanonical ? ' $meanwhileMove ' : ' while ');
    }
    final def = taxonomy.resolve(figure.move);
    if (def == null) {
      // Unknown move: fall back to the raw id so nothing is silently lost.
      return figure.move;
    }
    final params = taxonomy.effectiveParams(figure);
    // DISPLAY-ONLY base-line reword: a handful of moves adopt ContraDB's
    // `words()` sentence structure verbatim (not a suffix), so the whole terse
    // line is rebuilt rather than expanded from `renderTemplate`. Gated behind
    // `!forCanonical` so `renderCanonical` keeps expanding the template and
    // stays byte-for-byte stable — EXCEPT for the three moves below that have
    // explicit canonical overrides.
    if (!forCanonical) {
      final displayBase = _displayBaseRenderers[def.id];
      if (displayBase != null) {
        final line = _collapseSpaces(
          displayBase(this, def, params, dialect, verbose, decimals),
        );
        // Base lines tag the subject's exact end with [_subjectMarkSentinel]
        // (via [_subjectWho]); splice the marker there when the subject was
        // assumed, otherwise drop the sentinel so the output is unchanged.
        return figure.assumedSubject
            ? _spliceAssumedSubjectMarker(line)
            : _stripSubjectMark(line);
      }
    }
    // CANONICAL overrides (taxonomy v27, issue #749): three moves that include
    // grip or singleFile tokens in their FTS-indexed canonical text. These run
    // only when forCanonical is true; the display path above handles the
    // non-canonical case via _displayBaseRenderers.
    //
    // `star` is safe to use the same renderer as display (no display-only
    // polish: no _subjectWho, no direction silencing, no assumed marker).
    //
    // `promenade` and `circle` are NOT un-gated from the display entry because
    // the display entry applies direction silencing and subject omission that
    // would degrade ordinary-promenade FTS (e.g. "partners promenade across"
    // would lose `who` and `dir` from the search index). The canonical blocks
    // below use dedicated logic for each move.
    if (forCanonical) {
      if (def.id == 'star') {
        // Canonical mirrors the display entry for star: no display-only polish
        // exists, so the same word-order applies to both paths.
        final canonicalLine = _collapseSpaces(
          _displayBaseRenderers['star']!(
            this,
            def,
            params,
            Dialect.canonical,
            false,
            false,
          ),
        );
        return canonicalLine;
      }
      if (def.id == 'promenade' && params['singleFile'] == true) {
        // Canonical: "single file promenade {dir}" — who DROPPED (importer
        // artefact, no choreographic content), dir ALWAYS included (even at
        // the `across` default) so the FTS index reflects the stated direction.
        final dirRaw = params['dir'];
        final dir = _displayScalar(dirRaw);
        return _collapseSpaces(
          ['single file promenade', dir].where((s) => s.isNotEmpty).join(' '),
        );
      }
      if (def.id == 'circle' && params['singleFile'] == true) {
        // Canonical: "single file promenade {clockwise|counterclockwise} {places}
        // (circle)" — phrased as "promenade" to match TCB source text; the
        // parenthetical "(circle)" retains "circle" in the FTS index so this
        // figure is findable by "circle" searches. Clockwise = left (contra
        // convention: circling left travels clockwise).
        final turnRaw = params['turn'];
        final spinWord = turnRaw == 'left'
            ? 'clockwise'
            : turnRaw == 'right'
            ? 'counterclockwise'
            : _displayScalar(turnRaw);
        final placesRaw = params['places'];
        final places = placesRaw is int
            ? _formatPlaces(placesRaw)
            : _displayScalar(placesRaw);
        return _collapseSpaces(
          [
            'single file promenade',
            spinWord,
            places,
            '(circle)',
          ].where((s) => s.isNotEmpty).join(' '),
        );
      }
    }
    // Aliases render under their own name (a "see saw" is not shown as
    // "do si do"); dialect move substitution is still keyed canonically.
    final alias = taxonomy.aliases[figure.move];
    final displayName = alias?.displayName ?? def.displayName;
    // Params pinned by an alias are baked into its display name (e.g.
    // "meltdown swing" pins prefix=meltdown), so they must not be rendered a
    // second time as a template token — otherwise the word would double up.
    // Since v25 (#870), this invariant is ENFORCED at write time by
    // Taxonomy.resolvedMoveId: a figure whose effective param contradicts the
    // alias pin is re-routed to the correct half of the pair before it
    // reaches the renderer, so the pin and the data can never disagree.
    final pinned = alias?.pinnedParams ?? const <String, Object?>{};
    final rendered = def.renderTemplate.replaceAllMapped(_placeholder, (m) {
      final name = m[1]!;
      if (name == 'move') {
        return _renderMoveName(
          def.id,
          displayName,
          params,
          dialect,
          forCanonical,
        );
      }
      if (pinned.containsKey(name)) return '';
      // Display-only omission of a param whose value equals its silenced
      // default (direction/facing) or the move's default subject.
      if (!forCanonical && _isDisplaySilenced(def, name, params[name])) {
        return '';
      }
      final value = _renderValue(
        name,
        params[name],
        def.params[name],
        dialect,
        verbose,
        decimals,
        forCanonical,
      );
      // DISPLAY-ONLY: tag the exact end of the primary subject token as it is
      // emitted, so an assumed marker can be spliced at the subject's true
      // position rather than by searching the finished line (which misfires
      // when a move name or dialect substitution repeats the subject word).
      // The sentinel is stripped again below unless the subject was defaulted.
      if (!forCanonical && name == 'who' && value.isNotEmpty) {
        return '${value.replaceAll(_subjectMarkSentinel, '')}'
            '$_subjectMarkSentinel';
      }
      return value;
    });
    final line = _collapseSpaces(rendered);
    // DISPLAY-ONLY: flag a subject the import parser DEFAULTED (the source
    // omitted it) with a non-authoritative "(assumed)" marker, so fabricated
    // choreography never reads as source-stated fact (#460). The marker is
    // spliced at the sentinel emitted next to the subject above; the search/
    // dedupe (canonical) render never emits the sentinel and stays byte-stable.
    return (!forCanonical && figure.assumedSubject)
        ? _spliceAssumedSubjectMarker(line)
        : _stripSubjectMark(line);
  }

  /// The non-authoritative marker spliced after an ASSUMED subject in the
  /// display render (#460). Fixed structural vocabulary (like "balance &"),
  /// dialect-independent, and never emitted by [renderCanonical].
  static const String _assumedSubjectMarker = '(assumed)';

  /// Render-internal sentinel emitted immediately after the PRIMARY subject
  /// token (see the `who` branch of [_render] and [_subjectWho]) so the assumed
  /// marker can be spliced at the subject's exact position instead of by
  /// searching the finished line. String search is unreliable: a move name or
  /// a custom dialect substitution can repeat the subject word (e.g.
  /// `moves: {'box_circulate': 'partner circulate'}` renders the move name
  /// before the subject), which would land the marker on the wrong span. U+FDD0
  /// is a permanent Unicode *noncharacter* — guaranteed never to be valid text —
  /// so it cannot collide with real rendered content and is always safe to
  /// strip. It is emitted only on display renders and always removed before
  /// [_render] returns, so it never leaks into output or the canonical text.
  static const String _subjectMarkSentinel = '\uFDD0';

  /// DISPLAY-ONLY subject render for [_displayBaseRenderers] base lines: renders
  /// the primary subject (`who`) via [_displaySubject] and tags its exact end
  /// with [_subjectMarkSentinel] so [_render] can splice the assumed marker
  /// precisely. Any sentinel already present in the subject (only reachable via
  /// malformed input) is stripped first; an empty subject emits no sentinel.
  /// Base renderers run only on display renders, so tagging here is always safe;
  /// [_render] drops the sentinel when the subject is not assumed, leaving
  /// non-assumed output byte-for-byte unchanged.
  String _subjectWho(Map<String, Object?> params, Dialect dialect) =>
      _subjectToken(params['who'], dialect);

  /// [_subjectWho] for an arbitrary subject [value] — used by the merged `gate`
  /// base line, whose grammatical subject is `who` (ContraDB) OR `pair` (The
  /// Caller's Box) depending on which the source stated.
  String _subjectToken(Object? value, Dialect dialect) {
    final subject = _displaySubject(
      value,
      dialect,
    ).replaceAll(_subjectMarkSentinel, '');
    return subject.isEmpty ? subject : '$subject$_subjectMarkSentinel';
  }

  /// Splices [_assumedSubjectMarker] at the sentinel marking the subject's true
  /// end, then removes any residual sentinels. When no sentinel is present (the
  /// subject rendered empty or was omitted) the line is returned with sentinels
  /// stripped and NO marker — never a dangling marker. Never used by the
  /// canonical render, so search/dedupe text stays byte-stable.
  String _spliceAssumedSubjectMarker(String line) {
    final idx = line.indexOf(_subjectMarkSentinel);
    if (idx < 0) return _stripSubjectMark(line);
    final head = line.substring(0, idx);
    final tail = line.substring(idx + _subjectMarkSentinel.length);
    return _stripSubjectMark('$head $_assumedSubjectMarker$tail');
  }

  /// Removes every [_subjectMarkSentinel] from [line] (fast no-op path when
  /// none is present) so display output never leaks the internal sentinel.
  String _stripSubjectMark(String line) => line.contains(_subjectMarkSentinel)
      ? line.replaceAll(_subjectMarkSentinel, '')
      : line;

  /// Whether the template token [name] of [def] is omitted in the DISPLAY path
  /// because [value] equals a silenced default. Two ContraDB-parity rules:
  ///
  /// - set-direction / facing silencing: the param is omitted when it equals
  ///   the move's default (ContraDB `stringParamSetDirectionSilencingDefault`
  ///   and the `march_forward` "forward" default). Enumerated per move in
  ///   [_silencedDefaultParams].
  /// - default-subject omission: `who` is omitted when it equals the move's
  ///   `who` default, for the moves in [_omitDefaultSubject] (ContraDB
  ///   `upOrDownTheHallWords` `who === "everyone" ? "" : swho`, plus
  ///   star_promenade's default-subject omission).
  bool _isDisplaySilenced(MoveDef def, String name, Object? value) {
    if (name == 'who' && _omitDefaultSubject.contains(def.id)) {
      return value == def.params['who']?.defaultValue;
    }
    if (_silencedDefaultParams[def.id] == name) {
      return value == def.params[name]?.defaultValue;
    }
    return false;
  }

  String _renderMoveName(
    String moveId,
    String displayName,
    Map<String, Object?> params,
    Dialect dialect, [
    bool forCanonical = false,
  ]) {
    // Display path: fall back to a built-in `%S` move-name override (e.g.
    // shoulder_round → "%S shoulder round") when the dialect provides none, so
    // the shoulder word surfaces even under the canonical/identity dialect.
    // ContraDB `gyreWords` expands `%S` to the shoulder side. Never applied to
    // the canonical render (the search/dedupe text keeps the bare move name).
    final substitution =
        dialect.moves[moveId] ??
        (forCanonical ? null : _displayMoveNameOverrides[moveId]);
    return _applyMoveSubstitution(substitution, displayName, params);
  }

  /// DISPLAY-ONLY rendering of a single dancer/role [token] for the
  /// [_displayBaseRenderers] base lines: role tokens map to the dialect role
  /// term (canonical token when unmapped), single-dancer identities take
  /// [_singleDancerTerm] (substitution, else `<first|second> <role>`),
  /// [Dialect.dancers] substitutions win next, then positional dancer sets read
  /// as the PR1 singular subject (`partners` → `partner`), else the token
  /// humanizes. Mirrors the display-path branch of [_renderValue]; never used
  /// by the canonical render.
  String _displayDancer(String token, Dialect dialect) {
    if (roleTokens.contains(token)) return _roleTerm(token, dialect);
    final single = _singleDancerTerm(token, dialect);
    if (single != null) return single;
    final substitution = dialect.dancers[token];
    if (substitution != null) return substitution;
    return _singularDancerSets[token] ?? _humanize(token);
  }

  /// DISPLAY-ONLY rendering of a dancer/role [token] as a PLURAL group noun,
  /// for clauses whose verb agrees with the group (hey's `meetTarget`:
  /// "until neighbors meet"). Like [_displayDancer] but WITHOUT the singular
  /// subject collapse (`neighbors` stays `neighbors`, not `neighbor`), mirroring
  /// ContraDB `dancerSubstitution` which keeps the plural term. Role tokens,
  /// single-dancer identities and [Dialect.dancers] substitutions win first (a
  /// single-dancer identity names one dancer, so it has no plural form to keep).
  String _displayGroup(String token, Dialect dialect) {
    if (roleTokens.contains(token)) return _roleTerm(token, dialect);
    final single = _singleDancerTerm(token, dialect);
    if (single != null) return single;
    final substitution = dialect.dancers[token];
    if (substitution != null) return substitution;
    return _humanize(token);
  }

  /// DISPLAY-ONLY: renders a dancer/role subject [value] of any type for the
  /// [_displayBaseRenderers] base lines. A `String` routes through
  /// [_displayDancer]; a non-null non-`String` (which
  /// [Taxonomy.effectiveParams] passes through uncoerced) is surfaced via
  /// best-effort [_humanize] rather than silently blanked — malformed
  /// imported/user data must be visible, not hidden. `null` renders empty so
  /// the caller can drop the connective.
  String _displaySubject(Object? value, Dialect dialect) {
    if (value == null) return '';
    if (value is String) return _displayDancer(value, dialect);
    return _humanize(value.toString());
  }

  /// DISPLAY-ONLY: best-effort humanization of a non-dancer scalar param
  /// [value] (e.g. a hand side) for the [_displayBaseRenderers] base lines.
  /// Unknown non-null values are surfaced, not blanked; `null` renders empty.
  static String _displayScalar(Object? value) =>
      value == null ? '' : _humanize(value.toString());

  /// Whether [value] is the [ParamVocab.unspecified] sentinel — i.e. the source
  /// stated nothing for this param (issue #295). Base lines drop the whole
  /// clause in that case instead of writing the word "unspecified".
  static bool _isUnspecified(Object? value) => value == ParamVocab.unspecified;

  /// DISPLAY-ONLY: a `choice` param for the base lines, rendering the
  /// [ParamVocab.unspecified] sentinel as nothing and otherwise humanizing
  /// (so an unexpected imported value is still surfaced, never hidden).
  static String _displayChoice(Object? value) =>
      _isUnspecified(value) ? '' : _displayScalar(value);

  /// DISPLAY-ONLY: the trailing " - and balance" clause the wave-FORMATION base
  /// lines append for a truthy `balance` (issue #296, product wording shared by
  /// `form_long_waves` and `form_short_waves`). A wildcard `'*'` keeps the
  /// clause visible rather than silently dropping the flag; anything else — the
  /// default `false` included — renders nothing, so canonical/FTS text and every
  /// unbalanced figure are unaffected.
  static String _balanceSuffix(Object? balance) => balance == true
      ? ' - and balance'
      : balance == '*'
      ? ' - and *'
      : '';

  /// DISPLAY-ONLY: the "other pair" for a subject [value], mirroring ContraDB
  /// `dance.js` `invertPair` (`app/javascript/libfigure/dance.js` @13f38a5).
  /// ContraDB inverts only the four-dancer pairings it can name
  /// (role1s↔role2s, ones↔twos, firstCorners↔secondCorners) and returns
  /// "others" for an empty/undefined subject; it throws on any other value
  /// (e.g. `partners`, `neighbors`). We never throw — an out-of-domain or
  /// non-string subject renders the same "others" fallback ContraDB uses for
  /// the empty case, so a clause never emits a bogus pair. The inverted token
  /// is mapped through [_displayDancer] so it stays dialect-aware and plural.
  String _invertPair(Object? value, Dialect dialect) {
    final other = value is String ? invertPairDancerSet(value) : null;
    return other == null ? 'others' : _displayDancer(other, dialect);
  }

  /// DISPLAY-ONLY: the DEFAULT label for a single-dancer identity [token]
  /// (`onesRole1` …), as `<first|second> <role singular>` — e.g. `first lark`
  /// under larks/robins, `first role1` under the canonical dialect. Returns
  /// `null` for every other token, so callers can chain it ahead of their own
  /// fallback. Mirrors ContraDB's `chooser_dancer` "first/second
  /// gentlespoon/ladle" naming (`app/javascript/libfigure/chooser.js`
  /// @13f38a5). The ordinal (ones→first, twos→second) is fixed structural
  /// vocabulary; the role word is the active dialect's role term.
  ///
  /// DELIBERATELY IGNORES [Dialect.dancers]: this is the wording a token reads
  /// as with NO substitution set. The dialect editor labels its substitution
  /// rows with it, and must show the default rather than echoing the override
  /// the user is editing in the adjacent field. Rendering callers want
  /// [_singleDancerTerm], which lets a substitution win.
  static String? singleDancerDefaultTerm(String token, Dialect dialect) {
    final match = _singleDancerShape.firstMatch(token);
    if (match == null) return null;
    final ordinal = match[1] == 'ones' ? 'first' : 'second';
    final role = match[2]!.toLowerCase(); // Role1 -> role1
    return '$ordinal ${_roleTerm(role, dialect)}';
  }

  /// DISPLAY-ONLY label for a single-dancer identity [token]: a
  /// [Dialect.dancers] substitution wins, else [singleDancerDefaultTerm].
  /// `null` for every other token.
  ///
  /// THE one single-dancer path for the display renderer — every site that used
  /// to fall through to [_humanize] for these compound tokens (issue #832)
  /// calls this. Consulting the substitution map makes the `<ordinal> <role>`
  /// construction the DEFAULT rather than the only outcome, matching
  /// [_displayDancer]/[_displayGroup], which have always let a substitution win.
  static String? _singleDancerTerm(String token, Dialect dialect) =>
      _singleDancerShape.hasMatch(token)
      ? (dialect.dancers[token] ?? singleDancerDefaultTerm(token, dialect))
      : null;

  /// DISPLAY-ONLY: label for a single-dancer identity [value], via
  /// [_singleDancerTerm]. A value that does not match the
  /// `(ones|twos)(Role1|Role2)` shape falls back to [_displayDancer] so unknown
  /// values are still surfaced, not blanked.
  String _singleDancerLabel(Object? value, Dialect dialect) {
    if (value is! String) return _displaySubject(value, dialect);
    return _singleDancerTerm(value, dialect) ?? _displayDancer(value, dialect);
  }

  /// Display name for [moveId] under [dialect] for the dance editor / figure
  /// rows: applies [Dialect.moves] substitution (with `%S` shoulder/hand
  /// injection from [params]) when present, otherwise the taxonomy display name
  /// (alias-aware). Under [Dialect.canonical] this is the plain display name.
  ///
  /// Companion to [displayToken]; both are the display-only, single-item core
  /// API the editor uses so the editor never shows canonical vocabulary unless
  /// the active dialect is canonical. Storage stays canonical regardless.
  String displayMoveName(
    String moveId,
    Dialect dialect, {
    Map<String, Object?> params = const {},
  }) {
    final def = taxonomy.resolve(moveId);
    final alias = taxonomy.aliases[moveId];
    final displayName = alias?.displayName ?? def?.displayName ?? moveId;
    // Move substitutions are keyed by the canonical move id.
    final canonicalId = def?.id ?? moveId;
    // Trimmed so a %S substitution with a missing side word never surfaces a
    // stray leading/trailing space in the editor's move field.
    return _applyMoveSubstitution(
      dialect.moves[canonicalId],
      displayName,
      params,
    ).trim();
  }

  /// Display string for a single vocabulary [token] under [dialect], for use in
  /// the dance editor's param choices/labels. Role tokens render as the
  /// dialect's role term (canonical token when unmapped); single-dancer
  /// identities (`twosRole2`) take [_singleDancerTerm]; [ParamKind.dancerSet]
  /// / [ParamKind.dancerPair] tokens use [Dialect.dancers] (else humanized);
  /// every other token (structural params such as `shoulder`, `direction`) is
  /// humanized. Under [Dialect.canonical] the result equals the plain humanized
  /// / canonical form, except for a single-dancer identity, which reads
  /// `second role2` (its canonical-vocabulary default) rather than the raw
  /// `twos role2` — issue #832.
  ///
  /// The single-dancer branch is NOT spec-gated, mirroring [roleTokens]: these
  /// four are a closed structural vocabulary, so the label is right whatever
  /// spec (or none) the caller has to hand.
  static String displayToken(String token, ParamSpec? spec, Dialect dialect) {
    if (roleTokens.contains(token)) return _roleTerm(token, dialect);
    final single = _singleDancerTerm(token, dialect);
    if (single != null) return single;
    if (spec != null &&
        (spec.kind == ParamKind.dancerSet ||
            spec.kind == ParamKind.dancerPair)) {
      final substitution = dialect.dancers[token];
      if (substitution != null) return substitution;
    }
    return _humanize(token);
  }

  static String _applyMoveSubstitution(
    String? substitution,
    String displayName,
    Map<String, Object?> params,
  ) {
    if (substitution == null) return displayName;
    if (!substitution.contains('%S')) return substitution;
    // %S injects the figure's shoulder/hand side word.
    final side = params['shoulder'] ?? params['hand'];
    return substitution.replaceAll('%S', side is String ? side : '');
  }

  String _renderValue(
    String name,
    Object? value,
    ParamSpec? spec,
    Dialect dialect,
    bool verbose,
    bool decimals,
    bool forCanonical,
  ) {
    if (value == null) return '';
    // The `unspecified` sentinel means the SOURCE STATED NOTHING, so it renders
    // as nothing — in the canonical render too. This is what lets an additive
    // param sit in a `renderTemplate` (`mad_robin.direction`/`whom`,
    // `butterfly_whirl.who`/`direction`; issue #295) while every figure that
    // leaves it unset keeps a byte-identical canonical/FTS/dedupe key. Gated on
    // the spec explicitly admitting the sentinel, so a free-`text` param whose
    // value happens to be the word "unspecified" still renders verbatim.
    if (value == ParamVocab.unspecified &&
        (spec?.choices?.contains(ParamVocab.unspecified) ?? false)) {
      return '';
    }
    if (value is String && roleTokens.contains(value)) {
      return _roleTerm(value, dialect);
    }
    // Swing's `prefix` modifier reads as a natural phrase in front of the move
    // ("balance & swing" / "meltdown swing"); `none` renders to nothing.
    if (spec?.kind == ParamKind.choice && name == 'prefix' && value is String) {
      return _renderPrefix(value, verbose);
    }
    if (value is String &&
        (spec?.kind == ParamKind.dancerSet ||
            spec?.kind == ParamKind.dancerPair)) {
      // Display-only: a single-dancer identity reads as its substitution, else
      // `<first|second> <role term>` (issue #832). GATED ON !forCanonical — the
      // canonical render must keep emitting the humanized raw token
      // ("twos role2"), because that text is persisted to
      // `dance_figures.canonicalText` / `dance_fts` and is the dedupe key.
      // Changing it would be a migration + derived rebuild, not a display fix.
      if (!forCanonical) {
        final single = _singleDancerTerm(value, dialect);
        if (single != null) return single;
      }
      final substitution = dialect.dancers[value];
      if (substitution != null) return substitution;
      // Display-only: positional dancer sets read as singular subjects
      // (`neighbors` → `neighbor`). Role tokens are handled above and never
      // singularized; the canonical render keeps the plural token.
      if (!forCanonical) {
        final singular = _singularDancerSets[value];
        if (singular != null) return singular;
      }
    }
    if (spec?.kind == ParamKind.rotation && value is num) {
      return verbose
          ? _formatRotationVerbose(value)
          : _formatRotation(value, decimals: decimals);
    }
    if (spec?.kind == ParamKind.fraction && value is String && verbose) {
      return _formatFractionVerbose(value);
    }
    if (spec?.kind == ParamKind.places && value is int) {
      return _formatPlaces(value);
    }
    if (value is num) return _formatNumber(value);
    if (value is bool) return value ? name : '';
    return _humanize(value.toString());
  }

  /// Formats swing's `prefix` choice as a modifier that reads naturally in
  /// front of the move name in the render template `{who} {prefix} {move}`:
  /// `balance & swing` (visual) / `balance and swing` (verbose),
  /// `meltdown swing`, and nothing for `none`. The `&`/`and` connective lives
  /// here because it joins the prefix to the following move token.
  static String _renderPrefix(String value, bool verbose) {
    switch (value) {
      case 'none':
        return '';
      case 'balance':
        return verbose ? 'balance and' : 'balance &';
      case 'meltdown':
        return 'meltdown';
      default:
        return _humanize(value);
    }
  }

  static String _roleTerm(String token, Dialect dialect) {
    final plural = token.endsWith('s');
    final baseId = plural ? token.substring(0, token.length - 1) : token;
    final term = dialect.roles[baseId];
    if (term == null) return token; // canonical: render the token itself
    return plural ? term.plural : term.singular;
  }

  /// Free-text (notes, hooks, custom figures): apply role-term substitution
  /// with case preservation. Move-name substitution does not apply to prose.
  String renderFreeText(String text, Dialect dialect) {
    final map = <String, String>{};
    for (final entry in dialect.roles.entries) {
      map[entry.key] = entry.value.singular; // role1 -> Lark
      map['${entry.key}s'] = entry.value.plural; // role1s -> Larks
    }
    return Substitutor(
      map,
      caseInsensitive: true,
      preserveCase: true,
    ).apply(text);
  }

  /// Human phrasing for a set-relative facing token, shared by the derived
  /// rotation-gate ending facing (issue #294) and swing's `endFacing` clause
  /// (issue #543). An unexpected value humanizes rather than blanking,
  /// surfacing malformed data.
  static const Map<String, String> _gateFacingPhrases = {
    'in': 'into the set',
    'out': 'out of the set',
    'up': 'up the hall',
    'down': 'down the hall',
  };

  static String _gateFacingPhrase(String facing) =>
      _gateFacingPhrases[facing] ?? _humanize(facing);

  /// Swing `endFacing` values that render an ending-facing clause (issue #543).
  /// The default `in` (across) is deliberately ABSENT — a default swing renders
  /// exactly as before. Restricting to this allow-list means any unknown or
  /// tolerantly-decoded token renders no clause rather than being injected into
  /// the display line.
  static const Set<String> _swingRenderedEndFacings = {'out', 'up', 'down'};

  /// The DISPLAY-ONLY " facing …" clause a swing appends for a non-default
  /// [endFacing] (issue #543), or the empty string for the default `in`, an
  /// unknown token, or a non-String value. The wording reuses
  /// [_gateFacingPhrases] ("up the hall" / "down the hall" / "out of the set").
  static String _swingEndFacingClause(Object? endFacing) {
    if (endFacing is! String || !_swingRenderedEndFacings.contains(endFacing)) {
      return '';
    }
    return ' facing ${_gateFacingPhrase(endFacing)}';
  }

  /// ContraDB `libfigure` down/up-the-hall ender wording
  /// (`param.js` `stringParamDownTheHallEnder`), keyed by our taxonomy token.
  /// `none` is intentionally absent (renders no clause). `bendTheLine` is a
  /// CallersBox-origin ender absent from ContraDB, so it uses CallersBox's
  /// "bend the line" wording (`docs/research/callersbox.md`).
  static const Map<String, String> _hallEnderLabels = {
    'turnCouple': 'turn as a couple',
    'turnAlone': 'turn alone',
    'circle': 'bend into a ring',
    'cozy': 'form a cozy line',
    'cloverleaf': 'bend into a cloverleaf',
    'threadNeedle': 'thread the needle',
    'rightHandHigh': 'right hand high, left hand low',
    'slidingDoors': 'slide doors',
    'bendTheLine': 'bend the line',
  };

  /// ContraDB `libfigure` hey-length wording is emitted inline by
  /// [_summarySuffix] (compact parenthetical on screen, "half hey"/"full hey"
  /// or the "until…" clause when spoken), so no lookup table is needed here.

  /// DISPLAY-ONLY: the single template param, per move, whose value is omitted
  /// when it equals the move's taxonomy default. Mirrors ContraDB's per-param
  /// `stringParamSetDirectionSilencingDefault(<default>)`
  /// (`app/javascript/libfigure/param.js` @13f38a5) for the `dir` (set
  /// direction) params, and the `facing`/`march_forward` "forward" default for
  /// the hall moves. A non-default value still renders. `cross_trails` is
  /// intentionally absent — it is out of PR1 scope. `pass_through`'s default
  /// direction silencing is handled by its `_displayBaseRenderers` entry (which
  /// also handles the shoulder), so it is intentionally absent here. The
  /// canonical render is never affected (it keeps `everyone down the hall
  /// forward`, etc.).
  static const Map<String, String> _silencedDefaultParams = {
    // ContraDB set_direction_along → silences default 'along'.
    'pull_by_direction': 'dir',
    // ContraDB set_direction_across/acrossish → silences default 'across'.
    'right_left_through': 'dir',
    'chain': 'dir',
    'promenade': 'dir',
    // ContraDB march_forward → silences the "forward" facing default.
    'down_the_hall': 'facing',
    'up_the_hall': 'facing',
  };

  /// DISPLAY-ONLY: moves whose `who` subject is omitted when it equals the
  /// move's `who` default. Mirrors ContraDB `upOrDownTheHallWords`
  /// (`who === "everyone" ? "" : swho`) for the hall moves, ContraDB's
  /// `everyone`-omitting subject rendering for `turn_alone`/`rory_o_more`, and
  /// star_promenade's subject omission (ContraDB drops the gentlespoons subject
  /// there). This omission is NOT generalized to other subjects. A non-default
  /// `who` still renders.
  ///
  /// **star_promenade's entry no longer describes a ROLE-subject omission**
  /// (taxonomy v26, #843). Its `who` now means the dancer you PICK UP on the
  /// side, so the norm for an imported figure is a RELATIONSHIP value
  /// (`neighbors`/`partners`) — which is non-default and therefore renders.
  /// The `role1s` default it silences is now the residue of the old ContraDB
  /// reading rather than the common case, and ContraDB star promenades no
  /// longer import as this move at all. The entry is kept so a figure that
  /// really does carry the default subject renders as it always did.
  static const Set<String> _omitDefaultSubject = {
    'down_the_hall',
    'up_the_hall',
    'turn_alone',
    'rory_o_more',
    'star_promenade',
  };

  /// DISPLAY-ONLY built-in move-name overrides applied when the active dialect
  /// supplies no substitution, so the wording surfaces even under the
  /// canonical/identity dialect. `%S` expands to the figure's shoulder/hand
  /// side (see [_applyMoveSubstitution]). ContraDB `gyreWords` renders the
  /// shoulder via the same `%S` expansion (`neighbor right shoulder round`).
  /// The canonical render keeps the bare `{move}` display name.
  static const Map<String, String> _displayMoveNameOverrides = {
    'shoulder_round': '%S shoulder round',
    // ContraDB `figureGenericWords` always emits every non-who/bal/beats param,
    // so the shoulder appears unconditionally. `%S` expands to the side word
    // ("right" / "left" / "*"); ContraDB `stringParamShoulders` appends
    // "shoulders" making "right shoulders" etc. The canonical render keeps the
    // bare `{move}` display name (template: `{who} {move}`).
    'pass_by': 'pass by %S shoulders',
  };

  /// DISPLAY-ONLY singular forms for the positional dancer-set vocabulary that
  /// otherwise humanizes to a `partner`/`neighbor`/`shadow` plural. A figure's
  /// subject reads as a singular dancer in display (`neighbors` → `neighbor`),
  /// while the canonical render keeps the plural token. Role tokens
  /// (`role1s`/`role2s`) and the group tokens `everyone`/`ones`/`twos`/
  /// `centers`/`firstCorners`/`secondCorners`/`sameRoles` are intentionally
  /// absent — they are never singularized.
  static const Map<String, String> _singularDancerSets = {
    'partners': 'partner',
    'neighbors': 'neighbor',
    'shadows': 'shadow',
    'secondShadows': 'second shadow',
    'prevNeighbors': 'prev neighbor',
    'nextNeighbors': 'next neighbor',
    'thirdNeighbors': 'third neighbor',
    'fourthNeighbors': 'fourth neighbor',
    'prevPartners': 'prev partner',
    'nextPartners': 'next partner',
    'thirdPartners': 'third partner',
    'fourthPartners': 'fourth partner',
    'fifthPartners': 'fifth partner',
  };

  /// DISPLAY-ONLY base-line renderers that adopt ContraDB `libfigure`
  /// (`app/javascript/libfigure/figure.js` @13f38a5) `words()` sentence
  /// structure verbatim for moves whose display wording is a base-line
  /// restructure (not a trailing suffix). Consulted in [_render] only when
  /// `!forCanonical`; the canonical render keeps expanding `renderTemplate`, so
  /// the dedupe/FTS text stays byte-for-byte stable. Dancer/role tokens map
  /// through [_displayDancer] (dialect-aware + PR1 singularization); move names
  /// through [_renderMoveName].
  static final Map<String, _DisplayBaseRenderer> _displayBaseRenderers = {
    // Swing (issue #543). Reproduces the terse `{who} {prefix} {move}` line
    // (byte-identical to the template expansion) and appends an ending-facing
    // clause ONLY when `endFacing` is non-default. The default `in` (across)
    // renders exactly as before — no clause — so the overwhelming majority of
    // swings stay uncluttered. The clause is DISPLAY-ONLY (this map is consulted
    // only when `!forCanonical`), so the canonical render keeps expanding
    // `renderTemplate` (which omits `endFacing`) and stays byte-for-byte stable.
    // `endFacing` is allow-listed here (out/up/down); `in`, an unknown token, or
    // a non-String value all render NO clause (never injected), consistent with
    // the taxonomy's tolerant-decode contract.
    'swing': (r, def, params, dialect, verbose, decimals) {
      final swho = r._subjectWho(params, dialect);
      final prefixRaw = params['prefix'];
      final prefix = _renderPrefix(
        prefixRaw is String ? prefixRaw : 'none',
        verbose,
      );
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      // Join with spaces exactly like the `{who} {prefix} {move}` template; the
      // enclosing [_render] collapses the runs (and an empty `none` prefix) and
      // handles the subject sentinel, so the `in` case matches today verbatim.
      final base = '$swho $prefix $move';
      return '$base${_swingEndFacingClause(params['endFacing'])}';
    },
    // The unified gate (taxonomy v22 — was ContraDB `gate` + TCB
    // `rotation_gate`). Word order, preserved from both predecessors:
    //   * `mirror` reads as a modifier BEFORE the move name ("mirror gate");
    //     clockwise/counterclockwise read AFTER it ("gate counterclockwise").
    //   * the object dancers sit right after the move name, as ContraDB's
    //     `gateWords` does (`words(ssubject, smove, sobject, "to face", …)`).
    //   * the ending facing is the STORED `face`, rendered in ContraDB's own
    //     "to face …" wording. It is no longer derived: the withdrawn
    //     `gateEndFacing` computed from a nominal `in` start orientation and so
    //     claimed "to face out of the set" for every 1/2 gate, including after
    //     a down-the-hall where the answer is "up" (see gate_facing.dart).
    // Every slot is `unspecified` unless its source stated it, and an
    // unspecified slot renders NOTHING — so a ContraDB gate reads "ones gate
    // neighbors to face up the hall" and a TCB gate reads "neighbor mirror gate
    // once", each byte-identical to what its own predecessor move produced.
    // Canonical render is unaffected (it keeps expanding the template).
    'gate': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      // Grammatical subject: ContraDB's `who` (the side that extends a hand and
      // backs up) when stated, else TCB's `pair` (the pairing you gate with).
      // They are different axes, so whichever the source filled leads the line
      // and the other — normally absent — falls through to the object slot.
      final whoRaw = params['who'];
      final pairRaw = params['pair'];
      final whoLeads = !_isUnspecified(whoRaw) && whoRaw != null;
      final swho = r._subjectToken(whoLeads ? whoRaw : pairRaw, dialect);
      final whomRaw = params['whom'];
      final hasWhom = !_isUnspecified(whomRaw) && whomRaw != null;
      // ContraDB's grammar puts the object straight after the move — but that
      // only reads as "the side that walks forward" when a subject precedes it
      // ("ones gate neighbors"). A TCB gate names the pairing instead, so
      // "neighbor gate ones" would be ambiguous; there the forward-walking side
      // is stated explicitly as a trailing clause, mirroring the source's own
      // "(ones forward)" wording.
      final objects = [
        if (whoLeads && !_isUnspecified(pairRaw) && pairRaw != null)
          r._displaySubject(pairRaw, dialect),
        if (whoLeads && hasWhom) r._displaySubject(whomRaw, dialect),
      ].where((s) => s.isNotEmpty).join(' ');
      final forwardClause = (!whoLeads && hasWhom)
          ? ', ${r._displaySubject(whomRaw, dialect)} forward'
          : '';
      final directionRaw = params['direction'];
      // An unexpected direction value humanizes after the move (surfacing
      // malformed data) rather than silently vanishing.
      final direction = _displayChoice(directionRaw);
      final turnRaw = params['turn'];
      final turn = turnRaw is num
          ? (verbose
                ? _formatRotationVerbose(turnRaw)
                : _formatRotation(turnRaw, decimals: decimals))
          : _isUnspecified(turnRaw)
          ? ''
          : _displayScalar(turnRaw);
      final head = direction == 'mirror'
          ? '$swho mirror $move $objects $turn'
          : '$swho $move $objects $direction $turn';
      final faceRaw = params['face'];
      // Allow-listed exactly like `swing.endFacing` (v16): an unknown or
      // tolerantly-decoded token renders NO clause rather than being injected
      // into the line as "to face <garbage>". A facing is a closed cardinal
      // vocabulary, so surfacing a bad value here would read as choreography.
      final facingClause = (faceRaw is String && gateFacings.contains(faceRaw))
          ? ' to face ${_gateFacingPhrase(faceRaw)}'
          : '';
      return '$head$forwardClause$facingClause';
    },
    // The Caller's Box's standalone courtesy turn (taxonomy v23). Maintainer's
    // stated wording, verbatim:
    //   {who} courtesy turn {whom, when present} {direction, when not
    //   clockwise} {"to face" + endFacing, when set}
    // A `renderTemplate` cannot express those conditionals, so the canonical
    // (dedupe/FTS) render keeps expanding the flat template — byte-stability of
    // the canonical text is therefore untouched by anything here — and the
    // conditional wording lives on this DISPLAY-ONLY path, exactly as the
    // merged `gate`'s "to face …" clause does.
    //
    // `clockwise` is silenced because a courtesy turn wheels clockwise by
    // construction: all 10 corpus lines that state a direction say `clockwise`,
    // so printing it would add a word to nearly every courtesy turn while
    // distinguishing nothing. `counterclockwise` — unattested in the corpus but
    // authorable — is genuinely surprising and always shown. An unexpected
    // value is surfaced rather than silently vanishing, mirroring `gate`.
    //
    // `endFacing` renders in ContraDB's "to face …" idiom, but the value it
    // names is a DANCER (`face N2` → "to face next neighbors"), not one of the
    // four cardinals `swing.endFacing`/`gate.face` use — see the taxonomy param
    // comment. It therefore goes through `_displaySubject` (dialect-aware),
    // never `_gateFacingPhrase`.
    'courtesy_turn': (r, def, params, dialect, verbose, decimals) {
      final swho = r._subjectWho(params, dialect);
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final whomRaw = params['whom'];
      final whom = (!_isUnspecified(whomRaw) && whomRaw != null)
          ? r._displaySubject(whomRaw, dialect)
          : '';
      final directionRaw = params['direction'];
      final direction = (directionRaw == 'clockwise')
          ? ''
          : _displayChoice(directionRaw);
      final facingRaw = params['endFacing'];
      final facing = (!_isUnspecified(facingRaw) && facingRaw != null)
          ? ' to face ${r._displaySubject(facingRaw, dialect)}'
          : '';
      // The enclosing [_render] collapses the whitespace runs an empty slot
      // leaves behind, so the all-defaults line reads "partner courtesy turn".
      return '$swho $move $whom $direction$facing';
    },
    // ContraDB `zigZagWords`: words(twho, "zig", sspin, "zag", return_sspin, …).
    // The zag direction is the mirror of the zig (`turn`) direction. ContraDB
    // omits the partners subject; per the ratified decision we instead surface
    // it as a trailing "with <subject>" (singular, per PR1). The ender clause is
    // appended separately by [_summarySuffix].
    'zig_zag': (r, def, params, dialect, verbose, decimals) {
      final turnRaw = params['turn'];
      final turn = turnRaw is String
          ? turnRaw
          : turnRaw == null
          ? 'left'
          : _humanize(turnRaw.toString());
      final zag = turn == 'left'
          ? 'right'
          : turn == 'right'
          ? 'left'
          : turn;
      final swho = r._displaySubject(params['who'], dialect);
      // Omit the "with <subject>" suffix entirely when the subject renders
      // empty — never emit a dangling "with".
      final suffix = swho.isEmpty ? '' : ' with $swho';
      return 'zig $turn zag $zag$suffix';
    },
    // ContraDB `slice` has no `words` fn → `figureGenericWords` over its labels:
    // words(smove, sslide, sincrement, sreturn). `slice_increment` couple→"",
    // dancer→"one dancer" (`stringParamSliceIncrement`); `slice_return`
    // straight→"and straight back", diagonal→"and diagonal back", none→""
    // (`stringParamSliceReturn`). Unknown non-null by/return values humanize
    // (surfacing malformed data) rather than rendering as the empty default.
    'slice': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final slideRaw = params['slice'];
      final slide = slideRaw is String
          ? slideRaw
          : slideRaw == null
          ? 'left'
          : _humanize(slideRaw.toString());
      final by = params['by'];
      final byWord = by == null || by == 'couple'
          ? ''
          : by == 'dancer'
          ? 'one dancer'
          : _humanize(by.toString());
      final ret = params['return'];
      final retWord = ret == null || ret == 'none'
          ? ''
          : ret == 'straight'
          ? 'and straight back'
          : ret == 'diagonal'
          ? 'and diagonal back'
          : _humanize(ret.toString());
      return '$move $slide $byWord $retWord';
    },
    // ContraDB `madRobinWords`: words(smove, tangle, comma, srole, "in front"),
    // tangle = angle !== 360 && sangle + " around". Our `turn` is a rotation
    // (1.0 == 360° == once), so the "<turn> around" clause is shown only for a
    // non-default turn (formatted via our rotation vocabulary — an approximation
    // of ContraDB's degrees wording).
    //
    // v20 (#295) layers The Caller's Box's two extra facts on top, each shown
    // only when the source stated it (the `unspecified` sentinel renders
    // nothing, so a ContraDB import is unchanged): the rotation `direction`
    // right after the move name, and the "around <whom>" target folded INTO the
    // turn clause — so TCB's "Mad robin clockwise 1 & 1/2 around neighbor"
    // reads back as "mad robin clockwise 1½ around neighbor, ones in front"
    // rather than doubling the word "around".
    'mad_robin': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final dir = _displayChoice(params['direction']);
      final dirWord = dir.isEmpty ? '' : ' $dir';
      final turn = params['turn'];
      final turnWord = (turn is num && turn != 1.0)
          ? (verbose
                ? _formatRotationVerbose(turn)
                : _formatRotation(turn, decimals: decimals))
          : '';
      final swhom = _isUnspecified(params['whom'])
          ? ''
          : r._displaySubject(params['whom'], dialect);
      // "<turn> around <whom>" — either side may be absent; when BOTH are the
      // clause is dropped entirely (never a bare dangling "around").
      final around = (turnWord.isEmpty && swhom.isEmpty)
          ? ''
          : ' ${[turnWord, 'around', swhom].where((p) => p.isNotEmpty).join(' ')}';
      // Tag the subject so an import-assumed `who` (TCB never states the
      // in-front role) is marked "(assumed)" rather than read as source fact.
      final swho = r._subjectWho(params, dialect);
      // Only emit the comma + "<subject> in front" when the subject renders
      // non-empty (never "mad robin, " with nothing after it).
      final subject = swho.isEmpty ? '' : ', $swho in front';
      return '$move$dirWord$around$subject';
    },
    // ContraDB `revolvingDoorWords`: words(smove, " - ", ssubject, "take",
    // shand, "hands and drop off", sobject, "on other side"). The subject
    // (role2s) stays a plural role term; the object (partners) singularizes per
    // PR1. Unknown non-null who/whom/hand values humanize (surfacing malformed
    // data) rather than blanking out. This base line already carries the
    // drop-off outcome, so [_summarySuffix] no longer appends its own clarifier.
    'revolving_door': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final swho = r._displaySubject(params['who'], dialect);
      final hand = _displayScalar(params['hand']);
      final swhom = r._displaySubject(params['whom'], dialect);
      return '$move - $swho take $hand hands and drop off $swhom on other side';
    },
    // ContraDB `boxCirculateWords`: words(sbal, smove, "-", words(ssubject,
    // "cross while", invertPair(subject), "loop", sspin)). The leading balance
    // is NOT baked in here — it is composed by `renderSummary` via
    // [_balancePlacement]`[box_circulate] = leading` (PR2's default-shown-balance
    // handling), so `render()` shows the bare "box circulate - … cross while …
    // loop right" and only the summary prepends "balance &". `who` (partners)
    // is outside ContraDB's invert domain, so the loop pair renders "others"
    // (ContraDB's own empty-subject fallback).
    'box_circulate': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final swho = r._subjectWho(params, dialect);
      final other = r._invertPair(params['who'], dialect);
      final hand = _displayScalar(params['hand']);
      return '$move - $swho cross while $other loop $hand';
    },
    // ContraDB `crossTrailsWords`: words(smove, "-", sfirst_who, sfirst_dir,
    // sfirst_shoulder + ",", ssecond_who, ssecond_dir, ssecond_shoulder). The
    // second dir/shoulder are the fixed structural inverse of the first
    // (across<->"along the set"; right<->left shoulders). Shoulders render in
    // full ("right shoulders"), matching ContraDB `stringParamShoulders`.
    'cross_trails': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final swho = r._displaySubject(params['who'], dialect);
      final swho2 = r._displaySubject(params['who2'], dialect);
      final dir = params['dir'];
      final firstDir = dir == null
          ? ''
          : '${_humanize(dir.toString())} the set';
      final secondDir = dir == 'across'
          ? 'along the set'
          : dir == 'along'
          ? 'across the set'
          : dir == '*'
          ? '* the set'
          : '';
      final sh = params['shoulder'];
      final firstShoulder = sh == null
          ? ''
          : '${_humanize(sh.toString())} shoulders';
      final otherSh = sh == 'right'
          ? 'left'
          : sh == 'left'
          ? 'right'
          : null;
      final secondShoulder = otherSh == null ? '' : '$otherSh shoulders';
      final firstPart = [
        swho,
        firstDir,
        firstShoulder,
      ].where((s) => s.isNotEmpty).join(' ');
      final secondPart = [
        swho2,
        secondDir,
        secondShoulder,
      ].where((s) => s.isNotEmpty).join(' ');
      final body = secondPart.isEmpty ? firstPart : '$firstPart, $secondPart';
      return '$move - $body';
    },
    // ContraDB `poussetteWords`: words(shalf_or_full, smove, "-", swho, "pull",
    // swhom, tturn). tturn: turn truthy (clockwise) -> "back then left", falsy
    // (counterclockwise) -> "back then right", "*"" -> "back then *". The
    // half/full fraction word leads the clause.
    'poussette': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final half = _displayScalar(params['half']);
      final swho = r._displaySubject(params['who'], dialect);
      final swhom = r._displaySubject(params['whom'], dialect);
      final turn = params['turn'];
      final turnWord = turn == 'clockwise'
          ? 'back then left'
          : turn == 'counterclockwise'
          ? 'back then right'
          : turn == '*'
          ? 'back then *'
          : '';
      final pullClause = swhom.isEmpty ? 'pull' : 'pull $swhom';
      return [
        half,
        move,
        '-',
        swho,
        pullClause,
        turnWord,
      ].where((s) => s.isNotEmpty).join(' ');
    },
    // ContraDB `facingStarWords`: words(smove, sturn, splaces, "with", swho,
    // "putting their", shand, "hands in and backing up"). No leading subject.
    // The hand word is DERIVED from the turn (ContraDB: turn truthy/clockwise ->
    // "left", counterclockwise/false -> "right"). The turn word itself is our
    // own spinDirection vocabulary via [_displayScalar] ("clockwise" /
    // "counterclockwise") — matching the canonical text and every other spin
    // render — rather than ContraDB's hyphenated "counter-clockwise" spelling;
    // the default (clockwise) is identical either way.
    'facing_star': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final turn = params['turn'];
      final turnWord = _displayScalar(turn);
      final hand = turn == 'counterclockwise'
          ? 'right'
          : turn == '*'
          ? '*'
          : 'left';
      final placesRaw = params['places'];
      final places = placesRaw is int
          ? _formatPlaces(placesRaw)
          : _displayScalar(placesRaw);
      final swho = r._displaySubject(params['who'], dialect);
      final withClause = swho.isEmpty ? '' : 'with $swho';
      return [
        move,
        turnWord,
        places,
        withClause,
        'putting their',
        hand,
        'hands in and backing up',
      ].where((s) => s.isNotEmpty).join(' ');
    },
    // ContraDB `squareThroughWords`: words(smove, placewords, "-", ssubject1,
    // sbal, "pull by", shand, comma, "then", ssubject2, "pull by", shand2,
    // <tail>). The balance is embedded INSIDE the sequence (not via
    // [_balancePlacement], which has no square_through entry). The second hand
    // is the opposite of the first. The tail branches on places: 2 -> none,
    // 4 -> "then repeat", 3 -> repeat the first (balance &) pull. Places outside
    // {2,3,4} degrade to a humanized count with no tail (never throws, unlike
    // ContraDB's `throw_up`).
    'square_through': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final swho = r._displaySubject(params['who'], dialect);
      final swho2 = r._displaySubject(params['who2'], dialect);
      final placesRaw = params['places'];
      final placeWord = placesRaw == 2
          ? 'two'
          : placesRaw == 3
          ? 'three'
          : placesRaw == 4
          ? 'four'
          : placesRaw == '*'
          ? '*'
          : placesRaw is num
          ? _formatNumber(placesRaw)
          : _displayScalar(placesRaw);
      final bal = params['balance'] == true
          ? _renderPrefix('balance', verbose)
          : '';
      final hand = _displayScalar(params['hand']);
      final hand2 = params['hand'] == 'left'
          ? 'right'
          : params['hand'] == '*'
          ? '*'
          : 'left';
      String pull(String who, String balPrefix, String h) =>
          [who, balPrefix, 'pull by', h].where((s) => s.isNotEmpty).join(' ');
      final seq = <String>[
        pull(swho, bal, hand),
        'then ${pull(swho2, '', hand2)}',
      ];
      if (placesRaw == 3) {
        seq.add('then ${pull(swho, bal, hand)}');
      } else if (placesRaw == 4) {
        seq.add('then repeat');
      }
      return '$move $placeWord - ${seq.join(', ')}';
    },
    // ContraDB `heyWords`: words(sfirst_pass, "start", indefiniteArticleFor(mp),
    // mp, "-", sshoulder, first_place, comma, other_sshoulder, second_place,
    // uses_until && "-", uses_until && shey_length, rico_string). mp (main move
    // phrase) = words(sdir2, [shey_length,] smove). Shoulders render TERSE
    // ("rights"/"lefts") with the second the inverse of the first; the pair pass
    // is "in center", the other "on ends". `full`/`half` name the length inline;
    // `lessThanHalf`/`betweenHalfAndFull` instead append "- until someone meets
    // [the second time]", or "- until <meetTarget> meet[ the second time]" when
    // a partial hey names its `meetTarget` pair (issue #576). A non-`across` dir prefixes the phrase. Ricochet flags
    // add " - <who> ricochet[ first time| second time], …". Because the base
    // line now carries the length, [_summarySuffix] no longer appends "(half)".
    'hey': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final pass1 = params['pass1'];
      final pass2 = params['pass2'];
      final sfirst = r._displaySubject(pass1, dialect);
      final length = params['length'];
      final dir = params['dir'];
      final sdir2 = (dir == 'across' || dir == null) ? '' : _displayScalar(dir);
      final usesUntil =
          length == 'lessThanHalf' || length == 'betweenHalfAndFull';
      final lengthWord = length == 'half'
          ? 'half'
          : length == 'full'
          ? 'full'
          : length == '*'
          ? '*'
          : usesUntil
          ? ''
          : _displayScalar(length);
      final mainPhrase = [
        sdir2,
        lengthWord,
        move,
      ].where((s) => s.isNotEmpty).join(' ');
      final article = _indefiniteArticle(mainPhrase);
      final sh = params['shoulder'];
      final terse = _terseShoulder(sh);
      final otherTerse = _terseShoulder(
        sh == 'right'
            ? 'left'
            : sh == 'left'
            ? 'right'
            : sh,
      );
      final firstIsPair = _isPairToken(pass1);
      final firstPlace = firstIsPair ? 'in center' : 'on ends';
      final secondPlace = firstIsPair ? 'on ends' : 'in center';
      final shoulderClause = [
        if (terse.isNotEmpty) '$terse $firstPlace',
        if (otherTerse.isNotEmpty) '$otherTerse $secondPlace',
      ].join(', ');
      // issue #576: name WHICH pair you run until you meet, when a partial
      // length has a set `meetTarget`. Allow-listed against the taxonomy spec's
      // choices so a tolerantly-decoded/unknown token falls back to the generic
      // "someone meets" wording rather than injecting arbitrary text. Mirrors
      // ContraDB `stringParamHeyLength`: a named subject reads "until X meet[
      // the second time]" (bare "meet"), the unspecified case "until someone
      // meets[ the second time]".
      final meetTarget = params['meetTarget'];
      // Allow-list the target: prefer the taxonomy spec's explicit `choices`,
      // and — should a MoveDef ever omit them — fall back to the shared dancer
      // vocabulary rather than accepting arbitrary strings, so an unknown /
      // tolerantly-decoded token still degrades to the generic "someone"
      // wording instead of being injected verbatim.
      final meetChoices =
          def.params['meetTarget']?.choices ?? ParamVocab.dancerSets;
      final namedTarget =
          meetTarget is String &&
              meetTarget != ParamVocab.unspecified &&
              meetChoices.contains(meetTarget)
          ? r._displayGroup(meetTarget, dialect)
          : '';
      final untilSubject = namedTarget.isNotEmpty ? namedTarget : 'someone';
      final untilVerb = namedTarget.isNotEmpty ? 'meet' : 'meets';
      final untilClause = length == 'lessThanHalf'
          ? 'until $untilSubject $untilVerb'
          : length == 'betweenHalfAndFull'
          ? 'until $untilSubject $untilVerb the second time'
          : '';
      // Ricochets: pick the pair pass as the ricochet subject; odd-index flags
      // reference the inverted (other) pair, matching ContraDB `heyWords`.
      String center;
      if (_isPairToken(pass1)) {
        center = r._displaySubject(pass1, dialect);
      } else if (_isPairToken(pass2)) {
        center = r._displaySubject(pass2, dialect);
      } else {
        center = sfirst;
      }
      final inverted = _isPairToken(pass1)
          ? r._invertPair(pass1, dialect)
          : _isPairToken(pass2)
          ? r._invertPair(pass2, dialect)
          : center;
      final ricoFlags = [
        params['rico1'],
        params['rico2'],
        params['rico3'],
        params['rico4'],
      ];
      final ricoStrings = <String>[];
      for (var i = 0; i < ricoFlags.length; i++) {
        final flag = ricoFlags[i];
        if (flag == true || flag == '*') {
          final who = (i.isOdd) ? inverted : center;
          final time = length == 'half'
              ? ''
              : (i & 2) != 0
              ? ' second time'
              : ' first time';
          final verb = flag == '*' ? 'maybe ricochet' : 'ricochet';
          if (who.isNotEmpty) ricoStrings.add('$who $verb$time');
        }
      }
      final buffer = StringBuffer();
      if (sfirst.isNotEmpty) buffer.write('$sfirst ');
      buffer.write('start $article $mainPhrase');
      if (shoulderClause.isNotEmpty) buffer.write(' - $shoulderClause');
      if (usesUntil && untilClause.isNotEmpty) buffer.write(' - $untilClause');
      if (ricoStrings.isNotEmpty) {
        buffer.write(' - ${ricoStrings.join(', ')}');
      }
      return buffer.toString();
    },
    // ContraDB `dolphinHeyWords`: words(smove, "- start with", swho, "passing",
    // swhom, "by", sshoulder). `whom` is a single-dancer identity, rendered via
    // [_singleDancerLabel] ("first lark"); the shoulder renders in full
    // ("right shoulders").
    'dolphin_hey': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final swho = r._displaySubject(params['who'], dialect);
      final swhom = r._singleDancerLabel(params['whom'], dialect);
      final sh = params['shoulder'];
      final shoulder = sh == null
          ? ''
          : '${_humanize(sh.toString())} shoulders';
      final buffer = StringBuffer('$move - start with');
      if (swho.isNotEmpty) buffer.write(' $swho');
      buffer.write(' passing');
      if (swhom.isNotEmpty) buffer.write(' $swhom');
      buffer.write(' by');
      if (shoulder.isNotEmpty) buffer.write(' $shoulder');
      return buffer.toString();
    },
    // ContraDB `formLongWavesWords`: words(smove, "-", ssubject, "face in,",
    // invertPair(subject), "face out"). v21 (#295) extends it with the pair and
    // hand TCB states ("Balance long wave (NR, women face in)" = neighbors by
    // the right) and the trailing balance clause (#296). `who` keeps ContraDB's
    // meaning — the pair that faces IN — so no stored figure's meaning changes;
    // the hand clause is emitted ONLY when both `whom` and `hand` are stated
    // (they default to the `unspecified` sentinel, which renders as nothing),
    // so a ContraDB import renders as it did at v20. Consulted only when
    // `!forCanonical`, so `renderCanonical` stays byte-stable (dedupe/FTS).
    'form_long_waves': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final swho = r._displaySubject(params['who'], dialect);
      final other = r._invertPair(params['who'], dialect);
      final swhom = _isUnspecified(params['whom'])
          ? ''
          : r._displaySubject(params['whom'], dialect);
      final hand = _displayChoice(params['hand']);
      final holdClause = (swhom.isEmpty || hand.isEmpty)
          ? ''
          : '$swhom by the $hand';
      final body = [
        holdClause,
        '$swho facing in',
        '$other facing out',
      ].where((s) => s.isNotEmpty).join(', ');
      return '$move - $body${_balanceSuffix(params['balance'])}';
    },
    // ContraDB `formALongWaveWords`: branches on in/out/balance. in only ->
    // "<who> dance in to a long wave in the center"; out+in -> "<other> dance
    // out while <who> dance in…"; out only -> "<other> dance out[ & balance]";
    // neither -> "<who> form a long wave in the center". A truthy balance
    // appends " - balance the wave" (except the out-only branch, which uses
    // "& balance").
    'form_a_long_wave': (r, def, params, dialect, verbose, decimals) {
      final swho = r._displaySubject(params['who'], dialect);
      final other = r._invertPair(params['who'], dialect);
      final inFlag = params['in'] == true;
      final outFlag = params['out'] == true;
      final bal = params['balance'];
      final maybeBalance = bal == true
          ? ' - balance the wave'
          : bal == '*'
          ? ' - *'
          : '';
      if (outFlag) {
        if (inFlag) {
          return '$other dance out while $swho '
              'dance in to a long wave in the center$maybeBalance';
        }
        return '$other dance out'
            '${bal == true
                ? ' & balance'
                : bal == '*'
                ? ' & *'
                : ''}';
      }
      if (inFlag) {
        return '$swho dance in to a long wave in the center$maybeBalance';
      }
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      return '$swho $move in the center$maybeBalance';
    },
    // #290 product splits of the retired `form_an_ocean_wave` — OUR extensions
    // with no ContraDB `words()` analog (see docs/research/parity-fix-decisions
    // "our extensions/splits — leave as-is"), so the leading phrase is fixed
    // PRODUCT wording that intentionally diverges from the byte-stable canonical
    // (`form short waves` / `pass the ocean`). Center hand = the `centerHand`
    // param (default 'right'); side hand = its OPPOSITE (right<->left), mirroring
    // ContraDB's `sside_hand = stringParamHand(!center_hand)` derivation — never
    // hardcoded, so display tracks the data. Unknown/`*` centerHand best-effort
    // humanizes (never blank-drops, no dangling connective). v21 (#296) appends
    // the same " - and balance" clause `form_long_waves` uses, so a balanced
    // short wave no longer silently drops its balance. Consulted only when
    // `!forCanonical`, so `renderCanonical` stays byte-stable (dedupe/FTS).
    'form_short_waves': (r, def, params, dialect, verbose, decimals) {
      final scenter = r._displaySubject(params['center'], dialect);
      final ssides = r._displaySubject(params['sides'], dialect);
      final centerHandRaw = params['centerHand'];
      final centerHand = _displayScalar(centerHandRaw);
      final sideHand = centerHandRaw == 'right'
          ? 'left'
          : centerHandRaw == 'left'
          ? 'right'
          : _displayScalar(centerHandRaw);
      final centerClause = [
        scenter,
        centerHand.isEmpty ? '' : 'by the $centerHand',
        'in the center',
      ].where((s) => s.isNotEmpty).join(' ');
      final sideClause = [
        ssides,
        sideHand.isEmpty ? '' : 'by the $sideHand',
        'on the sides',
      ].where((s) => s.isNotEmpty).join(' ');
      final body = [
        centerClause,
        sideClause,
      ].where((s) => s.isNotEmpty).join(', ');
      final balance = _balanceSuffix(params['balance']);
      return body.isEmpty
          ? 'form short waves$balance'
          : 'form short waves - $body$balance';
    },
    // A non-default `dir` surfaces the diagonal word ("a right diagonal ocean
    // wave"), silent for the `across` default (ContraDB
    // `stringParamSetDirectionSilencingDefault('across')`); the indefinite
    // article tracks the resulting noun phrase. A truthy `balance` appends a
    // trailing " and balance" clause (product wording; not ContraDB's pre-dash
    // "& balance").
    'pass_the_ocean': (r, def, params, dialect, verbose, decimals) {
      final dirRaw = params['dir'];
      final dirWord = (dirRaw == null || dirRaw == 'across')
          ? ''
          : _humanize(dirRaw.toString());
      final noun = dirWord.isEmpty ? 'ocean wave' : '$dirWord ocean wave';
      final article = _indefiniteArticle(noun);
      final scenter = r._displaySubject(params['center'], dialect);
      final ssides = r._displaySubject(params['sides'], dialect);
      final centerHandRaw = params['centerHand'];
      final centerHand = _displayScalar(centerHandRaw);
      final sideHand = centerHandRaw == 'right'
          ? 'left'
          : centerHandRaw == 'left'
          ? 'right'
          : _displayScalar(centerHandRaw);
      final centerClause = [
        scenter,
        centerHand.isEmpty ? 'catch hands' : 'catch $centerHand hands',
        'in the center',
      ].where((s) => s.isNotEmpty).join(' ');
      final sideClause = [
        ssides,
        sideHand.isEmpty ? 'take hands' : 'take $sideHand hands',
        'on the sides',
      ].where((s) => s.isNotEmpty).join(' ');
      final balance = params['balance'] == true
          ? ' and balance'
          : params['balance'] == '*'
          ? ' and *'
          : '';
      final body = [
        centerClause,
        sideClause,
      ].where((s) => s.isNotEmpty).join(', ');
      final head = 'pass through to $article $noun';
      return body.isEmpty ? '$head$balance' : '$head - $body$balance';
    },
    // ContraDB `starWords`: `star <hand> [- <grip> -] <n> places`. The grip
    // clause appears between the hand and the count for the two non-`none`
    // grips ("- wrist grip -" and "- hands across -"; real ContraDB renders:
    // Al's Safeway Produce, Strange New Worlds, Sweet Vicki, Fun Dance for
    // Marjorie). `none` (the default / unspecified value) emits no clause so
    // a plain star is unchanged. The grip labels are fixed calling vocabulary;
    // an unexpected non-null grip humanizes (surfacing malformed data) rather
    // than silently vanishing. Emitted in ALL render paths including
    // `renderCanonical` since taxonomy v27 (issue #749 Gap B).
    'star': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final hand = _displayScalar(params['hand']);
      final placesRaw = params['places'];
      final places = placesRaw is int
          ? _formatPlaces(placesRaw)
          : _displayScalar(placesRaw);
      final grip = params['grip'];
      final gripClause = grip == 'none' || grip == null
          ? ''
          : grip == 'wristGrip'
          ? ' - wrist grip -'
          : grip == 'handsAcross'
          ? ' - hands across -'
          : ' - ${_humanize(grip.toString())} -';
      return [
        move,
        hand,
        if (gripClause.isNotEmpty) gripClause,
        places,
      ].where((s) => s.isNotEmpty).join(' ');
    },
    // `promenade.singleFile` (taxonomy v18 #634, updated v27 #749): a true
    // single-file promenade (nose-to-tail around the major set) differs
    // materially from the ordinary partnered promenade.
    //
    // DISPLAY (singleFile=true, since v27): "single file {move} {dir}" with
    // `who` DROPPED (it carries `everyone`, an importer artefact conveying no
    // choreographic information) and `dir` ALWAYS included (even when it
    // equals the `across` default) — matching the canonical form so display
    // and search stay aligned. "single file {move}" routes through
    // `_renderMoveName` so Dialect.moves overrides apply uniformly.
    //
    // DISPLAY (singleFile=false): the base line reproduces the existing
    // template expansion `{who} promenade {dir}` including the direction-
    // silencing rule for the `across` default (ContraDB parity).
    //
    // CANONICAL: handled by the `if (forCanonical)` block in `_render` (not
    // by this `_displayBaseRenderers` entry), which emits "single file
    // promenade {dir}" — `who` dropped, `dir` always present. The two forms
    // are asymmetric by design: the display path routes through this entry
    // (which uses `_renderMoveName` for dialect-aware move names), while the
    // canonical path uses the move id directly for stability.
    'promenade': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      if (params['singleFile'] == true) {
        // `who` is dropped (importer artefact; `everyone` has no
        // choreographic significance). `dir` always included (even `across`
        // default) so display matches what source stated and aligns with
        // the canonical form.
        final dirRaw = params['dir'];
        final dir = _displayScalar(dirRaw);
        return ['single file $move', dir].where((s) => s.isNotEmpty).join(' ');
      }
      final swho = r._subjectWho(params, dialect);
      // Re-apply the direction-silencing rule that the template-expansion path
      // uses for promenade (ContraDB `stringParamSetDirectionSilencingDefault`
      // 'across'): omit `dir` when it equals the taxonomy default.
      final dirRaw = params['dir'];
      final dirDefault = def.params['dir']?.defaultValue;
      final dir = (dirRaw == dirDefault) ? '' : _displayScalar(dirRaw);
      return [swho, move, dir].where((s) => s.isNotEmpty).join(' ');
    },
    // `circle.singleFile` (taxonomy v18 #634, reworded v27 #840): a single-
    // file circulation around the ring (ContraDB source: "promenade single file
    // around the circle N places"; TCB: "Single file promenade clockwise").
    //
    // DISPLAY (singleFile=true, since v27): prefix form "single file circle
    // {clockwise|counterclockwise} {places}" — `turn` maps to a spelled-out
    // spin direction (clockwise = left, counterclockwise = right, per contra
    // convention: circling left travels clockwise). The prefix reads naturally
    // as callers say it; the v26 suffix form ("circle … - single file") was a
    // deliberate minimal change in #805, superseded by this ruling.
    //
    // DISPLAY (singleFile=false): reproduces template `{move} {turn} {places}`.
    //
    // CANONICAL: handled by the `if (forCanonical)` block in `_render` — not
    // by this entry. Canonical uses a distinct form to include "circle" as a
    // searchable token despite phrasing as "promenade".
    'circle': (r, def, params, dialect, verbose, decimals) {
      final placesRaw = params['places'];
      final places = placesRaw is int
          ? _formatPlaces(placesRaw)
          : _displayScalar(placesRaw);
      if (params['singleFile'] == true) {
        // `turn` maps to spoken spin-direction words. Contra convention:
        // "circle left" travels clockwise; "circle right" counterclockwise.
        final turnRaw = params['turn'];
        final spinWord = turnRaw == 'left'
            ? 'clockwise'
            : turnRaw == 'right'
            ? 'counterclockwise'
            : _displayScalar(turnRaw); // tolerant-decode fallback
        final move = r._renderMoveName(
          def.id,
          def.displayName,
          params,
          dialect,
        );
        return [
          'single file $move',
          spinWord,
          places,
        ].where((s) => s.isNotEmpty).join(' ');
      }
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final turnRaw = params['turn'];
      final turn = _displayScalar(turnRaw);
      return [move, turn, places].where((s) => s.isNotEmpty).join(' ');
    },
    // pass_through (ContraDB `passThroughWords`): renders the shoulder ONLY when
    // it is not the default 'right' (right shoulders are implicit), and silences
    // the default 'along' direction — exactly matching ContraDB's behaviour.
    // `renderCanonical` keeps expanding `renderTemplate` (`{move} {dir}`) and is
    // unaffected; this entry handles the display path only.
    'pass_through': (r, def, params, dialect, verbose, decimals) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final shoulder = params['shoulder'];
      // Suppress the default 'right' shoulder; render 'left shoulders' / '* shoulders'
      // for any other value, matching ContraDB `stringParamShoulders` word forms.
      final shoulderClause = (shoulder is String && shoulder != 'right')
          ? '$shoulder shoulders'
          : '';
      final dir = params['dir'];
      // Silence the default 'along' direction (ContraDB set_direction_along).
      final dirClause = (dir is String && dir != 'along') ? _humanize(dir) : '';
      return [
        move,
        shoulderClause,
        dirClause,
      ].where((s) => s.isNotEmpty).join(' ');
    },
  };

  /// DISPLAY-ONLY: the four-dancer pairing tokens ContraDB's `dancerIsPair`
  /// treats as a "pair" for hey center/ends placement, mirroring
  /// [_invertPair]'s invert domain. Used by the `hey` base line to decide which
  /// pass dances "in center" vs "on ends".
  static const Set<String> _pairTokens = {
    'role1s',
    'role2s',
    'ones',
    'twos',
    'firstCorners',
    'secondCorners',
  };

  static bool _isPairToken(Object? value) =>
      value is String && _pairTokens.contains(value);

  /// DISPLAY-ONLY: the terse shoulder word for the `hey` base line, mirroring
  /// ContraDB `stringParamShouldersTerse` (right -> "rights", left -> "lefts",
  /// "*" -> "* shoulders"). A null value yields "" (no dangling clause); any
  /// other value is surfaced humanized rather than dropped (OWASP robustness).
  static String _terseShoulder(Object? value) {
    if (value == null) return '';
    switch (value) {
      case 'right':
        return 'rights';
      case 'left':
        return 'lefts';
      case '*':
        return '* shoulders';
      default:
        return _humanize(value.toString());
    }
  }

  /// DISPLAY-ONLY: the indefinite article ("a"/"an") for [phrase], mirroring
  /// ContraDB `indefiniteArticleFor` (vowel-initial -> "an", else "a").
  static String _indefiniteArticle(String phrase) {
    final trimmed = phrase.trimLeft();
    if (trimmed.isEmpty) return 'a';
    return 'aeiou'.contains(trimmed[0].toLowerCase()) ? 'an' : 'a';
  }

  /// Where the `balance` flag's "balance &" prefix sits relative to the base
  /// render, per each move's ContraDB `words` function word order (contradb
  /// `app/javascript/libfigure/figure.js` @13f38a5). Only source-verified
  /// ContraDB moves appear; moves whose ContraDB rendering embeds balance
  /// elsewhere (`square_through`, the wave moves) or that ContraDB does not
  /// model (`star_through`, a CallersBox extension) are intentionally absent so
  /// we never fabricate a prefix. The wave-formation moves in particular render
  /// their own balance inside their display base line (`form_long_waves` /
  /// `form_short_waves` append " - and balance"; `form_a_long_wave` and
  /// `pass_the_ocean` have always embedded it), so listing them here would
  /// double it — see [_balanceSuffix] and issue #296.
  static const Map<String, _BalancePlacement> _balancePlacement = {
    // `words(sbalance, smove)` / `words(sbal, smove, …)` — balance first.
    'petronella': _BalancePlacement.leading,
    'pull_by_direction': _BalancePlacement.leading,
    // `words(sbalance, swho2, smove, sdir)` — balance before the subject.
    'rory_o_more': _BalancePlacement.leading,
    // `words(sbal, smove, "-", details)` — balance first.
    'box_circulate': _BalancePlacement.leading,
    // `words(swho, sbal, smove, sspin)` — subject, then balance before move.
    'pull_by_dancers': _BalancePlacement.afterWho,
    // `words(swho, thand, sbalance, smove)` — subject, (hand,) then balance
    // before the move. Our terse '{who} {move}' template omits the hand
    // regardless of balance, so the hand omission is pre-existing base behavior;
    // the balance prefix is a strict addition, not a new divergence. The alias
    // `swat_the_flea` (target box_the_gnat) needs its own key because
    // `figure.move` is 'swat_the_flea' and it renders under its own name.
    'box_the_gnat': _BalancePlacement.afterWho,
    'swat_the_flea': _BalancePlacement.afterWho,
  };

  static String _humanize(String token) =>
      token.replaceAll(_camelBoundary, ' ').toLowerCase();
  static String _collapseSpaces(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _formatNumber(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  /// Formats a places count using caller vocabulary ("1 place", "4 places").
  static String _formatPlaces(int places) =>
      places == 1 ? '1 place' : '$places places';

  /// Formats a rotation in full turns using caller vocabulary.
  ///
  /// DISPLAY-ONLY [decimals]: when true, renders the amount as a plain decimal
  /// number (`0.75`, `1.5`, `2`) instead of the fraction glyphs (`¾`, `1½`,
  /// `twice`) — the opt-in "Show turns as decimals" preference (#368). This is
  /// a display-time transform only; [renderCanonical] never sets it, so the
  /// canonical (search/FTS/dedupe) text keeps the glyph form and stays
  /// byte-stable. The spoken [_formatRotationVerbose] path is intentionally
  /// unaffected (word fractions read better aloud).
  static String _formatRotation(num turns, {bool decimals = false}) {
    if (decimals) return _formatNumber(turns);
    if (turns == 1) return 'once';
    if (turns == 2) return 'twice';
    final whole = turns ~/ 1;
    final frac = turns - whole;
    final fracStr = frac == 0.25
        ? '¼'
        : frac == 0.5
        ? '½'
        : frac == 0.75
        ? '¾'
        : null;
    if (whole == 0) return fracStr ?? _formatNumber(turns);
    if (fracStr == null) return '$whole';
    return '$whole$fracStr';
  }

  /// Spoken-friendly rotation, free of the notation glyphs [_formatRotation]
  /// uses. Whole turns keep the caller words `once`/`twice`; mixed turns spell
  /// the fraction out (`one and a half times`); fractions of a single turn read
  /// as travel around the ring (`three quarters of the way`).
  static String _formatRotationVerbose(num turns) {
    final whole = turns ~/ 1;
    final frac = turns - whole;
    final fracWord = frac == 0.25
        ? 'a quarter'
        : frac == 0.5
        ? 'a half'
        : frac == 0.75
        ? 'three quarters'
        : null;
    if (frac == 0) {
      if (whole == 1) return 'once';
      if (whole == 2) return 'twice';
      return '$whole times';
    }
    if (whole == 0) {
      // A partial single turn: describe travel around the ring.
      switch (fracWord) {
        case 'a quarter':
          return 'a quarter of the way';
        case 'a half':
          return 'halfway';
        case 'three quarters':
          return 'three quarters of the way';
      }
      return _formatNumber(turns);
    }
    final wholeWord = _numberWord(whole);
    if (fracWord == null) {
      // A fraction outside the quarter-turn vocabulary (only reachable via
      // out-of-domain data): keep the numeric value rather than dropping it.
      return '${_formatNumber(turns)} times';
    }
    return '$wholeWord and $fracWord times';
  }

  /// Spelled-out fraction words for [ParamKind.fraction], avoiding the
  /// camelCase humanization ([_humanize] turns `threeQuarter` into
  /// `three quarter`) that reads awkwardly aloud.
  static String _formatFractionVerbose(String fraction) {
    switch (fraction) {
      case 'quarter':
        return 'a quarter';
      case 'half':
        return 'half';
      case 'threeQuarter':
        return 'three quarters';
      case 'full':
        return 'the whole way';
      default:
        return _humanize(fraction);
    }
  }

  /// Small whole-number words for spoken rotation counts (`one`, `two`, …),
  /// falling back to digits beyond the range figures ever use.
  static String _numberWord(int n) {
    const words = [
      'zero',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
    ];
    return (n >= 0 && n < words.length) ? words[n] : n.toString();
  }
}
