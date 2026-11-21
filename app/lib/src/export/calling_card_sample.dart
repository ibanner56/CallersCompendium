import 'package:compendium_core/compendium_core.dart';

/// The dance the calling-card layout editor previews: a plain improper contra
/// with a progression, a figure note and calling notes, so every block the
/// default layout uses has something to show. [title], [notes] and
/// [figureNote] come from the app's localizations; the author name the
/// preview prints is a display string passed beside it, as for any dance.
Dance callingCardSampleDance({
  required String title,
  required String notes,
  required String figureNote,
}) {
  final epoch = DateTime.utc(2026);
  return Dance(
    id: 'calling-card-sample',
    title: title,
    formation: const Formation(FormationShape.dupleImproper),
    callingNotes: notes,
    createdAt: epoch,
    updatedAt: epoch,
    figures: [
      Figure(move: 'balance', params: const {'who': 'neighbors', 'beats': 4}),
      Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 12}),
      Figure(
        move: 'circle',
        params: const {'places': 3, 'direction': 'left', 'beats': 8},
      ),
      Figure(move: 'swing', params: const {'who': 'partners', 'beats': 8}),
      Figure(move: 'chain', params: const {'who': 'role2s', 'beats': 8}),
      Figure(
        move: 'allemande',
        params: const {'hand': 'left', 'travel': 1.5, 'beats': 8},
        note: figureNote,
      ),
      Figure(move: 'do_si_do', params: const {'who': 'partners', 'beats': 8}),
      Figure(
        move: 'circle',
        params: const {'places': 3, 'direction': 'left', 'beats': 8},
        progression: true,
      ),
    ],
  );
}
