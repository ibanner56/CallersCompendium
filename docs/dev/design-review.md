# Design review: habits and findings

These entries were written during the review of the Device Sync design, in
[sync.md](../design/sync.md), where they had accumulated alongside the design
they came out of. They are reproduced here verbatim.

They were written in place, so their self-references need reading with that in
mind, and they are of two kinds. Where an entry says "this document" of a
*design* artefact — its purpose, its length, the `sync-spec.md` split, or a row
or a rule it states — it means [sync.md](../design/sync.md). Where an entry says
"this document", "these pages" or "here" of the body of review entries itself,
it means the entries collected on this page, which is where they now are.

Numbered section references (§4.4, §6.2) are sections of
[sync-spec.md](../design/sync-spec.md). The entries keep their original order,
because several of them refer to the entry above or below them, or count back a
fixed number of entries.

## Findings from the Device Sync design review

**When a rule is tightened, the gates that accepted the old rule do not fail —
they silently keep passing.** The spec moved from "redirected or refused" to
"refused", and the deployment gate that is the *only* check of that requirement
still said "redirected or refused". Nothing broke, because a loosened gate is
indistinguishable from a satisfied one. Tightening a rule means grepping for
the old permission, not just editing the sentence that granted it.

**A fact asserted by a reviewer enters the document with less scrutiny than one
the author wrote, because the author has no reason to re-derive it.** Round 43
corrected a claim the author had taken from stale official documentation. Two
of round 44's five findings were claims the *reviewer* supplied in that same
report — that `curl -L` retains `Authorization` across an `http`→`https`
redirect, and that DNS-rebinding protection is on by default in a named list of
products — neither checked against a primary source, both written straight into
the normative text on the strength of having been reported as verified. The
first was not merely wrong but was the exact behaviour curl classified as a
vulnerability and fixed in 7.83.0 (CVE-2022-27776), with an advisory page that
had been available the entire time. The lesson is symmetrical to round 43's and
needs stating separately, because the mitigation is different: the author's own
claims get re-read on every pass, and a reviewer's arrive pre-endorsed.
Anything a review asserts as verified must carry its primary source or be
marked unverified, and an unsourced fact should be treated as a question rather
than a finding.

**Correcting one half of a false conjunction can leave the other half standing
and now load-bearing.** The retention claim named two clients. The review found
`curl` wrong and proposed resting the argument on `dart:io` alone — which would
have replaced a claim that was half false with one that was wholly false and no
longer had a second clause to draw attention to it. `dart:io` strips sensitive
headers unless scheme, host *and* port all match (`_isSameOrigin`, consulted
from `shouldCopyHeaderOnRedirect` in `sdk/lib/_http/http_impl.dart`), so a
scheme upgrade is cross-origin and the header is dropped there too. Checking
only the half that was challenged is how a correction becomes the next defect.
Check the survivor precisely because it was not challenged.

**A correction reaches the sentence that was quoted, and stops there.** Round
44 retracted the claim that an `http`→`https` redirect carries `Authorization`
onward, having verified from primary sources that both named clients strip it.
The same commit left the retracted claim standing verbatim in two other places:
the §9 conformance rationale — in the same file, four hundred lines from its
own retraction, and the text an implementer reads to learn *why* the mutation
must fail, so it taught the retracted model to exactly the audience that would
encode it — and the ADR's requirement list, in a file that pass did edit.
Neither had been quoted in the review. The habit that would have caught it was
written into this document in that same commit.

**A lesson written down has no failure signal.** Fifteen rounds have produced a
long list of habits, and the only ones that have held without being remembered
are the **source-scanning ratchets** — CI tests that go red when the thing they
guard reappears. The ownership matrix and the conformance buckets are the
intermediate case, and it would be self-flattering to list them as mechanisms:
they are prose tables, better than a habit because a reviewer can *check* them,
but just as silent when nobody does. This document records both failing exactly
that way — round 33, where W18's own ratchet was gated by no conformance
bucket, and round 43, where the matrix row omitted W17 so the unit could have
closed green with its source scan never written. Each was caught by a reader,
not by anything breaking. A retrospective entry is a rung below even that,
which is the same argument `sync-implementation.md` makes for W17 existing at
all. So the standing conclusion of this document is not that the next reader
should remember these entries — it is that any rule worth keeping should be
moved into something that breaks when it is violated, and an entry here is a
placeholder for having not yet done that. The practical corollary, cheap enough
to be worth stating on its own: when a claim is retracted, grep the retracted
*wording* across every document before the commit lands, not the sentence that
prompted it.

**A supporting clause that is inert becomes the thing a later reader tests the
rule against.** The rewritten redirect rationale described the clients that
retain as "anything predating those two changes, and anything bespoke". Applied
to this app the first half is empty by construction — both fixes shipped in
early 2022 and no build carrying sync can predate them — so a future reader
checking "does anything reaching us predate Dart 2.16?" would find nothing and
could reasonably conclude the requirement was obsolete. The rule never rested
on that population; it rests on the operator not being able to see any client's
policy. The clause was narrowed to say which callers are actually meant.

