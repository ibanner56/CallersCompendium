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

  String _render(Figure figure, Dialect dialect) {
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
    final rendered = def.renderTemplate.replaceAllMapped(_placeholder, (m) {
      final name = m[1]!;
      if (name == 'move') {
        return _renderMoveName(def.id, displayName, params, dialect);
      }
      return _renderValue(name, params[name], def.params[name], dialect);
    });
    return _collapseSpaces(rendered);
  }

  String _renderMoveName(
    String moveId,
    String displayName,
    Map<String, Object?> params,
    Dialect dialect,
  ) {
    final substitution = dialect.moves[moveId];
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
  ) {
    if (value == null) return '';
    if (value is String && roleTokens.contains(value)) {
      return _roleTerm(value, dialect);
    }
    if (spec?.kind == ParamKind.rotation && value is num) {
      return _formatRotation(value);
    }
    if (spec?.kind == ParamKind.places && value is int) {
      return _formatPlaces(value);
    }
    if (value is num) return _formatNumber(value);
    if (value is bool) return value ? name : '';
    return _humanize(value.toString());
  }

  String _roleTerm(String token, Dialect dialect) {
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
}
