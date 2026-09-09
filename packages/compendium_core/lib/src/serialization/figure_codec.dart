import 'dart:convert';

import '../model/figure.dart';

/// JSON (de)serialization for [Figure] lists — the `figures_json` format.
///
/// Persisted shape (one object per figure):
/// ```json
/// {"schemaVersion": 1, "move": "swing",
///  "params": {"who": "partners", "beats": 16},
///  "note": "scoop", "progression": true}
/// ```
/// `note` and `progression` are omitted when absent/false; `params` is
/// omitted when empty. `customOrigin` is written only when it is not the
/// default `userEntered` (i.e. `"importGap"` for parser-gap customs), and
/// `assumedSubject` is written only when `true` (a parser-defaulted subject),
/// so existing data and ordinary figures stay byte-for-byte compatible.
/// `walkthroughOverride` (#411) is written only when present/non-blank and is
/// soft-clamped on decode. `wordingOverride` is handled the same way. A
/// Structural container figures (`meanwhile` and `modifier`) additionally carry
/// their children in `params['figures']`; those children are (de)serialized
/// recursively through this same codec and the shared beat count lives in
/// `params['beats']`. This is all additive — there is **no**
/// `figureSchemaVersion` bump. Decoding is tolerant: unknown keys are ignored (so files written by newer
/// app versions still load), a missing `schemaVersion` is treated as version 1,
/// a missing/unknown `customOrigin` decodes as `userEntered`, and a
/// missing/non-bool `assumedSubject` decodes as `false`.

Map<String, Object?> figureToJson(Figure figure) {
  final params = _paramsToJson(figure);
  return {
    'schemaVersion': figure.schemaVersion,
    'move': figure.move,
    if (params.isNotEmpty) 'params': params,
    if (figure.note != null) 'note': figure.note,
    if (figure.progression) 'progression': true,
    if (figure.customOrigin != CustomOrigin.userEntered)
      'customOrigin': figure.customOrigin.name,
    if (figure.assumedSubject) 'assumedSubject': true,
    if (figure.walkthroughOverride != null &&
        figure.walkthroughOverride!.trim().isNotEmpty)
      'walkthroughOverride': figure.walkthroughOverride,
    if (figure.wordingOverride != null &&
        figure.wordingOverride!.trim().isNotEmpty)
      'wordingOverride': figure.wordingOverride,
  };
}

/// Serializes a structural container's `params` to JSON. `params['figures']`
/// holds in-memory [Figure] children which are each re-encoded via
/// [figureToJson], so nested sub-figures use the exact same codec.
Map<String, Object?> _paramsToJson(Figure figure) {
  final params = figure.params;
  if (!figure.isContainer || params['figures'] is! List) return params;
  return {
    for (final entry in params.entries)
      entry.key: entry.key == 'figures'
          ? [
              for (final side in entry.value as List)
                if (side is Figure) figureToJson(side),
            ]
          : entry.value,
  };
}

Figure figureFromJson(Map<String, Object?> json) {
  return _figureFromJson(json, 0);
}

