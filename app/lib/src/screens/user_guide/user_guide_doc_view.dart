import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../data/reduce_motion_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/readable_width.dart';
import 'user_guide_docs.dart';

/// Renders a single bundled user-guide document as Markdown.
///
/// Headings, lists, tables, and fenced code come from
/// `flutter_markdown_plus` (GitHub-flavored). Three seams are wired for the
/// offline, in-app experience:
///
///  * **Links** are handed to [onTapLink] verbatim; the panel
///    ([user_guide_screen.dart]) classifies them via `UserGuideDocs` and either
///    navigates within the panel, opens a browser, or reports a not-yet-written
///    guide.
///  * **Anchors** resolve: every heading is tagged with the slug GitHub would
///    give it, so a link ending in `#some-heading` scrolls this view to that
///    heading — whether the link points at another guide or at a section of the
///    guide already open. Without this, an "on this page" link would work on
///    GitHub but silently do nothing in the app.
/// * **Images** are bundled with the guides (`assets/docs/user/images/`,
///   mirrored from `docs/user/images/`). A reference such as `images/x.png`
///   renders that asset via [_GuideImage], announced to screen readers as an
///   image labelled with its alt text (an empty alt marks it decorative).
///   Nothing is fetched from the network. A reference that is not a bundled
///   guide image, or whose asset fails to load, renders as a subtle italic
///   caption of its alt text instead of a broken-image icon.
///
/// The Markdown lays out inside a [SingleChildScrollView] rather than letting
/// the renderer own a lazy [ListView], so every heading is built and therefore
/// reachable by [Scrollable.ensureVisible]. A guide is a few screens of prose,
/// so laying one out in full is cheap.
class UserGuideDocView extends StatefulWidget {
  const UserGuideDocView({
    super.key,
    required this.docId,
    required this.data,
    required this.onTapLink,
    this.anchor,
    this.anchorRequest = 0,
    this.controller,
  });

  /// The id of the guide being shown (relative to `assets/docs/user`).
  final String docId;

  /// The raw Markdown source of [docId].
  final String data;

  /// Called with the raw `href` of any tapped link.
  final ValueChanged<String> onTapLink;

  /// The heading slug to scroll to once laid out, if any.
  final String? anchor;

  /// Bumped by the panel each time a link asks for an anchor, so following the
  /// same in-page link twice scrolls again instead of looking like no change.
  final int anchorRequest;

  /// Optional scroll controller so the panel can reset scroll on navigation.
  final ScrollController? controller;

  @override
  State<UserGuideDocView> createState() => _UserGuideDocViewState();
}

class _UserGuideDocViewState extends State<UserGuideDocView> {
  /// Owned only when the caller supplies none, so we dispose only our own.
  ScrollController? _ownedController;

  /// One stable key per heading slug in the guide on screen, so a heading keeps
  /// the same key across rebuilds and [_scheduleAnchorScroll] can find the
  /// element it was attached to.
  final Map<String, GlobalKey> _headingKeys = <String, GlobalKey>{};

  ScrollController get _controller =>
      widget.controller ?? (_ownedController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _scheduleAnchorScroll();
  }

  @override
  void didUpdateWidget(UserGuideDocView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.docId != widget.docId || oldWidget.data != widget.data) {
      // A different guide has different headings; start its key map clean so
      // stale slugs can't resolve to the guide the reader just left.
      _headingKeys.clear();
    }
    if (oldWidget.docId != widget.docId ||
        oldWidget.anchor != widget.anchor ||
        oldWidget.anchorRequest != widget.anchorRequest) {
      _scheduleAnchorScroll();
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  /// Scrolls to [UserGuideDocView.anchor] after the frame that lays the guide
  /// out, which is when the target heading's element first has a context.
  void _scheduleAnchorScroll() {
    final anchor = widget.anchor;
    if (anchor == null || anchor.isEmpty) return;
    final docId = widget.docId;
    final request = widget.anchorRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A newer navigation may have superseded this request between frames.
      if (!mounted ||
          widget.docId != docId ||
          widget.anchor != anchor ||
          widget.anchorRequest != request) {
        return;
      }
      final target = _headingKeys[anchor]?.currentContext;
      // An anchor naming no heading in this guide leaves the reader at the top
      // of the guide rather than failing — the guide still opened.
      if (target == null) return;
      // Respect "Reduce motion" (ROADMAP G.7, WCAG 2.3.3): jump instantly when
      // it's on. Read here rather than in initState, which runs before this
      // element may depend on an inherited widget.
      final reduceMotion = ReduceMotionScope.of(context);
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headings = _AnchoredHeadingBuilder(keyForSlug: _keyForSlug);
    return ReadableScrollView(
      key: ValueKey('user-guide-scroll-${widget.docId}'),
      controller: _controller,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Markdown(
        key: ValueKey('user-guide-doc-${widget.docId}'),
        data: widget.data,
        selectable: true,
        // The enclosing scroll view does the scrolling; the renderer's own list
        // must lay every block out so heading anchors are reachable.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        builders: {
          for (final tag in const ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'])
            tag: headings,
        },
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          // Give tables a visible frame in both light and dark themes.
          tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
          tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          blockquoteDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        onTapLink: (text, href, title) {
          if (href != null) widget.onTapLink(href);
        },
        imageBuilder: (uri, title, alt) => _GuideImage(uri: uri, alt: alt),
      ),
    );
  }

  GlobalKey _keyForSlug(String slug) => _headingKeys.putIfAbsent(
    slug,
    () => GlobalKey(debugLabel: 'user guide heading #$slug'),
  );
}

/// Tags each heading with the key its GitHub-style anchor slug maps to, so
/// [Scrollable.ensureVisible] can bring it into view when a link's `#fragment`
/// names it.
///
/// Guide headings are plain text by convention (see `docs/user/style-guide.md`),
/// so rendering the heading's text in the stylesheet's heading style matches
/// what the default renderer produces.
class _AnchoredHeadingBuilder extends MarkdownElementBuilder {
  _AnchoredHeadingBuilder({required this.keyForSlug});

