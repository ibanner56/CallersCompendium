/// Ratchet: every figure fixture in the test suites must be valid under
/// `contraTaxonomy`, or say why it is not.
///
/// Run from the repository root:
///
/// ```sh
/// dart run --directory packages/compendium_core \
///     tool/check_fixture_validity.dart
/// ```
///
/// ## The gap this closes
///
/// `Taxonomy.validateFigure` exists and works, but nothing called it over the
/// suites' own fixtures. Rendering *substitutes* rather than *validates*, so an
/// invalid param renders literally and every test still passes. When #697 split
/// `orbit` into a first-class move, seven `meanwhile` fixtures silently drifted
/// — `orbit {who: 'role2', turn: 0.5}`, where `who` wants a plural and `turn` is
/// a spin direction rather than a number — and nothing failed for days, until
/// #745 fixed them by hand (issue #747).
///
/// ## One gate, three permitted shapes
///
/// This walks **every** `Figure(...)` construction in `app/test` and
/// `packages/*/test` and requires each to be exactly one of:
///
/// 1. **fully literal** — validated here and now, against the real
///    `contraTaxonomy.validateFigure`;
/// 2. **deliberately invalid** — carrying an `// invalid-fixture: <reason>`
///    marker, on the fixture, its statement, or an enclosing `test(`/`group(`;
/// 3. **dynamic** — built from variables, so its values only exist at run time;
///    it must route through `testFigure` / `invalidTestFigure` from
///    `package:compendium_core/testing.dart`, which validates on construction.
///
/// A site fitting none of the three fails the build. That is what makes the
/// check exhaustive: static validation alone cannot see a fixture assembled
/// from variables, and routing everything through a helper cannot catch the
/// contributor who writes `Figure(...)` directly — which is precisely the
/// drift case. Neither half is sufficient; the gate is what binds them.
///
/// Exit codes: 0 = clean, 1 = at least one violation, 2 = bad input.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:compendium_core/compendium_core.dart';

/// Marker opting a fixture out of validation. Must be followed by a reason.
const String markerPrefix = '// invalid-fixture:';

/// Shortest reason accepted after [markerPrefix]. Mirrors the runtime bound in
/// `lib/testing.dart` so the two opt-outs demand the same standard of
/// explanation.
const int minReasonLength = 15;

/// How far above a fixture the marker may sit. A fixture spanning several lines
/// puts its opening line well below the comment that introduces the statement,
/// so this is a small window rather than "the line directly above".
const int markerLookbackLines = 6;

class FixtureViolation {
  FixtureViolation(this.file, this.line, this.kind, this.detail);

  final String file;
  final int line;
  final String kind;
  final String detail;

  @override
  String toString() => '$file:$line: [$kind] $detail';
}

/// Result of reading one `Figure(...)` construction out of the source.
class _Parsed {
  _Parsed.literal(this.move, this.params) : isLiteral = true;
  _Parsed.dynamic_() : isLiteral = false, move = null, params = const {};

  final bool isLiteral;
  final String? move;
  final Map<String, Object?> params;
}

class FixtureVisitor extends RecursiveAstVisitor<void> {
  FixtureVisitor(this._lineInfo, this._lines, this._path);

  final LineInfo _lineInfo;
  final List<String> _lines;
  final String _path;

  final List<FixtureViolation> violations = [];
  int literalCount = 0;
  int dynamicCount = 0;
  int markedCount = 0;

  /// Line ranges of `test(`/`group(` bodies carrying a VALID marker, so a
  /// fixture inside one inherits it. Populated as those calls are visited;
  /// because the visitor is top-down, an enclosing call is always seen before
  /// the fixtures inside it.
  final List<(int, int)> _markedScopes = [];

