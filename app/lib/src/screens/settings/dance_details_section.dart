import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/display_defaults.dart';
import '../../data/repositories_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../data/walkthrough_snippet_library_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';
import '../shorthand_mappings_screen.dart';
import '../walkthrough_snippets_screen.dart';
import 'settings_keys.dart';

/// Settings for how dance details and figure entry use the active dialect.
class DanceDetailsAndShorthandsSection extends StatefulWidget {
  const DanceDetailsAndShorthandsSection({super.key});

  @override
  State<DanceDetailsAndShorthandsSection> createState() =>
      _DanceDetailsAndShorthandsSectionState();
}

class _DanceDetailsAndShorthandsSectionState
    extends State<DanceDetailsAndShorthandsSection> {
  bool _loaded = false;
  bool _canonicalFigureText = false;
  DanceDetailRendering _defaultRendering = DanceDetailRendering.activeDialect;
  bool _freeTextEntry = false;
  bool _canonicalFigureTextUserSet = false;
  bool _defaultRenderingUserSet = false;
  bool _freeTextEntryUserSet = false;

  void _ensureLoaded(BuildContext context) {
    if (_loaded) return;
    _loaded = true;
    final settings = RepositoriesScope.of(context).settings;
    settings
        .get(kCanonicalFigureTextKey)
        .then((stored) {
          if (!mounted || _canonicalFigureTextUserSet) return;
          setState(() => _canonicalFigureText = stored is bool && stored);
        })
        .catchError((_) {
          // diagnostics: silent — use the safe off default on read failure.
          if (!mounted || _canonicalFigureTextUserSet) return;
          setState(() => _canonicalFigureText = false);
        });
    settings
        .get(kDefaultDanceDetailRenderingKey)
        .then((stored) {
          if (!mounted || _defaultRenderingUserSet) return;
          setState(
            () => _defaultRendering = danceDetailRenderingFromStored(stored),
          );
        })
        .catchError((_) {
          // diagnostics: silent — use the active-dialect default on read failure.
          if (!mounted || _defaultRenderingUserSet) return;
          setState(
            () => _defaultRendering = DanceDetailRendering.activeDialect,
          );
        });
    settings
        .get(kFreeTextEntryKey)
        .then((stored) {
          if (!mounted || _freeTextEntryUserSet) return;
          setState(() => _freeTextEntry = stored is bool && stored);
        })
        .catchError((_) {
          // diagnostics: silent — use the safe off default on read failure.
          if (!mounted || _freeTextEntryUserSet) return;
          setState(() => _freeTextEntry = false);
        });
  }

  Future<void> _onCanonicalFigureTextChanged(bool value) async {
    setState(() {
      _canonicalFigureTextUserSet = true;
      _canonicalFigureText = value;
    });
    await RepositoriesScope.of(
      context,
    ).settings.set(kCanonicalFigureTextKey, value);
  }

  Future<void> _onDefaultRenderingChanged(DanceDetailRendering value) async {
    setState(() {
      _defaultRenderingUserSet = true;
      _defaultRendering = value;
    });
    await RepositoriesScope.of(
      context,
    ).settings.set(kDefaultDanceDetailRenderingKey, value.name);
  }

  Future<void> _onFreeTextEntryChanged(bool value) async {
    setState(() {
      _freeTextEntryUserSet = true;
      _freeTextEntry = value;
    });
    await RepositoriesScope.of(context).settings.set(kFreeTextEntryKey, value);
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded(context);
    final l10n = AppLocalizations.of(context);
    final shorthandController = ShorthandMappingsScope.maybeOf(context);
    final walkthroughController = WalkthroughSnippetLibraryScope.maybeOf(
      context,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.settingsDialectDanceDetailsHeader),
        SwitchListTile(
          key: const ValueKey('dialect-canonical-figure-text'),
          value: _canonicalFigureText,
          onChanged: _onCanonicalFigureTextChanged,
          title: Text(l10n.settingsDialectCanonicalFigureTextTitle),
          subtitle: Text(l10n.settingsDialectCanonicalFigureTextSubtitle),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('dialect-dance-detail-canonical'),
          value: _defaultRendering == DanceDetailRendering.canonical,
          onChanged: _canonicalFigureText
              ? (value) => _onDefaultRenderingChanged(
                  value
                      ? DanceDetailRendering.canonical
                      : DanceDetailRendering.activeDialect,
                )
              : null,
          title: Text(l10n.settingsDefaultsCanonicalTitle),
          subtitle: Text(l10n.settingsDefaultsCanonicalSubtitle),
          isThreeLine: true,
        ),
        SwitchListTile(
          key: const ValueKey('dialect-free-text-entry'),
          value: _freeTextEntry,
          onChanged: _onFreeTextEntryChanged,
          title: Text(l10n.settingsDefaultsFreeTextEntryTitle),
          subtitle: Text(l10n.settingsDefaultsFreeTextEntrySubtitle),
          isThreeLine: true,
        ),
        if (shorthandController != null)
          ListTile(
            key: const ValueKey('dialect-figure-shorthands'),
            enabled: _freeTextEntry,
            title: Text(l10n.settingsDefaultsFigureShorthandsTitle),
            subtitle: Text(
              shorthandController.mappings.isEmpty
                  ? l10n.settingsDefaultsFigureShorthandsEmptySubtitle
                  : l10n.settingsDefaultsFigureShorthandsCountSubtitle(
                      shorthandController.mappings.length,
                    ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _freeTextEntry
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ShorthandMappingsScreen(),
                    ),
                  )
                : null,
          ),
        if (walkthroughController != null)
          ListTile(
            key: const ValueKey('dialect-walkthrough-snippets'),
            title: Text(l10n.settingsWalkthroughSnippetsTitle),
            subtitle: Text(
              walkthroughController.library.isEmpty
                  ? l10n.settingsWalkthroughSnippetsSubtitle
                  : l10n.settingsWalkthroughSnippetsCount(
                      walkthroughController.library.length,
                    ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WalkthroughSnippetsScreen(),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
