# ADR-003: Native Linux distribution channel (Flathub-first)

- **Status**: Accepted (2026-07-22) — evaluation decision; implementation deferred to a post-beta follow-up
- **Roadmap item**: 7.1 (post-beta follow-up)
- **Deciders**: @ibanner56
- **Relates to**: extends [ADR-002](002-distribution-and-update-channels.md) §4 (update mechanism) and §6 (per-platform distribution)

## Context

[ADR-002](002-distribution-and-update-channels.md) (Status: *Proposed*) lays out
the distribution spine: **GitHub Releases as the sole artifact host**, with a static per-channel
update manifest. For Linux the baseline is `.AppImage` + `.tar.gz` published on
GitHub Releases, plus `SHA256SUMS`, keyless SLSA build provenance, and an SBOM
for integrity (ADR-002 §6). Linux has **no OS trust-wall** (no Gatekeeper /
SmartScreen), so nothing blocks installability and no code signing is required
to install.

That baseline ships the beta fine, but it leaves four gaps for Linux users that
the other desktops either don't have or get "for free":

- **No auto-update.** ADR-002 §4 Stage-1 only *reveals/marks* the downloaded
  `.AppImage`; true in-place self-update is Stage-2 and is **gated on
  code-signing**, which Linux has no first-party mechanism for. So Linux users
  update by re-downloading, indefinitely.
- **No desktop integration.** A raw `.AppImage`/`.tar.gz` gives no menu entry,
  icon, or MIME/file associations unless the user wires them up by hand.
- **No discoverability.** Users must know to go to GitHub Releases.
- **No trusted-publisher signing.** There is integrity (checksums + provenance)
  but no store-level publisher identity.

There is also a known **AppImage papercut** (being clarified separately in the
docs, out of scope here): the shipped AppImage needs **`libfuse2`** at runtime,
which recent Ubuntu/Fedora do not preinstall, producing a cryptic
`libfuse.so.2` failure. The `.tar.gz` avoids it, but it is a rough first-run.

Constraints bounding the answer (per ADR-001 / ADR-002): volunteer maintainers,
**low operational burden**, **no telemetry**, a privacy-clean update story, and
a strong preference to avoid self-run infrastructure or GPG key management.

This ADR resolves the **evaluation** requested in #306. It records a *direction*
decision; it is **not** a commitment to ship a specific pipeline in the beta.

## Decision

Adopt **Flathub (Flatpak)** as the **first native Linux distribution channel to
pursue post-beta.** Keep `.AppImage` + `.tar.gz` on GitHub Releases as the
always-available direct-download baseline. Treat **Snap** and a **Launchpad
PPA** as secondary/optional. Do **not** stand up a **self-hosted apt/deb repo**
unless clear demand emerges and Flathub/PPA prove insufficient.

Concretely:

1. **Flathub is the store channel.** It provides store-managed auto-update,
   desktop integration (menu entry, icon, MIME associations via AppStream
   metainfo), a sandbox, and trusted-publisher signing — cross-distro, with no
   self-run repository infrastructure and no GPG keys to hold or rotate.
2. **GitHub Releases stays canonical.** The `.AppImage`/`.tar.gz` on GitHub
   Releases remains the direct-download baseline and the source of the in-app
   update manifest for non-Flatpak installs. Flathub *complements* the ADR-002
   spine; it does not replace it.
3. **The in-app update check must become Flatpak-aware.** A Flatpak install
   receives updates from Flathub, so the app should detect that it is running
   under Flatpak (e.g. the `FLATPAK_ID` environment variable / the
   `/.flatpak-info` marker) and **suppress or soften the Stage-1 update banner**
   there, so store users are never told to hand-download an AppImage. Non-Flatpak
   installs keep the existing `beta.json` / `stable.json` check unchanged. This
   is the one application-code touch-point and is deferred to the follow-up.
4. **Sandbox posture: tight by default.** As a local-first app, Caller's
   Compendium needs display/GPU, file access for import/export/backup, and
   printing. Start from minimal `finish-args` and prefer **XDG desktop portals**
   (file chooser, printing) over broad `--filesystem` holes; add permissions only
   as specific features require them.

## Rationale

- **Flathub is the single highest-leverage add** for a cross-distro Flutter/GTK
  desktop app: it erases the AppImage/FUSE papercut, and delivers auto-update +
  desktop integration + publisher signing at once, with essentially no infra for
  us to run. It is a well-trodden path for GTK/Flutter Linux desktop apps.
- **Snap (secondary).** Also store-managed with auto-update and it is the
  Flutter-documented Linux packaging route, but its ecosystem is Ubuntu-centric,
  `snapd` is not universal across distros, and classic/strict confinement has
  quirks for a file-and-print desktop app. Worth doing later, not first.