**A retraction can overshoot into the opposite falsehood, and the replacement
gets less scrutiny than the thing it replaced.** Three rounds were spent
removing the claim that an `http`→`https` redirect carries `Authorization`
onward. The sentence written in its place said that *any* client which follows
the redirect gets a working sync — which is false for exactly the two clients
the preceding paragraphs establish do strip, since stripping is not declining
to follow. The pendulum had swung from "the redirect leaks the credential" to
"the redirect always works", both wrong, both attached to a rule that was
correct throughout. A correction inherits the confidence of the analysis that
produced it, and is the sentence least likely to be re-read.

**The §9 justification slot has now carried a false justification for three
consecutive rounds, and the localisation is the signal.** That paragraph
explains *why* a mutation must fail, so it is the text an implementer converts
into a test — a wrong model there propagates into the suite rather than staying
in prose. It attracts errors because it is written last, reads as explanation
rather than as a claim, and asserts things about third-party behaviour that no
gate checks. The cheap discipline, smaller than the grep the previous round
adopted: **when a justification is rewritten, read it beside the passage it
cites, in both directions.** That catches the §9 defect, which was a
same-paragraph contradiction — a sentence conceding that the outcome depends on
the client's header policy, immediately after one asserting it does not — and
which cites §7.5, the passage that settles it.

**It does not catch the other defect, and the difference is the point.** The
ADR's version of the same error had nothing adjacent to contradict it: the
claim was simply *unconditioned*, and the one clause mentioning header policy
attached to refusal's outcome rather than the redirect's. An absent condition
is not a disagreement between two present sentences, so there was nothing for a
side-by-side read to catch — and the bullet's only cross-reference is to §8,
about the client refusing a plaintext endpoint, which says nothing about header
retention. A citation-adjacency check surfaces exactly nothing there. That
shape is caught by the previous round's cross-document grep instead, and the
two remedies are not substitutes: one finds a sentence that argues with its
neighbour, the other finds a sentence with no neighbour to argue with.
Generalising from two instances without saying what each one was is how a
remedy ends up fitted to one of them, leaving the other silently uncovered —
which is the failure the entry below this one names, committed in the same
paragraph that names it.

**An entry arguing for mechanisation listed, as its examples of mechanisms, two
artefacts this document records failing silently.** The claim that the
ownership matrix and the conformance buckets "hold because forgetting them
fails loudly" is refuted twice in these pages: round 33, where a unit's own
ratchet was gated by no bucket, and round 43, where the matrix row omitted the
unit that carried the clause. Both were caught by a reader. Only the CI
ratchets fail loudly; the matrix and the buckets are the intermediate case —
checkable, and therefore better than a habit, but silent when nobody checks.
Writing an entry about rigour is not an exemption from it, and the examples in
an argument are the part nobody verifies.

**The retrospective is now the least-scrutinised artefact in the set, and it
has started producing the defects it describes.** Each of the last two rounds
found a defect *here*: an entry arguing for mechanisation whose examples were
two artefacts these pages record failing silently, and an entry prescribing a
remedy whose worked example covered one of the two defects it claimed. What
changed in round 47 is that this is where *every* finding landed, and the
normative text came back clean for the first time in four rounds; round 46's
two most severe findings were in the specification and in the ADR. The reason
is structural and the same one this document gives for everything else — the
retrospective is written last, it is prose about prose, no gate reads it, and
it is the part of a commit a reviewer arrives at with the least attention left.
It has the property it keeps attributing to justifications.

**So an entry that generalises must name its instances.** The generalisation is
where the remedy comes from, and a remedy is fitted to the shape of the
examples in front of the person writing it. Two defects that look alike from a
distance — both false justifications attached to a correct rule, both about the
same claim, both fixed in one commit — turned out to need different checks,
because one contradicted its neighbour and the other had no neighbour at all.
Stating only the count hid that. Where an instance cannot be stated, the entry
should be weakened until it can, because an unstated instance is one nobody can
check the conclusion against, and this document's own verdict on unchecked
supporting material is three entries old.

**Naming the instances is not enough when an entry also says where the defects
were *not*.** The entry recording that the retrospective had begun producing
its own defects named both of them — exactly what the rule beside it asks for —
and was false anyway, because alongside the property it argued for it asserted
an exclusion: that the specification and the ADR had been clean while those two
defects were found. An exclusion's instances are the ones it claims do not
exist, so there is nothing to name and naming cannot discharge it. The only
check is the population, and for a claim about where a round's findings were
the population is that round's report — round 46's lists four, the two most
severe of them in the specification and in the ADR. A rule that checks the
positive half of a sentence has nothing to say about the negative half, and
both halves were written in one breath.

