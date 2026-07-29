import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/lingo_text_editing_controller.dart';
import 'dance_editor_controller.dart' show AddChoiceResult;
import 'lingo_discouraged_hint.dart';

/// Renders the editor control for a single [CustomFieldDef], dispatching on its
/// [CustomFieldType]. Text/number fields are backed by [textController] (a
/// lingo-styled controller) and report edits via [onTextChanged]; boolean and
/// choice fields report their new value via [onValueChanged] using
/// [currentValue] as the current selection.
///
/// For `choice` fields, [onAddOption] (when provided) enables an inline
/// "Add option…" affordance so a new option can be created while editing a
/// dance (issue #373); it returns an [AddChoiceResult] so validation failures
/// (empty / duplicate) can be surfaced.
class CustomFieldEditor extends StatelessWidget {
  const CustomFieldEditor({
    super.key,
    required this.def,
    required this.dialect,
    required this.textController,
    required this.currentValue,
    required this.onTextChanged,
    required this.onValueChanged,
    this.onAddOption,
  });

  final CustomFieldDef def;
  final Dialect dialect;

  /// Backing controller for text/number fields; `null` for boolean/choice
  /// fields (and defensively `null` if a text/number controller wasn't seeded).
  final LingoTextEditingController? textController;

  /// Current stored value for boolean/choice fields.
  final Object? currentValue;

  /// Called on each edit of a text/number field.
  final VoidCallback onTextChanged;

  /// Called with the new value of a boolean/choice field.
  final ValueChanged<Object?> onValueChanged;

  /// For `choice` fields only: adds a new option to the field definition and
  /// selects it, returning why the add succeeded or was rejected. When `null`,
  /// the inline add affordance is hidden (the dropdown stays read-only over the
  /// existing options).
  final Future<AddChoiceResult> Function(String raw)? onAddOption;

  @override
  Widget build(BuildContext context) {
    switch (def.type) {
      case CustomFieldType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: ValueKey('custom-${def.id}'),
                controller: textController,
                decoration: InputDecoration(labelText: def.label),
                onChanged: (_) => onTextChanged(),
              ),
              if (textController != null)
                LingoDiscouragedHint(
                  controller: textController!,
                  dialect: dialect,
                  fieldKey: 'custom-${def.id}',
                ),
            ],
          ),
        );
      case CustomFieldType.number:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: TextFormField(
            key: ValueKey('custom-${def.id}'),
            controller: textController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: def.label),
            onChanged: (_) => onTextChanged(),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return null;
              return num.tryParse(text) == null ? 'Enter a number' : null;
            },
          ),
        );
      case CustomFieldType.boolean:
        return SwitchListTile(
          key: ValueKey('custom-${def.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(def.label),
          value: (currentValue as bool?) ?? false,
          onChanged: (v) => onValueChanged(v),
        );
      case CustomFieldType.choice:
        final dropdown = DropdownButtonFormField<String?>(
          // Value-based key so undo/redo forces a rebuild with new state.
          key: ValueKey('custom-${def.id}-$currentValue'),
          initialValue: currentValue as String?,
          decoration: InputDecoration(labelText: def.label),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (final choice in def.choices ?? const <String>[])
              DropdownMenuItem(value: choice, child: Text(choice)),
          ],
          onChanged: (v) => onValueChanged(v),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: onAddOption == null
              ? dropdown
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: dropdown),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      key: ValueKey('custom-${def.id}-add-option'),
                      icon: const Icon(Icons.add),
                      tooltip: AppLocalizations.of(
                        context,
                      ).customFieldsAddOptionTooltip(def.label),
                      onPressed: () => _promptAddOption(context),
                    ),
                  ],
                ),
        );
    }
  }

  /// Opens a small dialog to enter a new option for this `choice` field, then
  /// delegates to [onAddOption]. The input is capped at
  /// [kMaxCustomFieldChoiceLength] characters; empty and duplicate values are
  /// reported inline in the dialog rather than silently dropped.
  Future<void> _promptAddOption(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _AddChoiceOptionDialog(label: def.label, onAddOption: onAddOption!),
    );
  }
}

/// Modal for adding a new option to a `choice` custom field from the dance
/// editor (issue #373). A [StatefulWidget] so it owns its [TextEditingController]
/// and disposes it only after the dialog is fully gone — avoiding a
/// use-after-dispose when the parent form rebuilds on a successful add.
class _AddChoiceOptionDialog extends StatefulWidget {
  const _AddChoiceOptionDialog({
    required this.label,
    required this.onAddOption,
  });

  final String label;
  final Future<AddChoiceResult> Function(String raw) onAddOption;

  @override
  State<_AddChoiceOptionDialog> createState() => _AddChoiceOptionDialogState();
}

class _AddChoiceOptionDialogState extends State<_AddChoiceOptionDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Set when [widget.onAddOption] rejects the value, so the reason shows under
  /// the field without closing the dialog.
  String? _asyncError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _asyncError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = await widget.onAddOption(_controller.text);
    if (!mounted) return;
    switch (result) {
      case AddChoiceResult.added:
      case AddChoiceResult.notFound:
        Navigator.of(context).pop();
      case AddChoiceResult.duplicate:
        setState(
          () => _asyncError = AppLocalizations.of(
            context,
          ).customFieldsChoiceDuplicate,
        );
      case AddChoiceResult.empty:
        setState(
          () => _asyncError = AppLocalizations.of(
            context,
          ).customFieldsChoiceEmpty,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.customFieldsAddOptionTitle(widget.label)),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('add-option-input'),
          controller: _controller,
          autofocus: true,
          maxLength: kMaxCustomFieldChoiceLength,
          decoration: InputDecoration(
            labelText: l10n.customFieldsNewChoiceHint,
            counterText: '',
            errorText: _asyncError,
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? l10n.customFieldsChoiceEmpty
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('add-option-confirm'),
          onPressed: _submit,
          child: Text(l10n.commonAdd),
        ),
      ],
    );
  }
}