- **Launchpad PPA (secondary).** The lowest-effort way into the real `apt`
  world with Canonical-signed packages, but it is **Ubuntu-only** and adds
  per-release maintenance. Reasonable as a second channel if Ubuntu demand is
  strong.
- **Self-hosted apt/deb repo (rejected unless demand is clear).** High burden:
  build `.deb`s per distro/arch, host them, sign with a self-managed GPG key, and
  maintain it all — directly against the low-operational-burden weighting. This
  mirrors ADR-002's rejection of **package-manager-only distribution as the
  *sole* channel**; here we simply decline to *self-run* one.
- **Additive, not a pivot.** ADR-002 already rejected package-manager-only as
  the sole story (it doesn't cover Windows, fragments "check for updates", and
  strands direct-download users). This ADR keeps the GitHub Releases spine intact
  and layers Flathub on top for Linux specifically.

## Consequences

- **Easier:** Linux users get auto-update, desktop integration, a discoverable
  and signed channel, and the FUSE papercut disappears for Flatpak installs — all
  without us running signing or repo infrastructure.
- **Harder / debts accepted:** we take on maintaining a Flatpak manifest +
  AppStream metainfo + `.desktop` file + icons, a release-automation step to
  publish to Flathub on each tag, the initial Flathub submission/review, and a
  hosted Flathub app repo (`flathub/org.callerscompendium.compendiumApp`). Sandbox
  `finish-args` must be re-audited whenever file/print features change.
- **Update-manifest interaction (the one code touch-point):** the in-app check
  must be Flatpak-aware (see Decision §3) so store users are not double-notified.
  Recorded here; implemented in the follow-up.
- **Identity:** the Flatpak `app-id` reuses the unified Apple-form bundle id
  `org.callerscompendium.compendiumApp` (see ADR-002 Consequences), keeping one
  identity across all platforms.
- **Privacy unchanged:** the Flathub update client is the store's, not ours, so
  no new always-on egress is introduced by us; the ADR-002 §5 privacy contract is
  unaffected on the store path.

## Implementation sketch (for the follow-up issue — not wired in by this ADR)

Illustrative only; exact runtime version, install wrapper, AppStream metainfo,
and `.desktop`/icon assets are defined during implementation. A manifest can
source the **already-published, checksum-verified `tar.gz` release asset**, so
the existing `release.yml` pipeline barely changes:

```yaml
# org.callerscompendium.compendiumApp.yml (sketch)
app-id: org.callerscompendium.compendiumApp
runtime: org.freedesktop.Platform
runtime-version: '24.08'
sdk: org.freedesktop.Sdk
command: compendium_app
finish-args:
  - --socket=wayland
  - --socket=fallback-x11
  - --share=ipc
  - --device=dri
  # File chooser + printing go through XDG portals rather than broad fs access.
modules:
  - name: compendium-app
    buildsystem: simple
    build-commands:
      - install -d /app/bin /app/lib/compendium_app
      - cp -r ./* /app/lib/compendium_app/         # prebuilt `flutter build linux` bundle
      - ln -s /app/lib/compendium_app/compendium_app /app/bin/compendium_app
      # + install .desktop, icon, and AppStream metainfo into /app/share/...
    sources:
      - type: archive
        url: https://github.com/ibanner56/CallersCompendium/releases/download/vX.Y.Z/CallersCompendium-X.Y.Z-linux-x64.tar.gz
        sha256: <sha from the release SHA256SUMS>
```

**Submission / maintenance path:**

1. Fork `flathub/flathub`, add `org.callerscompendium.compendiumApp` with the
   manifest + AppStream metainfo + `.desktop` + icons; pass Flathub review.
2. Thereafter, either Flathub's update bot opens version-bump PRs, or a small
   `release.yml` step bumps the pinned tag + `sha256` on each GitHub Release so
   Flathub rebuilds from the verified `tar.gz`.
3. Add the Flatpak-aware update-banner suppression (Decision §3) in the app.

## Revisit triggers

- Real Linux users ask for `apt install` / a specific channel → reassess a
  Launchpad PPA vs. a self-hosted `.deb` repo.
- Flathub review or runtime constraints make the sandbox impractical for
  import/export/printing → reconsider Snap.
- Stage-2 (signed) in-place auto-update lands for the other desktops → confirm
  Flatpak still owns Linux updates so there are no dueling updaters.
- The Flatpak manifest's maintenance burden outweighs its adoption → fall back to
  the GitHub Releases baseline only.
