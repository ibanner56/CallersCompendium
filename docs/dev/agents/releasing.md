# Cutting a release: the hazards

Load this chapter when cutting a release. The step-by-step lives in
[../releasing.md](../releasing.md); these are the failure modes that
step-by-step does not prevent on its own.

- **Promoting `## [Unreleased]` into the version section is a manual step, and
  it is the release's highest-risk moment.** Contributors write under
  `## [Unreleased]`; nothing promotes it for them. The notes generator resolves
  the section by SemVer *core*, so every prerelease in a line renders the same
  heading — which means a section left over from the previous release is found,
  is valid, and renders happily under the new version's banner.
  [`tools/ci/check_changelog_promoted.py`](../../../tools/ci/check_changelog_promoted.py)
  gates the common case.
- **A passing check is not evidence the notes are current.** The gate tests that
  a section *exists*; what matters is that it is *fresh*, and no exit code
  distinguishes those. Render the notes, read them, and confirm they describe
  this release — then read the rendered draft on the release page before
  publishing. (A CI gate now covers the common case; the read is still the
  backstop.)
- **Re-derive the schema and taxonomy versions from source at tag time.** They
  move while a release is being prepared, so a number quoted in a status report
  an hour old may already be wrong. The Data/Migrations section is where users
  learn what is about to happen to their data; a stale range misinforms them.
- **Derive the next tag from the existing tags.** Do not assume the increment.
- **Publish only after the provenance gate is green**, and confirm afterwards
  that the channel manifest *and* its detached signature are both live and that
  the signature verifies. A manifest without its signature makes the in-app
  updater fail closed and stop offering updates silently.
- **Guard concurrency mechanically, not by agreement.** Two agents able to tag
  is a real hazard, but deference between them fails silently the moment one
  stops existing. Compare the candidate commit against the newest release tag,
  check for an in-progress release run, and let the remote reject a duplicate
  tag. Those hold with no cooperating party at all.
- **A conversational session cannot hold a multi-hour watch.** It ends when the
  conversation does. Work that must outlive it belongs in a scheduled workflow
  whose prompt is self-contained, because each run starts with no memory of the
  one before. When two agents could act, authority belongs to the **durable**
  one — not to whichever engaged first.

For guard tests and CI ratchets added along the way, see
[verification.md](verification.md): a gate that has never been shown to go red is
indistinguishable from one that does nothing.
