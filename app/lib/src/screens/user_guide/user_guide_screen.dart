import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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
  late final List<_GuideRef> _stack;
  Future<_GuideBody>? _bodyFuture;

  /// Increments on every anchor request so following the *same* in-page link
  /// twice scrolls again rather than being ignored as "no change".
  int _anchorRequest = 0;

  @override
  void initState() {
    super.initState();
    _stack = [_GuideRef(widget.initialDoc ?? kUserGuideHomeDoc)];
    _docsFuture = UserGuideDocs.load(widget.bundle).then((docs) {
      _docs = docs;
      _loadCurrent();
      return docs;
    });
  }

  _GuideRef get _currentRef => _stack.last;

  String get _current => _currentRef.docId;

  bool get _canGoBackInPanel => _stack.length > 1;

  /// Starts reading the guide at the top of the stack. Resolving the title from
  /// the same read as the body keeps the header and the prose in step, so the
  /// panel never shows one guide's title above another's text.
  void _loadCurrent() {
    final docs = _docs;
    if (docs == null) return;
    final docId = _current;
    _bodyFuture = docs
        .read(docId)
        .then(
          (data) => _GuideBody(
            docId: docId,
            data: data,
            title:
                UserGuideDocs.titleFromMarkdown(data) ??
                UserGuideDocs.labelForDoc(docId),
          ),
        );
  }

  /// Returns to the previous guide in the in-panel stack. Only reachable while
  /// there is history (the back affordance is hidden at the hub), so there is
  /// nothing to pop out to — the guide is a shell destination, not a route.
  void _handleBack() {
    if (_canGoBackInPanel) {
      setState(() {
        _stack.removeLast();
        _loadCurrent();
      });
    }
  }

  void _openLink(String href) {
    final docs = _docs;
    if (docs == null) return;
    final target = docs.resolveLink(_current, href);
    switch (target) {
      case GuideInternalLink(:final docId, :final fragment):
        if (docId == _current) {
          // An in-page link: stay put and scroll to the heading rather than
          // stacking the guide on top of itself.
          if (fragment != null && fragment.isNotEmpty) {
            setState(() {
              _stack[_stack.length - 1] = _GuideRef(docId, anchor: fragment);
              _anchorRequest++;
            });
          }
        } else {
          setState(() {
            _stack.add(_GuideRef(docId, anchor: fragment));
            _anchorRequest++;
            _loadCurrent();
          });
        }
      case GuideMissingLink(:final label):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).userGuideMissing(label),
              ),
            ),
          );
      case GuideExternalLink(:final url):
        launchExternalUrl(context, url);
    }
  }

  /// The header title: the hub keeps its localized name, and every other guide
  /// is titled by its own first heading (falling back to a name derived from
  /// the file if a guide somehow has none).
  String _titleFor(AppLocalizations l10n, _GuideBody? body) {
    if (_current == kUserGuideHomeDoc) return l10n.userGuideTitle;
    if (body != null && body.docId == _current) return body.title;
    return UserGuideDocs.labelForDoc(_current);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          setState(() {
            _stack.removeLast();
            _loadCurrent();
          });
        }
      },
      // Reserve the safe-area insets within the widget itself so the header
      // stops below the status bar / Dynamic Island on the in-shell path
      // (AppShell's IndexedStack, which has no AppBar to consume the top inset),
      // matching the other destinations, and so the scrollable body doesn't run
      // under the home indicator / gesture bar on hosts without a bottom nav
      // (the pushed Settings > About route and the wide rail layout). On the
      // narrow shell the Scaffold's bottomNavigationBar already consumes the
      // bottom inset, so this stays a no-op there rather than double-insetting.
      // Making the embeddable guide self-inset keeps it consistent regardless of
      // where it is hosted, so callers don't need to wrap it in a SafeArea.
      child: SafeArea(
        child: FutureBuilder<UserGuideDocs>(
          future: _docsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _frame(
                l10n,
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snapshot.data;
            if (snapshot.hasError || docs == null || docs.isEmpty) {
              return _frame(l10n, body: _unavailable());
            }
            return _buildDoc();
          },
        ),
      ),
    );
  }

  /// The guide's chrome: the header (title + in-panel back) above [body].
  Widget _frame(AppLocalizations l10n, {required Widget body, _GuideBody? doc}) {
    return Column(
      key: const ValueKey('user-guide-screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GuideHeader(
          title: _titleFor(l10n, doc),
          onBack: _canGoBackInPanel ? _handleBack : null,
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _unavailable() => _UnavailableState(
    onOpenOnline: () => launchExternalUrl(context, kUserGuideOnlineUrl),
  );

  Widget _buildDoc() {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<_GuideBody>(
      // Key the read on the current doc so navigation reloads (and the view's
      // keyed scroll view resets to the top of the new guide).
      key: ValueKey('user-guide-body-$_current'),
      future: _bodyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _frame(
            l10n,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final body = snapshot.data;
        if (snapshot.hasError || body == null) {
          return _frame(l10n, body: _unavailable());
        }
        return _frame(
          l10n,
          doc: body,
          body: UserGuideDocView(
            docId: body.docId,
            data: body.data,
            anchor: _currentRef.anchor,
            anchorRequest: _anchorRequest,
            onTapLink: _openLink,
          ),
        );
      },
    );
  }
}

/// One entry in the panel's in-guide navigation stack: which guide, and which
/// heading (if the link that got here named one).
class _GuideRef {
  const _GuideRef(this.docId, {this.anchor});

  final String docId;
  final String? anchor;
}

/// A loaded guide: its Markdown plus the title read from its first heading.
class _GuideBody {
  const _GuideBody({
    required this.docId,
    required this.data,
    required this.title,
  });

  final String docId;
  final String data;
  final String title;
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
                    tooltip: AppLocalizations.of(context).commonBack,
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
              AppLocalizations.of(context).userGuideLoadError,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('user-guide-open-online'),
              onPressed: onOpenOnline,
              icon: const Icon(Icons.open_in_new),
              label: Text(AppLocalizations.of(context).userGuideOpenOnline),
            ),
          ],
        ),
      ),
    );
  }
}
