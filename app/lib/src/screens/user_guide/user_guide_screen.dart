import 'package:flutter/material.dart';

import '../../utils/launch_external_url.dart';
import 'user_guide_doc_view.dart';
import 'user_guide_docs.dart';

/// The in-app **User Guide**: an offline reader for the bundled user
/// documentation (`assets/docs/user`, mirrored from `docs/user`).
///
/// Opens on the documentation hub ([kUserGuideHomeDoc]) and keeps an in-panel
/// navigation stack: tapping a link to another bundled guide pushes it here and
/// the back affordance returns to the previous guide (only leaving the guide
/// once the stack is back at the hub). Links to not-yet-written guides surface
/// a brief message; external and non-bundled repo links open in the browser via
/// [launchExternalUrl]. Nothing is fetched from the network to render a guide.
class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({super.key, this.bundle, this.initialDoc});

  /// Asset bundle to load guides from; defaults to the root bundle. A test
  /// seam for injecting a fixture bundle.
  final AssetBundle? bundle;

  /// The guide to open on; defaults to the hub ([kUserGuideHomeDoc]).
  final String? initialDoc;

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

  void _handleBack() {
    if (_canGoBackInPanel) {
      setState(() => _stack.removeLast());
    } else {
      Navigator.of(context).maybePop();
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
      // While the in-panel stack has history, intercept back so the first
      // "back" returns to the previous guide rather than leaving the panel.
      canPop: !_canGoBackInPanel,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _canGoBackInPanel) {
          setState(() => _stack.removeLast());
        }
      },
      child: Scaffold(
        key: const ValueKey('user-guide-screen'),
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('user-guide-back'),
            icon: Icon(_canGoBackInPanel ? Icons.arrow_back : Icons.close),
            tooltip: _canGoBackInPanel ? 'Back' : 'Close',
            onPressed: _handleBack,
          ),
          title: Text(_title),
        ),
        body: FutureBuilder<UserGuideDocs>(
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
          docs: docs,
          docId: _current,
          data: data,
          onTapLink: _openLink,
        );
      },
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
              Icons.menu_book_outlined,
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