  /// Validates one `// invalid-fixture:` marker, whichever granularity it was
  /// written at, and reports every way it fails to justify itself.
  ///
  /// **Both granularities route through here, and that is the point.** A
  /// scope marker waives every fixture in its `test(`/`group(`, so it is at
  /// least as powerful as a per-fixture one and must clear at least the same
  /// bar. The two paths were separate once and the scope path silently
  /// inherited none of the per-fixture checks — `// invalid-fixture: n/a`
  /// above a `test(` waived everything inside it with no violation, while the
  /// identical string on a fixture was rejected. Any property added to
  /// reasons from here on applies at both granularities by construction,
  /// because there is only one place to add it.
  ///
  /// Returns `true` when the marker may take effect. A rejected marker is
  /// **not** honoured — failing closed, so the fixtures it would have covered
  /// stay checked rather than being waived by a marker that never earned it.
  bool _acceptMarker(String reason, int line, {required String scope}) {
    if (reason.length < minReasonLength) {
      violations.add(
        FixtureViolation(
          _path,
          line,
          'weak-marker',
          scope == _fixtureScope
              ? 'the `$markerPrefix` reason must be at least '
                    '$minReasonLength characters explaining why this fixture '
                    'is deliberately invalid; got "$reason"'
              : 'this `$markerPrefix` marker waives every fixture in the '
                    'enclosing `$scope(`, so its reason must be at least '
                    '$minReasonLength characters explaining why they are '
                    'deliberately invalid; got "$reason"',
        ),
      );
      return false;
    }
    return true;
  }

  /// Sentinel [scope] for a marker written directly above one fixture.
  static const String _fixtureScope = '';

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name == 'test' || name == 'testWidgets' || name == 'group') {
      final startLine = _lineInfo.getLocation(node.offset).lineNumber;
      final reason = _markerAbove(startLine);
      if (reason != null && _acceptMarker(reason, startLine, scope: name)) {
        _markedScopes.add((
          startLine,
          _lineInfo.getLocation(node.end).lineNumber,
        ));
      }
    }
    if (name == 'Figure') {
      _handle(node.argumentList, node.offset, node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'Figure') {
      _handle(node.argumentList, node.offset, node);
    }
    super.visitInstanceCreationExpression(node);
  }

  /// The reason from a marker governing [line], or `null` when there is none.
  String? _markerAbove(int line) {
    for (var i = line - 1; i >= 1 && i >= line - markerLookbackLines; i--) {
      final text = _lines[i - 1].trim();
      if (text.startsWith(markerPrefix)) {
        return text.substring(markerPrefix.length).trim();
      }
      // Stop at the first line that is neither blank nor a comment: the marker
      // must introduce this statement, not sit above an unrelated one.
      if (text.isNotEmpty && !text.startsWith('//')) return null;
    }
    return null;
  }

  bool _insideMarkedScope(int line) =>
      _markedScopes.any((s) => line >= s.$1 && line <= s.$2);

  void _handle(ArgumentList args, int offset, AstNode node) {
    final line = _lineInfo.getLocation(offset).lineNumber;
    final parsed = _parse(args);

    // A marker introduces a STATEMENT, but `line` is where the `Figure(`
    // token sits — and `dart format` routinely wraps a long statement so the
    // two differ:
    //
    //     // invalid-fixture: <reason>
    //     final f =
    //         Figure(move: 'swing', params: {'who': 'partner'});
    //
    // Looking only above `Figure(` finds `final f =`, a non-comment line, and
    // gives up. So try the enclosing statement's first line as well, which is
    // where an author would naturally put the marker and what the documented
    // contract promises.
    final statement = node.thisOrAncestorOfType<Statement>();
    final statementLine = statement == null
        ? line
        : _lineInfo.getLocation(statement.offset).lineNumber;
    final reason =
        _markerAbove(line) ??
        (statementLine != line ? _markerAbove(statementLine) : null);
    if (reason != null) {
      // Fails closed exactly as the scope path does: a rejected marker does
      // not waive its fixture, so the fixture stays checked below.
      if (_acceptMarker(reason, line, scope: _fixtureScope)) {
        markedCount++;
        return;
      }
    }
    if (_insideMarkedScope(line)) {
      markedCount++;
      return;
    }

    if (!parsed.isLiteral) {
      dynamicCount++;
      violations.add(
        FixtureViolation(
          _path,
          line,
          'unchecked-dynamic',
          'this fixture is built from variables, so its values cannot be '
              'checked by reading the source. Route it through '
              '`testFigure(...)` from package:compendium_core/testing.dart, '
              'which validates on construction — or mark it with '
              '`$markerPrefix <reason>` if it is invalid on purpose.',
        ),
      );
      return;
    }

    literalCount++;
    final Figure figure;
    try {
      figure = Figure(move: parsed.move!, params: parsed.params);
    } on ArgumentError catch (e) {
      violations.add(
        FixtureViolation(_path, line, 'unconstructible', '${e.message}'),
      );
      return;
    }
    final issues = contraTaxonomy
        .validateFigure(figure)
        .where((i) => i.severity == ValidationSeverity.error);
    for (final issue in issues) {
      violations.add(FixtureViolation(_path, line, issue.code, issue.message));
    }
  }

  /// Reads a `Figure(...)` argument list, returning its literal move and params
  /// when every part of it is a literal the analyzer can resolve without
  /// running the program.
  _Parsed _parse(ArgumentList args) {
    String? move;
    final params = <String, Object?>{};
    for (final arg in args.arguments) {
      if (arg is! NamedExpression) return _Parsed.dynamic_();
      final name = arg.name.label.name;
      final value = arg.expression;
      switch (name) {
        case 'move':
          if (value is! SimpleStringLiteral) return _Parsed.dynamic_();
          move = value.value;
        case 'params':
          if (value is! SetOrMapLiteral) return _Parsed.dynamic_();
          for (final element in value.elements) {
            if (element is! MapLiteralEntry) return _Parsed.dynamic_();
            final key = element.key;
            if (key is! SimpleStringLiteral) return _Parsed.dynamic_();
            final literal = _literalValue(element.value);
            if (!literal.$1) return _Parsed.dynamic_();
            params[key.value] = literal.$2;
          }
        default:
          // `note:`, `progression:`, … do not participate in validation.
          break;
      }
    }
    if (move == null) return _Parsed.dynamic_();
    return _Parsed.literal(move, params);
  }

  /// `(true, value)` when [expression] is a Dart literal we can evaluate
  /// statically; `(false, null)` otherwise.
  (bool, Object?) _literalValue(Expression expression) => switch (expression) {
    SimpleStringLiteral(:final value) => (true, value),
    IntegerLiteral(:final value) => (true, value),
    DoubleLiteral(:final value) => (true, value),
    BooleanLiteral(:final value) => (true, value),
    _ => (false, null),
  };
}

