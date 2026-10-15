/// Whether [value] nests lists and maps more than [limit] deep, walked
/// without recursion, so a value nested deep enough to overflow the stack is
/// caught before anything recursive (`jsonEncode`, normalisation) touches it.
///
/// Depth counts containers: a scalar is depth 0, `[]` and `{}` are depth 1,
/// `[[1]]` is depth 2.
bool jsonNestedDeeperThan(Object? value, int limit) {
  final stack = <(Object?, int)>[(value, 1)];
  while (stack.isNotEmpty) {
    final (current, depth) = stack.removeLast();
    final Iterable<Object?>? children = switch (current) {
      final Map<Object?, Object?> map => map.values,
      final List<Object?> list => list,
      _ => null,
    };
    if (children == null) continue;
    if (depth > limit) return true;
    for (final child in children) {
      stack.add((child, depth + 1));
    }
  }
  return false;
}
