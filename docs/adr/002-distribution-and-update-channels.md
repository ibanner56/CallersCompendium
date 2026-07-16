# ADR-002: Distribution & update channels

- **Status**: Proposed
- **Roadmap item**: 7.1
- **Deciders**: @ibanner56

## Context

Caller's Compendium ships to six targets (Windows, macOS, Linux desktops plus
Android and iOS). It is local-first, has **no telemetry**, and is maintained by
volunteer developers from the dance community, so we weight low operational
burden and contributor accessibility heavily (see ADR-001). Two forces shape
this decision:

- **The app has essentially zero outbound HTTP today.** The only network egress
  is user-initiated: clicking a link (`launchExternalUrl`,
  `app/lib/src/utils/launch_external_url.dart`) or explicitly importing a dance
  from a URL (`UrlFetcher` in `app/lib/src/data/import_io.dart`). An update check
  introduces a *new* egress path, so it must be introduced deliberately and
  privacy-cleanly, not as an always-on background beacon.
- **Signing is a cost/identity reality that differs per platform.** macOS
  notarization and iOS both require the Apple Developer Program ($99/yr);
  Windows SmartScreen trust needs an Authenticode certificate; Android needs a
  self-managed keystore. We cannot assume any paid signing exists on day one,
  so the baseline update path must work with **no signing at all**, on every
  desktop including Linux.

We also carry two pre-existing facts that a distribution/update design must
respect:

- Drift database `schemaVersion` is currently **9**
  (`packages/compendium_core/lib/src/storage/database.dart`) and migrations are
  **forward-only**: there is an `onUpgrade` chain but **no downgrade guard**
  (`beforeOpen` only enables foreign keys and defensively recreates the FTS
  table). An older build opening a newer database is undefined behavior today.
- A local **BackupService** (with `BackupDocument` / `encodeBackup` /
  `decodeBackup`, `app/lib/src/data/`) already exists (ROADMAP G.5).

This ADR records the Phase 7.1 distribution and update-channel architecture. It
deliberately specifies the **manifest schema and asset-naming as a contract**,
because later Wave-1 PRs will *produce* it (a `release.yml` workflow) and
*consume* it (a pure-Dart update client); the two must not drift.

## Decision

### 1. Spine — GitHub Releases + a static update manifest

GitHub Releases is the **sole artifact host**. Each release publishes a **static
update manifest** — `stable.json` and `beta.json`, one document per channel —
as a **release asset** (optionally mirrored to GitHub Pages for a stable URL).
The in-app update check is a plain HTTPS `GET` of that manifest.

We do **not** query the GitHub REST API (`/releases/latest`) for the check.
Reasons: it couples us to GitHub's API rate limits (shared/unauthenticated
limits are low and IP-based), forces us onto GitHub's response shape rather than
our own, is less cache/CDN-friendly, and — because the client must send an API
`User-Agent` and negotiate JSON — is harder to keep privacy-clean than a bare
`GET` of a static file. It is documented as a **fallback** only (see Rationale).

Bonus alignment: the same per-release artifact metadata that the manifest
captures is exactly what a Sparkle/WinSparkle **appcast** needs, so the static
manifest is the single source of truth from which the later appcast is
generated.

### 2. Manifest schema (the feed contract) and asset naming

**This schema is a contract.** `release.yml` writes it; the update client reads
it. Fields:

```jsonc
{
  "manifestSchemaVersion": 1,          // int, required. Client hard-refuses an unknown major.
  "channel": "stable",                 // "stable" | "beta", required. Must equal the file's channel.
  "version": "0.2.0",                  // SemVer string, required. Compared against kAppVersion.
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0",
  "pubDate": "2026-08-01T00:00:00Z",   // RFC3339 UTC, required. Also feeds appcast <pubDate>.
  "artifacts": [                       // required, >= 1 entry, one per platform+arch.
    {
      "platform": "macos",             // "linux" | "macos" | "windows" | "android" | "ios"
      "arch": "universal",             // "x64" | "arm64" | "universal"
      "url": "https://github.com/ibanner56/CallersCompendium/releases/download/v0.2.0/CallersCompendium-0.2.0-macos-universal.dmg",
      "sha256": "<lowercase 64-hex>",  // required. Integrity check + appcast signature companion.
      "size": 12345678,                // bytes, int, required.
      "minOsVersion": "11.0"           // optional. Per-platform OS floor for this artifact.
    }
  ]
}
```

Field rules:

- `manifestSchemaVersion` — integer feed-contract version. The client refuses a
  value whose **major** it does not understand rather than guessing; a breaking
  schema change bumps this and is a Revisit trigger.
- `channel` — must equal the channel implied by the filename (`stable.json` →
  `"stable"`), so a mis-published file is detectable.
