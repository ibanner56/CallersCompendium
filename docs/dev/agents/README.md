# Agent chapters

[`AGENTS.md`](../../../AGENTS.md) at the repository root is **resident context**:
it is injected into every turn of every session, so its cost is
`bytes × turns × sessions`. It therefore carries only the rules that bind in
*every* session.

Everything else lives here, in chapters, and is read by the session that needs
it and by nobody else. Each chapter is named in the core by one line saying when
to load it.

| Chapter | Load it when |
| --- | --- |
| [code-review.md](code-review.md) | Requesting or reading a Copilot review, or answering review findings |
| [merging.md](merging.md) | About to merge: review/CI freshness, unresolved threads, what the PR will close |
| [verification.md](verification.md) | Proving a guard test can fail; any red-run that mutates the working tree |
| [triage.md](triage.md) | Triaging or scoping an issue |
| [releasing.md](releasing.md) | Cutting a release (hazards; the step-by-step is [../releasing.md](../releasing.md)) |
| [session-cost.md](session-cost.md) | Scoping work for an agent, or adding to the resident instructions |
| [incidents.md](incidents.md) | You want the evidence behind a rule: the PR numbers, SHAs and reproductions |

Path-scoped instructions live in [`.github/instructions/`](../../../.github/instructions/).
Those attach automatically to sessions touching the matching paths, so a session
that never opens `packages/compendium_core/lib/src/privacy/` never pays for the
privacy-registry rules.

## Why the rules are split this way

A rule earns residency by applying to work in general. A rule that applies to
one path belongs in a path-scoped instruction file; a rule that applies to one
*phase* (review, merge, release, triage) belongs in a chapter, because the
session that reaches that phase can read it then.

The narrative behind a rule — which PR it came from, which SHA reproduced it —
is what stops the rule being relitigated, so it is never deleted. It lives in
[incidents.md](incidents.md), reachable rather than resident.
