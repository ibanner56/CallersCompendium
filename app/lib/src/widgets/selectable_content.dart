import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

/// Makes the text under [child] selectable and copyable with a pointer, on
/// desktop only (design note N5, `docs/design/selectable-text.md`).
///
/// On Windows, macOS and Linux the child is wrapped in a [SelectionArea], so a
/// drag selects, Ctrl/Cmd-C copies, Ctrl/Cmd-A selects all, and a secondary tap
/// shows the Copy / Select all menu. On Android, iOS and Fuchsia the child is
/// returned unchanged: phones keep **Copy dance** as their only copy path
/// (maintainer decision N5-1 = a).
///
/// This is the one place the platform gate lives, so turning selection on for
/// phones later is a change to [selectionEnabledOnThisPlatform] alone.
///
/// A copy is what the screen shows (N5-3 = a): the active dialect, the verbose
/// text, capitalisation and decimal-turns preferences. It differs from
/// **Copy dance** on those three (decimal turns only when verbose text is off).
///
/// Flutter joins the text of separate [Text] widgets with no separator, so wrap
/// each block of prose in a [SelectableLine] to end it with a newline in a copy.
///
/// Wrap a subtree that is not text — chips, badges, the beats column — in
/// [SelectionContainer.disabled] so a drag over it neither selects it nor puts
/// it in the copied text.
class SelectableContent extends StatelessWidget {
  const SelectableContent({super.key, required this.child});

  final Widget child;

  /// Whether text selection is offered on the running platform.
  static bool get selectionEnabledOnThisPlatform =>
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia => false,
      };

  @override
  Widget build(BuildContext context) {
    if (!selectionEnabledOnThisPlatform) return child;
    return SelectionArea(child: child);
  }
}

/// One block of selectable text that ends its line in a copy.
///
/// Flutter joins the text of separate [Text] widgets with nothing between them,
/// so a drag across a figure and its note would copy "partner swingwith your
/// neighbor". Wrapping each block in a [SelectableLine] ends it with a newline
/// when a selection reaches the block's end.
/// It also keeps everything inside one block, such as a link's text inside a
/// sentence, joined without a break.
///
/// Like [SelectableContent] it returns [child] unchanged where selection is off.
class SelectableLine extends StatefulWidget {
  const SelectableLine({super.key, required this.child});

  final Widget child;

  @override
  State<SelectableLine> createState() => _SelectableLineState();
}

class _SelectableLineState extends State<SelectableLine> {
  final _delegate = _LineDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SelectableContent.selectionEnabledOnThisPlatform) return widget.child;
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

class _LineDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content == null) return null;
    // Only a selection that reaches the end of the block ends its line; a drag
    // that stops partway, such as one word of a title, copies just those words.
    final range = getSelection();
    final reachesEnd =
        range != null &&
        (range.startOffset > range.endOffset
                ? range.startOffset
                : range.endOffset) >=
            contentLength;
    return reachesEnd
        ? SelectedContent(plainText: '${content.plainText}\n')
        : content;
  }
}
