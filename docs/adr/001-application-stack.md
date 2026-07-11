# ADR-001: Application stack — Flutter

- **Status**: Accepted (2026-07-10)
- **Roadmap item**: 1.5
- **Deciders**: @ibanner56

## Context

Caller's Compendium must run on Windows, macOS, and Linux desktops plus iOS/
Android tablets and phones (tablets are the primary gig device), fully offline
with a local SQLite database (FTS5), a large-print performance mode, printing/
PDF export, and drag-and-drop program building. It will be maintained by
volunteer developers from the dance community, so contributor accessibility and
low operational burden are weighted heavily. Accessibility requirements are
defined in `docs/research/accessibility-baseline.md`.

Candidates evaluated (July 2026 versions): Flutter 3.44, Tauri v2.11, React
Native 0.80/Expo SDK 57, .NET MAUI 10, Kotlin/Compose Multiplatform 1.7.3, and
Electron 43 + Capacitor 6 with a shared TypeScript core.

## Decision

**Flutter** (Dart), with drift (SQLite/FTS5), `printing` (PDF/print),
`wakelock_plus`, and built-in drag-and-drop/reorderable widgets.

## Rationale

Eliminations:

- **React Native** and **.NET MAUI**: no production Linux desktop target — hard
  blocker (RN's op-sqlite also lacks Linux).
- **Tauri v2**: any native work requires Rust — a steep barrier for hobbyist
  dance-community contributors; mobile WebView UX is inadequate for a
  large-print, touch-drag tablet interface; Linux GTK3 deps carry unmaintained
  RUSTSEC advisories.
- **Compose Multiplatform**: desktop screen-reader support (NVDA/Orca) is far
  below our WCAG 2.2 AA baseline as of 1.7.3. Revisit if 1.8+ closes the gap.

Finalists were Flutter and Electron+Capacitor (the Obsidian architecture).
Flutter wins on the criteria we weighted highest:

1. **One first-party codebase for all six targets** vs two shells, two build/
   signing pipelines, two plugin ecosystems, and a hand-rolled SQLite
   abstraction (`better-sqlite3` vs `@capacitor-community/sqlite`). For a small
   volunteer team, halving the operational surface matters more than any single
   feature.
2. **Tablet gig UX is our most critical surface** — Flutter's native-feel
   touch handling, text rendering (Impeller), and built-in reorderable/DnD
   widgets beat mobile WebViews without extra engineering.
3. **Requirement coverage is uniformly mature**: drift v2.34 (SQLite + FTS5 on
   all five platforms, reactive queries, type-safe migrations), `printing`
   (native print/PDF everywhere incl. Linux), `wakelock_plus` (all platforms).
4. **Testing story** (unit / widget / integration tiers) supports our
   comprehensive-testing mandate well.
5. Dart is niche but demonstrably easy to pick up from TypeScript/Java/Kotlin,
   and Flutter's tooling (single SDK, hot reload, `flutter create`) minimizes
   onboarding friction. Proven similar OSS apps: AppFlowy, Immich, Spotube.

## Consequences

- **Desktop screen-reader support (NVDA/JAWS/Orca) is Flutter's weakest area.**
  We accept this knowingly: the a11y baseline already mandates explicit
  semantics annotation, per-release manual AT passes on all five platforms, and
  screen-reader task coverage as acceptance criteria. Semantics work is a
  standing requirement on every UI work item, not a retrofit.
- Electron+Capacitor remains the documented fallback if Flutter's desktop a11y
  proves unworkable during Phase 2/3 validation — the domain layer should stay
  UI-agnostic to keep that door open (pure-Dart core, no Flutter imports in
  business logic).
- CI needs macOS, Linux, and Windows runners for the full build matrix
  (GitHub Actions supports all three).
- Contributors must install the Flutter SDK; we will keep setup to
  `flutter pub get && flutter run` plus documented platform toolchains.
- Web is not a v1 target but Flutter keeps it available at low cost.

## Revisit triggers

- Flutter desktop accessibility fails our Phase 3 screen-reader task-coverage
  tests despite semantics work.
- Material changes in Flutter governance/health (e.g. Google divestment
  without a credible successor).
