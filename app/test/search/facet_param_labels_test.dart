import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit coverage for the figure-param LABELLING helpers (issue #741).
///
/// Deliberately separate from `facet_param_choices_test.dart`, which covers
/// which values a param admits. That is a domain question settled by the
/// taxonomy; this is a presentation question settled by the active dialect.
/// Conflating them is what let the search facet render raw canonical tokens
/// (`role1s`, "Any meetTarget") while the dance editor rendered the very same
/// spec as "larks" / "meet target".
///
/// The widget-level proof that these reach the UI lives in
/// `test/widgets/advanced_query_builder_test.dart` and
/// `test/widgets/figure_param_editors_test.dart`; these are the cheap, exact
/// checks of the functions themselves.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  final larksRobins = Dialect.larksRobins;
  final gentsLadies = Dialect(
    name: 'Gents/Ladies',
    roles: const {
      'role1': RoleTerm('gent'),
      'role2': RoleTerm('lady', plural: 'ladies'),
    },
  );

  const dancerSpec = ParamSpec(
    ParamKind.dancerSet,
    defaultValue: ParamVocab.unspecified,
    choices: ['role1s', 'role2s', 'neighbors', ParamVocab.unspecified],
  );

  group('figureParamKeyLabel', () {
    test('splits camelCase so no internal identifier reaches the UI', () {
      expect(figureParamKeyLabel('meetTarget'), 'meet target');
      expect(figureParamKeyLabel('endFacing'), 'end facing');
    });

    test('leaves a single-word key alone', () {
      expect(figureParamKeyLabel('whom'), 'whom');
      expect(figureParamKeyLabel('shoulder'), 'shoulder');
    });
  });

  group('figureParamChoiceLabel', () {
    test('renders role tokens in the active dialect', () {
      expect(
        figureParamChoiceLabel(l10n, dancerSpec, larksRobins, 'role1s'),
        'larks',
      );
      expect(
        figureParamChoiceLabel(l10n, dancerSpec, gentsLadies, 'role1s'),
        'gents',
      );
      expect(
        figureParamChoiceLabel(l10n, dancerSpec, gentsLadies, 'role2s'),
        'ladies',
      );
    });

    test('renders the canonical token under the canonical dialect', () {
      expect(
        figureParamChoiceLabel(l10n, dancerSpec, Dialect.canonical, 'role1s'),
        'role1s',
      );
    });

    test('humanizes non-role dancer tokens', () {
      expect(
        figureParamChoiceLabel(l10n, dancerSpec, larksRobins, 'prevNeighbors'),
        'prev neighbors',
      );
    });

    test('humanizes structural vocabulary and ignores the dialect', () {
      const directionSpec = ParamSpec(ParamKind.direction, defaultValue: 'in');
      for (final dialect in [larksRobins, gentsLadies, Dialect.canonical]) {
        expect(
          figureParamChoiceLabel(l10n, directionSpec, dialect, 'rightDiagonal'),
          'right diagonal',
        );
      }
    });

    test('labels the sentinel as the unstated state, never as its token', () {
      // Only reachable when labelling a param's CURRENT state — the sentinel is
      // filtered out of every pickable list. Shown as prose because the raw
      // token means nothing to a caller.
      final label = figureParamChoiceLabel(
        l10n,
        dancerSpec,
        larksRobins,
        ParamVocab.unspecified,
      );
      expect(label, l10n.danceEditorParamNotStated);
      expect(label, isNot(ParamVocab.unspecified));
    });

    test('a spec that does NOT admit the sentinel shows the word verbatim', () {
      // A free-`text` param whose value happens to be the word "unspecified" is
      // real user content, not the sentinel, and must not be relabelled.
      const textSpec = ParamSpec(ParamKind.text, defaultValue: '');
      expect(
        figureParamChoiceLabel(
          l10n,
          textSpec,
          larksRobins,
          ParamVocab.unspecified,
        ),
        ParamVocab.unspecified,
      );
    });
  });

  group('figureParamSelectableChoices', () {
    test('drops the sentinel and keeps order', () {
      expect(figureParamSelectableChoices(dancerSpec.choices!), [
        'role1s',
        'role2s',
        'neighbors',
      ]);
    });

    test('leaves a domain without the sentinel untouched', () {
      // Compared against `ParamVocab.sides` itself, not a literal
      // `['right', 'left']`. The property under test is PASS-THROUGH — a domain
      // carrying no sentinel comes back unchanged — and only this form states
      // it. A literal would pin today's contents of shared vocabulary this test
      // does not own, so adding a third side would fail here for a reason that
      // has nothing to do with the filter.
      //
      // Not in tension with the domain-CONTENT assertions elsewhere in the
      // suite, which spell their vocabularies out on purpose: those exist to
      // notice when a param's declared domain changes. Assert the property you
      // actually mean.
      expect(figureParamSelectableChoices(ParamVocab.sides), ParamVocab.sides);
    });

    test('can empty a domain that is nothing but the sentinel', () {
      // The facet renders no dropdown at all in this case: "Any <param>" alone
      // cannot constrain anything.
      expect(
        figureParamSelectableChoices(const [ParamVocab.unspecified]),
        isEmpty,
      );
    });

    test('does NOT narrow the domain the other consumers see', () {
      // The boundary of the #741 fix. `figureParamChoices` and
      // `ParamSpec.validate` are two of the three consumers of one domain
      // contract (#726 / #746); only the presentation edge filters. If this
      // ever inverts, the editor loses its ability to represent "not stated"
      // and starts fabricating values over it.
      expect(figureParamChoices(dancerSpec), contains(ParamVocab.unspecified));
      expect(dancerSpec.validate(ParamVocab.unspecified), isTrue);
      expect(paramAdmitsUnspecified(dancerSpec), isTrue);
    });

    test('paramAdmitsUnspecified is false without an explicit opt-in', () {
      const noChoices = ParamSpec(
        ParamKind.dancerSet,
        defaultValue: 'partners',
      );
      expect(paramAdmitsUnspecified(noChoices), isFalse);
      const narrowed = ParamSpec(
        ParamKind.dancerSet,
        defaultValue: 'partners',
        choices: ['partners', 'neighbors'],
      );
      expect(paramAdmitsUnspecified(narrowed), isFalse);
    });
  });
}
