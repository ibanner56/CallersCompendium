import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../utils/launch_external_url.dart';
import 'user_guide_doc_view.dart';
import 'user_guide_docs.dart';

/// The in-app **User Guide**: an offline reader for the bundled user
/// documentation (`assets/docs/user`, mirrored from `docs/user`).
///
/// Rendered as a persistent destination inside [AppShell]'s content area (not a
/// pushed full-screen route), so the shell's navigation chrome stays visible
/// while the guide is open. Opens on the documentation hub
/// ([kUserGuideHomeDoc]) and keeps an in-panel navigation stack: tapping a link
/// to another bundled guide pushes it here and the in-content back affordance
/// returns to the previous guide. Links to not-yet-written guides surface a
/// brief message; external and non-bundled repo links open in the browser via
/// [launchExternalUrl]. Nothing is fetched from the network to render a guide.
class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({
    super.key,
    this.bundle,
    this.initialDoc,
    this.isActive = true,
  });

  /// Asset bundle to load guides from; defaults to the root bundle. A test
  /// seam for injecting a fixture bundle.
  final AssetBundle? bundle;

  /// The guide to open on; defaults to the hub ([kUserGuideHomeDoc]).
  final String? initialDoc;

  /// Whether this is the current shell destination. Because the guide is kept
  /// alive in an [IndexedStack], an offscreen instance must not intercept the
  /// system back gesture; only the active guide with in-panel history does.
  final bool isActive;

  @override
  State<UserGuideScreen> createState() => _UserGuideScreenState();
}

class _UserGuideScreenState extends State<UserGuideScreen> {
  late final Future<UserGuideDocs> _docsFuture;
  UserGuideDocs? _docs;
  late final List<String> _stack;

  @override
  void initState() {
    super.initState();
    _stack = [widget.initialDoc ?? kUserGuideHomeDoc];
    _docsFuture = UserGuideDocs.load(widget.bundle).then((docs) {
      _docs = docs;
      return docs;
    });
  }

  String get _current => _stack.last;

  bool get _canGoBackInPanel => _stack.length > 1;

  /// Returns to the previous guide in the in-panel stack. Only reachable while
  /// there is history (the back affordance is hidden at the hub), so there is
  /// nothing to pop out to — the guide is a shell destination, not a route.
  void _handleBack() {
    if (_canGoBackInPanel) {
      setState(() => _stack.removeLast());
    }
  }

  void _openLink(String href) {
    final docs = _docs;
    if (docs == null) return;
    final target = docs.resolveLink(_current, href);
    switch (target) {
      case GuideInternalLink(:final docId):
        if (docId != _current) {
          setState(() => _stack.add(docId));
        }
      case GuideMissingLink(:final label):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('The "$label" guide isn\'t available yet.')),
          );
      case GuideExternalLink(:final url):
        launchExternalUrl(context, url);
    }
  }

  String get _title => _current == kUserGuideHomeDoc
      ? 'User guide'
      : UserGuideDocs.labelForDoc(_current);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // While the active guide has in-panel history, intercept back so the
      // first "back" returns to the previous guide. An offscreen (kept-alive)
      // guide never intercepts, so back behaves normally on other destinations.
      canPop: !(widget.isActive && _canGoBackInPanel),
      onPopInvokedWithResult: (didPop, result) {
        // Only the active guide consumes back to rewind its in-panel stack; an
        // offscreen (kept-alive) instance must ignore back presses handled by
        // another destination so it never mutates its stack while hidden.
        if (!didPop && widget.isActive && _canGoBackInPanel) {
          setState(() => _stack.removeLast());
        }
      },
      child: Column(
        key: const ValueKey('user-guide-screen'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GuideHeader(
            title: _title,
            onBack: _canGoBackInPanel ? _handleBack : null,
          ),
          Expanded(
            child: FutureBuilder<UserGuideDocs>(
              future: _docsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data;
                if (snapshot.hasError || docs == null || docs.isEmpty) {
                  return _UnavailableState(
                    onOpenOnline: () =>
                        launchExternalUrl(context, kUserGuideOnlineUrl),
                  );
                }
                return _buildDoc(docs);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoc(UserGuideDocs docs) {
    return FutureBuilder<String>(
      // Key the read on the current doc so navigation reloads (and the view's
      // keyed ListView resets scroll to the top of the new guide).
      key: ValueKey('user-guide-body-$_current'),
      future: docs.read(_current),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (snapshot.hasError || data == null) {
          return _UnavailableState(
            onOpenOnline: () => launchExternalUrl(context, kUserGuideOnlineUrl),
          );
        }
        return UserGuideDocView(
          docId: _current,
          data: data,
          onTapLink: _openLink,
        );
      },
    );
  }
}

/// The slim in-content header for the embedded guide: the current guide's title
/// plus an in-panel back affordance shown **only** when there is history to go
/// back to. There is no "close" affordance — the guide is a persistent shell
/// destination, so the shell nav (not this header) is how you leave it.
class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.title, this.onBack});

  final String title;

  /// Returns to the previous guide; `null` at the hub (no history), which hides
  /// the back button.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    key: const ValueKey('user-guide-back'),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: onBack,
                  )
                else
                  const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('user-guide-title'),
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }
}

/// Shown if the bundled guides can't be loaded (e.g. a broken build). Offers a
/// link to the online documentation as a fallback — the only place in the
/// guide that reaches the network, and only on explicit tap.
class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.onOpenOnline});

  final VoidCallback onOpenOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'The user guide could not be loaded.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('user-guide-open-online'),
              onPressed: onOpenOnline,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open the guide online'),
            ),
          ],
        ),
      ),
    );
  }
}
