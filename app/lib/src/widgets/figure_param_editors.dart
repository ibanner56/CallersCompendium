import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/touch_density.dart';
import '../theme/app_spacing.dart';
import 'app_dropdown_field.dart';
import 'multi_select_dropdown.dart';
import '../search/facet_labels.dart';
import 'bar_timing.dart';

// `humanizeToken` moved to `search/facet_labels.dart` (issue #741) so the dance
// editor and the Advanced-search facet share one labelling primitive. Re-exported
// here because this file was its original home and several call sites (and its
// unit test) import it from here.
export '../search/facet_labels.dart' show humanizeToken;

/// Concrete-value editors for a single figure parameter, driven by its
/// [ParamSpec] kind (`docs/design/figure-taxonomy.md`; `docs/design/ux.md` §3).
///
/// Unlike the search "has figure" row (which offers a nullable *Any*), these
/// editors always hold a concrete value — seeded from the taxonomy's effective
/// params — because a figure being transcribed has a definite value for each
/// named parameter. Every editor reports edits through `onChanged`.
class FigureParamEditor extends StatelessWidget {
  const FigureParamEditor({
    super.key,
    required this.keyPrefix,
    required this.paramKey,
    required this.spec,
    required this.value,
    required this.onChanged,
    required this.dialect,
    this.mixer = false,
    this.moveId,
    this.fractionAmountFollows = false,
    this.correctsValue = true,
  });

  /// Stem for the child widget's [ValueKey] (e.g. `figure-0`); the editor
  /// appends `-<paramKey>` so tests can target it.
  final String keyPrefix;
  final String paramKey;
  final ParamSpec spec;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  /// Active dialect used to label role/dancer choices (display-only; the stored
  /// value stays canonical). Structural params ignore it.
  final Dialect dialect;

  /// Whether the enclosing dance is a mixer (issue #732).
  ///
  /// When `false` (the default), the five mixer partner-series tokens
  /// ([ParamVocab.mixerPartnerSeries]) are suppressed from dancer-set/pair
  /// dropdowns — unless the figure already stores one of them as [value], in
  /// which case it is retained so no write-back is triggered. When `true`,
  /// every token in the domain is offered.
  ///
  /// Non-dancer-set params ignore this field entirely.
  final bool mixer;

  /// Move identity used only for display-specific parameter labels.
  final String? moveId;

  /// Whether picking a fraction of `other` here reveals an amount field (the
  /// dance editor's, #2120), so the choice reads "other amount…". Off
  /// elsewhere, where a legacy `other` is shown with nothing after it.
  final bool fractionAmountFollows;

  /// Whether a dropdown corrects a value outside its choices by writing a
  /// valid one back after the frame. Off where the value is the user's
  /// standing choice and an invalid one must stay visible as such, not be
  /// replaced by opening the editor: a compound placeholder's argument, whose
  /// compound may have changed since it was chosen (#709). Off, such a value
  /// shows as nothing selected and is left as it is.
  final bool correctsValue;

  String get _key => '$keyPrefix-$paramKey';

  /// A dropdown item's label. Picking a fraction of `other` reveals the
  /// amount stepper (#2120) in the dance editor, on a move that has one, so
  /// there it reads "other amount…".
  String _choiceLabel(AppLocalizations l10n, String choice) =>
      spec.kind == ParamKind.fraction &&
          choice == 'other' &&
          fractionAmountFollows &&
          _moveHasFractionAmount
      ? l10n.figureParamFractionOtherPick
      : figureParamChoiceLabel(l10n, spec, dialect, choice);

  /// Whether [moveId] is a shipped move with a fraction amount (#2120).
  bool get _moveHasFractionAmount =>
      moveId != null &&
      (shippedTaxonomies.anyForm
              .resolve(moveId!)
              ?.params
              .containsKey(fractionAmountParam) ??
          false);

