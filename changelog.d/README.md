# Pending changelog fragments

Normal pull requests record release notes by adding one JSON fragment here. Do
not edit `app/CHANGELOG.md` or `packages/compendium_core/CHANGELOG.md`; those
are release-managed historical records compiled from these fragments during
release preparation.

Name a fragment `<id>.json`, where `<id>` is a stable, unique, lowercase
identifier such as an issue number plus a short slug. Its `"id"` must exactly
match the filename stem.

```json
{
  "id": "1165-json-export",
  "user_visible": true,
  "app": {
    "added": [
      "You can save, copy, share, or cancel a JSON export for a dance or program."
    ]
  },
  "core": {
    "added": [
      "Add JSON export serialization helpers."
    ]
  }
}
```

`app` entries are the published release notes: write user-facing prose in the
second person. `core` entries are the Compendium Core package version record.
Each audience supports `added`, `changed`, `fixed`, and `removed`; `app` also
supports `data_migrations`.

Every fragment declares whether its change is user-visible. `user_visible:
true` requires an `app` entry. A user-visible outcome caused by a core change
needs both `app` and `core` entries. A core-only internal change uses
`user_visible: false` and may have only `core`. Do not create a fragment for an
app-only change users cannot observe.

Validate pending fragments with:

```sh
python3 tools/release/compile_changelog_fragments.py --check
```

Release preparation runs the compiler with a chosen app version and release
date. It prepares both committed changelog outputs before writing them and
deletes consumed fragments only after validation succeeds. Git history and the
compiled changelogs retain released entries; fragments are deliberately not
archived.
