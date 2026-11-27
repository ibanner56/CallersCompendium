/// The words a taxonomy flag shows in a move's `renderTemplate` when it is
/// set, where its name is not already the word (a square chain's `{four}`
/// is). Both renders use them (`FigureRenderer`), so the words are
/// searchable: a square right left through's `fullTurn` reads "heads right
/// left through with a full turn" (square taxonomy v1, pre-release audit
/// B-08). A figure of the user's own copied from the move takes them as the
/// flag's label (`userFigureSeedFromMove`), so the copy reads as the move.
///
/// Not exported: the renderer and the seed are its only readers.
const Map<String, String> taxonomyFlagWords = {'fullTurn': 'with a full turn'};
