import 'package:flutter/material.dart';

/// Gates the app on a startup [future] — the schema migration / derived-index
/// back-fill run by `CompendiumRepositories.ensureMigrated()`. Shows a loading
/// screen while it runs (so nothing reads the derived indexes before they are
/// rebuilt), an error screen with retry if it fails, and [builder]'s content
/// once it completes.
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
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Preparing your collection',
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 8),
                  const Text('Could not prepare the collection.'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
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
