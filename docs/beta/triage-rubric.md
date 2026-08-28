# Beta Feedback Triage Rubric

This document is for maintainers and anyone curious about what happens to a report
after it is filed. It describes how incoming beta feedback is sorted, labeled, and
tracked so nothing gets lost and testers can see where their reports stand.

Every label named here comes from the project's single source of truth,
[`.github/labels.yml`](../../.github/labels.yml) — the 47-label taxonomy. Use labels
by their **exact names** (for example `severity: critical`, not "critical"); do not
invent ad-hoc labels in the GitHub UI.

> **How this connects to testers:** the [beta guide](./beta-guide.md) tells testers
> which form to use; this rubric is the other side of that — how a maintainer turns
> a report into a labeled, tracked issue and moves it to resolution.

## The triage flow at a glance

1. A report arrives as a GitHub issue (usually via a
   [beta feedback form](./beta-guide.md#how-to-give-feedback)) and starts at
   `status: triage`.
2. A maintainer reads it and applies **one label from each dimension** that
   applies: a **type**, a **severity**, one or more **area** labels, a **platform**
   label if it is OS-specific, and the `beta` marker when it came from a tester.
3. If the report cannot be acted on yet, it moves to `status: needs-info` and the
   maintainer asks the reporter a specific question.
4. Once understood and reproduced, it advances through the **status lifecycle**
   below, gaining a **priority** when it is scheduled.

The goal is that at any moment, an issue's labels answer four questions: *what kind
of thing is this, how bad is it, what part of the app and platform does it touch,
and where is it in its life?*

## Severity: how bad is the impact?

Severity is about **impact on a caller**, not effort to fix. Apply exactly one,
mapping to the severity labels in `labels.yml`:

| Label | Use it when… |
|---|---|
| `severity: critical` | Data loss, a crash, or something that stops you calling at a gig. Anything that loses a caller's collection or breaks **Perform mode** live is critical. Handle these first. |
| `severity: major` | A significant broken workflow with no easy workaround — an import that mangles dances, a program you cannot save — but you can still use the rest of the app. |
| `severity: minor` | Limited impact with a reasonable workaround. Annoying, not blocking. |
| `severity: trivial` | Cosmetic or very low impact — a typo, slight misalignment, an off-by-a-hair color. |

When in doubt between two levels, ask: *would this ruin someone's night at a
dance?* If yes, lean higher.

## Type: what kind of report is this?

Apply one **type** label so reports route to the right mindset:

- `type: bug` — a defect; something is not working as intended.
- `type: enhancement` — a new feature or an improvement to existing behavior.
- `type: feedback` — general beta-tester impressions (often from a **Beta
  check-in**).
- `type: usability` — a confusing, awkward, or inefficient experience, even if
  nothing is technically "broken."
- `type: import` — anything about importing dances or notation from external
  sources.
- `type: docs` — documentation, help text, or in-app guidance.
- `type: question` — a question or request for clarification.

## Area: which part of the app?

Apply one or more **area** labels so reports reach the right part of the codebase.
These mirror the parts of the app testers use:

- `area: collection` — the dance collection / library.
- `area: programs` — building and managing programs.
- `area: perform` — Perform / calling mode.
- `area: dialect` — figure taxonomy, notation, and dialects.
- `area: import` — the import pipeline and parsers.
- `area: search` — search and filtering.
- `area: settings` — settings and preferences (including backup/restore).
- `area: packaging` — packaging, installers, and distribution.
- `area: a11y` — accessibility.
- `area: docs` — documentation and help content.

Multiple areas are fine — a search-in-Perform-mode problem might get both
`area: perform` and `area: search`.

## Platform: is it OS-specific?

If a report only happens on one operating system, add the matching **platform**
label; leave it off when the issue is cross-platform:

- `platform: linux`
- `platform: macos`
- `platform: windows`
- `platform: android`
- `platform: ios` (iOS / iPadOS)

## Status: the lifecycle

Every issue carries exactly one **status** label showing where it is. This is the
backbone testers watch to see their report move:

1. `status: triage` — just arrived, awaiting initial triage. Every new issue starts
   here.
2. `status: needs-info` — waiting on more information from the reporter. Pair it
   with a specific question so the reporter knows what would unblock it.
3. `status: confirmed` — reproduced and accepted as valid.
4. `status: in-progress` — actively being worked on.
5. `status: fixed-pending-release` — fixed on `main`, waiting for a release to ship
   it. (During the beta this is common, since fixes queue up between builds.)
6. `status: wont-fix` — valid, but a decision was made not to address it. Explain
   why in a comment before closing.

Off to the side of the happy path:

- `status: blocked` — cannot proceed because of a dependency or a pending decision.
  Note what it is blocked on.

A typical bug travels `triage → confirmed → in-progress → fixed-pending-release`. A
report that needs clarification detours through `needs-info` and back. Not every
issue reaches every stage — a duplicate or a `wont-fix` exits early.

## Priority: when will it be scheduled?

Severity says *how bad*; **priority** says *how soon we plan to act*, weighing
severity against how many callers it affects and how close it is to a release. Add
one when an issue is scheduled:

- `priority: high` — schedule soon.
- `priority: medium` — normal queue.
- `priority: low` — nice to have when there is room.

Severity and priority are related but not identical: a `severity: trivial` typo on
the first-run screen might still be `priority: high` because everyone sees it, while
a `severity: major` edge case that hits almost no one could sit at `priority: low`.

## Cross-cutting markers

- `beta` — apply to anything reported or raised during the beta program, so we can
  see the whole beta picture at a glance regardless of type or area.
- `good first issue` — a well-scoped, low-context task suitable for a first-time
  contributor. Adding this to confirmed, small issues invites help.

## A worked example

A tester files a **Bug report**: on their iPad, **Perform mode** goes blank when
they advance past the last figure of a dance mid-gig.

A maintainer labels it:

- `type: bug` — it is a defect.
- `severity: critical` — it stopped them calling at a gig.
- `area: perform` — that is where it happens.
- `platform: ios` — only reported on iPadOS so far.
- `beta` — it came from a beta tester.
- `status: triage` → after reproducing on a simulator, `status: confirmed`, then
  `status: in-progress`, and `priority: high`.

When the fix merges, it becomes `status: fixed-pending-release` until the next beta
build ships — and the tester, watching the issue, sees exactly that.

## Where to go next

- [Beta guide](./beta-guide.md) — the tester-facing side, including which form to
  file.
- [Test charter](./test-charter.md) — the sessions that generate this feedback.
- [`.github/labels.yml`](../../.github/labels.yml) — the authoritative label list.