  /// Whether this field is that move's amount, not a rotation of a figure of
  /// the user's own that happens to be named `amount`.
  bool get _isFractionAmount =>
      paramKey == fractionAmountParam && _moveHasFractionAmount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (spec.kind) {
      case ParamKind.dancerSet:
      case ParamKind.dancerPair:
        final rawDomain = spec.choices ?? ParamVocab.dancerSets;
        return _dropdown(
          context,
          offerableDancerSets(rawDomain, mixer: mixer, currentValue: value),
        );
      case ParamKind.dancerList:
        return _DancerListDropdown(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          domain: [
            for (final token in figureParamSelectableChoices(
              spec.choices ?? ParamVocab.dancerSets,
            ))
              // A mixer's partner series only in a mixer, or when the list
              // already holds it.
              if (mixer ||
                  !ParamVocab.mixerPartnerSeries.contains(token) ||
                  (value is List && (value! as List).contains(token)))
                token,
          ],
          value: value,
          labelOf: (token) =>
              figureParamChoiceLabel(l10n, spec, dialect, token),
          onChanged: onChanged,
        );
      case ParamKind.handedness:
      case ParamKind.shoulder:
        return _dropdown(context, spec.choices ?? ParamVocab.sides);
      case ParamKind.spinDirection:
        return _dropdown(context, spec.choices ?? ParamVocab.spins);
      case ParamKind.fraction:
        return _dropdown(context, spec.choices ?? ParamVocab.fractions);
      case ParamKind.direction:
        return _dropdown(context, spec.choices ?? ParamVocab.directions);
      case ParamKind.choice:
        return _dropdown(context, spec.choices ?? const []);
      case ParamKind.rotation when _isFractionAmount:
        // The amount an `other` fraction states (#2120). Shown only while the
        // fraction is `other`, and picking `other` seeds it, so an `other`
        // with none is a row from before taxonomy v39: it asks for an amount,
        // in the error colour, and nothing is filled in until the caller
        // steps one. It starts past `full` and offers no Clear: an amount a
        // named fraction states is that fraction, and `other` always states
        // one.
        final amount = isFractionAmount(value) ? value! as num : null;
        return _RotationStepper(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          value: amount,
          min: _fractionAmountMin,
          firstStep: kFractionOtherSeedAmount.toDouble(),
          needsChoice: amount == null,
          formatValue: (n) =>
              l10n.danceEditorFractionAmountValue(_RotationStepper._format(n)),
          onChanged: onChanged,
        );
      case ParamKind.rotation:
        // A rotation spec may opt into the `unspecified` sentinel by listing it
        // in `choices` (taxonomy v22's `gate.turn`: ContraDB's gate states no
        // turn amount at all). For those, a non-numeric value means the source
        // stated NOTHING and must render as an explicit unset state — showing
        // the old `1.0` fallback would display "1 turn" for a figure that never
        // claimed one, and the first stepper nudge would silently promote that
        // fabricated number into stored data.
        final allowsUnset =
            spec.choices?.contains(ParamVocab.unspecified) ?? false;
        // A value left as it is (see [correctsValue]) that the spec rejects —
        // missing, a word other than the admitted sentinel, or an amount
        // outside the domain — is shown as needing a choice, never as "not
        // stated" or as an amount, as the dropdown does.
        final needsChoice = !correctsValue && !spec.validate(value);
        return _RotationStepper(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          value: needsChoice
              ? null
              : (value is num ? value! as num : (allowsUnset ? null : 1.0)),
          allowsUnset: allowsUnset,
          needsChoice: needsChoice,
          onChanged: onChanged,
        );
      case ParamKind.beats:
        // A step of a sequence that states its own span may be left with no
        // timing of its own ([SequenceSpanScope]).
        final allowsUntimed = SequenceSpanScope.allowsUntimedOf(context);
        // An English dance is timed in bars (ADR-006 §5.5).
        if (BarTimingScope.maybeOf(context) case final bars?) {
          return BarsField(
            fieldKey: _key,
            label: l10n.danceEditorBarsLabel,
            beats: value is int ? value! as int : null,
            timing: bars.timing,
            startBeat: FigureStartScope.startOf(context),
            allowsUntimed: allowsUntimed,
            onChanged: onChanged,
          );
        }
        // A square's, in beats (ADR-007 Q10).
        if (allowsUntimed) {
          return BeatsField(
            fieldKey: _key,
            label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
            beats: value is int ? value! as int : null,
            onChanged: onChanged,
          );
        }
        return _IntField(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          value: value is int ? value! as int : 0,
          min: 0,
          max: 64,
          onChanged: onChanged,
        );
      case ParamKind.number:
        return _IntField(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          value: value is int
              ? value! as int
              : (spec.defaultValue is int ? spec.defaultValue! as int : 0),
          min: 0,
          max: 99,
          onChanged: onChanged,
        );
      case ParamKind.places:
        // A places spec may opt into the `unspecified` sentinel by listing it
        // in `choices` (taxonomy v39: `circle.places`, `star.places`). For
        // those an empty field is "not stated", not an error, and stores the
        // sentinel; showing the default instead would claim a distance the
        // dance never gave.
        final placesUnset =
            spec.choices?.contains(ParamVocab.unspecified) ?? false;
        return _IntField(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          value: value is int
              ? value! as int
              : (placesUnset && value == ParamVocab.unspecified)
              ? null
              : (spec.defaultValue is int ? spec.defaultValue! as int : 1),
          min: 1,
          max: 10,
          allowsUnset: placesUnset,
          onChanged: onChanged,
        );
      case ParamKind.text:
        return _TextParamField(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          value: value is String ? value! as String : '',
          onChanged: onChanged,
        );
      case ParamKind.flag:
        return _FlagSwitch(
          fieldKey: _key,
          label: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
          value: value is bool ? value! as bool : false,
          onChanged: onChanged,
        );
    }
  }

  Widget _dropdown(BuildContext context, List<String> domain) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // The sentinel is a valid VALUE but never a pickable OPTION (issue #741):
    // "the source stated nothing" is a fact about provenance, not a
    // choreographic value a transcriber chooses. It stays in the domain —
    // `ParamSpec.validate` accepts it and the renderer emits it — and is shown
    // below as the field's current state, with a Clear button to return to it.
    final selectable = figureParamSelectableChoices(domain);
    final admitsUnstated = paramAdmitsUnspecified(spec);

    // Reconcile the displayed selection with the model: prefer the current
    // value when it is pickable, else the spec default (if pickable), else the
    // first choice. When we fall back, push that value back to the draft after
    // the frame so a saved-but-invalid value can't linger behind the UI.
    //
    // `null` here means "not stated" and is a legitimate resting state, NOT a
    // substitution target — which is why a param that admits the sentinel falls
    // back to `null` instead of a concrete value, and why `null` never writes
    // back a fabricated value. Without that, merely OPENING the editor on a hey
    // whose target was never stated would walk `value (unspecified) ->
    // specDefault (unspecified) -> selectable.first` and silently fabricate
    // `role1s` into the draft. Both rungs miss because `hey.meetTarget`'s own
    // `defaultValue` IS the sentinel, so this is the common path, not an edge
    // case — and it is exactly the invention issues #724 and #726 exist to
    // prevent. Specs that do not admit the sentinel keep the original behaviour
    // untouched.
    final specDefault = spec.defaultValue;
    final current = !correctsValue
        // Shown as it is when it is a choice, else as nothing selected.
        ? (value is String && selectable.contains(value)
              ? value! as String
              : null)
        : (admitsUnstated && value == ParamVocab.unspecified)
        ? null
        : (value is String && selectable.contains(value))
        ? value! as String
        : (specDefault is String && selectable.contains(specDefault))
        ? specDefault
        : (admitsUnstated
              ? null
              : (selectable.isNotEmpty ? selectable.first : null));
    if (!correctsValue) {
      // Nothing is written back.
    } else if (current != null && current != value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(current));
    } else if (admitsUnstated &&
        current == null &&
        value != null &&
        value != ParamVocab.unspecified) {
      // An out-of-domain value with no valid substitute available: when a
      // sentinel-admitting spec defaults to the sentinel, the default rung
      // misses too and the chain lands on `null`. (Two sentinel-admitting specs
      // have concrete defaults: `mad_robin.who` and `promenade.turn`. For
      // either, the default rung above does NOT miss, `current` lands on the
      // concrete default instead of `null`, and this branch is simply never
      // reached. That is the correct, desired self-healing behaviour for a
      // concrete default: an out-of-domain value corrects to that declared
      // default, the same way any ordinary non-sentinel spec does, rather than
      // to "not stated".)
      // Normalise the draft to the sentinel rather than leaving it
      // holding a token the field is already displaying as "not stated" —
      // that mismatch would keep rendering the bad token into the figure text
      // while offering no single-step way to fix it, since Clear is hidden
      // whenever nothing is selected. This stores exactly what is displayed,
      // so it corrects invalid data rather than inventing a value, and it
      // keeps the "invalid values can't linger behind the UI" invariant that
      // the fixed-vocabulary path has always had.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onChanged(ParamVocab.unspecified),
      );
    }

    // A value outside the choices that is left as it is (see
    // [correctsValue]) is not "not stated": the dropdown asks for a choice
    // instead, so it never claims a state the draft does not hold, and so does
    // the rotation stepper. The other kinds' editors show a fallback for such
    // a value; a caller that leaves values as they are says so beside them
    // (`CompoundArgumentEditor`).
    final needsChoice =
        !correctsValue &&
        current == null &&
        !(admitsUnstated && value == ParamVocab.unspecified);

    // Shown only when there is no selection: the unstated state, or a value
    // left as it is that must be replaced.
    final hintIfEmpty = needsChoice
        ? l10n.danceEditorParamChooseValue
        : admitsUnstated
        ? l10n.danceEditorParamNotStated
        : null;
    final hint = current != null ? null : hintIfEmpty;

    // As wide as its longest choice (or its hint) needs at the current text
    // size, so a value is never cut off, and no wider than the line: where
    // the line is narrower (large text on a phone), it takes the whole line.
    final dropdown = AppDropdownField<String?>(
      key: ValueKey(_key),
      fillWidth: false,
      // Room for the hint even while a value hides it, so the field keeps one
      // width whether a value is picked or cleared.
      widthFits: [?hintIfEmpty],
      value: current,
      // A long vocabulary (an unnarrowed set of dancers) can be typed.
      filterable: selectable.length >= appDropdownFilterFrom,
      decoration: InputDecoration(
        labelText: figureParamKeyLabel(l10n, paramKey, moveId: moveId),
        isDense: denseControls(context),
        // The label stays above the field so the hint is always on view, as
        // a value would be.
        hintText: hint,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: needsChoice
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
        floatingLabelBehavior: hint == null
            ? null
            : FloatingLabelBehavior.always,
      ),
      entries: [
        for (final choice in selectable)
          AppDropdownEntry<String?>(
            value: choice,
            label: _choiceLabel(l10n, choice),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    if (!admitsUnstated) return dropdown;

    // v30 (#989): the Clear affordance additionally requires
    // `spec.allowManualClear` (default `true`, so this changes nothing for
    // any existing spec). `promenade.turn` sets it `false` — the owner
    // explicitly does not want a manual UX escape hatch back to "not stated"
    // for a spec whose default is a concrete value; only the automatic reset
    // triggered by `where` (in/out/up/down) may drive it there (core's
    // `applyParamChange`, `param_change_rules.dart`).
    if (!spec.allowManualClear) return dropdown;

    // A Wrap, not a Row: where the field and its clear button do not fit on
    // one line (large text on a phone), the button moves under the field and
    // the field keeps the whole line, rather than being squeezed until its
    // value is cut off.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        dropdown,
        // Mirrors `_RotationStepper`'s clear affordance for this same
        // sentinel: offered only once a value is set, so a transcriber who
        // picked one by mistake can put the field back to "the source didn't
        // say" rather than being stuck with a value the source never gave.
        // A value left as it is (see [correctsValue]) can be cleared too.
        if (current != null || needsChoice)
          IconButton(
            key: ValueKey('$_key-clear'),
            tooltip: l10n.danceEditorParamClearTooltip,
            icon: const Icon(Icons.backspace_outlined),
            onPressed: () => onChanged(ParamVocab.unspecified),
          ),
      ],
    );
  }
}

