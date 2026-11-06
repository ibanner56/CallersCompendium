import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/calling_card_settings_scope.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../export/calling_card_layout.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/settings_dropdown_row.dart';
import 'calling_card_labels.dart';
import 'calling_card_layout_editor_screen.dart';

/// The size dropdown's value for "enter your own width and height".
const String _customSizeId = 'custom';

/// Settings › Experimental › Calling cards: whether the Export menus offer
/// calling cards, the card size, and the row into the layout editor.
class CallingCardSection extends StatefulWidget {
  const CallingCardSection({super.key, this.rasterizer});

  /// Forwarded to the layout editor's preview; see [CallingCardRasterizer].
  final CallingCardRasterizer? rasterizer;

  @override
  State<CallingCardSection> createState() => _CallingCardSectionState();
}

class _CallingCardSectionState extends State<CallingCardSection> {
  final _width = TextEditingController();
  final _height = TextEditingController();

  /// Whether the custom fields are shown. Starts on when the stored size is
  /// no preset; picking Custom turns it on even for a size that is one.
  bool? _custom;
  bool _customInvalid = false;

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  Future<void> _save(CallingCardSettings next) async {
    final notifier = CallingCardSettingsScope.notifierOf(context);
    if (next == notifier.value) return;
    final settings = RepositoriesScope.of(context).settings;
    notifier.value = next;
    await persistSetting(settings, kCallingCardSettingsKey, next.toJson());
  }

  static String? _presetFor(CallingCardSize size) {
    for (final MapEntry(:key, :value) in kCallingCardSizePresets.entries) {
      if (value.sameCardAs(size)) return key;
    }
    return null;
  }

  void _fillCustomFields(AppLocalizations l10n, CallingCardSize size) {
    _width.text = callingCardSideLabel(l10n, size.width);
    _height.text = callingCardSideLabel(l10n, size.height);
    _customInvalid = false;
  }

  double? _parseSide(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  void _onCustomChanged(CallingCardSettings current) {
    final width = _parseSide(_width.text);
    final height = _parseSide(_height.text);
    final size = width == null || height == null
        ? null
        : CallingCardSize(width, height, current.size.unit);
    final valid = size != null && size.isValid;
    setState(() => _customInvalid = !valid);
    if (valid) _save(current.copyWith(size: size));
  }

  void _onUnitChanged(
    AppLocalizations l10n,
    CallingCardSettings current,
    CallingCardUnit unit,
  ) {
    final from = current.size;
    if (from.unit == unit) return;
    // Two decimals of an inch, so millimetres survive the round trip
    // (105 mm is 4.13 in, which comes back as 104.9 mm, not 104.1).
    final places = unit == CallingCardUnit.inch ? 100 : 10;
    double convert(double v) =>
        (v * from.unit.points / unit.points * places).roundToDouble() / places;
    final size = CallingCardSize(
      convert(from.width),
      convert(from.height),
      unit,
    );
    _fillCustomFields(l10n, size);
    if (size.isValid) _save(current.copyWith(size: size));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = CallingCardSettingsScope.of(context);
    final enabled = settings.enabled;
    final preset = _presetFor(settings.size);
    if (_custom == null) {
      _custom = preset == null;
      if (_custom!) _fillCustomFields(l10n, settings.size);
    }
    // A size from elsewhere (Device Sync, a restore) that is no preset opens
    // the custom fields, or the dropdown would have no value to show. The
    // fields are not on screen yet, so filling them notifies no one.
    if (!_custom! && preset == null) {
      _custom = true;
      _fillCustomFields(l10n, settings.size);
    }
    final custom = _custom!;

    return CollapsibleSection(
      sectionKey: const ValueKey('calling-card-section'),
      title: l10n.settingsCallingCardsHeader,
      expanded: enabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            key: const ValueKey('calling-card-enabled'),
            secondary: const Icon(Icons.style_outlined),
            value: enabled,
            onChanged: (value) => _save(settings.copyWith(enabled: value)),
            title: Text(l10n.settingsCallingCardsEnableTitle),
            subtitle: Text(l10n.settingsCallingCardsEnableSubtitle),
            isThreeLine: true,
          ),
          SettingsDropdownRow(
            title: Text(l10n.settingsCallingCardsSizeTitle),
            subtitle: Text(callingCardSizeLabel(l10n, settings.size)),
            dropdownBuilder: (expanded) => DropdownButton<String>(
              key: const ValueKey('calling-card-size'),
              isExpanded: expanded,
              value: custom ? _customSizeId : preset,
              onChanged: (id) {
                if (id == null) return;
                if (id == _customSizeId) {
                  setState(() {
                    _custom = true;
                    _fillCustomFields(l10n, settings.size);
                  });
                  return;
                }
                setState(() => _custom = false);
                _save(
                  settings.copyWith(
                    size: kCallingCardSizePresets[id]!.oriented(
                      landscape: settings.size.isLandscape,
                    ),
                  ),
                );
              },
              items: [
                for (final id in kCallingCardSizePresets.keys)
                  DropdownMenuItem(
                    value: id,
                    child: Text(callingCardPresetLabel(l10n, id)),
                  ),
                DropdownMenuItem(
                  value: _customSizeId,
                  child: Text(l10n.settingsCallingCardsSizeCustom),
                ),
              ],
            ),
          ),
          if (custom) _customFields(l10n, settings),
          SwitchListTile(
            key: const ValueKey('calling-card-landscape'),
            value: settings.size.isLandscape,
            onChanged: (landscape) {
              final size = settings.size.oriented(landscape: landscape);
              if (custom) setState(() => _fillCustomFields(l10n, size));
              _save(settings.copyWith(size: size));
            },
            title: Text(l10n.settingsCallingCardsLandscapeTitle),
            subtitle: Text(l10n.settingsCallingCardsLandscapeSubtitle),
          ),
          ListTile(
            key: const ValueKey('calling-card-layout-open'),
            leading: const Icon(Icons.edit_note_outlined),
            title: Text(l10n.settingsCallingCardsLayoutTitle),
            subtitle: Text(l10n.settingsCallingCardsLayoutSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CallingCardLayoutEditorScreen(
                  rasterizer: widget.rasterizer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _customFields(AppLocalizations l10n, CallingCardSettings settings) {
    final error = _customInvalid ? l10n.settingsCallingCardsSizeInvalid : null;
    InputDecoration decoration(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('calling-card-width'),
                  controller: _width,
                  keyboardType: numberKeyboard,
                  decoration: decoration(l10n.settingsCallingCardsWidthLabel),
                  onChanged: (_) => _onCustomChanged(settings),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  key: const ValueKey('calling-card-height'),
                  controller: _height,
                  keyboardType: numberKeyboard,
                  decoration: decoration(l10n.settingsCallingCardsHeightLabel),
                  onChanged: (_) => _onCustomChanged(settings),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              DropdownButton<CallingCardUnit>(
                key: const ValueKey('calling-card-unit'),
                value: settings.size.unit,
                onChanged: (unit) {
                  if (unit != null) {
                    setState(() => _onUnitChanged(l10n, settings, unit));
                  }
                },
                items: [
                  DropdownMenuItem(
                    value: CallingCardUnit.inch,
                    child: Text(l10n.settingsCallingCardsUnitInches),
                  ),
                  DropdownMenuItem(
                    value: CallingCardUnit.millimetre,
                    child: Text(l10n.settingsCallingCardsUnitMillimetres),
                  ),
                ],
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                error,
                key: const ValueKey('calling-card-size-invalid'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
