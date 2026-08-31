# Accessibility baseline

*Roadmap item 1.6 · drafted 2026-07-10. This is a requirements baseline, not a
design; UX designs (1.11) and implementation must conform to it, and CI/testing
requirements below become acceptance criteria in later phases.*

## Standards target

- **WCAG 2.2 Level AA** as the normative baseline, interpreted for native apps
  where web-specific criteria don't apply directly (use W3C's WCAG2ICT guidance).
- Platform conventions on top of WCAG: each platform's accessibility API must be
  fed correctly (macOS/iOS Accessibility/VoiceOver, Windows UIA/Narrator+NVDA/JAWS,
  Android TalkBack, Linux AT-SPI/Orca).
- EN 301 549 / European Accessibility Act alignment follows automatically from
  WCAG 2.2 AA conformance; we do not target Level AAA globally, but stage-use
  needs push specific criteria beyond AA (see below).

## Why this app is unusual: the stage context

Callers use the app mid-performance: dim/variable lighting, standing distance
from a tablet, one free hand, high stress, no time to fiddle. Several AAA-level
criteria are therefore **required** in performance mode even though our general
baseline is AA:

| Need | Requirement |
|---|---|
| Readability at arm's length+ | Performance mode text scalable far beyond 200% (effectively unlimited reflow, target legibility at ~1 m for tablets) |
| Dim stage / bright hall | High-contrast light AND dark themes; ≥ 7:1 contrast for performance-mode text (AAA 1.4.6) |
| One-handed, gross-motor use | Large touch targets (≥ 44×44 pt in performance mode, ≥ 24 px min elsewhere per WCAG 2.5.8), edge-reachable next/prev navigation, no precision gestures required |
| No accidental state loss | No destructive actions reachable from performance mode without confirmation |
| Screen must stay on | Wake-lock while performing |
| Glare/angle issues | User-adjustable font, weight, line spacing in performance mode |

## Core requirements (all screens)

### Perceivable
- Text contrast ≥ 4.5:1 (3:1 for large text); non-text UI contrast ≥ 3:1.
- Respect OS-level text scaling (Dynamic Type / font scale / display scaling) up
  to 200% with reflow, no clipped or truncated-without-recourse content.
- Never encode meaning by color alone (e.g. program-slot type color coding must
  have a text/icon channel too — note Caller's Companion uses color-only set
  list coding; we must do better).
- Dark mode as a first-class theme, not an afterthought.

### Operable
- 100% keyboard operability on desktop (tab order, visible focus indicator per
  WCAG 2.4.11/2.4.13, standard shortcuts, no keyboard traps). Fast dance entry
  must be possible without touching the mouse — this is also a power-user feature.
- Drag-and-drop (program reordering) must have a non-drag alternative
  (WCAG 2.5.7): move up/down buttons or cut/paste reordering.
- Touch targets ≥ 24×24 px minimum, 44×44 pt preferred on touch surfaces.
- No time-based interactions as the only route to an action. A sustained primary
  press may be an optional shortcut only when a visible, keyboard-operable,
  non-timed equivalent provides the same capability; Program **View details**
  previews are the explicit exception.

### Understandable
- Consistent navigation and terminology across screens; user's dialect applied
  uniformly (a11y benefit: the user's own vocabulary *is* the display language).
- Destructive actions (delete dance/program) undoable or confirmed; prefer
  undo/soft-delete (already in roadmap 3.5) over confirmation dialogs.
- Error messages: specific, adjacent to the field, never color-only.

### Robust (assistive tech)
- Every interactive element exposes name/role/value/state to the platform
  accessibility API; screen-reader traversal order matches visual order.
- Structured figure display must read sensibly with a screen reader (e.g.
  "A1, 8 beats, neighbors balance and swing" — not raw notation glyphs).
  Notation abbreviations need accessible expansions.
- Custom widgets (matrix grid, program builder) need explicit accessibility
  tree work; prefer standard widgets wherever possible.
- Announce dynamic changes (search result counts, save confirmations) via
  polite live-region equivalents.

## Screen-reader support matrix (acceptance target)

| Platform | AT | Level |
|---|---|---|
| Windows | NVDA (primary), Narrator; JAWS best-effort | Full task coverage |
| macOS | VoiceOver | Full task coverage |
| iOS/iPadOS | VoiceOver | Full task coverage |
| Android | TalkBack | Full task coverage |
| Linux | Orca | Best-effort; core flows must work |

"Full task coverage" = a screen-reader user can catalog a dance, build a
program, and read a dance card end-to-end.

## Process requirements

- **ADR-001 (stack choice) must weigh accessibility maturity heavily**; a stack
  that can't feed platform accessibility APIs well is disqualified.
- Automated checks in CI where the stack allows (semantics/a11y linters,
  contrast tests on theme tokens); golden tests for text-scaling layouts.
- Manual screen-reader passes on the AT matrix before each release; a11y
  regression checklist in the release template.
- Accessibility acceptance criteria included in each UX design doc (1.11) per screen.
- Recruit at least one AT-using tester in the beta program (7.3).

## Release-blocking subset vs. full baseline

Everything above is the full, aspirational baseline. As of the release gate
added in `docs/dev/release-checklist.md` (§7, "Accessibility"), a **scoped
subset** of it is release-blocking; the rest remains advisory/tracked until
a later phase promotes it.

- **Release-blocking (enforced, prospective from the next tagged release
  onward — does not retroactively block a build already in progress):**
  - VoiceOver (iOS) + TalkBack (Android) screen-reader smoke test across the
    core flows (Collection browse/search, Dance detail, Program builder,
    Performance mode).
  - Text-scaling / reflow check: Android font scale **2.0×**, iOS largest
    Dynamic Type accessibility size.
  - Keyboard-only navigation check on desktop.
- **Advisory / not yet gating (still tracked here, still expected
  eventually, but won't block a tag today):**
  - NVDA, Narrator, and Orca full-task-coverage screen-reader passes (see
    the screen-reader support matrix above) — deferred to a later release
    cycle.
  - Contrast ratio audits, focus-order audits, and the rest of the
    Perceivable/Operable/Understandable/Robust requirements not called out
    as gating above.

This split exists so the gate is achievable and enforceable today without
waiting for full AT-matrix tooling/testers across every platform; the
advisory items are expected to graduate into the gate as the beta program
matures (see "Recruit at least one AT-using tester" in Process requirements,
above).

## Open items

- Validate WCAG2ICT mapping once the stack is chosen (some criteria shift).
- Decide printing/PDF export accessibility (tagged PDF?) in Phase 4 design.
- Localization interplay: dialects are user-level language; app-chrome i18n is
  out of scope for v1 but must not be architecturally precluded.
