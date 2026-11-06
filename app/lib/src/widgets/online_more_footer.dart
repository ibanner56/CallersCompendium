import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The last item of an online results list that has more to load.
///
/// A list builds its items lazily, so this is built only once the end of the
/// list is near the viewport: that is the cue to fetch the next page, which
/// [onLoad] does (once, after the first frame). Give it a key that changes with
/// the number of rows, so each new page builds a fresh footer and a page that
/// still leaves the end in view asks for the next one.
///
/// While [failed] it asks for nothing and shows [failedMessage] with a retry
/// button instead, so a source that is down is not asked again in a loop.
class OnlineMoreFooter extends StatefulWidget {
  const OnlineMoreFooter({
    super.key,
    required this.failed,
    required this.failedMessage,
    required this.onLoad,
    required this.onRetry,
  });

  final bool failed;
  final String failedMessage;
  final VoidCallback onLoad;
  final VoidCallback onRetry;

  @override
  State<OnlineMoreFooter> createState() => _OnlineMoreFooterState();
}

class _OnlineMoreFooterState extends State<OnlineMoreFooter> {
  @override
  void initState() {
    super.initState();
    if (!widget.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.failed) widget.onLoad();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.failed) {
      return Padding(
        key: const ValueKey('online-more-failed'),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(widget.failedMessage, textAlign: TextAlign.center),
            TextButton(
              key: const ValueKey('online-more-retry'),
              onPressed: widget.onRetry,
              child: Text(l10n.commonTryAgain),
            ),
          ],
        ),
      );
    }
    return const Padding(
      key: ValueKey('online-more-loading'),
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
