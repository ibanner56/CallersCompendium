import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

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
  });

  /// Stem for the child widget's [ValueKey] (e.g. `figure-0`); the editor
  /// appends `-<paramKey>` so tests can target it.
  final String keyPrefix;
  final String paramKey;
  final ParamSpec spec;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  String get _key => '$keyPrefix-$paramKey';

  @override
  Widget build(BuildContext context) {
    switch (spec.kind) {
      case ParamKind.dancerSet:
      case ParamKind.dancerPair:
        return _dropdown(spec.choices ?? ParamVocab.dancerSets);
      case ParamKind.handedness:
      case ParamKind.shoulder:
        return _dropdown(ParamVocab.sides);
      case ParamKind.spinDirection:
        return _dropdown(ParamVocab.spins);
      case ParamKind.fraction:
        return _dropdown(ParamVocab.fractions);
      case ParamKind.direction:
        return _dropdown(ParamVocab.directions);
      case ParamKind.choice:
        return _dropdown(spec.choices ?? const []);
      case ParamKind.rotation:
        return _RotationStepper(
          fieldKey: _key,
          label: humanizeToken(paramKey),
          value: value is num ? value! as num : 1.0,
          onChanged: onChanged,
        );
      case ParamKind.beats:
        return _IntField(
          fieldKey: _key,
          label: humanizeToken(paramKey),
          value: value is int ? value! as int : 0,
          min: 0,
          max: 64,
          onChanged: onChanged,
        );
      case ParamKind.text:
        return _TextParamField(
          fieldKey: _key,
          label: humanizeToken(paramKey),
          value: value is String ? value! as String : '',
          onChanged: onChanged,
        );
      case ParamKind.flag:
        return _FlagSwitch(
          fieldKey: _key,
          label: humanizeToken(paramKey),
          value: value is bool ? value! as bool : false,
          onChanged: onChanged,
        );
    }
  }

  Widget _dropdown(List<String> choices) {
    // Reconcile the displayed selection with the model: prefer the current
    // value when valid, else the spec default (if a valid choice), else the
    // first choice. When we fall back, push that value back to the draft after
    // the frame so a saved-but-invalid value can't linger behind the UI.
    final specDefault = spec.defaultValue;
    final current = value is String && choices.contains(value)
        ? value! as String
        : (specDefault is String && choices.contains(specDefault))
        ? specDefault
        : (choices.isNotEmpty ? choices.first : null);
    if (current != null && current != value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(current));
    }
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        key: ValueKey(_key),
        initialValue: current,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          labelText: humanizeToken(paramKey),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final choice in choices)
            DropdownMenuItem(value: choice, child: Text(humanizeToken(choice))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Turns `role1s` → `role1s`, `rightDiagonal` → `right diagonal`,
/// `threeQuarter` → `three quarter` for display.
String humanizeToken(String token) => token
    .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
    .toLowerCase();

class _RotationStepper extends StatelessWidget {
  const _RotationStepper({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final num value;
  final ValueChanged<Object?> onChanged;

  static const double _min = 0.25;
  static const double _max = 2.5;
  static const double _step = 0.25;

  static String _format(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              tooltip: 'Less',
              icon: const Icon(Icons.remove),
              visualDensity: VisualDensity.compact,
              onPressed: value > _min
                  ? () =>
                        onChanged((value - _step).clamp(_min, _max).toDouble())
                  : null,
            ),
            Text(
              '${_format(value)} turn${value == 1 ? '' : 's'}',
              key: ValueKey('$fieldKey-value'),
            ),
            IconButton(
              key: ValueKey('$fieldKey-inc'),
              tooltip: 'More',
              icon: const Icon(Icons.add),
              visualDensity: VisualDensity.compact,
              onPressed: value < _max
                  ? () =>
                        onChanged((value + _step).clamp(_min, _max).toDouble())
                  : null,
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
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
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
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
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