/// The smallest amount the fraction amount stepper offers: the first quarter
/// step past `full`, the last amount a named fraction states.
const double _fractionAmountMin = 1.25;

class _RotationStepper extends StatelessWidget {
  const _RotationStepper({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowsUnset = false,
    this.needsChoice = false,
    this.min = _domainMin,
    this.firstStep = _domainMin,
    this.formatValue,
  });

  final String fieldKey;
  final String label;

  /// The stored amount, or `null`: "not stated" (with [allowsUnset]), or a
  /// value left as it is that needs a choice (with [needsChoice]). Otherwise a
  /// spec without the sentinel always gets a number.
  final num? value;

  /// Whether this param admits [ParamVocab.unspecified], i.e. whether "the
  /// source stated no amount" is a representable state.
  final bool allowsUnset;

  /// Whether the stored value is one the spec rejects and is left as it is:
  /// shown as asking for a choice, with [value] null.
  final bool needsChoice;
  final ValueChanged<Object?> onChanged;

  static const double _domainMin = 0.25;
  static const double _max = 2.5;
  static const double _step = 0.25;

  /// The lowest amount offered: the rotation domain's, unless a narrower one
  /// is asked for (a fraction amount, which starts past `full`).
  final double min;

  /// The amount a first nudge lands on from no amount.
  final double firstStep;