**A scan that reports zero is an exclusion, and needs a positive control.** The
entry above says an exclusion is checkable only against its population, and a
scan *is* a population check — which is why "zero mid-word hyphen breaks in all
four documents" read as the verified kind of claim. It was asserted in two
consecutive commit messages here and in two consecutive review reports, and it
was false every time: four breaks were live in the text throughout, two of them
in the ADR, one of them inside the paragraph that settles how a poisoned
timestamp is classified. Both scans matched a pattern requiring the
continuation character to sit at the start of the line, so both skipped every
indented list continuation — and every surviving break was in one. That the
same blind spot appeared in two independently written scans is the part worth
keeping: both were written from the same picture of the text, so neither could
see the shape it left out. A scan asserting an absence should be run first
against a case known to be present. It costs one line, and it is the only thing
separating "nothing matched" from "nothing could have matched".

**The one class of claim here with a mechanical check is the one that keeps
going unchecked.** Three rounds running, the defect was a statement about what
a previous round found: that round 46's findings were all in the retrospective,
that both of round 47's defects had the same shape, and now that both of round
49's were about scans. Every one of those is decidable by opening a file that
was already on disk — the reports are files, their findings are headed, and a
grep answers the question in less time than writing the sentence took. This is
unlike the other things that go wrong in these pages: whether a justification
is true or a rule enforceable needs judgement, and judgement is what a review
is for. A claim about review history needs only that someone look. Two of the
three were written while the report they were about sat in the working
directory. The check is cheap enough that not doing it is the whole of the
defect.

**Prefer the unfavourable reading of a source that contradicts itself, or stop
and resolve it.** Round 49's report opened with "no findings against this
round's changes" and then raised one, marked Low and optional, against a
sentence added by that very commit. Both statements were in front of me. I took
the headline, wrote that the streak of defects-in-the-previous-repair had
ended, and recorded a nineteenth instance as the moment the run stopped — using
the one reading that made the record flattering. A self-critical document has a
standing appetite for the tidy narrative beat, and "the streak finally broke"
is a better sentence than "it did not". That appetite is exactly why the tie
should not go to the pleasing side. Where a source disagrees with itself, the
disagreement is the finding, and suppressing it silently is worse than either
reading.

**The general lesson, which is now twenty-one rounds old: the newest machinery
carries the round's defects.** W18 was created in round 32 to fix an ownership
gap, and in round 33 it was where both blocking findings lived — including a
fresh ownership gap, since its own ratchet was gated by no conformance bucket.
Round 34 then found that the *property* written in round 33 to close that
round's blocking finding was itself false, and false in a way round 33's own
new proof obligation was structurally unable to detect. Round 35 then found
both of its defects in the retry machinery round 34 had added to close *its*
blocking finding — unclassified new state, and a retry test that raises. Round
36 found its headline defect in the *replacement test* round 35 installed to
fix that raise, which broke the grouping guarantee it was protecting. Round 37
found the retirement rule round 36 added to be unbuildable from any accessor
that exists, in a way whose natural implementation destroys the repairs it was
written to protect. Round 38 found two more in the same machinery: a rule that
cited a sweep convention while dropping the step that makes it crash-safe, and
a widening rule whose actionable half could not fire for one of the two
triggers it named. Round 39 then found round 38's own repair incomplete in the
same direction — it reproduced the durable flag but not the generic pre-check
that reads it, and scoped the rule to the one-time pass when retry writes rows
too. Round 40 then found round 39's re-scoping applied to the flag's set but
not its clear, and its derivation rule mechanising two of the three criteria in
the scope sentence directly above it. Round 41 then found round 40's own remedy
for that rebuild cost self-defeating in both halves: it removed the work but
not the bookkeeping, so taking the permission deferred the identical rebuild to
app open, and it demanded a derivation from an artifact that does not carry the
fact. Round 42 then found five defects in the transport section written
*beside* round 41's repair — the repair itself being the strongest work in the
document — of which two were true rules carrying false justifications and two
were rules stated in prose with no mechanism that could enforce them. Round 43
then found that round 42's own correction rested on a false mechanism taken
from stale official documentation — inverting it, though the conclusion
survived — and that the certificate rule it reassigned had been moved in prose
but in neither the owning unit's gate nor the ownership matrix built to prevent
exactly that. Round 44 then found that two of round 43's corrections had
themselves been written from secondary sources supplied by the review, one of
them describing as current behaviour the exact thing curl had classified as a
vulnerability and fixed four years earlier — and that the rule they justified
was correct for a reason neither of them had stated. Round 45 then found that
round 44's retraction had reached the sentence it was shown and neither of the
two places that said the same thing unprompted — one of them four hundred lines
from the retraction, in the same file — and that the habit prescribing the grep
which would have caught it was added by that same commit. Round 46 then found
that the sentence written to replace the retracted claim was false in the
opposite direction, in the same slot of the same section, for the third round
running. Round 47 found the normative text correct for the first time in four
rounds, and both of its defects in the retrospective written to explain the
repair. Round 48 then found that the entry written to record *that* was false
about round 46, in the same commit as a sentence contradicting it. Round 49
raised two Low findings: that four mid-word line breaks had been live in the
text throughout while two independently written scans certified their absence,
and that the exclusion clause in the entry written the round before named only
half of what it was excluding. The second of those is a defect in the previous
round's repair, so the run did not stop, and this paragraph said it had — round
50 caught that. Nineteen consecutive rounds have found the round's defects in
the previous round's repair, which is no longer a coincidence and is better
read as a property of how repairs get written: under the belief that the hard
thinking has just been done. Round 30's instance was the spec paraphrasing an
algorithm; round 31's was the same thing twice more; round 32's was the plan
getting less scrutiny than the spec. Scaffolding built to close a gap is
written last, reviewed least, and inherits none of the scrutiny that produced
it — and a *justification* written to close a gap is the least reviewed
artefact of all, because it reads as the premise rather than as the new work.

