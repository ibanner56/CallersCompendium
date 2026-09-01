# Repository-backed work tracking

Git is the source of truth for large implementation programmes. GitHub Projects
is a generated view: its cards may be rebuilt and ordinary direct card edits are
overwritten. If both generated identity markers are edited to name different
valid units, synchronization fails closed; restore either the `Work Unit ID`
field or the hidden `tracking-card` marker before rerunning it.

Device Sync is tracked under `adr-004/`:

- `project.json` defines the Project, phases, checkpoints, expected work units,
  and maintainer decisions that alter scheduling.
- `units/WN.json` defines one implementation work unit from
  `docs/design/sync-implementation.md`.
- `tools/tracking/validate.py` rejects missing units, unknown fields, broken
  source references, duplicate PR ownership, and dependency cycles.
- `tools/tracking/sync_project.py` combines merged repository state with open PR
  state and reconciles the public Project.

The normative behavior remains in `docs/design/sync-spec.md`. Tracking metadata
may summarize a unit and its completion conditions but must not override or
duplicate the protocol.

## Lifecycle

`completion.complete` is the only durable lifecycle state stored in a unit.
Everything else is derived:

| Project status | Source |
| --- | --- |
| Planned | At least one start dependency is incomplete |
| Ready | Start dependencies are complete and no owning PR is open |
| In progress | An owning draft PR is open |
| In review | An owning non-draft PR is open |
| Done | Completion and evidence are merged |

Ready means eligible, not authorized. A human must assign or launch the work.
`hold` is independent of lifecycle so a blocked unit does not lose its actual
stage.

`dependsOn` controls when work may start. `completionDependsOn` records a
dependency that permits early or parallel work but must finish before this unit
can be declared complete.

## Pull request identity

An implementation PR owns exactly one work unit. A unit may have several PRs.

```text
Branch: adr-004-w10-short-purpose
Title:  [ADR-004/W10] Concise outcome
Body:   <!-- tracking-unit: ADR-004/W10 -->
```

Open the draft PR early, then add its number to the unit's `pullRequests` array.
Intermediate PRs leave `completion.complete` false. The last PR records evidence
and sets it true; merging that change is the human completion decision.

Administrative tracking changes use `<!-- tracking-admin -->` and do not claim
delivery of a work unit.

Do not create GitHub Issues for Device Sync implementation tracking. Historical
issue and PR numbers may remain as evidence of work completed before this system.

## Unit template

```json
{
  "schemaVersion": 1,
  "id": "ADR-004/W10",
  "title": "Exact implementation-plan title",
  "phase": 2,
  "sequence": 50,
  "summary": "One plain-language outcome.",
  "specReferences": [
    {
      "path": "docs/design/sync-implementation.md",
      "heading": "W10 · Exact implementation-plan title"
    }
  ],
  "dependsOn": ["ADR-004/W3"],
  "completionDependsOn": [],
  "checkpoints": ["C2"],
  "produces": ["Concrete artifact"],
  "pullRequests": [],
  "hold": null,
  "completion": {
    "complete": false,
    "conditions": ["Observable completion condition"],
    "summary": null,
    "evidence": []
  }
}
```

Run:

```sh
python3 tools/tracking/test_validate.py
python3 tools/tracking/test_validate_pr.py
python3 tools/tracking/test_sync_project.py
python3 tools/tracking/validate.py
```

Project synchronization uses a fine-grained personal access token owned by
`ibanner56`, with **Account permissions > Projects: Read and write**, in the
`DEVICE_SYNC_PROJECT_TOKEN` Actions secret. The Project token is used only for
Project API mutations; repository reads use the workflow's `GITHUB_TOKEN`, and
no privileged workflow checks out or executes pull-request code.
