import 'package:compendium_core/compendium_core.dart';

/// The dialect a program matrix column is named in: its figure's form's. A
/// figure of a form with its own taxonomy (an `ecd_` or `sq_` move) reads in
/// that form's. A figure with no prefix is contra's, and a dance of any form
/// can use it (an English or square dance may keep a contra figure from an
/// earlier import): it reads in the form of the dances that use it
/// ([usedBy]) when they are all of one form, else in the form of all the
/// program's dances ([program]) when they are, and in [fallback] when they mix
/// forms. A figure of the user's own reads in the dialect of the form it was
/// made for, however the dances using it read (#2294), or in [fallback] when
/// [userFigure] cannot find it; a free-text custom column, or one that isn't a
/// figure, reads in [fallback].
///
/// [usedBy] and [program] are asked for only when the figure has no form of
/// its own. The program matrix passes the dances of the rows that use the
/// column; a surface with no matrix, such as the picker's suggestion reasons,
/// passes none, and so reads a column by the program's dances.
Dialect matrixColumnDialect(
  MatrixColumn column, {
  required DialectsByForm dialects,
  required Dialect fallback,
  required UserFigureView? Function(String id) userFigure,
  required Set<DanceForm?> Function() usedBy,
  required Set<DanceForm?> Function() program,
}) {
  switch (column.kind) {
    case MatrixColumnKind.userFigure when isUserFigureKey(column.moveId):
      final view = userFigure(
        column.moveId.substring(userFigureRefPrefix.length),
      );
      return view == null ? fallback : dialects.forForm(view.form);
    case MatrixColumnKind.known ||
        MatrixColumnKind.split ||
        MatrixColumnKind.unknown:
      final form = shippedTaxonomies.formOfMoveId(column.moveId);
      if (form != DanceForm.contra) return dialects.forForm(form);
      var users = usedBy();
      if (users.isEmpty) users = program();
      return users.length == 1 && users.single != null
          ? dialects.forForm(users.single!)
          : fallback;
    default:
      return fallback;
  }
}
