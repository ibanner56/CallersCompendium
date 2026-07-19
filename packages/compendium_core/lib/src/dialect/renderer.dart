import '../model/figure.dart';
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
  String render(Figure figure, Dialect dialect) => _render(figure, dialect);

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
  String renderSummary(Figure figure, Dialect dialect, {bool verbose = false}) {
    final base = _render(figure, dialect, verbose: verbose);
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
        // ContraDB renders `full`/`half` as a "half hey"/"full hey" phrase and
        // the partial lengths as a trailing "until…" clause. On screen the
        // half/full label is a compact parenthetical to avoid repeating "hey";
        // the spoken path expands to the full ContraDB phrase. The "until…"
        // clauses are identical in both paths.
        switch (params['length']) {
          case 'half':
            return verbose ? ', half hey' : ' (half)';
          case 'full':
            return verbose ? ', full hey' : ' (full)';
          case 'lessThanHalf':
            return ' until someone meets';
          case 'betweenHalfAndFull':
            return ' until someone meets the second time';
          default:
            return '';
        }
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
    bool forCanonical = false,
  }) {
    if (figure.isCustom) {
      final text = (figure.params['text'] as String?)?.trim() ?? '';
      return text.isEmpty ? customMove : renderFreeText(text, dialect);
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
    // stays byte-for-byte stable (the dedupe/FTS invariant).
    if (!forCanonical) {
      final displayBase = _displayBaseRenderers[def.id];
      if (displayBase != null) {
        return _collapseSpaces(
          displayBase(this, def, params, dialect, verbose),
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
      return _renderValue(
        name,
        params[name],
        def.params[name],
        dialect,
        verbose,
        forCanonical,
      );
    });
    return _collapseSpaces(rendered);
  }

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
  ///   star_promenade's role-subject omission).
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
  /// term (canonical token when unmapped), [Dialect.dancers] substitutions
  /// win next, then positional dancer sets read as the PR1 singular subject
  /// (`partners` → `partner`), else the token humanizes. Mirrors the
  /// display-path branch of [_renderValue]; never used by the canonical render.
  String _displayDancer(String token, Dialect dialect) {
    if (roleTokens.contains(token)) return _roleTerm(token, dialect);
    final substitution = dialect.dancers[token];
    if (substitution != null) return substitution;
    return _singularDancerSets[token] ?? _humanize(token);
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
  /// dialect's role term (canonical token when unmapped); [ParamKind.dancerSet]
  /// / [ParamKind.dancerPair] tokens use [Dialect.dancers] (else humanized);
  /// every other token (structural params such as `shoulder`, `direction`) is
  /// humanized. Under [Dialect.canonical] the result equals the plain humanized
  /// / canonical form.
  static String displayToken(String token, ParamSpec? spec, Dialect dialect) {
    if (roleTokens.contains(token)) return _roleTerm(token, dialect);
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
    bool forCanonical,
  ) {
    if (value == null) return '';
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
      return verbose ? _formatRotationVerbose(value) : _formatRotation(value);
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
  /// intentionally absent — it is out of PR1 scope. The canonical render is
  /// never affected (it keeps `pass through along`, `everyone down the hall
  /// forward`, etc.).
  static const Map<String, String> _silencedDefaultParams = {
    // ContraDB set_direction_along → silences default 'along'.
    'pass_through': 'dir',
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
  /// star_promenade's role-subject omission (ContraDB drops the gentlespoons
  /// subject there). This omission is NOT generalized to other role subjects.
  /// A non-default `who` still renders.
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
    // ContraDB `zigZagWords`: words(twho, "zig", sspin, "zag", return_sspin, …).
    // The zag direction is the mirror of the zig (`turn`) direction. ContraDB
    // omits the partners subject; per the ratified decision we instead surface
    // it as a trailing "with <subject>" (singular, per PR1). The ender clause is
    // appended separately by [_summarySuffix].
    'zig_zag': (r, def, params, dialect, verbose) {
      final turn = params['turn'] is String ? params['turn'] as String : 'left';
      final zag = turn == 'left'
          ? 'right'
          : turn == 'right'
          ? 'left'
          : turn;
      final who = params['who'];
      final swho = who is String ? r._displayDancer(who, dialect) : '';
      return 'zig $turn zag $zag with $swho';
    },
    // ContraDB `slice` has no `words` fn → `figureGenericWords` over its labels:
    // words(smove, sslide, sincrement, sreturn). `slice_increment` couple→"",
    // dancer→"one dancer" (`stringParamSliceIncrement`); `slice_return`
    // straight→"and straight back", diagonal→"and diagonal back", none→""
    // (`stringParamSliceReturn`).
    'slice': (r, def, params, dialect, verbose) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final slide = params['slice'] is String
          ? params['slice'] as String
          : 'left';
      final byWord = params['by'] == 'dancer' ? 'one dancer' : '';
      final ret = params['return'];
      final retWord = ret == 'straight'
          ? 'and straight back'
          : ret == 'diagonal'
          ? 'and diagonal back'
          : '';
      return '$move $slide $byWord $retWord';
    },
    // ContraDB `madRobinWords`: words(smove, tangle, comma, srole, "in front"),
    // tangle = angle !== 360 && sangle + " around". Our `turn` is a rotation
    // (1.0 == 360° == once), so the "<turn> around" clause is shown only for a
    // non-default turn (formatted via our rotation vocabulary — an approximation
    // of ContraDB's degrees wording).
    'mad_robin': (r, def, params, dialect, verbose) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final turn = params['turn'];
      final around = (turn is num && turn != 1.0)
          ? ' ${verbose ? _formatRotationVerbose(turn) : _formatRotation(turn)} around'
          : '';
      final who = params['who'];
      final swho = who is String ? r._displayDancer(who, dialect) : '';
      return '$move$around, $swho in front';
    },
    // ContraDB `revolvingDoorWords`: words(smove, " - ", ssubject, "take",
    // shand, "hands and drop off", sobject, "on other side"). The subject
    // (role2s) stays a plural role term; the object (partners) singularizes per
    // PR1. This base line already carries the drop-off outcome, so
    // [_summarySuffix] no longer appends its own clarifier.
    'revolving_door': (r, def, params, dialect, verbose) {
      final move = r._renderMoveName(def.id, def.displayName, params, dialect);
      final who = params['who'];
      final swho = who is String ? r._displayDancer(who, dialect) : '';
      final hand = params['hand'] is String ? params['hand'] as String : '';
      final whom = params['whom'];
      final swhom = whom is String ? r._displayDancer(whom, dialect) : '';
      return '$move - $swho take $hand hands and drop off $swhom on other side';
    },
  };

  /// Where the `balance` flag's "balance &" prefix sits relative to the base
  /// render, per each move's ContraDB `words` function word order (contradb
  /// `app/javascript/libfigure/figure.js` @13f38a5). Only source-verified
  /// ContraDB moves appear; moves whose ContraDB rendering embeds balance
  /// elsewhere (`square_through`, the wave moves) or that ContraDB does not
  /// model (`star_through`, a CallersBox extension) are intentionally absent so
  /// we never fabricate a prefix.
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
  static String _formatRotation(num turns) {
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
