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
as a **release asset** and mirrors it to **GitHub Pages** for a stable
per-channel URL (`https://ibanner56.github.io/CallersCompendium/<channel>.json`),
which is what the in-app client actually fetches. (The Pages hosting is wired in
A11c — see [releasing.md](../dev/releasing.md#publishing-the-update-manifest-github-pages).)
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
  "manifestSchemaVersion": 1,          // int, required. Client hard-refuses a value it doesn't recognize.
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

- `manifestSchemaVersion` — integer feed-contract version. The client refuses
  any value it does not recognize rather than guessing; a breaking schema change
  increments this integer and is a Revisit trigger.
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
`launchExternalUrl`**. The baseline check itself downloads and installs nothing
(the manifest fetch aside); it merely links the user to the release page. This
works on every desktop (including Linux, where no auto-update framework is
assumed) and on mobile (deep-link to the store/release page), and requires no
code signing.

**Stage 1.5 (assisted download, desktop-only, no signing required).** A tier
*between* the Stage-1 link and Stage-2 auto-update that gives desktop users a
first-class download without any of Sparkle/WinSparkle's signing prerequisites.
When a newer version is found on **macOS/Windows/Linux**, the banner and
Settings ▸ Updates additionally offer a **"Download & install"** action that:

1. **Downloads** the manifest-selected `UpdateArtifact` (via the same injected
   `http.Client` seam as the check) to a **temp file**, with progress reporting
   and user **cancel**.
2. **Verifies** the file's **sha256 against `UpdateArtifact.sha256`** — a
   **mandatory** integrity gate. A mismatch **fails loudly**: the temp file is
   deleted and a clear error is surfaced (never a silent no-op).
3. **Hands the verified file off to the OS** so the user completes the install
   themselves — macOS opens the `.dmg`, Windows launches the installer `.exe`,
   Linux marks the `.AppImage` executable / reveals it. It **never replaces the
   running binary in place** — that self-update behavior is Stage 2 and stays
   gated on code-signing.

The download is always **explicit and user-initiated** (there is no automatic
background download), the "View release" link remains available as a fallback,
and A11a's dismiss/`dismissedVersion` behavior is preserved. **Mobile
(Android/iOS) does not get assisted download** — it keeps the Stage-1 link only.
The download/verify/handoff logic lives behind injectable, Flutter-free seams
(per §8 / ADR-001), mirroring the Stage-1 fetch seam.

**Stage 2 (true auto-update, gated on code-signing).** Later, desktop gains real
in-app update via the **`auto_updater`** package (leanflutter — the **same
ecosystem** as the app's existing `window_manager` / `screen_retriever`
dependencies), which wraps **Sparkle on macOS** and **WinSparkle on Windows**
and is driven by the **appcast** generated from the manifest data. This stage is
**gated on code-signing being in place** (Sparkle/WinSparkle require signed
updates to be trustworthy), so it does not ship until signing exists. Linux
continues to use the Stage-1 path (or distro/Flathub updates). **Sparkle system
profiling stays OFF** — we never set `sendsSystemProfile` — to honor the
no-telemetry stance.

### 5. Privacy contract for the update check

The check is a **plain HTTPS `GET` of the static manifest** and nothing more:

- **No query params, no fingerprinting User-Agent, no unique/install id, no app
  version, and no OS/arch transmitted** to the host. Platform/arch selection is
  done *client-side* after the manifest is fetched — the server never learns it.
- **Manual "Check for updates" is always available.**
- **Automatic background check is opt-in, default OFF.**
- On the baseline (Stage-1) path there is **no download and no install** — only
  a link out. **Stage 1.5** adds an **explicit, user-initiated** download +
  mandatory sha256 verification + OS-handoff on desktop; there is still **no
  *automatic* download and no *auto-install* / self-replacement**, and every
  §5 privacy guarantee above (no query params, no fingerprinting, no ids, no
  telemetry, client-side platform selection) applies unchanged to the artifact
  download.
- A newer version surfaces as a **dismissible, non-modal banner** (never a modal
  interrupt during a gig).
- The client honors a stored **`dismissedVersion`**: once a user dismisses a
  given version it is not shown again (no nagging) until a newer one appears.
- The check uses a **short timeout and fails silently offline** — a missing
  network is a no-op, never an error dialog.

### 6. Per-platform distribution + signing dependency table

Per-platform routes, cheapest-first. Where noted, this follows the official
Flutter deployment docs (<https://docs.flutter.dev/deployment>).

| Platform | Distribution route(s) | Trust / signing dependency & cost |
|----------|-----------------------|-----------------------------------|
| Linux    | AppImage + `tar.gz` (baseline); **Snap** (Flutter-documented); Flathub | None — Linux has no OS-trust-warning model (all free) |
| macOS    | Direct notarized `dmg`/`zip` (recommended); Mac App Store | Apple Developer Program **$99/yr** (both paths) |
| Windows  | (0) Unsigned installer+`zip` on GitHub Releases (free) → (a) Microsoft Store MSIX (~$19 one-time) → (b) Azure Trusted Signing (~$120/yr) → (c) Certum OSS (~$70–100/yr) → (d) OV (~$100–400/yr) → (e) EV (~$300–700/yr) | Rises with route; see below |
| Android  | Release APK signed with a self-generated upload keystore (official Flutter mechanism); F-Droid; optional Play Store | Self-managed keystore (free); Play $25 one-time (optional) |
| iOS      | App Store / TestFlight | Apple Developer Program **$99/yr** |

**Android.** The official Flutter-documented signing mechanism is a `keytool`
**upload-keystore** referenced from `android/key.properties` and wired into
Gradle `signingConfigs` for the release build type. The Flutter docs stress the
keystore **must not be committed to public source control** — so we store it (and
`key.properties`) as **CI secrets**. This confirms our free self-signed
release-key plan; no paid authority is required to produce an installable signed
APK. (Flutter: *Build and release an Android app*.)

**Windows.** Cheapest → priciest *trusted* routes:

- **(0) FREE** — ship an unsigned installer + `zip` on GitHub Releases and
  document the SmartScreen **"More info → Run anyway"** step. Flutter's docs
  **explicitly state publishing via the Microsoft Store is not required**; a
  self-distributed app is fully supported. (Flutter: *Build and release a Windows
  desktop app*.)
- **(a) Microsoft Store (MSIX)** — ~**$19 one-time** individual developer
  account; **the Store signs the MSIX**, so no standalone Authenticode
  certificate is needed. Built via the `msix` pub package + the `msstore` CLI
  (GitHub-Actions-automatable). This is the **cheapest cert-backed trusted route
  and the recommended first paid step** if/when Windows trust is wanted.
  Trade-off: Store certification and Store-based distribution/updates.
- **(b) Azure Trusted Signing** — ~**$9.99/mo (~$120/yr)**; signs a self-hosted
  installer, no HSM to manage.
- **(c) Certum Open Source code-signing** — ~**$70–100/yr**.
- **(d) OV certificate** — ~**$100–400/yr** (HSM-backed).
- **(e) EV certificate** — ~**$300–700/yr**; grants instant SmartScreen
  reputation.

A **sideloaded (non-Store) MSIX still needs a trusted certificate**; only a
**Store-distributed MSIX is signed by the Store**. **WinSparkle** (the Stage-2
auto-update path, §4) applies **only to the non-Store, self-hosted route** — the
Store owns updates for the MSIX route.

**macOS.** Flutter's own macOS deployment doc covers **only the Mac App Store**
path (Mac App Distribution + Mac Installer Distribution certificates). Our
recommended **direct-distribution** path — a **Developer ID Application**
certificate + **`notarytool`** + **`stapler`** to notarize a `.dmg` distributed
outside the Store — is valid and common but is an Apple-platform step **beyond**
the Flutter doc. We record **both**; both require the same Apple Developer
Program (**$99/yr**). (Flutter: *Build and release a macOS app*.)

> **Implemented (gated on secrets).** The direct-distribution path is now wired
> into `.github/workflows/release.yml`: on a `v*` tag the macOS leg deep-codesigns
> the `.app` with the hardened runtime, builds + signs the `.dmg`, notarizes via
> `notarytool`, staples the ticket to the `.app` and `.dmg`, and verifies with
> `codesign`/`spctl`. It is **gated exactly like Android** — active only when the
> `APPLE_DEVELOPER_ID_CERT_P12` / `APPLE_CERT_PASSWORD` / `APPLE_TEAM_ID` cert set
> **and** the `APPLE_API_KEY_P8` / `APPLE_API_KEY_ID` / `APPLE_API_ISSUER_ID`
> notarytool credentials are all present; otherwise the leg produces the same
> UNSIGNED artifacts as before. See
> [docs/dev/releasing.md](../dev/releasing.md#macos-developer-id-signed--notarized).

**iOS.** Flutter's iOS deployment doc covers App Store / TestFlight distribution
via Xcode; there is **no sideload or unsigned path** — Apple is the only channel.
We distribute **first to TestFlight** (internal testers, no App Review wait), not
the public App Store, using **automatic (Xcode-managed) code signing driven by an
App Store Connect API key** rather than a manually-created distribution
certificate + provisioning profile. `flutter build ipa` passes
`-allowProvisioningUpdates` to xcodebuild, so the iOS **distribution certificate +
App Store provisioning profile are created/managed in the cloud** at build time —
nothing to store or commit. The unified Apple bundle id is
`org.callerscompendium.compendiumApp`; no entitlements are declared. (Flutter:
*Build and release an iOS app*.)

> **Implemented (gated on secrets).** The iOS App Store archive + TestFlight
> upload is now wired into `.github/workflows/release.yml`: on a `v*` tag the iOS
> leg (`macos-latest`) archives + signs the `.ipa` with automatic signing and
> uploads it to TestFlight via `xcrun altool --upload-app`. It is **gated exactly
> like macOS/Android** — active only when `APPLE_API_KEY_P8` / `APPLE_API_KEY_ID`
> / `APPLE_API_ISSUER_ID` / `APPLE_TEAM_ID` are all present (the key needs the
> **App Manager** role, required for TestFlight upload); otherwise the leg is a
> clean skip. The build number is a monotonic `GITHUB_RUN_NUMBER * 1000 +
> GITHUB_RUN_ATTEMPT` (unique across re-runs; TestFlight rejects duplicates)
> passed on the CLI, **not** committed to `pubspec.yaml`.
> Upload is gated to **real tag pushes** (a `workflow_dispatch` builds + signs the
> `.ipa` for validation but never uploads). **No manual cert or provisioning
> profile is required**, and no Beta App Review / public App Store submission is
> triggered. The signed `.ipa` is store-delivered — it is **not** a GitHub Release
> asset and never enters `SHA256SUMS` / the channel manifest / the SLSA subject
> glob. See
> [docs/dev/releasing.md](../dev/releasing.md#ios-testflight-via-app-store-connect-api).

**Linux.** Alongside the AppImage + `tar.gz` baseline and Flathub, we also list
**Snap** (`snapcraft`), which is the **Flutter-documented** Linux release path.
All three are free, and Linux has no OS-trust-warning model to satisfy. (Flutter:
*Build and release a Linux app*.) The post-beta evaluation of which native Linux
channel to actually pursue — **Flathub-first**, with Snap/PPA secondary — is
recorded in [ADR-003](003-linux-native-distribution-channel.md).

Independent of OS-trust signing, a **free integrity layer applies to ALL
platforms**, even where signing is absent: a per-release **`SHA256SUMS`**,
**keyless SLSA build-provenance attestations** (GitHub OIDC, no secret to
manage), and an **SBOM**. The `sha256` in each manifest entry lets the client
verify a downloaded artifact regardless of platform trust.


### 7. Data-safety across updates

Migrations are forward-only today (`schemaVersion` 9). We **add**:

- **Downgrade protection** — refuse to open a database whose `user_version` is
  **greater than** the running `schemaVersion` (an older build must not run new-
  schema data). This is primarily an **app-layer preflight** that reads
  `PRAGMA user_version` *before* drift opens the file and surfaces a clear
  message to the user, backed by an optional **core belt** — an
  `if (from > to) throw` guard in the database open path
  (`packages/compendium_core/lib/src/storage/database.dart`) — rather than
  risking silent corruption.
- **Backup-before-migrate** — take a snapshot of the database *before* an upgrade
  runs. This is a **physical, schema-agnostic byte copy** of the SQLite file
  (after a WAL checkpoint), **distinct from — not folded into — the logical
  `BackupService` export** (`app/lib/src/data/`, ROADMAP G.5). The G.5 backup is
  a *logical v9-schema JSON export* that queries through repositories modeling
  the **current** schema, so it **cannot run against an un-migrated older-schema
  file**; the pre-migration snapshot must therefore be a complementary
  disaster-recovery mechanism (a raw file copy that restores byte-for-byte if a
  migration fails), different in kind from the user-triggered logical backup.
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
- **Stage 1.5's** download, sha256-verify, and OS-handoff steps are each their
  own **injectable, Flutter-free seam** (`artifact_downloader.dart`,
  `artifact_verifier.dart`, `artifact_handoff.dart`) in `app/lib/src/update/`,
  composed by `UpdateController`. This keeps the orchestration unit-testable with
  fakes (no real network, filesystem race, or OS launch) exactly like the
  Stage-1 fetch seam. Verification promotes **`package:crypto`** (sha256) from a
  transitive to a **direct** app dependency — the one dependency Stage 1.5 needs
  — with no `pubspec.lock` version change.

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
  - **Bundle-id mismatch — RESOLVED.** Android/Linux previously used
    `org.callerscompendium.compendium_app` while Apple used
    `org.callerscompendium.compendiumApp`; all platforms now unify on the Apple
    form `org.callerscompendium.compendiumApp` (Apple bundle IDs disallow
    underscores, so the Apple form is the source of truth).
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
