import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_spacing.dart';
import 'user_guide_docs.dart';

/// Renders a single bundled user-guide document as Markdown.
///
/// Headings, lists, tables, and fenced code come from
/// `flutter_markdown_plus` (GitHub-flavored). Two seams are wired for the
/// offline, in-app experience:
///
///  * **Links** are handed to [onTapLink] verbatim; the panel
///    ([user_guide_screen.dart]) classifies them via [UserGuideDocs] and either
///    navigates within the panel, opens a browser, or reports a not-yet-written
///    guide.
///  * **Images** are resolved to bundled assets via
///    [UserGuideDocs.resolveImageAsset] and drawn from the bundle — SVG
///    wireframes through `flutter_svg`, any raster through [Image.asset] — so
///    nothing is fetched from the network.
class UserGuideDocView extends StatelessWidget {
  const UserGuideDocView({
    super.key,
    required this.docs,
    required this.docId,
    required this.data,
    required this.onTapLink,
    this.controller,
  });

  /// The loaded doc registry, used to resolve image assets for [docId].
  final UserGuideDocs docs;

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
      imageBuilder: (uri, title, alt) => _GuideImage(
        assetKey: docs.resolveImageAsset(docId, uri.toString()),
        alt: alt,
      ),
    );
  }
}

/// Draws a bundled guide image: an SVG wireframe via `flutter_svg`, or a raster
/// via [Image.asset]. Falls back to a captioned placeholder when the image
/// can't be resolved or loaded, so a broken reference never blanks the guide.
class _GuideImage extends StatelessWidget {
  const _GuideImage({required this.assetKey, required this.alt});

  final String? assetKey;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final key = assetKey;
    if (key == null) {
      return _placeholder(context);
    }

    final Widget image;
    if (key.toLowerCase().endsWith('.svg')) {
      image = SvgPicture.asset(
        key,
        semanticsLabel: alt,
        placeholderBuilder: (context) => _placeholder(context),
        fit: BoxFit.contain,
      );
    } else {
      image = Image.asset(
        key,
        semanticLabel: alt,
        errorBuilder: (context, error, stack) => _placeholder(context),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: image,
    );
  }

  Widget _placeholder(BuildContext context) {
    final theme = Theme.of(context);
    final label = (alt == null || alt!.trim().isEmpty) ? 'Image' : alt!.trim();
    return Semantics(
      label: label,
      image: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              Icons.image_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
