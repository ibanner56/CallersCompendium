import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The outcome of the batch edit-custom-field dialog: the chosen [def] plus
/// either a type-respecting [value] to upsert across the selection, or
/// [clear] `true` to remove that one field from every selected dance.
/// Cancelling the dialog returns `null` instead.
class BatchCustomFieldChoice {
  const BatchCustomFieldChoice({
    required this.def,
    this.value,
    this.clear = false,
  });

  final CustomFieldDef def;

  /// The value to set (type matches [def]); `null` when [clear] is `true`.
  final Object? value;

  /// Whether the user chose to clear the field instead of setting a value.
  final bool clear;
}

/// Shows the batch **edit custom field** dialog for the Collection multi-select
/// flow (#423). The user picks ONE [CustomFieldDef] and then either enters a
/// value (respecting the field's type) to upsert across the selection, or turns
/// on "Clear this field" to remove that one key everywhere. All other custom
/// fields on the selected dances are left untouched.
///
/// [defs] are the available field definitions; an empty list renders an
/// informational empty state with the confirm button disabled. Controls expose
/// role + text labels (dropdowns, switches, labelled text fields) — never color
/// alone. Returns the [BatchCustomFieldChoice], or `null` if cancelled.
Future<BatchCustomFieldChoice?> showBatchCustomFieldDialog(
  BuildContext context, {
  required List<CustomFieldDef> defs,
}) {
  return showDialog<BatchCustomFieldChoice>(
    context: context,
    builder: (_) => _BatchCustomFieldDialog(defs: defs),
  );
}

class _BatchCustomFieldDialog extends StatefulWidget {
  const _BatchCustomFieldDialog({required this.defs});

  final List<CustomFieldDef> defs;

  @override
  State<_BatchCustomFieldDialog> createState() =>
      _BatchCustomFieldDialogState();
}

class _BatchCustomFieldDialogState extends State<_BatchCustomFieldDialog> {
  CustomFieldDef? _selectedDef;
  bool _clear = false;

  // Backing state for the value control; interpretation depends on the type.
  final _textController = TextEditingController();
  bool _boolValue = false;
  String? _choiceValue;

  @override
  void initState() {
    super.initState();
    if (widget.defs.length == 1) _selectedDef = widget.defs.first;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onDefChanged(CustomFieldDef? def) {
    setState(() {
      _selectedDef = def;
      // Reset the value state so a stale value from a prior field type never
      // leaks into the new one.
      _textController.clear();
      _boolValue = false;
      _choiceValue = null;
    });
  }

  /// The value to submit for the current field, or `null` if invalid/empty.
  Object? _currentValue() {
    final def = _selectedDef;
    if (def == null) return null;
    switch (def.type) {
      case CustomFieldType.text:
        final text = _textController.text.trim();
        return text.isEmpty ? null : text;
      case CustomFieldType.number:
        final text = _textController.text.trim();
        return text.isEmpty ? null : num.tryParse(text);
      case CustomFieldType.boolean:
        return _boolValue;
      case CustomFieldType.choice:
        return _choiceValue;
    }
  }

  bool get _canConfirm {
    if (_selectedDef == null) return false;
    if (_clear) return true;
    return _currentValue() != null;
  }

  void _confirm() {
    final def = _selectedDef!;
    Navigator.of(context).pop(
      _clear
          ? BatchCustomFieldChoice(def: def, clear: true)
          : BatchCustomFieldChoice(def: def, value: _currentValue()),
    );
  }

  Widget _valueControl(CustomFieldDef def, AppLocalizations l10n) {
    switch (def.type) {
      case CustomFieldType.text:
        return TextField(
          key: ValueKey('batch-custom-field-value-${def.id}'),
          controller: _textController,
          decoration: InputDecoration(
            labelText: def.label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        );
      case CustomFieldType.number:
        return TextField(
          key: ValueKey('batch-custom-field-value-${def.id}'),
          controller: _textController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: def.label,
            isDense: true,
            border: const OutlineInputBorder(),
            errorText:
                _textController.text.trim().isNotEmpty &&
                    num.tryParse(_textController.text.trim()) == null
                ? l10n.collectionBatchCustomFieldNumberInvalid
                : null,
          ),
          onChanged: (_) => setState(() {}),
        );
      case CustomFieldType.boolean:
        return SwitchListTile(
          key: ValueKey('batch-custom-field-value-${def.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(def.label),
          value: _boolValue,
          onChanged: (v) => setState(() => _boolValue = v),
        );
      case CustomFieldType.choice:
        return DropdownButtonFormField<String>(
          key: ValueKey('batch-custom-field-value-${def.id}'),
          initialValue: _choiceValue,
          decoration: InputDecoration(
            labelText: def.label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final choice in def.choices ?? const <String>[])
              DropdownMenuItem(value: choice, child: Text(choice)),
          ],
          onChanged: (v) => setState(() => _choiceValue = v),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final def = _selectedDef;
    return AlertDialog(
      key: const ValueKey('batch-custom-field-dialog'),
      title: Text(l10n.collectionEditCustomField),
      content: SizedBox(
        width: 360,
        child: widget.defs.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.collectionBatchCustomFieldEmpty),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<CustomFieldDef>(
                    key: const ValueKey('batch-custom-field-key'),
                    initialValue: _selectedDef,
                    decoration: InputDecoration(
                      labelText: l10n.collectionBatchCustomFieldKeyLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final d in widget.defs)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: _onDefChanged,
                  ),
                  const SizedBox(height: 12),
                  if (def != null && !_clear) _valueControl(def, l10n),
                  if (def != null)
                    SwitchListTile(
                      key: const ValueKey('batch-custom-field-clear'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.collectionBatchCustomFieldClearOption),
                      value: _clear,
                      onChanged: (v) => setState(() => _clear = v),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('batch-custom-field-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('batch-custom-field-confirm'),
          onPressed: _canConfirm ? _confirm : null,
          child: Text(l10n.collectionBatchCustomFieldConfirm),
        ),
      ],
    );
  }
}