/// Every `.dart` file under `app/test` and `packages/*/test`.
List<File> testFiles(Directory root) {
  final files = <File>[];
  void addAll(Directory dir) {
    if (!dir.existsSync()) return;
    files.addAll(
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    );
  }

  addAll(Directory('${root.path}/app/test'));
  final packages = Directory('${root.path}/packages');
  if (packages.existsSync()) {
    for (final entry in packages.listSync().whereType<Directory>()) {
      addAll(Directory('${entry.path}/test'));
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Analysis totals for a run.
typedef FixtureReport = ({
  List<FixtureViolation> violations,
  int literal,
  int marked,
  int dynamic_,
});

/// Analyses [files], returning every violation found.
FixtureReport analyse(List<File> files, String rootPath) {
  final violations = <FixtureViolation>[];
  var literal = 0, marked = 0, dynamic_ = 0;
  for (final file in files) {
    final source = file.readAsStringSync();
    if (!source.contains('Figure(')) continue;
    final result = parseString(content: source, throwIfDiagnostics: false);
    final relative = file.path.startsWith(rootPath)
        ? file.path.substring(rootPath.length + 1)
        : file.path;
    final visitor = FixtureVisitor(
      result.lineInfo,
      source.split('\n'),
      relative,
    );
    result.unit.accept(visitor);
    violations.addAll(visitor.violations);
    literal += visitor.literalCount;
    marked += visitor.markedCount;
    dynamic_ += visitor.dynamicCount;
  }
  return (
    violations: violations,
    literal: literal,
    marked: marked,
    dynamic_: dynamic_,
  );
}

int run(List<String> args) {
  final cwd = Directory.current.path;
  final rootPath = args.isNotEmpty
      ? args.first
      : cwd.endsWith('packages/compendium_core')
      ? Directory(cwd).parent.parent.path
      : cwd;
  final root = Directory(rootPath);
  if (!Directory('${root.path}/app/test').existsSync()) {
    stderr.writeln(
      '::error::could not find app/test under "$rootPath" — pass the '
      'repository root as the first argument',
    );
    return 2;
  }

  final files = testFiles(root);
  final result = analyse(files, root.path);

  if (result.violations.isNotEmpty) {
    for (final violation in result.violations) {
      stderr.writeln('::error::invalid figure fixture: $violation');
    }
    stderr.writeln(
      '::error::${result.violations.length} figure fixture violation(s). '
      'A fixture must be valid under contraTaxonomy, routed through '
      'testFigure(), or marked `$markerPrefix <reason>`.',
    );
    return 1;
  }

  stdout.writeln(
    'OK: ${result.literal} literal fixture(s) validated, '
    '${result.marked} deliberately-invalid, '
    '${files.length} test file(s) scanned.',
  );
  return 0;
}

void main(List<String> args) => exit(run(args));
