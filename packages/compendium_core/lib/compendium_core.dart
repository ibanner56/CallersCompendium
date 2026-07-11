/// Pure-Dart domain core for Caller's Compendium.
///
/// Contains the domain model, figure taxonomy, dialect engine, and import
/// parsers. This package must remain free of Flutter dependencies so the
/// domain layer stays portable and independently testable (ADR-001).
library;

export 'src/model/choreographer.dart';
export 'src/model/custom_field.dart';
export 'src/model/dance.dart';
export 'src/model/dance_link.dart';
export 'src/model/enums.dart';
export 'src/model/figure.dart';
export 'src/model/formation.dart';
export 'src/model/phrase_structure.dart';
export 'src/model/program.dart';
export 'src/model/provenance.dart';
export 'src/model/tag.dart';
export 'src/util/uuid.dart';
export 'src/validation/validation.dart';
