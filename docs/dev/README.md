# Developer docs: which document answers which question

Start here. One read of this page routinely replaces several broad greps, and it
names the documents that are **generated** so you read the source instead of the
rendering.

## By question

| Question | Read |
| --- | --- |
| What are the rules for working in this repo as an agent? | [`AGENTS.md`](../../AGENTS.md) (resident) and the chapters in [agents/](agents/) |
| Why is my session so expensive? | [agents/session-cost.md](agents/session-cost.md); `python3 tools/ci/report_comment_weight.py` for per-read comment bytes |
| How do I request/read a review, or merge safely? | [agents/code-review.md](agents/code-review.md), [agents/merging.md](agents/merging.md) |
| What does reviewing a design here keep catching? | [design-review.md](design-review.md) — the habits, and the findings they came from |
| Why does this rule exist? | [agents/incidents.md](agents/incidents.md) |
| Where is a 2026-10 audit finding or maintainer decision recorded? | [`audits/2026-10-behavior/`](audits/2026-10-behavior/README.md) — the October 2026 behaviour audit, kept as a historical record (see [Citing a record](#citing-a-record)) |
| How do I contribute / set up the toolchain? | [`CONTRIBUTING.md`](../../CONTRIBUTING.md) |
| What is planned, and what is done? | [`docs/ROADMAP.md`](../ROADMAP.md) (open work), [`docs/ROADMAP-archive.md`](../ROADMAP-archive.md) (completed phases) |
| Why is the stack what it is? | [`docs/adr/`](../adr/) — 001 stack, 002 distribution/update channels, 003 Linux packaging, 004 Device Sync and the Athenaeum server, 005 difficulty vocabulary, 006 English country dance grammar |
| How does Device Sync work? | [`docs/design/sync.md`](../design/sync.md), [`sync-spec.md`](../design/sync-spec.md) (the wire contract), [`sync-implementation.md`](../design/sync-implementation.md); the server is [`server/README.md`](../../server/README.md) |
| What does the data model look like? | [`docs/design/domain-model.md`](../design/domain-model.md), [`docs/design/storage.md`](../design/storage.md) |
| How do imports work? | [`docs/design/imports.md`](../design/imports.md) (large; read the section index at its head) |
| What is a figure, formally? | [`docs/design/figure-taxonomy.md`](../design/figure-taxonomy.md), [`docs/design/dialect.md`](../design/dialect.md) |
| What changed in taxonomy vN / schema vN? | the version histories in [`figure-taxonomy.md`](../design/figure-taxonomy.md#taxonomy-version-history) and [`storage.md`](../design/storage.md#schema-version-history) — a bump appends its entry there in the same PR |
| How does search work? | [`docs/design/search.md`](../design/search.md) |
| What may a field do — can it be exported? | the registry: `packages/compendium_core/lib/src/privacy/field_registry.dart` |
| How do I cut a release? | [`releasing.md`](releasing.md) (steps), [agents/releasing.md](agents/releasing.md) (hazards), [`release-checklist.md`](release-checklist.md) |
| How do I record a pending release note? | [`changelog.d/README.md`](../../changelog.d/README.md) — add one JSON fragment, not a shared CHANGELOG edit |
| How does localization work? | [`localization.md`](localization.md) |
| What did users see change? | [`app/CHANGELOG.md`](../../app/CHANGELOG.md) |
| What do users read? | [`docs/user/`](../user/) — mirrored into the app, see below |

## Run the gates

```sh
python3 tools/preflight.py           # every gate CI runs, one line each
python3 tools/preflight.py --fast    # Python gates only, no Dart/Flutter, seconds
python3 tools/preflight.py --list    # what runs, and why
```

Each gate also lives in [`.github/workflows/_checks.yml`](../../.github/workflows/_checks.yml)
with a comment saying which defect it exists to prevent — that file is the
authoritative list; `preflight.py` is the local mirror of it.

## Citing a record

Design documentation on `main` does not point to files or recorded decisions on
another branch (the maintainer's rule, 2026-11-12). A branch is deleted or
rewritten long before the document that cites it is retired, and a decision
whose only record is on a branch loses its provenance with it. So:

- If a document or comment needs to cite a record that lives only on a branch
  (an audit report, a decision log), bring the record onto `main` in the same
  PR and cite its path there. Copy it byte-for-byte if anything cites it by
  `file:line`.
- To say where work was done, cite the merged PR (`#N`) or a commit SHA that
  is on `main`, not the branch it was built on. A GitHub link pins such a SHA
  or `main`, never a branch. A SHA that exists only on a branch is a branch
  citation in disguise: it stops resolving once the branch is deleted, and
  the check below cannot tell (CI checks out a single commit).
- Naming the branch a *planned* piece of work will be built on, in a plan
  table, is fine: that names work, not a place where a record lives.

`python3 tools/ci/check_branch_citations.py` enforces the common shapes of this
in every Markdown file, the text files under `docs/`, and the comments of
hand-written Dart. Its docstring lists exactly what it flags, what it knowingly
misses, and the one exempt path: the audit record, whose logs name the session
branches its work was built on and must stay byte-for-byte.

## Generated files: read the source, not the rendering

Generated Markdown carries a `<!-- generated-by: ... -->` marker on its first
line naming the tool and the source. Generated Dart carries its generator's own
header instead (`// GENERATED CODE - DO NOT MODIFY BY HAND` from drift;
`flutter gen-l10n` emits no marker at all), so `grep -rl 'generated-by:'` finds
only the Markdown — the table below is the authoritative list. Never hand-edit
one; a gate will fail, and the edit is lost at the next regeneration.

| Generated | From | By |
| --- | --- | --- |
| the field-catalogue block of [`data-classification.md`](data-classification.md) | `packages/compendium_core/lib/src/privacy/field_registry.dart` | `packages/compendium_core/tool/generate_data_classification_doc.dart` |
| `app/assets/docs/user/*.md` and `app/assets/docs/user/images/*.png` (the in-app User Guide bundle) | `docs/user/*.md` and `docs/user/images/*.png` | `tools/ci/sync_user_docs.py` |
| the `/guide/` section of the Pages site | `docs/user/*.md` | `tools/site/render_user_docs.py` |
| `app/lib/l10n/*.dart` | `app/lib/l10n/*.arb` | `flutter gen-l10n` |
| `packages/compendium_core/lib/src/storage/database.g.dart` | `tables.dart` | `build_runner` (drift) |
| `packages/compendium_core/lib/src/sync/generated_sync_allow_list.dart` | `privacy/field_registry.dart` and `sync/wire_mapping.dart` | `packages/compendium_core/tool/generate_sync_allow_list.dart` (`test/sync/wire_mapping_test.dart` fails when it is stale) |
| `packages/compendium_core/drift_schemas/generated/*.json` and `packages/compendium_core/test/storage/generated/*.dart` | a database written by `tool/write_head_database.dart` at each schema version | `drift_dev` — see [`drift_schemas/README.md`](../../packages/compendium_core/drift_schemas/README.md) |

`app/assets/docs/` is a byte-for-byte mirror, gated by
`python3 tools/ci/sync_user_docs.py --check`; it deliberately carries **no**
marker of its own, because the bundle is rendered verbatim in the app and a
comment line would be user-visible. Edit `docs/user/`, then run the tool with
`--write`.

`app/CHANGELOG.md` and `packages/compendium_core/CHANGELOG.md` are
release-managed historical records. Their pending source is
[`changelog.d/`](../../changelog.d/); the release compiler preserves prior
history while consuming validated JSON fragments, so these are not fully
reproducible generated files.

## Where the code lives

| Area | Path |
| --- | --- |
| Domain core (no Flutter — ADR-001) | `packages/compendium_core/lib/src/` |
| Importers and dialects | `packages/compendium_core/lib/src/imports/`, `.../dialect/` |
| Taxonomy | `packages/compendium_core/lib/src/taxonomy/` |
| Privacy registry | `packages/compendium_core/lib/src/privacy/` |
| Schema and migrations | `packages/compendium_core/lib/src/storage/` |
| Device Sync (client side) | `packages/compendium_core/lib/src/sync/` |
| Athenaeum sync server (pure Dart, a workspace member) | `server/` |
| UI | `app/lib/src/screens/`, `app/lib/src/widgets/` |
| Android share intake (size cap, staging, cold vs warm) | `app/android/app/src/main/kotlin/.../IncomingFileStager.kt`; JVM tests in `app/android/app/src/test/` |
| CI ratchets | `tools/ci/` (each `check_*.py` / `report_*.py` should have a matching `test_*.py`; `check_l10n_drift.py`, a thin wrapper, has none. `tools/test_preflight.py` asserts every `test_*.py` under `tools/` is run by a workflow and by preflight) |
| Release tooling | `tools/release/` |
| Site rendering | `tools/site/` |
