import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/app_spacing.dart';

/// Renders a single bundled user-guide document as Markdown.
///
/// Headings, lists, tables, and fenced code come from
/// `flutter_markdown_plus` (GitHub-flavored). Two seams are wired for the
/// offline, in-app experience:
///
///  * **Links** are handed to [onTapLink] verbatim; the panel
///    ([user_guide_screen.dart]) classifies them via `UserGuideDocs` and either
///    navigates within the panel, opens a browser, or reports a not-yet-written
///    guide.
///  * **Images** are not bundled yet (the guide ships text-only). Each image
///    reference renders as a subtle italic caption of its alt text via
///    [_GuideImageCaption] — no asset lookup, no network, no broken-image icon —
///    so the prose reads cleanly until real screenshots are added.
class UserGuideDocView extends StatelessWidget {
  const UserGuideDocView({
    super.key,
    required this.docId,
    required this.data,
    required this.onTapLink,
    this.controller,
  });

  /// The id of the guide being shown (relative to `assets/docs/user`).
  final String docId;

  /// The raw Markdown source of [docId].
  final String data;

  /// Called with the raw `href` of any tapped link.
  final ValueChanged<String> onTapLink;

  /// Optional scroll controller so the panel can reset scroll on navigation.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Markdown(
      key: ValueKey('user-guide-doc-$docId'),
      controller: controller,
      data: data,
      selectable: true,
      padding: const EdgeInsets.all(AppSpacing.md),
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
        if (href != null) onTapLink(href);
      },
      imageBuilder: (uri, title, alt) => _GuideImageCaption(alt: alt),
    );
  }
}

/// Stands in for an image the guide references. The guide is text-only for now,
/// so instead of loading an asset this renders the image's alt text as a subtle
/// italic caption — a graceful, non-blocking placeholder that keeps the page
/// readable (and accessible) until real screenshots are bundled.
class _GuideImageCaption extends StatelessWidget {
  const _GuideImageCaption({required this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = alt?.trim() ?? '';
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      image: true,
      label: text,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          text,
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