  /// How an amount is shown; a count of turns when null.
  final String Function(num)? formatValue;

  static String _format(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  // The amount a first nudge lands on from the unset state is, for a turn,
  // deliberately the domain minimum ([firstStep]'s default) rather than a
  // "typical" value: stepping UP from the floor is an unambiguous user action,
  // whereas seeding a plausible middle value would be the app guessing
  // choreography. A fraction amount has no floor of its own to step from that
  // is not a named fraction, so it lands on the editor's seed (1½) instead.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final current = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('$fieldKey-dec'),
              tooltip: l10n.danceEditorLessTooltip,
              icon: const Icon(Icons.remove),
              // Disabled while unset: there is nothing to decrement, and
              // stepping DOWN into a value would read as "the app picked one".
              onPressed: (current != null && current > min)
                  ? () =>
                        onChanged((current - _step).clamp(min, _max).toDouble())
                  : null,
            ),
            Text(
              current == null
                  ? (needsChoice
                        ? l10n.danceEditorParamChooseValue
                        : l10n.danceEditorParamNotStated)
                  : (formatValue?.call(current) ??
                        l10n.danceEditorTurnCount(current, _format(current))),
              key: ValueKey('$fieldKey-value'),
              style: current == null
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: needsChoice
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            IconButton(
              key: ValueKey('$fieldKey-inc'),
              tooltip: l10n.danceEditorMoreTooltip,
              icon: const Icon(Icons.add),
              // From the unset state the first nudge ADOPTS a value — an
              // explicit user action, never an implicit default.
              onPressed: current == null
                  ? () => onChanged(firstStep)
                  : current < _max
                  ? () =>
                        onChanged((current + _step).clamp(min, _max).toDouble())
                  : null,
            ),
            // Only offered when the param can actually represent "not stated",
            // and only once a value is set or while a choice is needed — so a
            // user who set an amount by mistake can put it back rather than
            // being stuck with a number the source never gave.
            if (allowsUnset && (current != null || needsChoice))
              IconButton(
                key: ValueKey('$fieldKey-clear'),
                tooltip: l10n.danceEditorParamClearTooltip,
                icon: const Icon(Icons.backspace_outlined),
                onPressed: () => onChanged(ParamVocab.unspecified),
              ),
          ],
        ),
      ],
    );
  }
}