### A grep that finds nothing is an exclusion, and needs its population

The `DELETE /v1/store` row in this document was the fourth statement of a claim
the other three documents had already corrected — and the commit that fixed the
third asserted that a grep had found no other instance. That assertion was
wrong. It is the sixth false absence in this review's history, and the panel
disclosed one of its own in the same round: a "remote untouched" claim derived
from an unpaginated `gh` listing.

The rule is already written down here — an exclusion is checkable only against
its population, so a scan reporting zero must first be run against a case known
to be present. What was missing is that a cross-document claim sweep *has* a
population, namely the set of documents, and it has an obvious positive
control: run the pattern against the line you are about to fix and watch it
match. If it does not match, the pattern is wrong and the zero everywhere else
means nothing.

## Review habits this design produced

These rules came out of reviewing this design rather than out of the sync
mechanism itself, and they are collected here, in the wording they were adopted
in, because they generalise beyond Device Sync.

### State must be named where the mechanism is introduced

> **Any mechanism that needs state to survive a restart must name where that
> state lives, add it to the schema scope, and classify it — in the same
> revision that introduces the mechanism.**

The third normative invariant, adopted for the same reason as the other two: the
mistake has now been made three times. The baseline manifest and epoch were
introduced as behaviour with no storage; so was `id_aliases`; so was the pending
tombstone, in the same revision that documented the rule for `id_aliases` two
sections earlier.

It is easy to miss because the mechanism reads as complete — "hold the tombstone
pending" describes a behaviour fully, and only a second reading asks *where the
pending flag is written*. Two things make the omission expensive here rather than
merely untidy: the coverage ratchet walks `db.allTables` and fails CI on any
unclassified column, so the gap surfaces late; and an unclassified field has no
egress ruling, which is the difference between a bookkeeping oversight and a
leak.

The check is mechanical. For each new mechanism, ask what it must remember across
a restart, and if the answer is anything at all, it appears in the table above
before the revision lands.

### A rule may only read what its own path can reach

> **Every rule must name the data it reads, and that data must be reachable on
> the path where the rule runs** — in the HTTP contract if a client needs it, in
> the server schema if the server needs it, and on the code path in question
> rather than a neighbouring one.

The fourth invariant, and the one that would have caught the two worst defects of
the round it was written in. Alias pruning was bounded on a per-device watermark
that `GET /v1/store` was asserted to return and does not; the pending-hold
mechanism relied on a revive-on-citation rule that runs on the steady-state apply
path, on behalf of a fresh-attaching device that explicitly skips it.

Both read as correct when written, and that is the point: the quantity each rule
needed obviously *existed somewhere* — on some device, in some table, on some
code path — just not anywhere the rule could see it. "Which `GET /v1/store`
already returns" is checkable against the endpoint's own definition four hundred
lines further down the same document. "The revive-on-citation rule handles it" is
checkable against the fresh-attach section that says no deletion logic runs.

So when a rule cites a quantity, name where it comes from, and check that the
path in question can actually reach it — rather than that it exists.

### A changed ruling must be propagated to every restatement

> **When a ruling changes, grep for every restatement of the old one — in the
> algorithm steps, the test list, and the ADR — before the revision is done.**

The fifth check, and the only one that is about the document rather than the
design. This document deliberately restates its key rules at the point of use,
which is right for an implementer reading one section and wrong for a reviser
changing one: the normative statement gets updated and a restatement three
hundred lines away does not, leaving two contradictory specifications of the same
mechanism with nothing to indicate which is current.

It has happened three times. The rename-collision ruling landed in the identity
section while "Renames collide too" still prescribed the opposite; the
tombstone-advertisement ruling landed in the normative section and the tests but
not in the fresh-attach algorithm; and a superseded test survived seventeen lines
above its own replacement, each asserting what the other forbids.

The repository already requires this discipline for claims about *code* — grep
for the property, not the citation. The same applies to claims about the design:
the place a stale rule survives is never where the change was made.

### Scope: check every rule the change makes load-bearing

The five checks above apply to more than the lines a revision edits.

> **Apply them to every rule the revision's changes make load-bearing, not only
> to the rules the revision rewrites.**

