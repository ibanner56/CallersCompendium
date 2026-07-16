// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';
import '../../app_metadata.dart';
import '../../theme/app_spacing.dart';
import '../../utils/launch_external_url.dart';
import '../../widgets/section_header.dart';

/// The About settings section (routing wrapper).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AboutView();
  }
}

/// The About section: app identity, the AGPL-3.0 notice with the corresponding
/// source offer (an AGPL conveyance obligation), attribution for the bundled
/// fonts, the "inspired by" theme note, and the dance-data provenance — plus a
/// "View licenses" entry into Flutter's `showLicensePage` (which also lists the
/// bundled font license texts registered via `registerBundledFontLicenses`).
///
/// Intentionally brand-free: a later item layers the app mark / Fraunces
/// wordmark on top of this same section, so this half only builds the structure
/// and the compliance content.
class _AboutView extends StatelessWidget {
  const _AboutView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        SectionHeader(title: 'About'),
        const ListTile(
          key: ValueKey('about-app-version'),
          leading: Icon(Icons.info_outline),
          title: Text(kAppName),
          subtitle: Text('Version $kAppVersion'),
        ),
        SectionHeader(title: 'License'),
        const _AboutParagraph(
          "Caller's Compendium is free software, licensed under the GNU "
          'Affero General Public License, version 3 (AGPL-3.0). You are free '
          'to use, study, share, and modify it under that license. Because the '
          'AGPL requires it, the complete corresponding source code is offered '
          'to everyone who uses the app.',
        ),
        ListTile(
          key: const ValueKey('about-source-link'),
          leading: const Icon(Icons.code),
          title: const Text('View source on GitHub'),
          subtitle: const Text(kSourceRepoUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchExternalUrl(context, kSourceRepoUrl),
        ),
        SectionHeader(title: 'Fonts'),
        const _AboutParagraph(
          'This app bundles the following typefaces under the SIL Open Font '
          'License 1.1. Their full license texts are available under '
          '“View licenses” below.',
        ),
        const ListTile(
          dense: true,
          leading: Icon(Icons.font_download_outlined),
          title: Text('Fraunces'),
          subtitle: Text(
            'SIL Open Font License 1.1 · © The Fraunces Project Authors — '
            'display & headings',
          ),
          isThreeLine: true,
        ),
        const ListTile(
          dense: true,
          leading: Icon(Icons.font_download_outlined),
          title: Text('Atkinson Hyperlegible'),
          subtitle: Text(
            'SIL Open Font License 1.1 · © Braille Institute of America, Inc. '
            '— body, UI & Perform',
          ),
          isThreeLine: true,
        ),
        const ListTile(
          dense: true,
          leading: Icon(Icons.font_download_outlined),
          title: Text('Roboto'),
          subtitle: Text(
            'SIL Open Font License 1.1 · © The Roboto Project Authors — '
            'fallback',
          ),
          isThreeLine: true,
        ),
        SectionHeader(title: 'Themes'),
        const _AboutParagraph(
          'Several optional color themes are inspired by popular code-editor '
          'palettes — One Dark, Dracula, Nord, Tokyo Night, Gruvbox, and '
          'Catppuccin among them — re-derived and contrast-tuned for this app. '
          'Theme names are used only to credit that inspiration.',
        ),
        SectionHeader(title: 'Dance data'),
        const _AboutParagraph(
          'Dance data draws on The Caller’s Box (Chris Page & Michael Dyck), '
          'whose collection is published under the Creative Commons '
          'Attribution-NonCommercial license (CC BY-NC), with gratitude.',
        ),
        SectionHeader(title: 'Licenses'),
        ListTile(
          key: const ValueKey('about-view-licenses'),
          leading: const Icon(Icons.description_outlined),
          title: const Text('View licenses'),
          subtitle: const Text(
            'Full open-source license texts, including the bundled fonts.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: kAppName,
            applicationVersion: kAppVersion,
            applicationLegalese:
                '© The Caller’s Compendium contributors. '
                'Licensed under AGPL-3.0.',
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
            '$kAppName · Version $kAppVersion · $kAppLicenseSpdx',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
