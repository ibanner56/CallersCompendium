// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';
import '../../app_metadata.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../utils/launch_external_url.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/section_header.dart';
import '../user_guide/user_guide_screen.dart';

/// The About settings section (routing wrapper).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key, this.onOpenGuide});

  /// Selects the shell's User Guide destination. When `null` the "User guide"
  /// tile falls back to pushing the guide as a full-screen route.
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    return _AboutView(onOpenGuide: onOpenGuide);
  }
}

/// The About section: the app's brand home (mark, wordmark, version, and a
/// one-line mission) followed by the AGPL-3.0 notice with the corresponding
/// source offer (an AGPL conveyance obligation), attribution for the bundled
/// fonts, the "inspired by" theme note, and the dance-data provenance — plus a
/// "View licenses" entry into Flutter's `showLicensePage` (which also lists the
/// bundled font license texts registered via `registerBundledFontLicenses`).
///
/// The brand header at the top carries the app's identity and version; the
/// remaining entries build the structure and the compliance content.
class _AboutView extends StatelessWidget {
  const _AboutView({this.onOpenGuide});

  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        const _AboutBrandHeader(),
        SectionHeader(title: l10n.settingsAboutHelpHeader),
        ListTile(
          key: const ValueKey('about-user-guide'),
          leading: const Icon(Icons.help_outline),
          title: Text(l10n.settingsAboutUserGuideTitle),
          subtitle: Text(l10n.settingsAboutUserGuideSubtitle),
          trailing: const Icon(Icons.chevron_right),
          isThreeLine: true,
          onTap:
              onOpenGuide ??
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  // Standalone fallback (no shell to host the guide as a
                  // destination): the guide is embeddable and no longer
                  // self-hosts a Scaffold, so give the pushed route its own
                  // chrome — an AppBar (for a back affordance) and a Scaffold
                  // (so ScaffoldMessenger can show SnackBars). The guide now
                  // reserves the safe-area insets itself, so no SafeArea wrapper
                  // is needed here (that would double-inset).
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                      title: Text(l10n.settingsAboutUserGuideTitle),
                    ),
                    body: const UserGuideScreen(),
                  ),
                ),
              ),
        ),
        SectionHeader(title: l10n.settingsAboutLicenseHeader),
        _AboutParagraph(l10n.settingsAboutLicenseBody),
        ListTile(
          key: const ValueKey('about-source-link'),
          leading: const Icon(Icons.code),
          title: Text(l10n.settingsAboutViewSourceTitle),
          subtitle: const Text(kSourceRepoUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchExternalUrl(context, kSourceRepoUrl),
        ),
        SectionHeader(title: l10n.settingsAboutFontsHeader),
        _AboutParagraph(l10n.settingsAboutFontsBody),
        ListTile(
          dense: true,
          leading: const Icon(Icons.font_download_outlined),
          title: const Text('Fraunces'), // i18n-ignore (font name)
          subtitle: Text(l10n.settingsAboutFontFrauncesSubtitle),
          isThreeLine: true,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.font_download_outlined),
          title: const Text('Atkinson Hyperlegible'), // i18n-ignore (font name)
          subtitle: Text(l10n.settingsAboutFontAtkinsonSubtitle),
          isThreeLine: true,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.font_download_outlined),
          title: const Text('Roboto'), // i18n-ignore (font name)
          subtitle: Text(l10n.settingsAboutFontRobotoSubtitle),
          isThreeLine: true,
        ),
        SectionHeader(title: l10n.settingsAboutThemesHeader),
        _AboutParagraph(l10n.settingsAboutThemesBody),
        SectionHeader(title: l10n.settingsAboutDanceDataHeader),
        _AboutParagraph(l10n.settingsAboutDanceDataBody),
        SectionHeader(title: l10n.settingsAboutLicensesHeader),
        ListTile(
          key: const ValueKey('about-view-licenses'),
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.settingsAboutViewLicensesTitle),
          subtitle: Text(l10n.settingsAboutViewLicensesSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: kAppName,
            applicationVersion: kAppVersion,
            applicationLegalese: l10n.settingsAboutLegalese,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Text(
            l10n.settingsAboutVersionLine(
              kAppName,
              kAppVersion,
              kAppLicenseSpdx,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The centered brand home shown at the very top of the About section: the
/// full-color app mark, the [kAppName] wordmark in Fraunces, the current
/// version, and a one-line mission ([kAppTagline]). Carries the app identity
/// so the sections below can focus on compliance and attribution content.
class _AboutBrandHeader extends StatelessWidget {
  const _AboutBrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const ValueKey('about-brand-header'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const BrandMark(size: 80, showTile: true, semanticLabel: kAppName),
          const SizedBox(height: AppSpacing.md),
          Text(
            kAppName,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.settingsAboutVersion(kAppVersion),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kAppTagline,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// A left-aligned block of explanatory prose used throughout [_AboutView],
/// matching the section's `SectionHeader` rhythm and padding.
class _AboutParagraph extends StatelessWidget {
  const _AboutParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
  }
}
