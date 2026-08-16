---
applyTo:
  - "packages/compendium_core/lib/src/privacy/**"
  - "packages/compendium_core/test/privacy/**"
  - "packages/compendium_core/lib/src/storage/**"
  - "app/lib/src/data/**"
  - "app/test/data/**"
  - "docs/dev/data-classification.md"
---

# Privacy registry: classifying a persisted field

These rules load for sessions touching the privacy registry, the database
schema, the settings layer, or their ratchets. The universal statement of the
rule is in [`AGENTS.md`](../../AGENTS.md); this is the detail.

## The registry is the boundary

`packages/compendium_core/lib/src/privacy/field_registry.dart` is the source of
truth for whether a field may be transmitted. `docs/dev/data-classification.md`
is **generated** from it by
`packages/compendium_core/tool/generate_data_classification_doc.dart` — never
hand-edit the document, and read the registry rather than the rendering.

Code that decides whether a field may leave the device reads `EgressClass` from
the registry rather than carrying its own allow-list, so there is exactly one
place to change and no second list to drift.

## What must be classified, and when

Any new database column, settings key, or data-entry surface must be classified
**in the same PR that introduces it**. Ratchets across
`packages/compendium_core/test/privacy/` and `app/test/data/` enforce this,
covering:

- database columns,
- settings keys declared as an exact constant, and
- settings keys built at runtime from a declared prefix.

The failure mode is a red CI run rather than a silent leak. This exists because
the boundary used to be prose and prose did not hold — see
[incidents.md](../../docs/dev/agents/incidents.md#the-privacy-boundary-that-was-prose).

## Choosing the three axes

- **Category** — a W3C DPV v2.3 term. Freely readable, so check your own work
  against the source rather than guessing at a near-match.
- **Subject** — `none` / `appUser` / `thirdParty`. No published taxonomy supplies
  this axis, and it is the one most often got wrong: venue contacts and
  choreographers never touch this app and cannot consent to a transfer they do
  not know about, so their data is `thirdParty` even though the app user typed it.
- **Egress** — `shareable` / `deviceLocal` / `deviceScoped` / `derived`.
  `deviceLocal` is withheld because of what the value *contains*, and may still
  move by a direct device-to-device transfer. `deviceScoped` is withheld because
  of what the value *means* on another device, and must not travel by any route.
  Conflating the two is how a device-scoped value ends up in a backup.

Record **why** in the entry's `note` whenever the call is not self-evident, and
say who decided it if it was contested. A classification with no stated reason is
indistinguishable from a guess.

## Do not narrow a ratchet to silence a false positive

The settings ratchet flags `kUpdateManifestPublicKey`, which is the Ed25519 root
of trust for update authenticity rather than a preference. It is excluded **by
name, with a reason**, so the next non-settings `…Key` constant still fails
loudly. A cleverer detection pattern would have dropped both silently.

## Before pushing

```sh
python3 tools/preflight.py
```

runs the privacy ratchets along with the rest. If you changed the registry,
regenerate the document in the same PR:

```sh
fvm dart run packages/compendium_core/tool/generate_data_classification_doc.dart
```
