import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';

/// The Experimental settings section for features still in development.
class ExperimentalSection extends StatelessWidget {
  const ExperimentalSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      children: [
        SectionHeader(title: l10n.settingsExperimentalTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(l10n.settingsExperimentalPlaceholder),
        ),
      ],
    );
  }
}