  /// Returns the stable key the view uses to locate a heading by slug.
  final GlobalKey Function(String slug) keyForSlug;

  /// How many headings have already claimed each slug in this render, so a
  /// guide that repeats a heading gets `-1`, `-2`, … suffixes the way GitHub
  /// does instead of tripping over duplicate global keys.
  final Map<String, int> _slugUses = <String, int>{};

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    final base = UserGuideDocs.slugify(text);
    final uses = _slugUses.update(base, (n) => n + 1, ifAbsent: () => 0);
    final slug = uses == 0 ? base : '$base-$uses';
    return KeyedSubtree(
      key: keyForSlug(slug),
      child: SelectableText(text, style: preferredStyle),
    );
  }
}

/// Where the guides' bundled screenshots live, relative to the app's asset
/// root. Only files under here are ever loaded for a guide image.
const String _guideAssetDir = 'assets/docs/user/';
const String _guideImageAssetDir = '${_guideAssetDir}images/';

/// The widest a screenshot is drawn, in logical pixels. The captures are up to
/// 1800 px wide; letting them span a very wide window would only blow them up.
const double _guideImageMaxWidth = 720;

/// The bundled asset key a guide's image [uri] names, or `null` when it is not
/// a guide image (an `http(s)` URL, an absolute path, or anything that resolves
/// outside `images/`). Guides reference images relative to themselves
/// (`images/x.png`), and every guide sits at the top of `assets/docs/user`.
String? _guideImageAssetKey(Uri uri) {
  if (uri.hasScheme || uri.hasAuthority || uri.path.startsWith('/')) {
    return null;
  }
  final key = Uri.parse(_guideAssetDir).resolveUri(uri).path;
  return key.startsWith(_guideImageAssetDir) ? key : null;
}

/// An image the guide references: the bundled screenshot when there is one,
/// else its alt text as a subtle italic caption.
///
/// The picture is exposed to assistive technology as one image labelled with
/// the alt text (and its pixels excluded, so the label is not read twice). An
/// empty alt marks the image decorative: it is hidden from assistive
/// technology, and a decorative image that cannot load renders nothing.
class _GuideImage extends StatelessWidget {
  const _GuideImage({required this.uri, required this.alt});

  final Uri uri;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final text = alt?.trim() ?? '';
    final caption = _GuideImageCaption(alt: text);
    final key = _guideImageAssetKey(uri);
    // Whichever of picture or caption is drawn, it is one labelled image.
    Widget labelled(Widget child) => text.isEmpty
        ? ExcludeSemantics(child: child)
        : Semantics(image: true, label: text, child: child);
    if (key == null) return labelled(caption);

    // Decode no wider than the picture is drawn, so a guide with several
    // screenshots does not hold each one at full resolution.
    final cacheWidth =
        (_guideImageMaxWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final picture = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _guideImageMaxWidth),
          child: Image.asset(
            key,
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) => caption,
          ),
        ),
      ),
    );
    return labelled(picture);
  }
}

/// The text stand-in for an image the guide references but cannot show: its alt
/// text as a subtle italic caption, so the page stays readable. Carries no
/// semantics of its own: [_GuideImage] labels it.
class _GuideImageCaption extends StatelessWidget {
  const _GuideImageCaption({required this.alt});

  final String alt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (alt.isEmpty) {
      return const SizedBox.shrink();
    }
    // The label is on the enclosing Semantics; the text must not repeat it.
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          alt,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
