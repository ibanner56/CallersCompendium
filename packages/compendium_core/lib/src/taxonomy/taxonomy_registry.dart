import 'package:meta/meta.dart';

import '../model/enums.dart';
import 'contra_taxonomy.dart';
import 'ecd_taxonomy.dart';
import 'square_taxonomy.dart';
import 'taxonomy.dart';

/// The prefix every stored move ID of a dance form's own taxonomy carries
/// (ADR-006 §5.1). Contra has none: its IDs predate the other forms, and an
/// ID with no prefix is a contra move in a dance of any form.
///
/// A form whose own taxonomy is registered must have an entry here. ECD's
/// `ecd_` is decided in ADR-006 §5.1, and the squares' `sq_` in ADR-007 §5.1
/// (accepted by the maintainer, 15 November 2026).
const Map<DanceForm, String> danceFormMovePrefixes = {
  DanceForm.ecd: 'ecd_',
  DanceForm.square: 'sq_',
};

/// Every dance form's taxonomy, and which one resolves a move.
///
/// A [base] taxonomy (contra's) owns every move ID with no prefix. Each other
/// form may add a taxonomy of its own, whose move and alias IDs all carry
/// that form's prefix ([danceFormMovePrefixes]). Because the prefixes keep
/// the forms' IDs apart, a stored ID names the taxonomy that defines it: an
/// `ecd_` ID resolves through ECD's taxonomy, and an ID with no prefix
/// resolves through contra's, in an ECD dance as in any other (ADR-006
/// §5.1). That is how an ECD dance imported before ECD had a taxonomy keeps
/// its contra moves (ADR-006 §12.1, F5).
///
/// Two lookups follow from that:
///
/// - [forForm] is the taxonomy a dance of one form is edited, parsed and
///   checked with: the form's own taxonomy laid over [base]. Its own moves
///   come first, so where both forms name a figure alike (a poussette, a
///   star) a lookup by name that keeps the first match finds the form's own.
///   A form with no taxonomy of its own gets [base] itself, so its dances
///   behave as they always have.
/// - [anyForm] lays every registered form over [base]. It resolves and
///   renders a stored figure from a dance of any form, so code that reads
///   figures without one dance in hand (a program of mixed forms, the
///   repository, sync) needs no form to do it. It is not a vocabulary to
///   parse a dance's text with: use [forForm] for that.
///
/// Built for any number of forms (ADR-006 §12.1, F6), so squares can register
/// theirs the same way.
@immutable
final class TaxonomyRegistry {
  /// Registers [base] and each form's own taxonomy in [forms].
  ///
  /// Throws [ArgumentError] when a [base] ID carries another form's prefix,
  /// a taxonomy in [forms] is for [base]'s form, two are for the same form, a form has no prefix in
  /// [danceFormMovePrefixes], or one of its move or alias IDs lacks that
  /// prefix.
  TaxonomyRegistry({required this.base, Iterable<Taxonomy> forms = const []})
    : _own = _validated(base, forms) {
    _forForm = Map.unmodifiable({
      for (final form in DanceForm.values)
        form: switch (_own[form]) {
          null => base,
          final own when identical(own, base) => base,
          final own => _layered(
            form: form,
            version: own.version,
            label: '${form.name} taxonomy',
            layers: [own, base],
          ),
        },
    });
    final overlays = [
      for (final form in DanceForm.values)
        if (form != base.form && _own[form] != null) _own[form]!,
    ];
    anyForm = overlays.isEmpty
        ? base
        : _layered(
            form: base.form,
            version: base.version,
            label: 'taxonomy of every dance form',
            layers: [base, ...overlays],
          );
  }

  /// The taxonomy that owns every move ID with no form prefix: contra's.
  final Taxonomy base;

  /// Each form's own taxonomy, [base] included under its own form.
  final Map<DanceForm, Taxonomy> _own;

  late final Map<DanceForm, Taxonomy> _forForm;

  /// Every registered taxonomy laid over [base]: resolves and renders a
  /// stored move ID of any form. Identical to [base] while no other form is
  /// registered.
  late final Taxonomy anyForm;

  /// The taxonomy a dance of [form] is edited, parsed and checked with:
  /// [form]'s own taxonomy over [base], or [base] alone when [form] has none
  /// yet.
  Taxonomy forForm(DanceForm form) => _forForm[form]!;

  /// [form]'s own taxonomy, without [base] under it, or null when the app
  /// ships none for [form]. For [base]'s form this is [base].
  Taxonomy? ownTaxonomy(DanceForm form) => _own[form];

  /// The form whose taxonomy defines [moveId], read from its prefix: [base]'s
  /// form for an ID with no registered prefix (ADR-006 §5.1).
  DanceForm formOfMoveId(String moveId) {
    for (final MapEntry(key: form, value: prefix)
        in danceFormMovePrefixes.entries) {
      if (moveId.startsWith(prefix)) return form;
    }
    return base.form;
  }

  static Map<DanceForm, Taxonomy> _validated(
    Taxonomy base,
    Iterable<Taxonomy> forms,
  ) {
    for (final id in [...base.moves.keys, ...base.aliases.keys]) {
      for (final MapEntry(key: form, value: prefix)
          in danceFormMovePrefixes.entries) {
        if (id.startsWith(prefix)) {
          throw ArgumentError(
            '${base.form.name} move "$id" carries ${form.name}\'s '
            '"$prefix" prefix',
          );
        }
      }
    }
    final own = <DanceForm, Taxonomy>{base.form: base};
    for (final taxonomy in forms) {
      final form = taxonomy.form;
      if (own.containsKey(form)) {
        throw ArgumentError(
          'more than one taxonomy is registered for ${form.name}',
        );
      }
      final prefix = danceFormMovePrefixes[form];
      if (prefix == null) {
        throw ArgumentError('${form.name} has no move ID prefix');
      }
      for (final id in [...taxonomy.moves.keys, ...taxonomy.aliases.keys]) {
        if (!id.startsWith(prefix)) {
          throw ArgumentError(
            '${form.name} move "$id" does not carry the "$prefix" prefix',
          );
        }
      }
      own[form] = taxonomy;
    }
    return Map.unmodifiable(own);
  }

  static Taxonomy _layered({
    required DanceForm form,
    required int version,
    required String label,
    required List<Taxonomy> layers,
  }) => Taxonomy(
    version: version,
    form: form,
    label: label,
    moves: [for (final layer in layers) ...layer.moves.values],
    aliases: [for (final layer in layers) ...layer.aliases.values],
  );
}

/// The taxonomies this build ships: contra's, which owns every unprefixed
/// move ID, English Country Dance's ([ecdTaxonomy], ADR-006), and the
/// traditional squares' ([squareTaxonomy], ADR-007).
final TaxonomyRegistry shippedTaxonomies = TaxonomyRegistry(
  base: contraTaxonomy,
  forms: [ecdTaxonomy, squareTaxonomy],
);