- `version` — SemVer; the pure-Dart client compares it against `kAppVersion`
  (`app/lib/src/app_metadata.dart`).
- `releaseNotesUrl` — opened via the existing `launchExternalUrl` seam from the
  update banner.
- `pubDate` — RFC3339 UTC; also reused verbatim when generating the appcast.
- `artifacts[]` — at least one entry; each is
  `{platform, arch, url, sha256, size, minOsVersion?}`. The client selects the
  entry matching the running platform+arch.

**Deterministic asset naming:**

```
CallersCompendium-<version>-<platform>-<arch>.<ext>
```

| platform | arch(s)             | ext(s)                   |
|----------|---------------------|--------------------------|
| linux    | `x64`, `arm64`      | `AppImage`, `tar.gz`     |
| macos    | `universal`         | `dmg`, `zip`             |
| windows  | `x64`, `arm64`      | `exe` (installer), `zip` |
| android  | `universal`         | `apk`                    |
| ios      | (store-delivered)   | — (App Store/TestFlight) |

Example: `CallersCompendium-0.2.0-windows-x64.exe`. `<version>` is the bare
SemVer (no `+build`). Every release additionally publishes a `SHA256SUMS` file
plus the free integrity attestations described in §6.

### 3. Channels — stable and beta

Two channels: **stable** and **beta**.

- A beta build is published as a GitHub **pre-release** and described by a
  separate `beta.json` (its own `channel: "beta"` entry).
- Channel selection is an **opt-in Settings toggle, default OFF** (stable). Only
  when a user opts into beta does the client fetch `beta.json`; otherwise it
  only ever fetches `stable.json`.

### 4. Update mechanism — staged

**Stage 1 (baseline, universal, no signing required).** An in-app
"Check for updates" action fetches the channel manifest, compares versions, and
— if newer — shows a banner whose action **opens the release download page via
`launchExternalUrl`**. It does not download or install anything. This works on
every desktop (including Linux, where no auto-update framework is assumed) and
on mobile (deep-link to the store/release page), and requires no code signing.

**Stage 2 (true auto-update, gated on code-signing).** Later, desktop gains real
in-app update via the **`auto_updater`** package (leanflutter — the **same
ecosystem** as the app's existing `window_manager` / `screen_retriever`
dependencies), which wraps **Sparkle on macOS** and **WinSparkle on Windows**
and is driven by the **appcast** generated from the manifest data. This stage is
**gated on code-signing existing** (Sparkle/WinSparkle require signed updates to
be trustworthy), so it does not ship until signing is in place. Linux continues
to use the Stage-1 path (or distro/Flathub updates). **Sparkle system profiling
stays OFF** — we never set `sendsSystemProfile` — to honor the no-telemetry
stance.

### 5. Privacy contract for the update check

The check is a **plain HTTPS `GET` of the static manifest** and nothing more:

- **No query params, no fingerprinting User-Agent, no unique/install id, no app
  version, and no OS/arch transmitted** to the host. Platform/arch selection is
  done *client-side* after the manifest is fetched — the server never learns it.
- **Manual "Check for updates" is always available.**
- **Automatic background check is opt-in, default OFF.**
- On the baseline path there is **no auto-download and no auto-install**.
- A newer version surfaces as a **dismissible, non-modal banner** (never a modal
  interrupt during a gig).
- The client honors a stored **`dismissedVersion`**: once a user dismisses a
  given version it is not shown again (no nagging) until a newer one appears.
- The check uses a **short timeout and fails silently offline** — a missing
  network is a no-op, never an error dialog.

### 6. Per-platform distribution + signing dependency table

| Platform | Distribution | OS-trust signing dependency |
|----------|--------------|-----------------------------|
| Linux    | AppImage + `tar.gz`; Flathub | None (free) |
| macOS    | `dmg` / `zip` | **Developer ID + notarization → Apple Developer Program $99/yr** |
| Windows  | Inno/NSIS installer + `zip` | **Authenticode code-signing certificate** |
| Android  | Release APK (self-generated keystore); F-Droid; optional Play Store | Self-managed keystore; Play $25 one-time (optional) |
| iOS      | App Store / TestFlight | **Apple Developer Program $99/yr** |

Independent of OS-trust signing, a **free integrity layer applies to ALL
platforms**, even where signing is absent: a per-release **`SHA256SUMS`**,
**keyless SLSA build-provenance attestations** (GitHub OIDC, no secret to
manage), and an **SBOM**. The `sha256` in each manifest entry lets the client
verify a downloaded artifact regardless of platform trust.

### 7. Data-safety across updates

Migrations are forward-only today (`schemaVersion` 9). We **add**:

- **Downgrade protection** — refuse to open a database whose `user_version` is
  **greater than** the running `schemaVersion` (an older build must not run new-
  schema data). This is a defensive check in the database open path
  (`packages/compendium_core/lib/src/storage/database.dart`), surfaced to the
  user rather than risking silent corruption.