class _IntField extends StatefulWidget {
  const _IntField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.allowsUnset = false,
  });

  final String fieldKey;
  final String label;

  /// The stored number, or `null` for "not stated" (only with [allowsUnset]),
  /// which shows as an empty field.
  final int? value;
  final int min;
  final int max;
  final ValueChanged<Object?> onChanged;

  /// Whether the param admits [ParamVocab.unspecified]: an empty field then
  /// reports the sentinel and is not an error.
  final bool allowsUnset;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _controller;

  /// Whether the text currently in the field is not a whole number within
  /// `[min, max]`. Such text is never reported through `onChanged` — the draft
  /// keeps its last valid value — so the field says so next to itself rather
  /// than silently showing a number that will not be saved.
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(_IntField old) {
    super.didUpdateWidget(old);
    // Keep the field in sync when the value is reseeded programmatically (e.g.
    // a move change reseeds default params). Only overwrite when it actually
    // differs from what the user is looking at, to avoid fighting the cursor.
    if (widget.value != old.value &&
        int.tryParse(_controller.text.trim()) != widget.value) {
      _controller.text = widget.value?.toString() ?? '';
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: 96,
      child: TextField(
        key: ValueKey(widget.fieldKey),
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          // The label floats while the field is empty so this hint shows,
          // as the dropdowns show "not stated" for the same sentinel.
          floatingLabelBehavior: widget.allowsUnset
              ? FloatingLabelBehavior.always
              : null,
          hintText: widget.allowsUnset ? l10n.danceEditorParamNotStated : null,
          hintStyle: widget.allowsUnset
              ? theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
          errorText: _invalid
              ? l10n.danceEditorIntParamRangeError(widget.min, widget.max)
              : null,
        ),
        onChanged: (text) {
          final trimmed = text.trim();
          if (widget.allowsUnset && trimmed.isEmpty) {
            widget.onChanged(ParamVocab.unspecified);
            if (_invalid) setState(() => _invalid = false);
            return;
          }
          final n = int.tryParse(trimmed);
          final valid = n != null && n >= widget.min && n <= widget.max;
          if (valid) widget.onChanged(n);
          if (_invalid == valid) setState(() => _invalid = !valid);
        },
      ),
    );
  }
}

