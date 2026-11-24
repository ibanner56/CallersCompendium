import 'figure_draft.dart';

/// Lets the dance editor's Title field hand the caller on to the figures
/// (#2491 follow-up): its keyboard's Next opens the first figure still to
/// fill, or starts the first figure, as the figure list itself would, so the
/// on-screen keyboard stays up for the Move box rather than closing on a
/// control that takes no typing.
///
/// The figure list attaches its own way of doing that; the Title field asks
/// [start]. Which figure that is comes from [figureToFill], which both share.
class FigureEntryController {
  void Function(FigureDraft? draft)? _start;

  /// Called by the figure list when it starts serving this controller.
  void attach(void Function(FigureDraft? draft) start) => _start = start;

  /// Called by the figure list when it stops serving this controller, with
  /// the [start] it attached; another's is ignored, so a replacement list
  /// that attached first stays attached.
  void detach(void Function(FigureDraft? draft) start) {
    if (_start == start) _start = null;
  }

  /// Opens [draft]'s Move box, or with null starts a new figure. Returns
  /// whether a figure list was there to do it.
  bool start(FigureDraft? draft) {
    final start = _start;
    if (start == null) return false;
    start(draft);
    return true;
  }
}

/// What a new dance's Title hands on to ([FigureEntryController]): the first
/// top-level figure still to fill (one with no move yet, or the `stand_still`
/// placeholder a new dance starts with), as `(draft: it)`; `(draft: null)`
/// when there are no figures, so the first is started; or null when every
/// figure is already set, so there is nothing to type next.
({FigureDraft? draft})? figureToFill(List<FigureDraft> drafts) {
  if (drafts.isEmpty) return (draft: null);
  for (final draft in drafts) {
    if (draft.isContainerDraft || draft.isCompoundPlaceholder) continue;
    if (draft.move == null || draft.move == standStillMove) {
      return (draft: draft);
    }
  }
  return null;
}

/// The move id of the placeholder figure a new dance's rows start as.
const String standStillMove = 'stand_still';
