import 'package:flutter/material.dart';

import '../app_metadata.dart';
import '../utils/launch_external_url.dart';
import 'update_controller.dart';
import 'update_scope.dart';

/// App-wide update banner (ADR-002 §4/§5). Hosted once at the app shell (above
/// the shell content) so it can appear on any tab, it is **dismissible and
/// non-modal** — never a modal interrupt during a gig.
///
/// Renders nothing unless the [UpdateController] has a newer version to show
/// (after the dismissed-version gate). Its primary action opens the release
/// page via the existing [launchExternalUrl] seam (which deep-links to the
/// store/release page on mobile); "Dismiss" records the version so it is not
/// shown again until a strictly-newer one appears.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = UpdateScope.of(context);
    final update = controller.bannerUpdate;
    if (update == null) return const SizedBox.shrink();

    return MaterialBanner(
      key: const ValueKey('update-banner'),
      content: Text(
        'A newer version of $kAppName (${update.version}) is available.',
      ),
      leading: const Icon(Icons.system_update_alt),
      actions: [
        TextButton(
          key: const ValueKey('update-banner-dismiss'),
          onPressed: () =>
              UpdateScope.controllerOf(context).dismiss(update.version),
          child: const Text('Dismiss'),
        ),
        TextButton(
          key: const ValueKey('update-banner-view'),
          onPressed: () => launchExternalUrl(context, update.releaseNotesUrl),
          child: const Text('View release'),
        ),
      ],
    );
  }
}
