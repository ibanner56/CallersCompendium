import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

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

  String get _key => '$keyPrefix-$paramKey';

  @override
  Widget build(BuildContext context) {
    switch (spec.kind) {
      case ParamKind.dancerSet:
      case ParamKind.dancerPair:
        return _dropdown(context, spec.choices ?? ParamVocab.dancerSets);
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
        return _RotationStepper(
          fieldKey: _key,
          label: figureParamKeyLabel(paramKey),
          value: value is num ? value! as num : (allowsUnset ? null : 1.0),
          allowsUnset: allowsUnset,
          onChanged: onChanged,
        );
      case ParamKind.beats:
        return _IntField(
          fieldKey: _key,
          label: figureParamKeyLabel(paramKey),
          value: value is int ? value! as int : 0,
          min: 0,
          max: 64,
          onChanged: onChanged,
        );
      case ParamKind.places:
        return _IntField(
          fieldKey: _key,
          label: figureParamKeyLabel(paramKey),
          value: value is int
              ? value! as int
              : (spec.defaultValue is int ? spec.defaultValue! as int : 1),
          min: 1,
          max: 10,
          onChanged: onChanged,
        );
      case ParamKind.text:
        return _TextParamField(
          fieldKey: _key,
          label: figureParamKeyLabel(paramKey),
          value: value is String ? value! as String : '',
          onChanged: onChanged,
        );
      case ParamKind.flag:
        return _FlagSwitch(
          fieldKey: _key,
          label: figureParamKeyLabel(paramKey),
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
    final current = (admitsUnstated && value == ParamVocab.unspecified)
        ? null
        : (value is String && selectable.contains(value))
        ? value! as String
        : (specDefault is String && selectable.contains(specDefault))
        ? specDefault
        : (admitsUnstated
              ? null
              : (selectable.isNotEmpty ? selectable.first : null));
    if (current != null && current != value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(current));
    } else if (admitsUnstated &&
        current == null &&
        value != null &&
        value != ParamVocab.unspecified) {
      // An out-of-domain value with no valid substitute available: every
      // sentinel-admitting spec defaults TO the sentinel, so the default rung
      // misses too and the chain lands on `null`. Normalise the draft to the
      // sentinel rather than leaving it holding a token the field is already
      // displaying as "not stated" — that mismatch would keep rendering the bad
      // token into the figure text while offering no single-step way to fix it,
      // since Clear is hidden whenever nothing is selected. This stores exactly
      // what is displayed, so it corrects invalid data rather than inventing a
      // value, and it keeps the "invalid values can't linger behind the UI"
      // invariant that the fixed-vocabulary path has always had.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onChanged(ParamVocab.unspecified),
      );
    }

    final dropdown = SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        key: ValueKey(_key),
        initialValue: current,
        isExpanded: true,
        isDense: true,
        // Shown only when there is no selection, i.e. the unstated state.
        // Supplying a hint also keeps `InputDecorator.isEmpty` false, so the
        // floating label behaves exactly as it does for a set value.
        hint: admitsUnstated
            ? Text(
                l10n.danceEditorParamNotStated,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        decoration: InputDecoration(
          labelText: figureParamKeyLabel(paramKey),
          isDense: true,
        ),
        items: [
          for (final choice in selectable)
            DropdownMenuItem(
              value: choice,
              child: Text(figureParamChoiceLabel(l10n, spec, dialect, choice)),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
    if (!admitsUnstated) return dropdown;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dropdown,
        // Mirrors `_RotationStepper`'s clear affordance for this same sentinel:
        // offered only once a value is set, so a transcriber who picked one by
        // mistake can put the field back to "the source didn't say" rather than
        // being stuck with a value the source never gave.
        if (current != null)
          IconButton(
            key: ValueKey('$_key-clear'),
            tooltip: l10n.danceEditorParamClearTooltip,
            icon: const Icon(Icons.backspace_outlined),
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(ParamVocab.unspecified),
          ),
      ],
    );
  }
}

class _RotationStepper extends StatelessWidget {
  const _RotationStepper({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowsUnset = false,
  });

  final String fieldKey;
  final String label;

  /// The stored amount, or `null` when the source stated none. Only reachable
  /// when [allowsUnset] — a spec without the sentinel always gets a number.
  final num? value;

  /// Whether this param admits [ParamVocab.unspecified], i.e. whether "the
  /// source stated no amount" is a representable state.
  final bool allowsUnset;
  final ValueChanged<Object?> onChanged;

  static const double _min = 0.25;
  static const double _max = 2.5;
  static const double _step = 0.25;

  static String _format(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  /// The amount a first nudge lands on from the unset state. Deliberately the
  /// domain minimum rather than a "typical" value: stepping UP from the floor
  /// is an unambiguous user action, whereas seeding a plausible middle value
  /// would be the app guessing choreography.
  static const double _firstStep = _min;

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
              visualDensity: VisualDensity.compact,
              // Disabled while unset: there is nothing to decrement, and
              // stepping DOWN into a value would read as "the app picked one".
              onPressed: (current != null && current > _min)
                  ? () => onChanged(
                      (current - _step).clamp(_min, _max).toDouble(),
                    )
                  : null,
            ),
            Text(
              current == null
                  ? l10n.danceEditorParamNotStated
                  : l10n.danceEditorTurnCount(current, _format(current)),
              key: ValueKey('$fieldKey-value'),
              style: current == null
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            IconButton(
              key: ValueKey('$fieldKey-inc'),
              tooltip: l10n.danceEditorMoreTooltip,
              icon: const Icon(Icons.add),
              visualDensity: VisualDensity.compact,
              // From the unset state the first nudge ADOPTS a value — an
              // explicit user action, never an implicit default.
              onPressed: current == null
                  ? () => onChanged(_firstStep)
                  : current < _max
                  ? () => onChanged(
                      (current + _step).clamp(_min, _max).toDouble(),
                    )
                  : null,
            ),
            // Only offered when the param can actually represent "not stated",
            // and only once a value is set — so a user who set an amount by
            // mistake can put it back rather than being stuck with a number the
            // source never gave.
            if (allowsUnset && current != null)
              IconButton(
                key: ValueKey('$fieldKey-clear'),
                tooltip: l10n.danceEditorParamClearTooltip,
                icon: const Icon(Icons.backspace_outlined),
                visualDensity: VisualDensity.compact,
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
  });

  final String fieldKey;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<Object?> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_IntField old) {
    super.didUpdateWidget(old);
    // Keep the field in sync when the value is reseeded programmatically (e.g.
    // a move change reseeds default params). Only overwrite when it actually
    // differs from what the user is looking at, to avoid fighting the cursor.
    if (widget.value != old.value &&
        int.tryParse(_controller.text.trim()) != widget.value) {
      _controller.text = widget.value.toString();
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
      width: 96,
      child: TextField(
        key: ValueKey(widget.fieldKey),
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: widget.label, isDense: true),
        onChanged: (text) {
          final n = int.tryParse(text.trim());
          if (n != null && n >= widget.min && n <= widget.max) {
            widget.onChanged(n);
          }
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
