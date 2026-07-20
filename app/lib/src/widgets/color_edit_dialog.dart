import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A lightweight, dependency-free color editor: a live swatch, a hex field, and
/// R/G/B sliders. Returns the chosen [Color] (fully opaque) via
/// [Navigator.pop], or `null` if canceled.
///
/// Shared by the custom-theme editor and the per-formation color picker
/// (issue #367) so both use the same accessible, no-extra-dependency control.
class ColorEditDialog extends StatefulWidget {
  const ColorEditDialog({
    super.key,
    required this.title,
    required this.initial,
  });

  final String title;
  final Color initial;

  @override
  State<ColorEditDialog> createState() => _ColorEditDialogState();
}

class _ColorEditDialogState extends State<ColorEditDialog> {
  late int _r;
  late int _g;
  late int _b;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    final argb = widget.initial.toARGB32();
    _r = (argb >> 16) & 0xFF;
    _g = (argb >> 8) & 0xFF;
    _b = argb & 0xFF;
    _hexController = TextEditingController(text: _hex);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color => Color.fromARGB(0xFF, _r, _g, _b);

  String get _hex =>
      '#${((_r << 16) | (_g << 8) | _b).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _syncHexField() {
    _hexController.value = TextEditingValue(
      text: _hex,
      selection: TextSelection.collapsed(offset: _hex.length),
    );
  }

  void _onHexSubmitted(String value) {
    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final parsed = int.tryParse(cleaned, radix: 16);
      if (parsed != null) {
        setState(() {
          _r = (parsed >> 16) & 0xFF;
          _g = (parsed >> 8) & 0xFF;
          _b = parsed & 0xFF;
        });
        _syncHexField();
        return;
      }
    }
    // Reject invalid input by restoring the current color's hex.
    _syncHexField();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              decoration: const InputDecoration(
                labelText: 'Hex',
                prefixText: '',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(7),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              ],
              onSubmitted: _onHexSubmitted,
            ),
            const SizedBox(height: 8),
            _channel('R', _r, (v) {
              setState(() => _r = v);
              _syncHexField();
            }),
            _channel('G', _g, (v) {
              setState(() => _g = v);
              _syncHexField();
            }),
            _channel('B', _b, (v) {
              setState(() => _b = v);
              _syncHexField();
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _channel(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 18, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }
}