The provenance gate is the worked example. Its text was written when it only had
to hold for the device performing a deletion, which knows the provenance of its
own writes — no wire representation needed, and check #4 had nothing to catch.
Extending it to *applied* tombstones a round later never touched that sentence,
but it turned a local rule into a cross-device one, and from that moment the gate
read a quantity that existed only on the writing device. The defect was
introduced by a change somewhere else, and both checks were run — against the
rules that had been edited.

So the trigger for re-checking a rule is not "did I change these words" but "did
I change who has to evaluate this, or where". A rule can rot without being
touched.

### A rule belongs in the step it governs

> **A rule that governs a step of an algorithm belongs *in* that step.** Prose
> may explain it; the algorithm, the table and the test must state it. If a
> rule's only home is a section elsewhere, an implementer following the steps
> will not apply it.

The sixth check, and the one that has cost the most rounds. Three separate
findings have had this exact shape: a ruling that reached a normative paragraph
but not the section describing the same case; one that reached the normative text
and the tests but not the algorithm; and the provenance gate, which reached the
normative text but neither the merge table nor a test of the case that matters.

The checks above are all framed around rules that *changed*, which is why they
kept missing this: a rule can be brand new, correct, prominently stated — and
still absent from the one place an implementer reads. The failure is not staleness
but **placement**.

It also predicts where the damage lands. A rule stated only in prose gets applied
to the case the prose discusses and missed everywhere else, so the surviving hole
is usually the *commoner* path rather than the exotic one — the gate's prose
argued the `changed`/`changed` collision while the resurrection actually arrives
through `same`/`changed`, the bystander case, which is the mainline for any
tombstone that travels more than one hop.

### Check what a condition is composed with

> **When hardening a condition, check what it is ANDed or ORed with.** A
> guarantee that holds for one term does not hold for the compound. If another
> term can independently block or admit the outcome, it needs the same treatment
> — or the guarantee is void.

The seventh check, and the natural sequel to the sixth. That one put a rule in
the step it governs; this one asks whether the rule *decides* anything once it is
there.

The worked example is one round of this design's own history. The existence rule
was written in prose, so it was placed into the merge table — correctly — as a
**second condition ANDed with recency**. Both terms were then visible on the same
line, and the conjunction still had a hole: recency could block a download before
the hardened term was ever evaluated, so a deliberate un-delete from a
slow-clocked device was silently reverted. Hardening one term of a conjunction
hardens nothing.

The fix was not a third condition but the removal of the conjunction: existence
disagreements are decided by `existenceAt` alone, before the table. When a
guarantee needs to hold, the question to ask is not "is my term strong enough"
but **"can anything else decide this first?"** — and where the answer is yes, the
usual remedy is to separate the decisions rather than to strengthen both terms.

### Trace a new rule to every path that decides the same question

> **The checks above apply to rules a revision *introduces*, not only to rules it
> edits.** A new rule must be traced to every path that can decide the same
> question, and the trace written down.

The eighth check exists because the seven above are all phrased around a rule
that *changes* — "when a ruling changes", "when hardening a condition". A brand
new rule has no prior version to grep for and no existing condition to inspect,
so all seven pass over it in silence. The round that introduced `existenceAt`
shipped it correctly in two places and missed four others, and the round that
introduced the seventh check was the same round.

New rules are also where the *old* text is most dangerous, because prose written
for a predecessor field reads as current: a "which writes set it" enumeration
survived a field's generalisation from one direction to two, and contradicted the
rule stated thirty lines above it.

So a rule that decides something gets a table naming every path that decides it.
The worked example is the existence decision matrix, which lives with the field
it governs under **`existenceAt`, and why existence needs its own clock**.

Written as a table because the alternative is discovering the paths one review
round at a time, which is what happened.

#### A safety rationale must name the readers it claims do not exist

A related habit, from two consecutive failures of the same shape. "This value is
safe to write freely because nothing else reads it" was asserted twice here, and
both times something did: `deletedAt` was said to be "never displayed or used for
retention" while the purge sweep and the Recently Deleted countdown both read it,
and `existenceAt` was said not to be "the merge discriminator" ninety lines after
this document made it exactly the discriminator for existence.

Both were load-bearing for accepting a decision, and both were checkable in under
a minute. So **when a rationale rests on nothing reading a value, enumerate the
readers and say you checked** — the claim is a factual one about the codebase,
not a design intention, and it is the kind that stays wrong quietly.

#### A global claim needs a global enforcer

The sibling habit, and the one that has now produced the more expensive error.

> **When a safety argument says "every peer", "nowhere", or "always", identify
> what actually enforces it.** If the enforcing check runs locally — against
> local state or a local clock — then the guarantee is local, and the argument
> needs its real precondition stated or a mechanism that makes it global.

