/// The minimum number of hands four needed to evaluate any dance
/// (`docs/architecture.md` §3.1).
///
/// Two: enough to have a neighbor to interact with and somewhere to progress
/// to. Everything else is additive on top of this.
const int kBaseHandsFour = 2;

/// Sums the pre-scan hands-four contributions onto [kBaseHandsFour] (§3.1, D7).
///
/// `total = base + Σ(success-criterion contribution) + Σ(per-operation-instance
/// contributions)`. Contributions are counted **per instance**, so the caller
/// passes one entry per operation in the figure list — three expanding
/// occurrences yield `+3`, not `+1`.
///
/// Deliberately takes plain ints rather than the operations themselves: sizing
/// happens before any formation exists, and this keeps the arithmetic testable
/// without standing up a whole dance.
int computeHandsFour(Iterable<int> contributions) =>
    contributions.fold(kBaseHandsFour, (total, amount) => total + amount);