- **Backup-before-migrate** — snapshot the database *before* an upgrade runs.
  This **folds into the existing `BackupService`** (`app/lib/src/data/`,
  ROADMAP G.5) rather than adding a new mechanism, so a failed migration is
  always recoverable.
- **CI migration-fixture gate** — CI **requires a migration fixture test on any
  `schemaVersion` bump** (extending the existing rule that every migration ships
  a fixture test in `test/storage/migration_test.dart`).
- **Release rule** — **never bump `schemaVersion` in a PATCH release.** A schema
  change is at least a MINOR version, so users reason about data-format changes
  from the version number.

### 8. Placement and testability (ADR-001)

Per ADR-001's "pure-Dart core, no Flutter/I-O in business logic" rule:

- Update logic lives in **`app/lib/src/update/`**, **not** in
  `packages/compendium_core/` (updating is an app/desktop concern, and the fetch/
  launch seams are app-layer).
- The model is **pure Dart and unit-testable without I/O**: a manifest model
  (parse + `manifestSchemaVersion` guard), a **SemVer compare**, a **channel
  filter**, and `isNewerThan(kAppVersion)`.
- Network is an **injected fetch seam mirroring the existing `UrlFetcher`
  pattern** in `app/lib/src/data/import_io.dart` (injectable `http.Client`,
  short timeout, message-safe failures). `package:http` is already an app
  dependency, so no new dependency is needed for Stage 1.

## Rationale

- **Static manifest over GitHub-API polling.** Owning the schema decouples us
  from GitHub's API shape and rate limits, makes responses cache/CDN-friendly,
  keeps the request a privacy-clean bare `GET`, and yields the exact data a
  Sparkle/WinSparkle appcast needs. The API approach is kept as a *fallback* for
  the rare case the static asset URL is unavailable, but it is not the primary
  path. **Package-manager-only distribution** (Flathub/F-Droid/Homebrew) was
  rejected as the *sole* channel: it does not cover Windows, does not give a
  single "check for updates" story, and leaves direct-download users un-served —
  though we still publish to those ecosystems where free.
- **Staged update, launch-first over Sparkle-from-day-one.** The launch-page
  baseline works on all platforms with zero signing and zero background egress,
  which matches our day-one reality (no paid certs, Linux has no first-party
  auto-updater). Bringing up `auto_updater` before signing exists would ship an
  update path users cannot trust (unsigned updates) — worse than a manual link.
- **`auto_updater` (leanflutter) for Stage 2.** It reuses the ecosystem the app
  already depends on (`window_manager`, `screen_retriever`), wraps the mature
  Sparkle/WinSparkle stacks, and is appcast-driven — so the manifest we already
  produce is the input. Rolling our own download/verify/relaunch installer on
  three desktop OSes was rejected as far more surface for a volunteer team.
- **Privacy-clean by construction.** Doing platform/arch selection client-side
  after a static `GET` means the server literally cannot profile users, which is
  a stronger guarantee than a policy promise on an API call that carries a
  User-Agent.

## Consequences

- **A new, deliberately-gated network egress is introduced.** The app goes from
  "only user-clicked links leave the machine" to "an opt-in/manual update check
  can leave the machine." The privacy contract (§5) is what keeps this
  acceptable; it must be honored by the Stage-1 client PR.
- **Escalation flags to resolve before store submission / Stage 2:**
  - **Apple Developer Program ($99/yr)** — gates macOS notarization and iOS.
  - **Windows Authenticode certificate** — gates SmartScreen-clean installers and
    WinSparkle-signed updates.
  - **Android keystore custody policy** — who holds the signing key and how it is
    stored/rotated (a lost key blocks all future updates).
  - **Bundle-id mismatch to reconcile** — Android
    `org.callerscompendium.compendium_app` vs Apple
    `org.callerscompendium.compendiumApp`. These must be reconciled (or a
    deliberate divergence documented) before store submission.
- **Easier:** one artifact host, one deterministic naming scheme, one schema
  shared by producer and consumer, and a free integrity layer everywhere.
- **Harder / debts accepted:** we take on maintaining the manifest/appcast
  generation, the downgrade guard + backup-before-migrate wiring, and the
  per-platform signing pipelines when budget allows.

## Revisit triggers

- A signing budget (Apple/Windows) is approved → enable Stage 2 auto-update.
- A store or ecosystem rejects the naming/distribution scheme.
- The manifest needs a breaking change → bump `manifestSchemaVersion` and
  re-ratify the contract with the producing/consuming PRs.
- GitHub Releases becomes an unsuitable host (policy, quota, or cost) → revisit
  the artifact-host decision.
- Evidence that the update check leaks identifying data despite the contract.
