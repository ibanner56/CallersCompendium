import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../widgets/lingo_text_editing_controller.dart';
import 'lingo_discouraged_hint.dart';

/// Renders the editor control for a single [CustomFieldDef], dispatching on its
/// [CustomFieldType]. Text/number fields are backed by [textController] (a
/// lingo-styled controller) and report edits via [onTextChanged]; boolean and
/// choice fields report their new value via [onValueChanged] using
/// [currentValue] as the current selection.
class CustomFieldEditor extends StatelessWidget {
  const CustomFieldEditor({
    super.key,
    required this.def,
    required this.dialect,
    required this.textController,
    required this.currentValue,
    required this.onTextChanged,
    required this.onValueChanged,
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
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: DropdownButtonFormField<String?>(
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
          ),
        );
    }
  }
}
