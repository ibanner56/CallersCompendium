import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/custom_theme.dart';
import '../theme/wcag.dart';
import '../widgets/color_edit_dialog.dart';

/// Full-role editor for a [CustomTheme] (`docs/design/ux-modernization.md`
/// §4B). Lets the user rename the theme and edit every major color role, with
/// live WCAG AA pass/fail badges on the key foreground/background pairs.
///
/// AA is **warn-but-allow**: failing pairs are flagged clearly but never block
/// saving (the caller decided some palettes are intentionally low-contrast).
/// Returns the edited [CustomTheme] via [Navigator.pop], or `null` if canceled.
class ThemeEditorScreen extends StatefulWidget {
  const ThemeEditorScreen({super.key, required this.initial});

  final CustomTheme initial;

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late CustomTheme _theme;
  late Map<String, int> _resolved;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _setTheme(widget.initial);
    _nameController = TextEditingController(text: _theme.name);
  }

  /// Updates the edited theme and recomputes the cached resolved role map once,
  /// rather than rebuilding it on every [_colorOf] lookup during a frame.
  void _setTheme(CustomTheme theme) {
    _theme = theme;
    _resolved = CustomTheme.rolesFromScheme(theme.toScheme());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Every editable role resolved to a concrete color (defaults fill any gaps),
  /// keyed by role name — cached via [_setTheme] and reused for swatches,
  /// badges, and the preview.
  Color _colorOf(String key) => Color(_resolved[key]!);

  Future<void> _editRole(ColorRole role) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) =>
          ColorEditDialog(title: role.label, initial: _colorOf(role.key)),
    );
    if (picked != null) {
      setState(() => _setTheme(_theme.withColor(role.key, picked)));
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    Navigator.of(
      context,
    ).pop(_theme.copyWith(name: name.isEmpty ? _theme.name : name));
  }

  int get _failingPairs => CustomThemeRoles.allPairs
      .where(
        (p) => !Wcag.meetsAA(
          _colorOf(p.foreground),
          _colorOf(p.background),
          largeOrNonText: p.largeOrNonText,
        ),
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final failing = _failingPairs;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.themeEditorTitle),
        actions: [TextButton(onPressed: _save, child: Text(l10n.commonSave))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _PreviewCard(scheme: _theme.toScheme()),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.themeEditorNameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (failing > 0)
            _AaWarningBanner(failing: failing)
          else
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.themeEditorContrastAllPass,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          for (final group in CustomThemeRoles.groups)
            _RoleGroupSection(
              group: group,
              colorOf: _colorOf,
              onEdit: _editRole,
            ),
        ],
      ),
    );
  }
}

class _AaWarningBanner extends StatelessWidget {
  const _AaWarningBanner({required this.failing});

  final int failing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // `liveRegion: true` makes assistive tech announce the warning when the
    // banner appears — and re-announce when the failing-pair count changes —
    // so AT users get the same heads-up sighted users do before an app-wide
    // low-contrast theme takes effect (warn-but-allow). See issue #448.
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.themeEditorContrastFailing(failing),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleGroupSection extends StatelessWidget {
  const _RoleGroupSection({
    required this.group,
    required this.colorOf,
    required this.onEdit,
  });

  final RoleGroup group;
  final Color Function(String key) colorOf;
  final ValueChanged<ColorRole> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            group.label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        for (final pair in group.pairs)
          _ContrastBadge(
            label: pair.label,
            ratio: Wcag.contrastRatio(
              colorOf(pair.foreground),
              colorOf(pair.background),
            ),
            passes: Wcag.meetsAA(
              colorOf(pair.foreground),
              colorOf(pair.background),
              largeOrNonText: pair.largeOrNonText,
            ),
          ),
        if (group.pairs.isNotEmpty) const SizedBox(height: 8),
        for (final role in group.roles)
          _RoleTile(
            role: role,
            color: colorOf(role.key),
            onTap: () => onEdit(role),
          ),
      ],
    );
  }
}

class _ContrastBadge extends StatelessWidget {
  const _ContrastBadge({
    required this.label,
    required this.ratio,
    required this.passes,
  });

  final String label;
  final double ratio;
  final bool passes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final color = passes ? theme.colorScheme.primary : theme.colorScheme.error;
    final ratioText = ratio.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            passes ? Icons.check_circle : Icons.error,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            passes
                ? l10n.themeEditorRatioPass(ratioText)
                : l10n.themeEditorRatioFail(ratioText),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.color,
    required this.onTap,
  });

  final ColorRole role;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hex =
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return ListTile(
      key: ValueKey('role-${role.key}'),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
      ),
      title: Text(role.label),
      subtitle: Text(hex),
      trailing: const Icon(Icons.edit_outlined, size: 18),
    );
  }
}

/// A compact live preview of the theme being edited.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.themeEditorPreviewHeading,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.themeEditorBodySample,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _swatch(
                l10n.themeEditorSwatchPrimary,
                scheme.primary,
                scheme.onPrimary,
              ),
              _swatch(
                l10n.themeEditorSwatchSecondary,
                scheme.secondary,
                scheme.onSecondary,
              ),
              _swatch(
                l10n.themeEditorSwatchTertiary,
                scheme.tertiary,
                scheme.onTertiary,
              ),
              _swatch(
                l10n.themeEditorSwatchError,
                scheme.error,
                scheme.onError,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatch(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
