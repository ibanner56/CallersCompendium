import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_metadata.dart';
import 'install_location_channel.dart';

/// App-wide notice that the macOS app is running from the disk image (or a
/// translocated copy) rather than from Applications — issue #1725. Hosted at
/// the app shell beside the [RetirementBanner] and matching it: non-modal, and
/// "Dismiss" hides it only until the next launch. Nothing is persisted; the
/// check re-runs every launch and stops firing once the app is installed.
///
/// Renders nothing on every other platform, and until the native check (which
/// runs off the main thread and never delays startup) reports the condition.
class InstallLocationBanner extends StatefulWidget {
  const InstallLocationBanner({super.key, this.channel, this.platform});

  /// Test seam; a real [InstallLocationChannel] when null.
  final InstallLocationChannel? channel;

  /// Test seam; [defaultTargetPlatform] when null.
  final TargetPlatform? platform;

  @override
  State<InstallLocationBanner> createState() => _InstallLocationBannerState();
}

class _InstallLocationBannerState extends State<InstallLocationBanner> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    if ((widget.platform ?? defaultTargetPlatform) != TargetPlatform.macOS) {
      return;
    }
    (widget.channel ?? InstallLocationChannel()).isRunningUninstalled().then((
      uninstalled,
    ) {
      if (uninstalled && mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return MaterialBanner(
      key: const ValueKey('install-location-banner'),
      leading: const Icon(Icons.drive_file_move_outlined),
      content: Text(l10n.installLocationBannerMessage(kAppName)),
      actions: [
        TextButton(
          key: const ValueKey('install-location-banner-dismiss'),
          onPressed: () => setState(() => _show = false),
          child: Text(l10n.installLocationBannerDismiss),
        ),
      ],
    );
  }
}
