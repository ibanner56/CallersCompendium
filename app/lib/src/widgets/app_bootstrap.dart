import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/migration_guard.dart' show DatabaseDowngradeError;

/// Gates the app on a startup [future] — the schema migration / derived-index
/// back-fill run by `CompendiumRepositories.ensureMigrated()`. Shows a loading
/// screen while it runs (so nothing reads the derived indexes before they are
/// rebuilt), an error screen with retry if it fails, and [builder]'s content
/// once it completes.
///
/// One error is special-cased: a [DatabaseDowngradeError] (the on-disk data was
/// written by a newer build) shows that error's guidance and *no* Retry — the
/// only fix is to update the app, so retrying would just fail again.
class AppBootstrap extends StatelessWidget {
  const AppBootstrap({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
  });

  final Future<void> future;
  final WidgetBuilder builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: future,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context);
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                semanticsLabel: l10n.appBootstrapPreparing,
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is DatabaseDowngradeError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.system_update_alt, size: 48),
                      const SizedBox(height: 8),
                      Text(error.message, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            );
          }
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 8),
                  Text(l10n.appBootstrapError),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ),
            ),
          );
        }
        return builder(context);
      },
    );
  }
}
