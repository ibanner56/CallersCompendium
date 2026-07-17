import '../model/figure.dart';
import '../taxonomy/param_types.dart';
import '../taxonomy/taxonomy.dart';
import 'dialect.dart';
import 'substitution.dart';

/// The canonical role tokens recognized specially everywhere (rendering and
/// canonicalization). Singular and plural forms of the two contra roles.
const Set<String> roleTokens = {'role1', 'role2', 'role1s', 'role2s'};

final RegExp _placeholder = RegExp(r'\{(\w+)\}');
final RegExp _camelBoundary = RegExp(r'(?<=[a-z])(?=[A-Z])');

/// Renders figures to text in two flavors: canonical (dialect-free, feeds
/// search/FTS) and display (a chosen [Dialect] applied). Pure functions —
/// golden-tested.
class FigureRenderer {
  FigureRenderer(this.taxonomy);

  final Taxonomy taxonomy;

  /// Canonical text for [figure]: role tokens stay as `role1`/`role2`, no
  /// dialect. Used to build the search index.
  String renderCanonical(Figure figure) => _render(figure, Dialect.canonical);

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
  /// and zig-zag `ender`, and hey `length`. These params otherwise render as
  /// nothing (enders) or drop the length, so a caller reading the summary loses
  /// information ContraDB's params→description rendering surfaces.
  ///
  /// This is a display-only path layered on top of [_render]; [renderCanonical]
  /// (which feeds storage/search/dedupe) never calls it and stays byte-for-byte
  /// unchanged. The appended wording is copied verbatim from ContraDB's
  /// `libfigure` (`param.js` string functions), except `bendTheLine` — a
  /// CallersBox-origin ender not present in ContraDB — which uses CallersBox's
  /// own "bend the line" phrasing (see `docs/research/callersbox.md`). The
  /// modifier phrases are fixed structural vocabulary (not role/move tokens),
  /// so they are dialect-independent; the dialect-aware part is the [_render]
  /// base, which already maps roles and move names under [dialect].
  String renderSummary(Figure figure, Dialect dialect, {bool verbose = false}) {
    final base = _render(figure, dialect, verbose: verbose);
    if (figure.isCustom) return base;
    if (taxonomy.resolve(figure.move) == null) return base;
    final params = taxonomy.effectiveParams(figure);
    final suffix = _summarySuffix(figure.move, params);
    return suffix.isEmpty ? base : '$base$suffix';
  }

  /// The trailing secondary-modifier clause (connective included) appended by
  /// [renderSummary] for [moveId], or the empty string when nothing is
  /// surfaced. Only non-`none` enders and set hey lengths produce a clause.
  String _summarySuffix(String moveId, Map<String, Object?> params) {
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
      case 'hey':
        // ContraDB renders `full`/`half` as a "half hey"/"full hey" phrase and
        // the partial lengths as a trailing "until…" clause; the terse template
        // can't reorder, so the exact wording is appended after the base line.
        final length = params['length'];
        final label = length is String ? _heyLengthLabels[length] : null;
        return label == null ? '' : ' - $label';
      default:
        return '';
    }
  }

  String _render(Figure figure, Dialect dialect, {bool verbose = false}) {
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
        return _renderMoveName(def.id, displayName, params, dialect);
      }
      if (pinned.containsKey(name)) return '';
      return _renderValue(
        name,
        params[name],
        def.params[name],
        dialect,
        verbose,
      );
    });
    return _collapseSpaces(rendered);
  }

  String _renderMoveName(
    String moveId,
    String displayName,
    Map<String, Object?> params,
    Dialect dialect,
  ) => _applyMoveSubstitution(dialect.moves[moveId], displayName, params);

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

  /// ContraDB `libfigure` hey-length wording (`param.js` `stringParamHeyLength`
  /// + `heyWords`): `full`/`half` read as a "full hey"/"half hey" phrase, the
  /// partial lengths as a trailing "until…" clause.
  static const Map<String, String> _heyLengthLabels = {
    'half': 'half hey',
    'full': 'full hey',
    'lessThanHalf': 'until someone meets',
    'betweenHalfAndFull': 'until someone meets the second time',
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
