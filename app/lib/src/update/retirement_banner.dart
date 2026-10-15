import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_metadata.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../utils/launch_external_url.dart';
import 'update_controller.dart';
import 'update_scope.dart';

/// Where "Get update" goes when no check this session has found a newer
/// release to link to: the project's release list, which always names the
/// current versions.
const String kReleasesPageUrl = '$kSourceRepoUrl/releases';

/// The sentence announcing [notice] for the running build — a deadline before
/// the end-of-life day, a lapse from it on. Shared by [RetirementBanner] and
/// Settings ▸ Updates so the two never word it differently.
String retirementNoticeMessage(
  BuildContext context,
  UpdateController controller,
  RetirementNotice notice,
) {
  final l10n = AppLocalizations.of(context);
  // The user's date-format preference when it names a fixed pattern. The
  // system default falls back to the *full* date rather than the medium one
  // event dates use: the medium form omits the year, and a deadline without
  // its year is ambiguous.
  final date =
      formatDatePattern(
        notice.endOfLife,
        DateFormatScope.of(context),
        monthNames: monthNamesFromL10n(l10n),
      ) ??
      MaterialLocalizations.of(context).formatFullDate(notice.endOfLife);
  final version = controller.currentVersion.toString();
  return notice.isPast
      ? l10n.retirementNoticePast(kAppName, version, date)
      : l10n.retirementNoticeUpcoming(kAppName, version, date);
}

/// Opens the newer release found by this session's check, or the release list
/// when none was found (a check may not have run, or the user's channel may
/// have nothing newer than a retired beta).
Future<void> openRetirementUpdatePage(
  BuildContext context,
  UpdateController controller,
) => launchExternalUrl(
  context,
  controller.foundUpdate?.releaseNotesUrl ?? kReleasesPageUrl,
);

/// App-wide end-of-support banner (ADR-002 §2 `retirements`). Hosted at the
/// app shell beside the [UpdateBanner] so it shows on every tab. Non-modal, as
/// ADR-002 §5 requires of anything the update client surfaces — but "Later"
/// hides it only until the next launch, because the user cannot opt out of an
/// end of support the way they can skip one update.
///
/// Renders nothing unless the running build has a known end-of-life date.
class RetirementBanner extends StatelessWidget {
  const RetirementBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = UpdateScope.of(context);
    final notice = controller.retirementBanner;
    if (notice == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      key: const ValueKey('retirement-banner'),
      backgroundColor: notice.isPast ? scheme.errorContainer : null,
      leading: Icon(
        Icons.event_busy_outlined,
        color: notice.isPast ? scheme.onErrorContainer : null,
      ),
      content: Text(
        retirementNoticeMessage(context, controller, notice),
        style: notice.isPast ? TextStyle(color: scheme.onErrorContainer) : null,
      ),
      actions: [
        TextButton(
          key: const ValueKey('retirement-banner-later'),
          onPressed: () =>
              UpdateScope.controllerOf(context).hideRetirementBanner(),
          child: Text(l10n.retirementBannerLater),
        ),
        TextButton(
          key: const ValueKey('retirement-banner-update'),
          onPressed: () => openRetirementUpdatePage(context, controller),
          child: Text(l10n.retirementBannerGetUpdate),
        ),
      ],
    );
  }
}
