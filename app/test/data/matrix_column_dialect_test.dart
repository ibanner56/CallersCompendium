import 'package:compendium_app/src/data/matrix_column_dialect.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialect a program matrix column, and a suggestion reason that names
/// one, is read in (#2294). Each form gets a different dialect, so reading a
/// column in the wrong form's cannot pass.
void main() {
  final contra = Dialect.larksRobins;
  final english = Dialect.canonical;
  final square = Dialect.canonical.copyWith(moves: {'swing': 'quokka'});
  final fallback = Dialect.larksRobins.copyWith(moves: {'swing': 'fallback'});
  final dialects = DialectsByForm({
    DanceForm.contra: contra,
    DanceForm.ecd: english,
    DanceForm.square: square,
  });

  MatrixColumn known(String id) =>
      MatrixColumn(moveId: id, kind: MatrixColumnKind.known);

  MatrixColumn own(String id) => MatrixColumn(
    moveId: '$userFigureRefPrefix$id',
    kind: MatrixColumnKind.userFigure,
    label: 'mine',
  );

  Dialect read(
    MatrixColumn column, {
    Set<DanceForm?> usedBy = const {},
    Set<DanceForm?> program = const {},
    Map<String, DanceForm> figures = const {},
  }) => matrixColumnDialect(
    column,
    dialects: dialects,
    fallback: fallback,
    userFigure: (id) => figures[id] == null
        ? null
        : UserFigureView(
            id: id,
            name: 'mine',
            form: figures[id]!,
            definition: null,
          ),
    usedBy: () => usedBy,
    program: () => program,
  );

  test('controls: each form and the fallback read differently', () {
    expect({contra, english, square, fallback}, hasLength(4));
  });

  group('a figure of a form with its own taxonomy', () {
    test('reads in that form\'s dialect, whoever uses it', () {
      expect(read(known('ecd_set'), usedBy: {DanceForm.contra}), english);
      expect(read(known('sq_swing')), square);
    });
  });

  group('an unprefixed figure', () {
    test('reads in the form of the dances that use it, when one form', () {
      expect(read(known('swing'), usedBy: {DanceForm.ecd}), english);
      expect(read(known('swing'), usedBy: {DanceForm.contra}), contra);
    });

    test('reads in the fallback when its dances mix forms', () {
      expect(
        read(known('swing'), usedBy: {DanceForm.ecd, DanceForm.contra}),
        fallback,
      );
    });

    test('with no dance using it, reads in the form of the program\'s dances '
        'when one form, as a suggestion reason does', () {
      expect(read(known('swing'), program: {DanceForm.ecd}), english);
      expect(read(known('swing'), program: {DanceForm.square}), square);
    });

    test('with no dance using it, or no dance in the program, or a mixed '
        'program, reads in the fallback', () {
      expect(read(known('swing')), fallback);
      expect(
        read(known('swing'), program: {DanceForm.ecd, DanceForm.contra}),
        fallback,
      );
      // A dance that is not loaded has no form.
      expect(read(known('swing'), program: {null}), fallback);
    });

    test('the dances that use it win over the program\'s', () {
      expect(
        read(
          known('swing'),
          usedBy: {DanceForm.contra},
          program: {DanceForm.ecd},
        ),
        contra,
      );
    });
  });

  group('a figure of the user\'s own', () {
    test('reads in the dialect of the form it was made for', () {
      expect(
        read(
          own('e'),
          figures: {'e': DanceForm.ecd},
          usedBy: {DanceForm.contra},
        ),
        english,
      );
      expect(read(own('c'), figures: {'c': DanceForm.contra}), contra);
    });

    test('reads in the fallback when it is hidden or gone', () {
      expect(read(own('gone')), fallback);
    });
  });

  group('every kind of figure column is read by the same rule', () {
    test('a split column and an unknown one, prefixed or not', () {
      const split = MatrixColumn(
        moveId: 'swing:left',
        kind: MatrixColumnKind.split,
        baseMoveId: 'swing',
        variant: 'left',
      );
      const unknownEnglish = MatrixColumn(
        moveId: 'ecd_unheard_of',
        kind: MatrixColumnKind.unknown,
      );
      const unknownPlain = MatrixColumn(
        moveId: 'unheard_of',
        kind: MatrixColumnKind.unknown,
      );
      expect(read(split, usedBy: {DanceForm.ecd}), english);
      expect(read(unknownEnglish, usedBy: {DanceForm.contra}), english);
      expect(read(unknownPlain, usedBy: {DanceForm.square}), square);
      expect(read(unknownPlain), fallback);
    });

    test('a dance that is not loaded has no form, alone or among others', () {
      expect(read(known('swing'), usedBy: {null}), fallback);
      expect(read(known('swing'), usedBy: {DanceForm.ecd, null}), fallback);
    });

    test('a column of your own that is not a figure key reads in the '
        'fallback', () {
      const notKey = MatrixColumn(
        moveId: 'not-a-figure-key',
        kind: MatrixColumnKind.userFigure,
        label: 'mine',
      );
      expect(
        read(notKey, figures: {'not-a-figure-key': DanceForm.ecd}),
        fallback,
      );
    });
  });

  test('a custom column reads in the fallback', () {
    expect(
      read(
        const MatrixColumn(moveId: customMove, kind: MatrixColumnKind.custom),
      ),
      fallback,
    );
  });
}
