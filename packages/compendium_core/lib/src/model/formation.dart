import 'package:meta/meta.dart';

/// Canonical formation shapes, seeded from The Caller's Box vocabulary.
enum FormationShape {
  dupleImproper,
  becketCw,
  becketCcw,
  dupleProper,
  dupleIndecent,
  tripleMinor,
  threeFaceThree,
  fourFaceFour,
  circleMixer,
  sicilianCircle,
  scatterMixer,
  longways,
  triplet,
  grid,
  other,
}

/// A dance formation: canonical [shape] plus optional free-text [detail].
///
/// Enum-with-detail avoids ContraDB's regex-over-free-text weakness while
/// never losing information from unusual source formations.
@immutable
class Formation {
  const Formation(this.shape, {this.detail});

  final FormationShape shape;

  /// Free-text qualifier (e.g. "double progression variant"). Canonicalized
  /// on input like all free text. Not normalized by this constructor (kept
  /// `const`-constructible for the common canonical-shape case) — callers
  /// building a [Formation] from user-entered or imported text should treat
  /// an empty/whitespace-only string as equivalent to `null` themselves.
  final String? detail;

  Formation copyWith({FormationShape? shape, String? detail}) =>
      Formation(shape ?? this.shape, detail: detail ?? this.detail);

  @override
  bool operator ==(Object other) =>
      other is Formation && other.shape == shape && other.detail == detail;

  @override
  int get hashCode => Object.hash(shape, detail);

  @override
  String toString() =>
      'Formation(${shape.name}${detail == null ? '' : ', $detail'})';
}