The repair path is the worked example: "safe precisely because the poisoned value
was rejected **everywhere**" rested on a threshold defined as `localNow + 24h`,
which is one receiver's opinion evaluated against one receiver's clock. Both
halves sat thirty lines apart in the same section. The retired `T₀` constraint
had the same structure — "older than every `deleted_at` **in the table**" was a
per-device check standing in for a fleet-wide property — which suggests this is a
recurring shape rather than one slip.

The tell is a quantifier in the justification that does not appear in the
mechanism. When the argument says *every* and the code says *mine*, the gap is
where the defect lives.

#### A rejected assumption survives in the fallback

> **When a mechanism is hardened because some input is untrustworthy, check every
> branch that still consumes that input — the fallback first.**

The tenth habit, and the one with the worst record here: two consecutive rounds
of repair mechanisms failed on it. A fallback is written as "the case where the
new mechanism has nothing to work with", which is precisely the phrasing under
which the old, rejected assumption slips back in — the primary path stopped
trusting the local clock and the fallback ended "`localNow` alone is used".

It is easy to miss because the fallback looks like a degenerate case rather than
a decision. It is not: it is the branch that runs exactly when the situation is
worst, and it inherits none of the reasoning that made the primary path safe. A
hardened primary with an unhardened fallback is an unhardened mechanism with
extra steps.

The companion question is what a mechanism should do when it genuinely has
nothing to work with. Minting a value from the distrusted source is one answer;
declining, staying in a stable and loud failure, and reporting is usually the
better one — a device that cannot tell what time it is should not be ordering
events, and saying so is more useful than guessing.

#### A rule's scope is its wording, not its motivating case

> **When a rule is written for a case, enumerate the other cases its own wording
> will also govern** — the empty set, the symmetric actor, the sibling branch —
> and derive the behaviour there before shipping it.

The eleventh habit, and the one that describes three findings from a single
revision:

- *"It also restamps `updatedAt`"* was written for the branch where local and
  peer state differ. The wording governs the agree-branch too, where it
  contradicted that branch's own guarantee and turned a local cleanup into a
  content push that could lose a peer's genuine edit.
- *"When every observed peer value lies outside the local window"* was written
  for a device surrounded by disagreeing peers. The wording is vacuously true of
  **zero** peers, which would condemn every solo install on no evidence.
- *"Each stamps above the greatest it observed"* was written for one repairer
  against its peers. The wording governs two repairers running at once, who
  observe the same set, compute the same value, and tie.

The failure is not sloppiness about the motivating case — each rule is correct
there. It is that a rule's scope is fixed by how it is written, and the cases it
silently acquires are the ones nobody derives. The three worth checking every
time are the **empty input**, the **symmetric actor** doing the same thing
concurrently, and the **sibling branch** the wording also reaches.

#### Reconciling two texts is not resolving the question they disagree about

> **When two statements of the same mechanism disagree, find the question neither
> answers before making them consistent.** Consistency reached by giving each
> answer its own branch hides the open question instead of closing it.

The twelfth habit, and the one that cost this design a full round. Two documents
specified different `updatedAt` restamps; the fix made them agree. But they had
drifted apart *because* an underlying question had never been answered — what
should repair do with a large local value it cannot classify? — and each text had
absorbed a different half of it. Making them consistent produced one rule
containing both halves, keyed on a condition orthogonal to the question, with a
guarantee attached to each branch that the other branch falsified.

The tell was available and unusually concrete: **two entries in the test list
demanded opposite outcomes from the same input.** Prose can disagree with itself
quietly for a long time, but a test list cannot — two tests that cannot both pass
are a decision that has not been made, written down in the one place where that
is unambiguous.

So when a fix consists of making two statements match, check whether it also
determines an answer. If the answer differs by branch, ask what distinguishes the
branches, and whether that distinction is actually the one the question turns on.
Here it was not: the branch condition was live-or-deleted agreement, and the
question was poisoned-versus-genuine, which are unrelated.

#### Check a classifier against the case where it diverges from the question

> **State the question a classifier must answer, then find a case where the
> chosen signal and the question give different answers.** If that case is
> reachable, the signal is a proxy and not a classifier.

The thirteenth habit, and the one this design has now paid for twice in
consecutive rounds. Each time the need for a classifier was correctly identified,
and each time the nearest available observable was reached for instead of the one
that answers the question:

- live-or-deleted agreement, for *poisoned versus genuine* — orthogonal;
- content-differs-from-peer, for *edited versus stale* — agrees in the common
  case and diverges exactly when the local copy is behind.

The second is the more instructive, because the signal is not merely orthogonal
but **anti-correlated on the cases that matter**: a forward-poisoned discriminator
wins every content merge, so it *manufactures* the staleness that makes
"differs" mean the opposite of what the rule assumed. A proxy that is right in
the common case and wrong in the mechanism's own motivating case is worse than an
obviously bad one, because nothing about it looks wrong when read.

The tell in both rounds came from the test list, and the failure mode is worth
separating from the twelfth habit's: there, two tests could not both pass; here,
a single test could not pass *at all* under the rule it accompanied. A test that
contradicts its own rule is a decision made twice, differently, in two places.

