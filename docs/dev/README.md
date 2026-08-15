# Developer docs: which document answers which question

Start here. One read of this page routinely replaces several broad greps, and it
names the documents that are **generated** so you read the source instead of the
rendering.

## By question

| Question | Read |
| --- | --- |
| What are the rules for working in this repo as an agent? | [`AGENTS.md`](../../AGENTS.md) (resident) and the chapters in [agents/](agents/) |
| Why is my session so expensive? | [agents/session-cost.md](agents/session-cost.md) |
| How do I request/read a review, or merge safely? | [agents/code-review.md](agents/code-review.md), [agents/merging.md](agents/merging.md) |
| Why does this rule exist? | [agents/incidents.md](agents/incidents.md) |
| How do I contribute / set up the toolchain? | [`CONTRIBUTING.md`](../../CONTRIBUTING.md) |
| What is planned, and what is done? | [`docs/ROADMAP.md`](../ROADMAP.md) (open work), [`docs/ROADMAP-archive.md`](../ROADMAP-archive.md) (completed phases) |
| Why is the stack what it is? | [`docs/adr/`](../adr/) — 001 stack, 002 distribution/update channels, 003 Linux packaging |
| What does the data model look like? | [`docs/design/domain-model.md`](../design/domain-model.md), [`docs/design/storage.md`](../design/storage.md) |
| How do imports work? | [`docs/design/imports.md`](../design/imports.md) (large; read the section index at its head) |
| What is a figure, formally? | [`docs/design/figure-taxonomy.md`](../design/figure-taxonomy.md), [`docs/design/dialect.md`](../design/dialect.md) |
| What changed in taxonomy vN / schema vN? | the version histories in [`figure-taxonomy.md`](../design/figure-taxonomy.md#taxonomy-version-history) and [`storage.md`](../design/storage.md#schema-version-history) — a bump appends its entry there in the same PR |
| How does search work? | [`docs/design/search.md`](../design/search.md) |
| What may a field do — can it be exported? | the registry: `packages/compendium_core/lib/src/privacy/field_registry.dart` |
| How do I cut a release? | [`releasing.md`](releasing.md) (steps), [agents/releasing.md](agents/releasing.md) (hazards), [`release-checklist.md`](release-checklist.md) |
| How does localization work? | [`localization.md`](localization.md) |
| What did users see change? | [`app/CHANGELOG.md`](../../app/CHANGELOG.md) |
| What do users read? | [`docs/user/`](../user/) — mirrored into the app, see below |
| Why is this session so expensive? | [agents/session-cost.md](agents/session-cost.md); `python3 tools/ci/report_comment_weight.py` for per-read comment bytes |

## Run the gates

```sh
python3 tools/preflight.py           # every gate CI runs, one line each
python3 tools/preflight.py --fast    # pure-stdlib gates only, seconds
python3 tools/preflight.py --list    # what runs, and why
```

Each gate also lives in [`.github/workflows/_checks.yml`](../../.github/workflows/_checks.yml)
with a comment saying which defect it exists to prevent — that file is the
authoritative list; `preflight.py` is the local mirror of it.

## Generated files: read the source, not the rendering

Generated files carry a `<!-- generated-by: ... -->` marker (Markdown) or an
equivalent header comment, so `grep -rl 'generated-by:'` finds them. Never
hand-edit one; a gate will fail, and the edit is lost at the next regeneration.

| Generated | From | By |
| --- | --- | --- |
| the field-catalogue block of [`data-classification.md`](data-classification.md) | `packages/compendium_core/lib/src/privacy/field_registry.dart` | `packages/compendium_core/tool/generate_data_classification_doc.dart` |
| `app/assets/docs/user/*.md` (the in-app User Guide bundle) | `docs/user/*.md` | `tools/ci/sync_user_docs.py` |
| the `/guide/` section of the Pages site | `docs/user/*.md` | `tools/site/render_user_docs.py` |
| `app/lib/l10n/*.dart` | `app/lib/l10n/*.arb` | `flutter gen-l10n` |
| `packages/compendium_core/lib/src/storage/database.g.dart` | `tables.dart` | `build_runner` (drift) |

`app/assets/docs/` is a byte-for-byte mirror, gated by
`python3 tools/ci/sync_user_docs.py --check`; it deliberately carries **no**
marker of its own, because the bundle is rendered verbatim in the app and a
comment line would be user-visible. Edit `docs/user/`, then run the tool with
`--write`.

## Where the code lives

| Area | Path |
| --- | --- |
| Domain core (no Flutter — ADR-001) | `packages/compendium_core/lib/src/` |
| Importers and dialects | `packages/compendium_core/lib/src/imports/`, `.../dialect/` |
| Taxonomy | `packages/compendium_core/lib/src/taxonomy/` |
| Privacy registry | `packages/compendium_core/lib/src/privacy/` |
| Schema and migrations | `packages/compendium_core/lib/src/storage/` |
| UI | `app/lib/src/screens/`, `app/lib/src/widgets/` |
| CI ratchets | `tools/ci/` (each `check_*.py` / `report_*.py` has a matching `test_*.py`) |
| Release tooling | `tools/release/` |
| Site rendering | `tools/site/` |
