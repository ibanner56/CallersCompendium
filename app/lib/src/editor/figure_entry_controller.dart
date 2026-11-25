import 'package:compendium_core/compendium_core.dart';

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
  bool Function(FigureDraft? draft)? _start;

  /// Whether a figure list is built and serving this controller. The dance
  /// editor's form is a lazy list, so the figures may not be built yet when
  /// the Title asks; it scrolls toward them until they are.
  bool get isAttached => _start != null;

  /// Called by the figure list when it starts serving this controller.
  /// [start] returns whether it put the focus in a figure's text field.
  void attach(bool Function(FigureDraft? draft) start) => _start = start;

  /// Called by the figure list when it stops serving this controller, with
  /// the [start] it attached; another's is ignored, so a replacement list
  /// that attached first stays attached.
  void detach(bool Function(FigureDraft? draft) start) {
    if (_start == start) _start = null;
  }

  /// Puts the focus in [draft]'s Move box, or with null starts a new figure
  /// and focuses its entry. Returns whether it did: false when no figure list
  /// is attached ([isAttached]), or the list could not.
  bool start(FigureDraft? draft) => _start?.call(draft) ?? false;
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