Figure _figureFromJson(Map<String, Object?> json, int depth) {
  final move = json['move'];
  if (move is! String) {
    throw FormatException('figure is missing a string "move": $json');
  }
  final params = json['params'] ?? const <String, Object?>{};
  if (params is! Map) {
    throw FormatException('figure "params" must be an object: $json');
  }
  final schemaVersion = json['schemaVersion'] ?? 1;
  if (schemaVersion is! int) {
    throw FormatException('figure "schemaVersion" must be an int: $json');
  }
  final note = json['note'];
  if (note != null && note is! String) {
    throw FormatException('figure "note" must be a string: $json');
  }
  final progression = json['progression'] ?? false;
  if (progression is! bool) {
    throw FormatException('figure "progression" must be a bool: $json');
  }
  // Decoding is tolerant: a missing key (existing stored data) and any
  // unrecognized value both fall back to userEntered, so no real user custom
  // is ever mislabeled as an import-gap custom.
  final originName = json['customOrigin'];
  final customOrigin = CustomOrigin.values.firstWhere(
    (o) => o.name == originName,
    orElse: () => CustomOrigin.userEntered,
  );
  // Tolerant: a missing key (existing stored data) or any non-bool value
  // decodes as false, so a subject is never spuriously flagged as assumed.
  final assumedSubject = json['assumedSubject'] == true;
  // Per-dance walkthrough snippet override (#411). Untrusted free text: a
  // non-string decodes as null (no override); a string is soft-clamped so an
  // oversized value can never fail an otherwise-valid decode. Trimmed-empty is
  // treated as "no override" so it never resurfaces as a blank snippet line.
  final rawOverride = json['walkthroughOverride'];
  final String? walkthroughOverride;
  if (rawOverride is String && rawOverride.trim().isNotEmpty) {
    walkthroughOverride = rawOverride.length > kMaxWalkthroughSnippetLength
        ? rawOverride.substring(0, kMaxWalkthroughSnippetLength)
        : rawOverride;
  } else {
    walkthroughOverride = null;
  }
  final wordingOverride = _optionalOverride(json['wordingOverride']);
  return Figure(
    schemaVersion: schemaVersion,
    move: move,
    params: move == meanwhileMove || move == modifierMove
        ? _decodeContainerParams(
            move,
            params.map((k, v) => MapEntry(k.toString(), v)),
            depth,
          )
        : params.map((k, v) => MapEntry(k.toString(), v)),
    note: note as String?,
    progression: progression,
    customOrigin: customOrigin,
    assumedSubject: assumedSubject,
    walkthroughOverride: walkthroughOverride,
    wordingOverride: wordingOverride,
  );
}

String? _optionalOverride(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return raw.length > kMaxWalkthroughSnippetLength
      ? raw.substring(0, kMaxWalkthroughSnippetLength)
      : raw;
}

/// Replaces a structural container's raw `params['figures']` (a JSON array)
/// with decoded in-memory [Figure] children. Tolerant / parse-never-fails and
/// defensive against untrusted input:
///
/// * non-object / junk entries are ignored;
/// * only the opposite container may nest, and only one level deep;
/// * the child count is clamped to [kMaxMeanwhileSides];
/// * deeper or same-kind containers are dropped rather than flattened.
Map<String, Object?> _decodeContainerParams(
  String move,
  Map<String, Object?> params,
  int depth,
) => {
  ...params,
  'figures': List<Figure>.unmodifiable(
    _decodeContainerChildren(params['figures'], move, depth),
  ),
};

List<Figure> _decodeContainerChildren(
  Object? raw,
  String parentMove,
  int depth,
) {
  final children = <Figure>[];
  if (raw is! List || depth >= kMaxContainerDepth) return children;
  for (final entry in raw) {
    if (children.length >= kMaxMeanwhileSides) break;
    if (entry is! Map) continue; // ignore junk; never fabricate
    final map = entry.cast<String, Object?>();
    final childMove = map['move'];
    if (childMove is String &&
        (childMove == meanwhileMove || childMove == modifierMove)) {
      if (childMove == parentMove) continue;
      final child = _figureFromJson(map, depth + 1);
      if (child.isContainer && child.subFigures.isNotEmpty) {
        children.add(child);
      }
      continue;
    }
    children.add(_figureFromJson(map, depth + 1));
  }
  return children;
}

/// Encodes an ordered figure list to a compact JSON array string.
String encodeFigures(List<Figure> figures) =>
    jsonEncode([for (final f in figures) figureToJson(f)]);

/// Decodes a `figures_json` string. Throws [FormatException] on malformed
/// input (invalid JSON, non-array root, malformed figure objects).
List<Figure> decodeFigures(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    rethrow;
  }
  if (decoded is! List) {
    throw FormatException('figures_json root must be an array', json);
  }
  return [
    for (final entry in decoded)
      if (entry is Map<String, Object?>)
        figureFromJson(entry)
      else
        throw FormatException('figure entries must be objects: $entry'),
  ];
}
