import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// A note on a meanwhile side or a modifier part has no row of its own on any
/// surface, so the display renders carry it on the line (AUTH-3, October
/// behaviour audit). `renderCanonical` is the dedupe/FTS key and never does.
void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final dialect = Dialect.larksRobins;

  // The audit's probe line, built as the parser used to save it: the turn
  // amount the caller typed sits in the side's note.
  const allemandeParams = {'who': 'role2s', 'hand': 'right'};
  final allemande = testFigure(
    move: 'allemande',
    params: allemandeParams,
    note: '1 1/2',
  );
  final orbit = customFigure('role1s orbit');
  final meanwhile = Figure.meanwhile(figures: [allemande, orbit], beats: 8);

  test('a meanwhile side shows its note on the summary line', () {
    expect(
      renderer.renderSummary(meanwhile, dialect),
      'robins allemande right once (1 1/2) while larks orbit',
    );
  });

  test('render, the verbose summary and the canonical-terms summary show it '
      'too', () {
    expect(renderer.render(meanwhile, dialect), contains('(1 1/2)'));
    expect(
      renderer.renderSummary(meanwhile, dialect, verbose: true),
      contains('(1 1/2)'),
    );
    expect(
      renderer.renderSummaryWithCanonicalDiscouragedTerms(meanwhile, dialect),
      contains('(1 1/2)'),
    );
  });

  test('a child note is free text: role words in the dialect, emphasis '
      'marks dropped', () {
    final side = Figure(
      move: 'swing',
      params: const {'who': 'neighbors'},
      note: '*role2s* on the outside',
    );
    final container = Figure.meanwhile(
      figures: [side, customFigure('role1s wait')],
      beats: 8,
    );
    expect(
      renderer.renderSummary(container, dialect),
      contains('(robins on the outside)'),
    );
  });

  test('a modifier core and a modifier part show their notes', () {
    final core = Figure(
      move: 'swing',
      params: const {'who': 'partners'},
      note: 'end facing down',
    );
    final part = customFigure('larks clap').copyWith(note: 'on beat 8');
    final modifier = Figure.modifier(figures: [core, part], beats: 8);
    final line = renderer.renderSummary(modifier, dialect);
    expect(line, contains('(end facing down)'));
    expect(line, contains('(on beat 8)'));
  });

  test('a side with no note renders as before', () {
    final plain = Figure.meanwhile(
      figures: [
        testFigure(move: 'allemande', params: allemandeParams),
        orbit,
      ],
      beats: 8,
    );
    expect(renderer.renderSummary(plain, dialect), isNot(contains('(')));
  });

  test('canonical text never carries a child note', () {
    expect(renderer.renderCanonical(meanwhile), isNot(contains('1 1/2')));
  });
}
