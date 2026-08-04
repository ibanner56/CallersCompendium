import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/validation_issue_labels.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class EnumDropdown<T> extends StatelessWidget {
  const EnumDropdown({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$fieldKey-field'),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(labelOf(v))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// An accessible 1..5 star rating control with an explicit UNRATED affordance.
///
/// Accessibility (a11y is a merge gate for this control):
/// - Each star is a focusable, actionable [IconButton] with a semantic label
///   ('Set rating to N of 5 stars').
/// - The whole control is wrapped in [Semantics] with `label: 'Rating'` and a
///   value like '3 of 5 stars' or 'unrated' (announced as 'Rating, 3 of 5
///   stars'). The value deliberately omits a 'Rating:' prefix so the label
///   isn't announced twice.
/// - Filled vs empty stars differ by icon *shape* ([Icons.star] vs
///   [Icons.star_border]) and carry semantics — state is never conveyed by
///   colour alone.
/// - Clearing is available two ways: an explicit labelled clear button, and
///   tapping the currently-selected top star to unset it.
///
/// `null` is the unrated state; saved via `copyWith(clearRating: true)`.
class RatingField extends StatelessWidget {
  const RatingField({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  static const _max = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final semanticValue = value == null
        ? l10n.danceEditorRatingUnrated
        : l10n.danceEditorRatingValue(value!, _max);

    return Semantics(
      key: const ValueKey('rating-field'),
      container: true,
      label: l10n.danceEditorRatingLabel,
      value: semanticValue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xxs,
              bottom: AppSpacing.xxs,
            ),
            child: Text(
              l10n.danceEditorRatingLabel,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var star = 1; star <= _max; star++)
                IconButton(
                  key: ValueKey('rating-star-$star'),
                  // Tapping the current top star unsets; otherwise sets to it.
                  onPressed: () => onChanged(value == star ? null : star),
                  tooltip: l10n.danceEditorSetRatingTooltip(star, _max),
                  icon: Icon(
                    (value ?? 0) >= star ? Icons.star : Icons.star_border,
                    semanticLabel: l10n.danceEditorSetRatingTooltip(star, _max),
                    color: (value ?? 0) >= star
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
              if (value != null)
                IconButton(
                  key: const ValueKey('rating-clear'),
                  onPressed: () => onChanged(null),
                  tooltip: l10n.danceEditorClearRating,
                  icon: Icon(
                    Icons.clear,
                    semanticLabel: l10n.danceEditorClearRating,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A difficulty [DanceLevel] dropdown that includes an explicit "Unspecified"
/// (`null`) option. Mirrors [EnumDropdown] but is nullable so a dance can have
/// no assigned level (saved via `copyWith(clearLevel: true)`).
class LevelDropdown extends StatelessWidget {
  const LevelDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DanceLevel? value;
  final ValueChanged<DanceLevel?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<DanceLevel?>(
      key: const ValueKey('level-field'),
      initialValue: value,
      decoration: InputDecoration(labelText: l10n.danceEditorLevelLabel),
      items: [
        DropdownMenuItem<DanceLevel?>(
          value: null,
          child: Text(l10n.danceEditorLevelUnspecified),
        ),
        for (final v in DanceLevel.values)
          DropdownMenuItem<DanceLevel?>(
            value: v,
            child: Text(danceLevelLabel(l10n, v)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A precision-aware partial-date entry: a required 4-digit **Year** plus an
/// optional **Month** and (when a month is set) **Day**. Emits a [PartialDate]
/// via [onChanged] — `null` when the year is blank/invalid. A raw date picker
/// is deliberately avoided: it would force full year/month/day, but composition
/// dates are frequently known only to the year (or year+month).
class PartialDateField extends StatefulWidget {
  const PartialDateField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.helperText,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final String helperText;
  final PartialDate? value;
  final ValueChanged<PartialDate?> onChanged;

  @override
  State<PartialDateField> createState() => _PartialDateFieldState();
}

class _PartialDateFieldState extends State<PartialDateField> {
  late final TextEditingController _yearController;
  int? _month;
  int? _day;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(
      text: widget.value?.year.toString() ?? '',
    );
    _month = widget.value?.month;
    _day = widget.value?.day;
  }

  @override
  void didUpdateWidget(covariant PartialDateField old) {
    super.didUpdateWidget(old);
    // Re-sync when the value changes externally (undo/redo, draft restore),
    // but not when it merely echoes what this field just emitted (avoids
    // clobbering the caret mid-edit).
    if (widget.value != _compute()) {
      _yearController.text = widget.value?.year.toString() ?? '';
      _month = widget.value?.month;
      _day = widget.value?.day;
    }
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  int? get _year {
    final y = int.tryParse(_yearController.text.trim());
    if (y == null || y < 1 || y > 9999) return null;
    return y;
  }

  /// The current value, or `null` when the year is blank/invalid.
  PartialDate? _compute() {
    final y = _year;
    if (y == null) return null;
    try {
      return PartialDate(y, _month, _day);
    } on ArgumentError {
      return null;
    }
  }

  static int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  void _emit() => widget.onChanged(_compute());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final year = _year;
    final yearText = _yearController.text.trim();
    final showYearError = yearText.isNotEmpty && year == null;
    final dayEnabled = year != null && _month != null;
    final maxDay = dayEnabled ? _daysIn(year, _month!) : 31;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: ValueKey('${widget.fieldKey}-year'),
                controller: _yearController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorYearLabel,
                  hintText: l10n.danceEditorYearHint,
                  counterText: '',
                  errorText: showYearError
                      ? l10n.danceEditorYearRangeError
                      : null,
                ),
                onChanged: (_) => setState(() {
                  // A year change can invalidate a chosen day (e.g. Feb 29 in a
                  // leap year, then a non-leap year). Clear it so the Day
                  // dropdown never gets an initialValue absent from its items.
                  final y = _year;
                  if (y != null &&
                      _month != null &&
                      _day != null &&
                      _day! > _daysIn(y, _month!)) {
                    _day = null;
                  }
                  _emit();
                }),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int?>(
                key: ValueKey('${widget.fieldKey}-month'),
                initialValue: _month,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorMonthLabel,
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem<int?>(
                      value: m,
                      child: Text(_monthLabel(l10n, m)),
                    ),
                ],
                onChanged: year == null
                    ? null
                    : (m) => setState(() {
                        _month = m;
                        // A day needs a month, and must stay valid for it.
                        if (m == null) {
                          _day = null;
                        } else if (_day != null && _day! > _daysIn(year, m)) {
                          _day = null;
                        }
                        _emit();
                      }),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int?>(
                key: ValueKey('${widget.fieldKey}-day'),
                initialValue: _day,
                decoration: InputDecoration(
                  labelText: l10n.danceEditorDayLabel,
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  for (var d = 1; d <= maxDay; d++)
                    DropdownMenuItem<int?>(value: d, child: Text('$d')),
                ],
                onChanged: dayEnabled
                    ? (d) => setState(() {
                        _day = d;
                        _emit();
                      })
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(widget.helperText, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

String _monthLabel(AppLocalizations l10n, int month) => switch (month) {
  1 => l10n.danceEditorMonthJan,
  2 => l10n.danceEditorMonthFeb,
  3 => l10n.danceEditorMonthMar,
  4 => l10n.danceEditorMonthApr,
  5 => l10n.danceEditorMonthMay,
  6 => l10n.danceEditorMonthJun,
  7 => l10n.danceEditorMonthJul,
  8 => l10n.danceEditorMonthAug,
  9 => l10n.danceEditorMonthSep,
  10 => l10n.danceEditorMonthOct,
  11 => l10n.danceEditorMonthNov,
  12 => l10n.danceEditorMonthDec,
  _ => '',
};

class TuneEditor extends StatelessWidget {
  const TuneEditor({
    super.key,
    required this.tunes,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tunes;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tunes.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final tune in tunes)
                Chip(
                  key: ValueKey('tune-chip-$tune'),
                  label: Text(tune),
                  onDeleted: () => onRemove(tune),
                ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('tune-field'),
                controller: controller,
                decoration: InputDecoration(
                  hintText: l10n.danceEditorAddTuneHint,
                  isDense: true,
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              key: const ValueKey('tune-add'),
              tooltip: l10n.danceEditorAddTuneTooltip,
              icon: const Icon(Icons.add),
              onPressed: onAdd,
            ),
          ],
        ),
      ],
    );
  }
}

class WarningsCard extends StatelessWidget {
  const WarningsCard({super.key, required this.warnings});

  final List<ValidationIssue> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('warnings-card'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.danceEditorWarningsTitle,
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final warning in warnings)
            Padding(
              // intentional: 2px optical inset, below the 4px AppSpacing grid
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${validationIssueMessage(l10n, warning)}'),
            ),
        ],
      ),
    );
  }
}