And the remedy both times was already present in the design: the acceptance
window for one question, the baseline for the other. **Before inventing a
classifier, look for the one the design already uses to make the same
distinction** — a mechanism that already separates "I changed this" from "I
haven't caught up" is worth more than a fresh signal that seems to.

#### A comparator's granularity is part of the classifier

> **When a classifier compares two things, check that the comparison's
> granularity matches the question.** The tell is an answer that goes *constant*
> — always-differs or always-matches — in exactly the situation the classifier
> exists for.

The fourteenth habit, and the companion to the thirteenth: that one checks
whether the *signal* answers the question, this one whether the *measurement*
can. Both are needed, and picking the right signal with the wrong granularity
fails just as completely.

The whole-blob content hash defeated two consecutive attempts at the same
comparison. Against a peer it could never report *equal*, because repair only
runs when the ordering fields differ. Against this device's own baseline it could
never report *matches*, because poisoning is a timestamp-only change and the hash
covers timestamps. One comparator, two opposite degeneracies, both invisible in
the common case and both total in the case that mattered.

A hash is especially prone to this, because its convenience hides its scope: it
is one value, cheap to compare, already computed for another purpose — and that
last part is the trap. **A value computed for one question is not automatically
the right measurement for another**, however closely the two are related.

#### A convenience must consult the principles the document already settled

> **Before smoothing an edge case, search for the principle the smoothing might
> contradict.** The tell is a new rule whose motivation is ergonomic — "don't
> fail on arithmetic", "avoid a spurious warning" — rather than derived from the
> mechanism's own invariants.

The fifteenth habit, and a failure mode this document only became large enough to
suffer from recently. A clamp was added so a repair would not fail "on arithmetic
at the last tick". It was unsound, and both halves of the argument against
it were already written down in other sections: that clamping a comparand into a
comparison manufactures ties, and that a tie in this particular comparison loses
to the tombstone. Neither had to be discovered. The new rule simply did not
consult them, because it did not feel like a decision — it felt like tidying.

That is the distinguishing quality worth watching for. A rule introduced to
*answer* something gets checked against the design; a rule introduced to *smooth*
something often does not, and a long document will not re-derive a point it has
already made when the same shape reappears three hundred lines away under a
different name.

A useful sanity check on any such rule: work out the exact conditions under which
it fires. The clamp turned out to activate only when the selected peer sat
precisely at the ceiling — which is exactly the case where clamping produces a
tie — so its entire domain was the case it broke.

#### A narrowing must be keyed on its precondition, not on an observable

> **When a rejected signal is re-admitted under a narrowing, name the
> precondition the narrowing actually requires, then enumerate every path that
> produces the narrowing's *observable* without that precondition.**

The sixteenth habit, and the deepest version of the eleventh: there a rule's
scope was fixed by its wording; here a *precondition's* scope is fixed by
whatever the implementation actually tests for.

The worked example is the local-versus-peer content comparison, rejected as a
general classifier for conflating "I edited" with "I am stale", then correctly
re-admitted in one branch where staleness cannot arise. The precondition is
**"this device has never agreed on this record"** — sound, and enough. What the
rule tested was **"there is no baseline entry"**, which is a different statement:
five paths produce a missing entry, and only one of them means never-agreed. The
upgrade path that violates it was described seventy lines below the argument
asserting it could not happen, in the same revision.

The instinct to narrow is right and worth keeping. The discipline is to write the
precondition down as a sentence about the world — not about a field — and then
ask what else can make the field look that way. A precondition tested by proxy is
a precondition that holds until someone adds a fifth way to clear a table.

#### The scaffolding gets less scrutiny than the fix

> **Apply the checks to the rules added to *support* a fix, not only to the fix
> itself.** The supporting rule is where the next defect lives, because the fix
> is what is being reasoned about and the scaffolding is what is being assumed.

The seventeenth habit, and the fifteenth at a different scale: that one separated
conveniences from answers, this one separates a load-bearing correction from the
rules introduced to make it work.

One revision produced three defects of this shape at once, none in the correction
itself. "A quarantined record is never uploaded" was added to protect the fix and
shipped without the advertise-versus-withhold analysis its sibling rule — pending
tombstones — had received in full, leaving a manifest entry pointing at a blob
nobody could fetch. A replacement diagnostic shipped claiming to need no state,
having inherited that phrase from mechanisms that genuinely need none. And a
safety branch shipped with a cost of "a pass of delay" that nobody traced — three
existing rules formed a closed cycle around it and the wait was indefinite.

Each was checkable by a habit already written down. What they had in common was
attention: the fix was the thing under examination, and these were the things
holding it up. **A rule you add without hesitation is a rule you have not
examined** — hesitation is what triggers the checks, and scaffolding rarely
produces any.

#### Follow a changed value to its readers, not to its neighbours

> **When a rule changes what a value *means*, trace that value to everything that
> reads it.** Neighbouring rules are the ones you will check anyway; the readers
> are a section away, and that is where the defect lands.

