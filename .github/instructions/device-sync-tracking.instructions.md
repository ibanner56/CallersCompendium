---
applyTo:
  - ".github/tracking/**"
  - "tools/tracking/**"
  - ".github/workflows/device-sync-tracking.yml"
---

# Device Sync work tracking

Read `.github/tracking/README.md` before editing these paths.

- Git files are authoritative; GitHub Project cards are generated.
- Protocol behavior stays in `docs/design/sync-spec.md`.
- One implementation PR owns one work unit; one unit may use several PRs.
- Never commit derived lifecycle states. Only completion and evidence are
  durable; open PRs supply active state.
- Ready means dependencies are satisfied, not authorization to begin.
- Never create GitHub Issues for Device Sync implementation work.
- Run the tracking validator and both of its mutation-proven test suites.
