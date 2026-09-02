/// ContraCompiler — a stateless, functional compiler for contra-dance figure
/// sequences.
///
/// It applies an ordered list of parameterized operations (figures) to an
/// immutable formation and verifies the result against a named success
/// criterion. See `docs/architecture.md` (execution model) and
/// `docs/fundamentals.md` (domain state-model).
///
/// This barrel exposes the domain model, geometry, and the operation
/// framework; the compiler entry point lands with the engine phase.
library;

export 'src/domain/couple_number.dart';
export 'src/domain/dancer.dart';
export 'src/domain/facing.dart';
export 'src/domain/formation.dart';
export 'src/domain/formation_type.dart';
export 'src/domain/position.dart';
export 'src/domain/role.dart';
export 'src/domain/starting_formations.dart';
export 'src/engine/compile_result.dart';
export 'src/engine/compiler.dart';
export 'src/engine/end_normalization.dart';
export 'src/engine/invocation.dart';
export 'src/engine/result.dart';
export 'src/engine/sizing.dart';
export 'src/engine/success_criterion.dart';
export 'src/geometry/geometry.dart';
export 'src/io/callersbox_source.dart';
export 'src/io/dance_json.dart';
export 'src/io/roles_notation.dart';
export 'src/ops/diagnostics.dart';
export 'src/ops/operation.dart';
export 'src/ops/params.dart';
export 'src/ops/who.dart';

/// Package version marker.
const String compendiumRubricVersion = '0.1.0';