class _TextParamField extends StatefulWidget {
  const _TextParamField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final String value;
  final ValueChanged<Object?> onChanged;

  @override
  State<_TextParamField> createState() => _TextParamFieldState();
}

class _TextParamFieldState extends State<_TextParamField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextParamField old) {
    super.didUpdateWidget(old);
    // Sync when the parent reseeds the value (e.g. a move change) without
    // clobbering in-progress typing.
    if (widget.value != old.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextField(
        key: ValueKey(widget.fieldKey),
        controller: _controller,
        decoration: InputDecoration(labelText: widget.label, isDense: true),
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// The editor of a [ParamKind.dancerList] (ECD's `who`, ADR-006 §5.2): a
/// field that reads the dancers picked, in the order picked, and opens a list
/// with a checkbox per selector and a search box that narrows it. `everyone`
/// stands alone, so checking it clears the others and checking another clears
/// it; clearing the last leaves the list as "not stated" (`["unspecified"]`).
class _DancerListDropdown extends StatelessWidget {
  const _DancerListDropdown({
    required this.fieldKey,
    required this.label,
    required this.domain,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final List<String> domain;
  final Object? value;
  final String Function(String token) labelOf;
  final ValueChanged<Object?> onChanged;

  List<String> get _picked => [
    if (value case final List<Object?> list)
      for (final token in list)
        if (token is String && token != ParamVocab.unspecified) token,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final picked = _picked;
    return MultiSelectDropdown(
      key: ValueKey(fieldKey),
      fieldKey: fieldKey,
      valueText: picked.map(labelOf).join(', '),
      decoration: InputDecoration(
        labelText: label,
        isDense: denseControls(context),
        // As the single-choice fields show it: the label stays above, so
        // "not stated" is on view as a value would be.
        hintText: l10n.danceEditorParamNotStated,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      panelBuilder: (context, placement) => _DancerListPanel(
        fieldKey: fieldKey,
        domain: domain,
        picked: picked,
        labelOf: labelOf,
        onChanged: onChanged,
        autofocus: placement.autofocus,
        scrollController: placement.scrollController,
      ),
    );
  }
}

/// The open list of a [_DancerListDropdown]: a search box, when the list is
/// long, and a checkbox row per selector, in the vocabulary's order.
class _DancerListPanel extends StatefulWidget {
  const _DancerListPanel({
    required this.fieldKey,
    required this.domain,
    required this.picked,
    required this.labelOf,
    required this.onChanged,
    required this.autofocus,
    this.scrollController,
  });

  final String fieldKey;
  final List<String> domain;
  final List<String> picked;
  final String Function(String token) labelOf;
  final ValueChanged<Object?> onChanged;
  final bool autofocus;
  final ScrollController? scrollController;

  @override
  State<_DancerListPanel> createState() => _DancerListPanelState();
}

class _DancerListPanelState extends State<_DancerListPanel> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  /// The picks, changed here as each box is checked. The owner's rebuild
  /// reaches this list a frame or two later, so a second check made before
  /// then must build on the first, not on the owner's older value.
  late List<String> _picked = widget.picked;

  @override
  void didUpdateWidget(covariant _DancerListPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.picked, oldWidget.picked)) _picked = widget.picked;
  }

  /// Checks or unchecks [token]. `everyone` stands alone, so checking it
  /// clears the others and checking another clears it; unchecking the last
  /// leaves the list "not stated".
  void _toggle(String token, bool selected) {
    final List<String> next;
    if (!selected) {
      next = [
        for (final t in _picked)
          if (t != token) t,
      ];
    } else if (ParamVocab.soloDancerTokens.contains(token)) {
      next = [token];
    } else {
      next = [
        for (final t in _picked)
          if (!ParamVocab.soloDancerTokens.contains(t)) t,
        token,
      ];
    }
    setState(() => _picked = next);
    widget.onChanged(next.isEmpty ? const [ParamVocab.unspecified] : next);
  }

  bool get _searchable => widget.domain.length >= appDropdownFilterFrom;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// The selectors whose label holds the typed text.
  List<String> get _rows {
    final wanted = _query.text.trim().toLowerCase();
    if (wanted.isEmpty) return widget.domain;
    return [
      for (final token in widget.domain)
        if (widget.labelOf(token).toLowerCase().contains(wanted)) token,
    ];
  }

  /// Enter in the search box: checks the first match not yet picked, then
  /// clears the box for the next. With every match picked, Enter does
  /// nothing and the typed text stays.
  void _submit() {
    if (_query.text.trim().isEmpty) return;
    final first = _rows.where((t) => !_picked.contains(t)).firstOrNull;
    if (first == null) return;
    _toggle(first, true);
    _query.clear();
    _queryFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rows;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: TextField(
              key: ValueKey('${widget.fieldKey}-input'),
              controller: _query,
              focusNode: _queryFocus,
              autofocus: widget.autofocus,
              decoration: InputDecoration(
                hintText: l10n.figureParamSearchDancersHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        Flexible(
          child: ListView.builder(
            key: ValueKey('${widget.fieldKey}-options'),
            controller: widget.scrollController,
            shrinkWrap: true,
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final token = rows[i];
              final checked = _picked.contains(token);
              return CheckboxListTile(
                key: ValueKey('${widget.fieldKey}-$token'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: checked,
                title: Text(widget.labelOf(token)),
                onChanged: (_) => _toggle(token, !checked),
              );
            },
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: TextButton(
              key: ValueKey('${widget.fieldKey}-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonDone),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlagSwitch extends StatelessWidget {
  const _FlagSwitch({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final bool value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(key: ValueKey(fieldKey), value: value, onChanged: onChanged),
        Text(label),
      ],
    );
  }
}
