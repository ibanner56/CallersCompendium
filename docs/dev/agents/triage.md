# Triaging an issue

Load this chapter when triaging or scoping an issue.

A report is a hypothesis. The job is to establish what is true, not to restate
the report in more words.

- **Verify the report's own evidence before scoping the work.** A cited example
  frequently disproves the claim it was offered for, or turns out to be a
  different defect than the one described. Check it first; a fix scoped around a
  wrong example fixes nothing.
- **Check whether it is already fixed but unreleased.** Compare the fix's merge
  date against the newest release tag. A user on the last build reports things
  `main` resolved weeks ago, and that reads as a live defect until someone looks.
- **Say whether it is live or latent, and why.** "Reachable today by ordinary
  use" and "unreachable because an unrelated guard happens to hold" are different
  issues with different priorities. When a hazard is closed only incidentally,
  say which incidental fact closes it — that is the thing that will change.
- **Check the defaults before blaming configuration.** A setting only explains a
  report if the reporter plausibly had it set. Read the shipped default rather
  than assuming the one that fits the theory.
- **Name the in-repo precedent.** Most gaps here have a sibling that already
  does the thing correctly. Pointing at it is worth more than a design
  description: it fixes the shape, and it stops the second implementation
  diverging from the first.
- **Ask whether it is one site or a class.** Grep for siblings before writing the
  acceptance criteria. Shared widgets and duplicated walks mean a report about
  one screen is often a defect in three.
- **Separate display from canonical.** A rendering change is cheap. Putting the
  same value into canonical text changes FTS, dedupe and the derived projection,
  and therefore means a taxonomy bump, a migration and a derived rebuild. Decide
  which is being asked for before estimating anything.
- **Structured and free-text search are different capabilities.** A structured
  param is filterable the moment it exists; it is findable by typing its words
  into search only if it reaches canonical text. An issue asking for "searchable"
  needs to say which.
- **Re-check the issue's own cross-references.** Bodies cite sibling issues as
  open, closed or blocking, and those claims age badly — including within a
  single working session. Verify before relying on one, and correct it in place
  when it has moved.
- **Do not fold a report into a root cause that only explains part of it.** When
  a single mechanism accounts for two of three symptoms, say so and leave the
  third open. A tidy story that covers most of the evidence is how the remaining
  defect gets closed unfixed.
- **Retitle when the title misroutes.** A title describing a feature that
  already ships, or a symptom whose cause turned out to be elsewhere, will be
  triaged on its title by whoever reads it next.
- **Enrich in place; do not append corrections.** A ticket is read top to bottom
  as a spec. A superseded ruling sitting above the current one is how an
  implementer picks up the wrong decision — edit the comment and leave a visible
  note that it changed.
- **Record the rejected alternative and why it was rejected.** The decision is
  the cheap half; the reasoning is what stops it being relitigated, or silently
  reintroduced by a later change that looks unrelated.

## Leave the issue cheaper to implement than you found it

An issue that names the files to touch, the docs to update, and the acceptance
criteria costs the implementing session far less than one that does not — the
alternative is rediscovering, turn by turn, scope the triager already knew. See
[session-cost.md](session-cost.md#scope-before-dispatch).