The eighteenth habit, and the fourth inverted: that one asks what data a rule
reads and whether the path can reach it, this one asks who reads what a rule
writes.

The manifest gained a second meaning in one revision — for quarantined records it
began advertising a last-agreed hash rather than the current one — and that
change was reasoned carefully against the pending-tombstone rule sitting beside
it. Its *readers* were elsewhere: the baseline-advance trigger, which would have
taken this device's own fallback echoing back as agreement; the steady-state
merge table, which had no idea quarantined records existed at all; and
referential closure, where omitting a record left the device free to publish
another that cited it. Three sections, three defects, one changed meaning.

The tell is a value that now means different things in different places. That is
sometimes correct — the pending-tombstone rule deliberately holds two hashes for
one record — but it is only correct when every reader has been told which one it
gets, and a document large enough to have distant readers will not tell them by
itself.

#### Read the tests before changing a rule

> **When a rule changes, read the tests that assert it first.** They are the
> compressed form of every prior round's conclusions, and they are where the
> previous answer is written most precisely.

The nineteenth habit, and the cheapest one here. A revision inserted a new
disposition — "adopt the peer's record wholesale" — immediately ahead of an
existing sentence giving the *same condition* the opposite outcome, leaving two
contradictory instructions in one paragraph with the old sentence's tail carried
forward unedited. Not a reasoning failure but an editing one, which is a distinct
hazard in a document this size.

Two tests already said "stays quarantined", and one of them explicitly asserted
that passes do **not** clear the record and only a local write does. Reading them
first would have surfaced the contradiction before the sentence was written,
because the test list states outcomes without the prose's room for
interpretation. It is also the fastest available check: the tests are a few
hundred lines, and they encode what every earlier round concluded.

This is the twelfth habit with a search order attached. Where that one says two
disagreeing statements mean an unanswered question, this one says where to look
for the answer that was already given.

#### An elaboration can be wrong where the decision is right

> **A clause added to scope or justify a correct rule is as capable of being
> false as the rule itself, and gets a fraction of the scrutiny.** Check a
> narrowing against the thing it claims to narrow, and a justification against
> the code it claims to describe.

The twentieth habit, and the last one produced before this document was split.
Two defects survived
into a closure audit, in one paragraph, both of this shape. The fixpoint rule was
right; the clause scoping it to FKs "with cascade or restrict semantics" named a
semantic this schema does not contain and excluded both edges the fixpoint
existed for. The venue exemption was right; the sentence explaining it asserted
that a program with a dangling `venueId` "commits fine", where the repository
throws.

In both cases the decision survived review and its supporting clause did not, and
in both cases the clause was checkable in one grep. That they appeared together,
in one paragraph, in the round that produced no other defect, is the tell: the
attention went to the rule, and the sentences around it were written as though
explaining a settled thing carried no risk.

The ADR states both points correctly, and states them in one line each. It was
right precisely where it declined to elaborate — which is not an argument for
saying less, since this document exists to be implementable, but is an argument
for treating every added clause as a claim rather than as commentary.

#### Bounds are directional

A related and simpler slip. Every bound in the quarantine mechanism —
`localNow + 24h` for both rejection and quarantine — is **one-sided and upper**.
That is correct against a clock running fast and inverts entirely against one
running slow, which the same paragraph's own motivating hardware ("a dead RTC, a
mis-set year") does about as often. When a bound guards against a value being
wrong, ask which *direction* of wrong it catches, and whether the other direction
turns the guard into its opposite.

#### Moving a rule is a revision

> **When rules are extracted, split, or restated into another document, run the
> propagation checks over every rule that moved — not only the ones reworded.**
> A rule that arrives without its convergent formulation, its limitation entry
> or its test has been dropped, even though the text it came from is unchanged.

The twenty-first habit, and the first produced after this document was split.
Extracting `sync-spec.md` relocated the whole rule set, and four rules did not
survive the move intact. The custom-field rename kept the *argument* for its
suffix — "derived from the losing UUID, not a counter" — and lost the derivation
itself, leaving a convergence rule that two conforming implementations could
implement incompatibly. The equal-`updatedAt` tie lost the merge-table row, the
limitations entry and the conformance test, all three, while the existence
section went on citing it. The unreflected-uploads report lost its "at least one
peer observed" guard while the sibling diagnostic one sentence earlier kept the
identical clause.

None of those was a changed ruling, which is why the propagation habit above did
not fire: that one is worded for a ruling that changes, and here nothing
changed. The text moved. That is precisely when a rule can arrive stripped of
the parts that made it work, because attention goes to whether the sentence
survived rather than to whether the *rule* did.

The check that catches it is to read each relocated rule against the new
document's purpose rather than against its source. Not "does this match what
`sync.md` said" — the rename suffix matched its source sentence exactly and was
still unimplementable — but "could someone build this from here, with the source
unavailable". A document meant to stand alone has to be checked alone.
