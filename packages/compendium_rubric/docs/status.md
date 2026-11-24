# Implementation status

> Measured on September 15, 2026, from branch `rubric` after merging
> `origin/main` at `8f180a9` and applying taxonomy-v35 compatibility.
> The corpus is the 24,107-file local Caller's Box mirror described in
> [`implementation.md`](implementation.md). These numbers are a snapshot:
> re-run the corpus harness after figure, parser, or `compendium_core` changes.
>
> **Stale since the taxonomy-v40 sync.** `main` was merged again at `a5281105`
> (taxonomy v40), which changed what an omitted parameter means for eleven
> moves (v37's `courtesy_turn` and v38's ten; `arch_and_dive` among them was not
> implemented then), made `long_lines` an alias of `forward_and_back` (v39),
> added `hand_cast` as an alias of `gate` (v40), and added five moves this
> compiler then deferred (`circular_hey`, `trade_the_wave`, `starburst`,
> `hey_for_three`, `cast`), on top of many Caller's Box adapter changes. The
> figures below have not been re-measured since; see `implementation.md` §15
> for the current vocabulary.
>
> **Added since (2026-11-22):** `slice`, `butterfly_whirl` and `revolving_door`
> are built on user rulings (`taxonomy.md` has each entry). Measured on the
> same mirror against `rubric` at `eb52b309`, they took the in-scope count
> from 2,517 to 2,759 compiled, and Hudson's Seattle core set from 360 to 391,
> with no previously compiling dance lost. `arch_and_dive` and
> `contra_corners` followed, also on rulings: against `rubric` at `11b1860a`
> they took the count from 2,759 to 2,795 and the core set from 391 to 397,
> again losing nothing. The tables below count all six figures added since
> (with `circular_hey`, below) in their new rows but keep the September
> per-figure numbers.
>
> **Becket progressions (2026-11-23):** the Caller's Box bridge now places a
> Becket dance's progression on its first diagonal `chain` or `pass_through`
> along the set, and a Becket progression with no whole couple at an end is
> held until one gets there (both user-ruled). Measured against `rubric` at
> `e88bc9ce`: 2,795 to 2,843 compiled in scope (49 gained, 1 lost: *More
> Summer Haze*, whose pass through along goes to the previous neighbours), and
> the core set from 397 to 410. Holding was then extended to every formation
> (user-ruled the same day). Against `rubric` at `ee39d32f` that changed no
> dance's outcome (3,031 compiled in scope, core set 435): 21 dances that
> already mismatched gain a `heldProgressionUnfinished` warning.
>
> **Diagonal `chain` (2026-11-23)** pairs the dancers who stand on the
> diagonal rather than pairing by couple number (user-ruled). Against
> `rubric` at `64c2803e`, together with an across chain falling back to
> pairing by line when the numbers name no pair (the agent's call), it took
> the count from 3,298 to 3,352 compiled in scope (36 refused and 18
> mismatched dances now compile), and the core set from 473 to 485, with no
> previously compiling dance lost. 8 dances that refused now mismatch and 3
> that mismatched now refuse.
>
> **Your shadow is the same dancer all dance (2026-11-24)**: the first
> figure naming shadows remembers who danced together, and a later one that
> finds shadow pairs in both band phases is danced in the phase that keeps
> those pairs together, instead of being refused (user-ruled 2026-11-23).
> Against `rubric` at `bf4b4c06` it took the count from 4,064 of 5,258 to
> 4,072 of 5,257 compiled in scope (77.3% to 77.5%), losing nothing; the core
> set is unchanged at 532. 8 dances now compile, among them Shadow Boxing
> (7967) and Needle and Thread (18914), and one now reaches a deferred
> allemande and leaves the scope. Dances refused because both phases fit went
> from 36 to 18; 12 of those first meet their shadow in a diagonal "chain to
> shadow", which does not name the set.
>
> **The hands fours follow the dancers (2026-11-24)**: a figure naming
> partners who are not together in the set's current grouping is danced one
> band phase over, and the set stays grouped that way; nobody is moved to
> make a pair. An end couple with no next neighbours swings each other. Both
> are user-ruled; the limits in `taxonomy.md` ("The hands fours follow the
> dancers") are the agent's calls. Against `rubric` at `0ea6dbc8` they took
> the count from 3,962 of 5,149 to 3,973 of 5,146 compiled in scope (76.9% to
> 77.2%), and the core set from 530 to 531, losing nothing: 11 dances now
> compile, among them Prince of Hales (16691) and Bees in a Becket (7978).
> Five that were refused now run to the end and mismatch (10098, 10738,
> 14639, 15271, 7529), and three now reach a deferred figure and leave the
> scope.
>
> **A waiting couple swings on any distance swing (2026-11-24)**: the
> waiting-couple swing built for N0 below now applies to every distance set
> (N0, N2, N3, ...), on Hudson's go-ahead. Against `rubric` at `5dced3a5` it
> took the count from 4,316 to 4,318 of 5,426 compiled in scope (79.5% to
> 79.6%), core set unchanged at 556, losing nothing: Pull a Fast One (6910)
> and Swing the Next One, Too (947) now compile. Measured before the
> end-effect retry it lost Dynamic Appeal (10404) and Composition 88 (14633),
> whose top couple must cross back before the N1 swing; the retry now does
> that, with an `endEffectSwap` warning.
>
> **A pair waiting at an end trades places when a refused figure needs it
> (2026-11-24)**: when a figure refuses and names one of two dancers standing
> alone in an end row who stood out of the figure before, the compile re-runs
> from that figure with the two traded in place, and keeps the retry only if
> the whole dance compiles (`fundamentals.md` §10.7; user-ruled, partners or
> not, and a dance that runs but lands elsewhere is not retried). Against
> `rubric` at `c610d077` it took the count from 4,303 of 5,423 to 4,316 of
> 5,426 compiled in scope (79.3% to 79.5%), and the core set from 554 to 556,
> losing nothing: Jam Doodle (10513) and Some Pig (16666) are the core
> dances, and Kimberley's Here (15249), Swing to Sian (16771) and Redwood Reel
> (8077) compile through a pair that is not a couple. Trading the waiting pair
> ahead of time, whenever every active couple crossed the set, was measured at
> +10 / −687 and not built.
>
> **A waiting couple swings on an N0 swing, and "~" places a progression
> (2026-11-24)**: a couple waiting out at an end when a swing names the
> previous neighbours now swings each other and faces into the set, and when
> neither the positional nor the N2 reading compiles a dance, the last hey
> whose final pass Caller's Box marks "~" is tried as its progression (both
> user-ruled; the core import now keeps that "~" as the note "last pass
> partial"). Against `rubric` at `6e39e4e1` they took the count from 4,298 to
> 4,303 of 5,423 compiled in scope (79.3%), with the core set unchanged at 554
> and nothing lost: Haven't We Met Before? (10129), Be
> Careful What You Wish For (12608) and Reverberations (2630) compile through
> the swing, Rowdy Rendezvous (18981) and Joel and Louise 30th Anniversary
> (4343) through the "~". Two that were refused now run to the end and
> mismatch (14543, 1761).
>
> **Duple Proper starts proper (2026-11-24)**: Caller's Box's "Duple Minor -
> Proper" was read as Duple Improper, with a warning. It now has its own start,
> every lark in c0, with the 1s facing down crossed, so their first swing
> leaves them improper (user-ruled, from Heather's Hop Redux). The bridge also
> reads a swing noted "face up" or "finish proper" as finishing facing up, which
> is how several of them bring the 1s back proper (agent's call). Against
> `rubric` at `a1c3cf7b` the two took the count from 4,195 to 4,228 of 5,425
> compiled in scope (77.3% to 77.9%), with the core set unchanged at 544: 35
> dances now compile, among them Heather's Hop Redux (10172, 10173), Chorus
> Jig (3418) and Festival Jig (3793). Two that compiled no longer do: Venetia
> Burney's Planet (14847), whose neighbours along the side are the same role,
> and the triple-minor Chorus Jig (11113), which no start models. One more that
> was refused now runs to the end and mismatches (2018).
>
> **Progressed Improper starts with the 1s below the 2s (2026-11-24)**:
> Caller's Box's "Duple Minor - Progressed improper" was read as Duple
> Improper, with a warning. It now has its own start, Duple Improper with the
> 1s below the 2s in each hands four (user-ruled). Against `rubric` at
> `58b6d4e4` it took the count from 3,938 to 3,962 of 5,149 compiled in scope
> (76.5% to 76.9%), and the core set from 528 to 530: 25 dances now compile,
> among them Camden's Cap and Gown (10018) and Ice House (10035), and one that
> compiled under the Duple Improper reading, Last Train to Chester (18653), no
> longer does.
>
> **A balanced long wave and a slide is a Rory O'More (2026-11-24)**: Caller's
> Box writes a Rory O'More as "Balance long wave" then "Slide right (past N)",
> which the import reads as a wave and a slide along the set; the bridge now
> records the slide as `rory_o_more` (user-ruled 2026-11-23). Against `rubric`
> at `5e7cfac3` it took the count from 3,874 of 5,119 to 3,908 of 5,118
> compiled in scope (75.7% to 76.4%), and the core set from 519 to 521: 41
> dances now compile, among them Butterbump (10017) and Cards on the Table
> (10019), and 7 that compiled before do not, including Missing Duck (2754,
> core). Each of the 7 refuses on the Rory O'More's own geometry: a long-wave
> slide at the end of the set, or into an occupied cell. One dance (7276) left
> scope, because it now reaches a deferred across-the-set allemande.
>
> **A waiting couple chains on either diagonal (2026-11-23)**: a couple
> waiting out at an end now takes part in a diagonal chain from whichever line
> its chaining dancer stands on (user-ruled, on Ragtime Annie, 10098); a
> dancer stays put only when no couple stands on that diagonal. Against
> `rubric` at `c1f98f57` the count is unchanged at 3,874 of 5,119 compiled in
> scope (75.7%) and the core set at 519; no dance changed status, and six
> still-failing dances report different detail. Ragtime Annie itself still
> fails, at its figure 5 swing.
>
> **Allemande out of a centre long wave (2026-11-24)**: the pair of one hands
> four standing in a centre long wave turns a quarter or three quarters from
> its hold into the centre of a short wave, and the band's side dancers join
> as the ends (the agent's call, not yet ratified). Against `rubric` at
> `3e525db2`, measured on `d8b81b20` (later commits on the PR change only
> comments): 3,908 of 5,118 to 3,938 of 5,149 compiled in scope (76.5%), the
> core set from 521 to 528. 30 refused dances now compile and 1
> now mismatches; no previously compiling dance was lost. The denominator grows
> by those 31 because a dance blocked by a deferral is counted outside it.
>
> **Diagonal right and left through (2026-11-24)**: the west-line couple of
> each hands four trades with the east-line couple of the next hands four on
> the diagonal, the couple left at each end coming back in as the other
> number; a flagged trade is its own progression and spends two of the
> distance count, and the Caller's Box bridge places an unflagged Becket
> progression on it (all the agent's calls, not yet ratified). Against
> `rubric` at `24d0358f`: 3,973 of 5,146 to 4,064 of 5,258 compiled in scope
> (77.3%), the core set from 531 to 532. 91 refused dances now compile and 6
> now mismatch; no previously compiling dance was lost.
>
> **A chain after an N2 figure chains with N2 (2026-11-24)**: an across chain
> straight after a figure danced one grouping over is danced in that grouping
> too, and an allemande half turn along a side line leaves each dancer facing
> the way the turn carried them, so the robins face in after Heather's Hop
> Redux's allemande left (both user-ruled on #10172; the limits are the
> agent's calls). Against `rubric` at `064b4256`: 4,072 to 4,073 of 5,257
> compiled in scope (77.5%), the core set unchanged at 532. Rerouted to
> Tulsa (4959) now compiles; nothing else changed outcome. Heather's Hop
> Redux and its alternate still mismatch, at their final half figure eight.
>
> **A dance one column off still compiles (2026-11-24)**: a dance whose
> final state has every dancer in the expected row, with the expected number
> and in the row's expected order, but some up to one column to the side
> (ending in a wave rather than on the side lines), now compiles with an
> `endedColumnOffset` warning instead of mismatching (user-ruled 2026-11-24
> from Hudson's note on Chuck the Budgie; the number and order guards and the
> warning are the agent's calls). The Caller's Box bridge retries its
> alternative progression placement on such a near miss and prefers an exact
> match. Against `rubric` at `f628f80b`: unchanged at 4,435 of 5,590 compiled
> in scope (79.3%), the core set unchanged at 568; no corpus dance ends as
> such a near miss today. Chuck the Budgie (10345) still
> mismatches: its couples end a row out, which Hudson ruled an input issue
> (the source should record it as progressed improper).
>
> **An open chain closes with a full allemande (2026-11-24)**: where Caller's
> Box writes an open chain as a titled line over the chainers' allemande half
> and a courtesy allemande "3/4", the bridge now dances that courtesy
> allemande once around in full (Hudson's report note on Every Second Counts:
> it should be a full allemande, and the source uses quarter allemandes
> inconsistently; reading every open chain that way, and its limits, are the
> agent's calls). Against `rubric` at `cc543ed3`:
> 4,277 of 5,423 to 4,298 of 5,423 compiled in scope (79.3%), the core set
> 551 to 554, no previously compiling dance lost. Every Second Counts (10417)
> now compiles, with 20 others. The Prodigal Daughter (84) still fails, now
> refused at an allemande with the next neighbours rather than mismatching
> at the end.
>
> **A Becket dance's only slide is a progression move (2026-11-24)**: in a
> single-progression Becket dance (including one whose source states no
> tier) whose only slide or slice, counting those inside containers but not a
> Rory O'More's slide, is a `slide_along_set` or a straight slice by couple,
> the import now treats that slide as a progression move in either direction
> and wherever it falls, alongside the diagonal chain, right and left through
> and pass through along the set; the first of them progresses (Hudson's
> report note on Apogee: the slide right is the progression; applying it to
> every such dance, and those limits, are the agent's calls). Against
> `rubric` at `75e4e565` (whose corpus result matches `253f56db`'s): 4,240 of
> 5,425 to 4,277 of 5,423 compiled in scope (78.9%), the core set 547 to
> 551, no previously compiling dance lost. Apogee (10265) now compiles, with
> 36 others. Two failing dances now get further and stop at a deferred
> figure, so they leave the denominator: More New-mown Hay (3115, at a hey
> stopping mid-pass) and Salute to Dave Colestock (14148, at an
> across-the-set quarter allemande).
>
> **Refused when keeping remembered shadows would strand a couple
> (2026-11-24)**: where a remembered shadow pair stand beside each other and
> keeping them would leave dancers in the hands four unpaired who could all
> have been paired, a figure that asks for shadow pairs is now refused instead
> of falling back to first match (user-ruled 2026-11-24, for that pair with
> partners across; testing against the largest pairing, and leaving a pair
> across the set to pair as before, are the agent's calls). Against `rubric`
> at `253f56db`: 4,240 of 5,425 compiled in scope (78.2%) before and after,
> the core set unchanged at 547, and no dance changes outcome: no corpus dance
> reaches the case ruled on.
>
> **Shadows who remember each other dance together (2026-11-24)**: within a
> hands four, a figure naming shadows pairs two dancers who remember each
> other as shadows first, then the rest as before (the user's 2026-11-23
> ruling that your shadow is the same dancer all dance; pairing only a mutual
> memory is the agent's call; where the remembered pairs strand dancers it
> falls back to first match, except in the case refused in the entry above). At an end with nobody out the shadow wraps to
> the neighbour, and the first match had been taking one of a remembered
> pair. Against `rubric` at `9680f588`: 4,228 of 5,425 to 4,240 of 5,425
> compiled in scope (78.2%), the core set 544 to 547, no previously compiling
> dance lost. Now compiling: Lauren's Lagniappe (10025, 6086, 6087), Sawdust
> Liquor (10027, 6126), Chaos Pie (10338), Spare Parts (12030), Train Delay
> (14841), Head of the Bed (4528), Salute to Denice Reese (5437), Moonshadow
> (7966) and Honeyville (7969).
>
> **A diagonal chain from beside a neighbour is to a shadow (2026-11-24)**:
> each robin who stood beside a neighbour before a diagonal chain remembers
> the lark she ends beside as her shadow (user-ruled: the pairing comes from
> where the dancers stand, not from Caller's Box's "to shadow"). A shadow
> promenade across now reads each side column for its own pair, so at an end
> where the shadow wraps to the neighbour a dancer who also matches someone
> across the set no longer hides the pair beside them (agent's call). Against
> `rubric` at `fd6083a1`: 4,194 of 5,426 to 4,195 of 5,425 compiled in scope
> (77.3%), the core set unchanged at 544, no previously compiling dance lost. South
> Carolina Education Lottery (2411) now compiles. Lauren's Lagniappe (10025)
> and Sawdust Liquor (10027) get past the shadow figures and still refuse at
> the B2 partner swing, in the top hands four. One refused dance (15111) now
> reaches a deferred allemande and leaves the scope.
>
> **An arch and dive from a line of four bends it first (2026-11-24)**: "in
> a line of four, go up the hall; ones arch, twos dive" bends the line into a
> ring before the couples trade, and the Caller's Box bridge takes an arch and
> dive straight after a hall figure as the progression (both user-ruled). The
> bridge also reads a hall figure noted "backwards" as a line backing along the
> hall. The bend geometry, that reading and the progression rule's scope are
> the agent's calls. Against `rubric` at `fd3447ef`: 4,073 to 4,090 of 5,257
> compiled in scope (77.5% to 77.8%), the core set unchanged at 532, no
> previously compiling dance lost. 17 dances now compile, among them Peekaboo
> Street (14834) and Ends Turn in Contra (11511). Contra Madness (1013) still
> refuses, at its N3 swing: it needs a second progression. Three refused
> dances now mismatch (2012, 5397, 16963).
>
> **A hey after an N2 figure follows it too (2026-11-24)**: a hey straight
> after a figure danced one grouping over is danced there, like the chain
> (the agent's call, from the maintainer's notes on Haven't We Met Before?
> and Hey-ja Vu). Against `rubric` at `db0f6537`: 4,090 of 5,257 to 4,092 of
> 5,254 compiled in scope (77.9%), the core set from 532 to 533, losing none.
> Blue and Green Candles (16101) and Waylaid in Tulsa (4960) now compile, four
> refused dances now run to the end and mismatch, and three now stop at a
> deferred figure past the hey and leave the scope (945, 946, 18296).
>
> **N3 and N4 place later progressions (2026-11-23)**: on the N2 retry, a
> Double dance flags its second progression by the first N3 mention and a
> Triple its third by the first N4 (user-ruled). Against `rubric` at
> `52009f35` it took the count from 3,835 to 3,874 of 5,119 compiled in scope
> (74.9% to 75.7%), and the core set from 515 to 519, with no previously
> compiling dance lost; 30 refused and 9 mismatched dances now compile.
> Mallomars (10095) now progresses where the maintainer reads it: after the
> ones' swing and at the allemande that faces N3.
>
> **The swung couple walks into the line (2026-11-23)**: a hall figure's
> gather now walks a couple facing the other along the hall into the middle
> of that couple's row (the maintainer's choice of a positional guess, since
> the import drops the stated order). Against `rubric` at `1d5a62bd` it took
> the count from 3,779 to 3,835 of 5,119 compiled in scope (73.8% to 74.9%),
> and the core set from 512 to 515; 10095 Mallomars, which the maintainer
> flagged, now compiles. Six dances that compiled no longer do. Three were
> expected: 3475 and 13043 (Merry Dance, whose opening line wants the ones on
> the ends) and 7387 Jackson Four, which now progresses at its bend the line,
> ahead of the assumed progression. Three are not yet explained: 17577
> Topsy-Turvy and 5502 The New Flow (a hand cast follows the line) and 2109
> Penguin Quits (its bend the line leaves the twos below the ones, where the
> next figure's "[with N2]" wants them above). A line formed in one row of a
> band whose other row is still occupied is no longer collapsed as a wave (it
> crashed Garden Gate).
>
> **"Twos swing" (2026-11-23)**: the twos swing in their own row and finish
> facing up, toward the ones (user-ruled). Against `rubric` at `080d9f1c` it
> took the count from 3,761 to 3,779 of 5,119 compiled in scope (73.5% to
> 73.8%), and the core set from 511 to 512, with no previously compiling dance
> lost; 10 dances that refused now get further and mismatch.
>
> **An unstated short-wave pairing warns (2026-11-23)**: `form_short_waves`
> and `pass_the_ocean` with no stated `sides` or `center` form with whoever is
> in position and raise `unstatedPairing` instead of refusing (user-ruled).
> Against `rubric` at `dfc97ef5` it took the count from 3,729/5,122 to
> 3,761/5,119 compiled in scope (72.8% to 73.5%), and the core set from 507
> to 511, with no previously compiling dance lost; 10 dances that refused now
> get further and mismatch. The in-scope denominator fell by 3 because 159,
> 11216 and 13801 now get as far as a partial `hey`, which is an agreed
> exclusion.
>
> **N2 notes place the progression (2026-11-23)**: when the positional
> placement does not compile, the retry now also reads a figure's note, so
> "[with N2]" and "face N2" place an unflagged progression (user-ruled).
> Against `rubric` at `9c32153f` it took the count from 3,547 to 3,729
> compiled in scope (69.3% to 72.8%), and the core set from 488 to 507
> (`core-set-seattle.txt` with the core-set decisions applied). One dance that
> compiled now mismatches: 16101 Blue and Green Candles, whose first "[with
> N2]" note comes before the param reach that used to place it. Letting
> params win instead saves it but loses 85 others. The excursion skip on its
> own is net +1 (it keeps 14072 and 14858 and costs 13597).
>
> **"Ones swing" (2026-11-23)**: the ones swing in their own row and finish
> facing down, toward the twos (user-ruled). Against `rubric` at `59dfdd15`
> it took the count from 3,352 to 3,536 compiled in scope (65.6% to 69.4%),
> and the core set from 485 to 487, with no previously compiling dance lost;
> 65 dances that refused now get further and mismatch, and 15 now reach a
> deferred figure, which takes the in-scope count from 5,108 to 5,093 (on the
> old count the rate would be 69.2%). Most of the new mismatches gather the
> swung ones into the outside of a line of four, which needs a ruling. Five
> of the compiled dances write "Ones swing; face up", a facing the import
> keeps as a note, so they compile with the ruled `down`.
>
> **`circular_hey` (2026-11-23)** is built on the agent's reading of the core
> definition, not yet ruled. Against `rubric` at `5f683503` it took the count
> from 2,843 to 2,849 compiled in scope, with the core set unchanged at 410 and
> nothing lost.
>
> **`cast` (2026-11-23)** is built on Hudson's ruling for up and down casts,
> one place only. Against `rubric` at `2bf7a0e1` it compiles no new dance yet:
> 147 of the 202 dances it unblocked first stop at a `down_the_hall` led by part
> of the set (mostly "ones lead down"), which was then deferred (built since;
> see below). The count stays
> at 2,849 (the in-scope denominator grows from 4,506 to 4,539), the core set at
> 410, and nothing is lost.
>
> **`modifier` and `meanwhile` (2026-11-23)** are built on user rulings
> (`taxonomy.md`, "Containers"). Against `rubric` at `14ada564` they took the
> count from 2,849 to 3,031 compiled in scope (the denominator grew too, from
> 4,539 to 4,824, as dances these had blocked now reach a verdict), and the
> core set from 410 to 435, with no previously compiling dance lost. No
> corpus dance has two meanwhile parts moving the same dancer.
>
> **Hall figures led by part of the set (2026-11-23)** are built on Hudson's
> rulings ("ones lead down/up" and "go down/up the outside" move the set like a
> cast). Against `rubric` at `ee39d32f` they took the count from 3,031 to
> 3,116 compiled in scope (the denominator grew from 4,824 to 4,970), with the
> core set unchanged at 435 and no previously compiling dance lost. Of the 85
> new passes, 36 are triple-minor dances, which this compiler reads as Duple
> Improper (with its existing warning). Five of the 85 (two duple, three
> triple) lead past two couples in their text, which the import drops, and
> compile on a one-place reading. Five dances that refused now mismatch.
>
> **Side-opening half heys (2026-11-23)** are built on Hudson's ruling: they
> end like a centre-opening half hey, each pair exchanging. Against `rubric` at
> `f18e1b68` they took the count from 3,116 to 3,236 compiled in scope (the
> denominator grew from 4,970 to 5,104), and the core set from 435 to 458, with
> no previously compiling dance lost. All 120 new passes are duple improper or
> Becket; 17 dances that refused now mismatch.
>
> **Hall round trips (2026-11-23)** follow Hudson's ruling that a lead out
> immediately followed by a lead back moves nobody else. Against `rubric` at
> `29402576` they took the count from 3,245 to 3,253 compiled in scope (the
> denominator grew from 5,102 to 5,111), with the core set unchanged at 459
> and no previously compiling dance lost or changed.
>
> **Three Caller's Box line shapes that stayed free text (2026-11-24)** now
> import, on Hudson's rulings: `N2 Men allemande left 3/4` reads as the two
> larks allemanding with a `with N2` note (never as next neighbours), a hey
> pass list may name same-role neighbours (`SRN`), with `with hands` and a
> trailing `[with N1]` kept as notes, and `Pass the ocean (to wave of four
> (NR,WL))` reads its nested wave. The change is in `compendium_core`'s
> Caller's Box dialect. Against `rubric` at `fd3447ef` it took 232 dances out
> of the free-text group and the count from 4,073 to 4,176 compiled in scope
> (the denominator grew from 5,257 to 5,430, so the rate fell from 77.5% to
> 76.9%), and the core set from 532 to 543 (`core-set-seattle.txt` with the
> core-set decisions applied), with no previously compiling dance lost. Of the other 129, the largest group (about 25) is a same-role
> allemande across the set landing in a wave, which is deferred.
>
> **Four more Caller's Box line shapes (2026-11-24)** now import, on Hudson's
> rulings of what each means (accepting the double slice's neighbour spellings
> is the agent's call): `Hey 1/8 (WR)` is one pass by (`pass_by`, the robins by the right
> shoulder, note `1/8 hey`); `As couples, neighbor do si do` is the neighbour
> do si do with the note `as couples`; `Partner Jersey twirl` is a California
> twirl with the note `Jersey twirl`; and a double slice whose diagonals meet
> a neighbour and then the next one (`N1` then `N2`, `N2` then `N3`) is the
> diagonal-return slice, as the `S1`/`S2` spelling already was. Against
> `rubric` at `a657a6b0` it took 169 dances out of the free-text group and the
> count from 4,318 to 4,435 compiled in scope (the denominator grew from 5,426
> to 5,590, so the rate fell from 79.6% to 79.3%), and the core set from 556 to
> 568 (`core-set-seattle.txt` with the core-set decisions applied), with no
> previously compiling dance lost. Of the other 52, 32 refuse, 16 mismatch, 3
> reach unsupported figures, and one, A Rose by Another Name (519), now reaches
> a `gate` in a progressed-improper start that crashes the compiler (see
> Known crashes).
>
> **Two more Caller's Box line shapes (2026-11-24)** now import, on Hudson's
> "try it and see" (each reading is the agent's call): `Men go forward` then
> `Men bring back partner` (or `neighbor`) folds into one `give_and_take`, and
> `Men balance long wave in center` on its own line, with the wave already
> standing, is a `balance` of that role with the note `long wave in center`.
> Against `rubric` at `f628f80b`, and again at `75190a5f` with the same
> result, they took 37 dances out of the free-text
> group and the count from 4,435 to 4,460 compiled in scope (the denominator
> grew from 5,590 to 5,617, so the rate went from 79.3% to 79.4%), with the
> core set unchanged at 568 and no previously compiling dance lost. All 25
> new compiles are give and takes. The 12 new refusals are dances whose wave
> balance now imports: 9 then refuse at a same-role allemande across the set
> that lands in a wave, which is deferred, one at a diagonal hey, one at a
> wave of four and one at a swing whose pair are not partners. A role's wave
> balance straight after a `form_a_long_wave`, even across a phrase boundary,
> stays custom.

The compiler implements 53 canonical figures. Twenty-eight have no deliberately
deferred parameter values, 25 have an implemented core with explicit
deferrals, and one of the figures this table has tracked since September
remains entirely deferred (taxonomy v36 to v40 added five more, of which
`circular_hey` and `cast` are now built; see `implementation.md` §15). The
`meanwhile` and `modifier` structural containers are built too, but they are
not normal taxonomy moves and are therefore counted separately. A top-level
`sequence` container is danced as the figures it holds (`implementation.md`
§10.1), and one nested in a container is danced in order (`taxonomy.md`,
"Containers").

The current headline result is **2,035 of 3,254 in-scope dances compiled
(62.5%)**. "In scope" means the dance parsed without a custom/free-text figure
and was not stopped by a deliberately deferred move, vocabulary value, or
parameter value.

## Implementation summary

"Full parameter surface" means the accepted parameter surface contains no
deliberate `unsupportedParam` branch. It does not mean every dance containing
the figure compiles: another figure may fail, the final state may mismatch, or
the implementation may have a defect.

| Status | Count | Figures |
| --- | ---: | --- |
| **Full parameter surface** | 28 | `arch_and_dive`, `balance`, `balance_the_ring`, `box_circulate`, `box_the_gnat`, `butterfly_whirl`, `california_twirl`, `circle`, `contra_corners`, `courtesy_turn`, `facing_star`, `form_a_long_wave`, `form_long_waves`, `give_and_take`*, `pass_by`, `pass_the_ocean`, `petronella`, `revolving_door`, `roll_away`, `rory_o_more`, `slide_along_set`, `square_through`, `stand_still`, `star`, `star_through`, `turn_alone`, `turn_as_couples`, `zig_zag` |
| **Implemented with explicit deferrals** | 25 | `allemande`, `cast`, `chain`, `circular_hey`, `cross_trails`, `do_si_do`, `down_the_hall`, `figure_8`, `form_short_waves`, `gate`, `hey`, `long_lines`, `mad_robin`, `orbit`, `pass_through`, `poussette`, `promenade`, `pull_by`, `right_left_through`, `shoulder_round`, `slice`, `star_promenade`, `swing`, `two_hand_turn`, `up_the_hall` |
| **Entirely deferred canonical figures** | 1 | `dolphin_hey` |
| **Structural containers** | 3 | `meanwhile` (simultaneous figures by different dancers), `modifier` (a main figure changed by ordered modifier figures) and a nested `sequence`; none is an ordinary taxonomy move. Built 2026-11-23 |

The external vocabulary (`supportedMoves`) reports 63 supported names: the 53
canonical implementations, the three containers, and seven aliases that resolve
onto the canonical figures:

- `meltdown_swing` resolves to `swing`;
- `pull_by_dancers` and `pull_by_direction` resolve to `pull_by`;
- `see_saw` resolves to `do_si_do`;
- `swat_the_flea` resolves to `box_the_gnat`;
- `hand_cast` resolves to `gate`;
- `long_lines` resolves to `forward_and_back`, which the table above lists as
  `long_lines` because only its long-lines formation is built.

\* `give_and_take` has no deliberate parameter deferral, but it refuses a
hands four whose two takers stand on the same side of the set; see
[Known crashes](#known-crashes).

## Corpus results by implemented figure

Each dance is counted once for every canonical figure it contains. **Pass**
means the complete dance compiled to its claimed progression. **Mismatch**,
**refused**, and **crash** are also whole-dance outcomes, so those columns show
correlation rather than necessarily blaming the listed figure.

**At figure** is the directly attributable subset: the listed figure was the
first operation to refuse. Unsupported and unstructured records are excluded
from this table because the compiler never ran against them. **Pass rate** is
`pass / (pass + mismatch + refused + crash)`.

| Figure | Status | Pass | Mismatch | Refused | Crash | At figure | Pass rate |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `allemande` | Partial | 1,239 | 144 | 745 | 2 | 96 | 58.2% |
| `balance` | Full | 92 | 6 | 44 | 0 | 4 | 64.8% |
| `balance_the_ring` | Full | 403 | 22 | 146 | 0 | 0 | 70.6% |
| `box_circulate` | Full | 44 | 6 | 17 | 0 | 0 | 65.7% |
| `box_the_gnat` | Full | 165 | 18 | 71 | 0 | 15 | 65.0% |
| `california_twirl` | Full | 255 | 12 | 72 | 0 | 0 | 75.2% |
| `chain` | Partial | 995 | 85 | 504 | 2 | 0 | 62.7% |
| `circle` | Full | 1,376 | 142 | 846 | 1 | 0 | 58.2% |
| `courtesy_turn` | Full | 6 | 4 | 19 | 0 | 1 | 20.7% |
| `cross_trails` | Partial | 28 | 2 | 14 | 0 | 0 | 63.6% |
| `do_si_do` | Partial | 629 | 56 | 415 | 0 | 53 | 57.2% |
| `down_the_hall` | Partial | 146 | 23 | 147 | 0 | 14 | 46.2% |
| `facing_star` | Full | 25 | 3 | 4 | 0 | 0 | 78.1% |
| `figure_8` | Partial | 7 | 6 | 39 | 0 | 1 | 13.5% |
| `form_a_long_wave` | Full | 51 | 10 | 76 | 1 | 1 | 37.0% |
| `form_long_waves` | Full | 88 | 15 | 86 | 0 | 0 | 46.6% |
| `form_short_waves` | Partial | 151 | 16 | 210 | 1 | 62 | 39.9% |
| `gate` | Partial | 14 | 1 | 15 | 0 | 8 | 46.7% |
| `give_and_take` | Full* | 118 | 13 | 51 | 2 | 0 | 64.1% |
| `hey` | Partial | 687 | 103 | 492 | 0 | 211 | 53.6% |
| `long_lines` | Partial | 753 | 72 | 454 | 3 | 0 | 58.7% |
| `mad_robin` | Partial | 128 | 11 | 54 | 0 | 11 | 66.3% |
| `orbit` | Partial | 0 | 0 | 0 | 0 | 0 | - |
| `pass_by` | Full | 137 | 20 | 77 | 0 | 0 | 58.5% |
| `pass_the_ocean` | Full | 44 | 8 | 46 | 0 | 11 | 44.9% |
| `pass_through` | Partial | 468 | 52 | 297 | 1 | 0 | 57.2% |
| `petronella` | Full | 281 | 36 | 113 | 0 | 0 | 65.3% |
| `poussette` | Partial | 34 | 5 | 15 | 0 | 0 | 63.0% |
| `pull_by` | Partial | 112 | 20 | 96 | 1 | 7 | 48.9% |
| `right_left_through` | Partial | 384 | 47 | 252 | 0 | 76 | 56.2% |
| `roll_away` | Full | 201 | 19 | 87 | 0 | 10 | 65.5% |
| `rory_o_more` | Full | 4 | 0 | 70 | 0 | 55 | 5.4% |
| `shoulder_round` | Partial | 154 | 37 | 121 | 0 | 29 | 49.4% |
| `slide_along_set` | Full | 163 | 45 | 154 | 1 | 2 | 44.9% |
| `square_through` | Full | 114 | 16 | 53 | 1 | 6 | 62.0% |
| `stand_still` | Full | 0 | 0 | 0 | 0 | 0 | - |
| `star` | Full | 721 | 83 | 354 | 0 | 0 | 62.3% |
| `star_promenade` | Partial | 17 | 2 | 12 | 0 | 1 | 54.8% |
| `star_through` | Full | 60 | 2 | 17 | 0 | 1 | 75.9% |
| `swing` | Partial | 2,004 | 229 | 1,239 | 3 | **584** | 57.7% |
| `turn_alone` | Full | 58 | 16 | 45 | 0 | 0 | 48.7% |
| `turn_as_couples` | Full | 1 | 0 | 0 | 0 | 0 | 100.0% |
| `two_hand_turn` | Partial | 0 | 0 | 0 | 0 | 0 | - |
| `up_the_hall` | Partial | 146 | 23 | 146 | 0 | 0 | 46.3% |
| `zig_zag` | Full | 37 | 12 | 47 | 0 | 0 | 38.5% |

## Explicit deferrals inside implemented figures

### Rotation and wave landings

- `allemande`, `do_si_do`, and `shoulder_round` defer across-the-set
  quarter-turn landings, except that an `allemande` turning the centre pair
  of a centre long wave out into a short wave is built (fundamentals §8.5.7).
- `two_hand_turn`, `mad_robin`, `orbit`, and `star_promenade` defer quarter and
  three-quarter amounts entirely.

### Direction and axis

- `pass_through` and the direction-selected form of `pull_by` support the
  along/across axes only.
- `cross_trails` and `form_short_waves` support across only;
  `right_left_through` supports across and the diagonals, the diagonals only
  with no couples waiting out.
- `chain dir:along` is deferred as four-facing-four choreography.
- `promenade` supports `where: across` for side-by-side pairs only. Single-file
  promenades, stated destinations, every other `where`, and a `direction`
  stated `unspecified` are deferred. (A Caller's Box promenade that imports
  with no `where` is not a deferral: see "Entirely deferred impact".)
- Diagonal `hey` is deferred; it must agree with diagonal
  `right_left_through`, which is now built.

### Dancer sets

- `shadows` is modelled (`taxonomy.md`, "Shadows"). `secondShadows` and the
  corner sets are still refused at parse time as unmodelled vocabulary values.

### Amounts and fractions

- `poussette` and `figure_8` support half and full amounts only.
- `hey` defers mid-pass lengths and late ricochets that cannot occur at the
  stated length. A side-opening half hey is built (user-ruled 2026-11-23).

### Hall figures

- A whole-hands-four `down_the_hall` or `up_the_hall` requires `moving:all`.
- Led by part of the set (`who:ones`, `twos`, `role1s` or `role2s`; user-ruled
  2026-11-23), the leaders move one place and the dancers they pass step back
  one. They take `moving:center` or `outsides`, `facing:forward`, and the
  `none` or `turnAlone` enders; leads by `partners`, a single lead ending
  `turnCouple`, and the rest stay deferred.
- A lead out immediately followed by the same leaders' lead back is a round
  trip (user-ruled 2026-11-23): nobody else moves, and the leaders end where
  they started, or in their partner's place after a `turnCouple`. Role-set
  leaders cannot trade, so their `turnCouple` stays deferred.
- The `cozy`, `cloverleaf`, `threadNeedle`, and `rightHandHigh` enders remain
  deferred.

### Other boundaries

- `slice` supports `by: couple` with a straight or diagonal return; `by: dancer`
  and `return: none` are deferred.
- `gate` turns a fractional amount (¼, ¾, 1¼) only between a complete hands
  four and a line of four; a landing that would be a two-faced line (what a
  same-sense gate from the ring makes) stays deferred. An unstated turn is
  refused except for a bare hand cast closing a line of four, which lands as
  `bendTheLine` does. `face:along` is refused.
- `long_lines` requires `goBack:true`.
- `swing` supports side-column landings but not `where:center`.
- Couple-`who` `orbit` executes under the existing ruling, but its true
  compound `meanwhile` interaction remains unresolved. It is less strongly
  grounded than the same-role case.

## Failure hotspots

The largest directly attributable first-refusal populations are:

| Figure | First refusals |
| --- | ---: |
| `swing` | **584** |
| `hey` | **211** |
| `allemande` | **96** |
| `right_left_through` | **76** |
| `form_short_waves` | **62** |
| `rory_o_more` | **55** |
| `do_si_do` | **53** |

`swing` is the largest genuine gap in the active denominator. Most of its
refusals are `whoMismatch`: the named relationship does not match the dancers
physically standing in swing position.

The largest mismatch associations are `swing` 229, `allemande` 144, `circle`
142, `hey` 103, `chain` 85, `star` 83, and `long_lines` 72. These are
not causally attributed. A mismatch is detected only after the entire dance
runs.

## Entirely deferred impact

"Dances mentioning it" includes dances already blocked elsewhere or rejected
as unstructured. "First unsupported blocker" is the direct coverage
opportunity.

| Deferred surface | Dances mentioning it | First unsupported blocker |
| --- | ---: | ---: |
| `dolphin_hey` | 0 | 0 |

`promenade` left this table when its `across` form was built, and
`butterfly_whirl`, `slice`, `revolving_door`, `arch_and_dive` and
`contra_corners` when they were (2026-11-22), and `meanwhile` when it was
(2026-11-23).
On the Caller's Box mirror, 98 more dances hold a promenade that imports with no `where`
(whole-set, counter-rotating, around-a-dancer and mixer promenades). They are
reported as `unstructured`, an import-pipeline problem, not as a deferral.

## Overall corpus state

| Outcome | Count |
| --- | ---: |
| Compiled | 2,035 |
| Final-state mismatch | 241 |
| Figure refused | 1,259 |
| Compiler crashed | 3 |
| Unsupported before compilation | 1,430 |
| Custom/free-text figure present | 6,531 |
| No figures supplied | 9,017 |
| Adapter failed | 3,591 |
| **Total** | **24,107** |

- **In-scope success:** 2,035 / 3,254, **62.5%**.
- **All-attempted success:** 2,035 / 3,538, **57.5%**.
- **Deferred exclusions:** 1,714 dances.
- The in-scope rate is a conservative floor. A genuine early refusal may hide
  a later deferred figure, leaving the dance in the denominator.
- The upstream source ceiling remains material: 6,531 records contain at least
  one figure left as `custom`. Standing policy rejects the whole dance rather
  than compiling around unknown choreography.

## Known crashes

The tables and headline above were measured before the changes below, so they
still count three crashes.

Three dances escape the operation error channel, all with `Bad state: Cell
collision at (r0,c0): L-D and R-B` at a figure the bridge assumed to be the
progression: *Men at Work* (14689) and *Morland Magic* (14692) at a
`box_the_gnat`, and *A Rose by Another Name* (519), a progressed-improper
dance, at a `gate`. Measured on the Caller's Box mirror on 2026-11-24: the
first two already crashed against `rubric` at `a657a6b0`, and 519 reaches the
compiler since its `Hey 1/8 (WR)` imports. None is investigated yet.

*Gypsy for Chris & Sara* (9779) used to collide at `r0,c2`. It opens with a
slide left, which leaves a couple standing out in each end row, and
`form_a_long_wave` stepped the standing-out dancers into the centre too. The
next settle does not cover those rows, so the other role's step-in landed on
them. `form_a_long_wave` now steps in only the dancers of active hands fours,
as `fundamentals.md` §10.3.2 already required of every figure. Measured on the
Caller's Box mirror against `rubric` at `f18e1b68`: the dance now refuses at
its later allemande, 9 dances that refused or mismatched now compile (1 in the
core set: *Toward Your Partner*), and none is lost.

*The Digital Divide* (12771) and *Road to Rochester* (4292) used to collide at
`r0,c0` inside `give_and_take`: both takers of one hands four stood on the same
side of the set, so each slid along that column into the cell the other's
taken partner was entering. `give_and_take` now refuses that state as an
`unresolvableDancerSet` before moving anyone. *(Proposed as the agent's call on
2026-11-22; user-ruled 2026-11-23: a refusal rather than a crash.)* Measured in a local corpus
sweep on 2026-11-22: both dances now end `FIGUREREFUSED` at their
`give_and_take`. The evidence so far points at an earlier wrong position rather
than at the permutation: both dances progress mid-dance (*The Digital Divide*
repeats its 64 beats with N2; *Road to Rochester* walks forward to N2 in A1),
the importer places the progression on a late figure, and a step trace of *The
Digital Divide* shows that after the N2 swing the original band phase is handed
back, so its first hands four holds two 2s couples when the second
`give_and_take` runs. Neither dance is checked in as a regression case, because the
committed Caller's Box corpus is deliberately one dance.

## Coverage blind spots

- `orbit`, `stand_still`, and `two_hand_turn` have no compiler-attempted corpus
  dances.
- `orbit` appears in four source records, but none reaches compilation: one is
  unsupported and three are unstructured. (September figures. Since
  2026-11-23 an orbit inside a `meanwhile` is compiled, as in *Binary System*
  (Caller's Box #10296), so this no longer holds; not re-counted.)
- `turn_as_couples` has one attempted example, so its nominal 100% rate is not
  meaningful.
- `rory_o_more` is now recognized in 74 attempted dances. Only four compile;
  its 55 direct refusals are a newly visible implementation hotspot. (Since
  2026-11-23 a Rory O'More danced from the side lines first forms the wave its
  slide implies, *user-ruled*. Measured on the Caller's Box mirror against
  `rubric` at `29402576`, together with the figure no longer sliding a couple
  standing out (§10.3.2): 45 dances that refused now compile (14 in the core
  set), 2 that refused now mismatch (*Mistletoe*, 15972, and *Mongoose
  Stomp*, 18142, both with the progression assumed at a later figure), and
  none is lost. The table above is not re-counted.)

## Validation and refresh

At this snapshot:

- `fvm dart analyze` is clean;
- `fvm dart test` passes **1,019 tests**, with one skipped corpus test.

The headline corpus report can be refreshed with:

```powershell
fvm dart run bin\callersbox_harness.dart --quiet $env:RUBRIC_TCB_CORPUS
```

Add `--report <dir>` (and optionally `--core-ids <file>`) to also write a
failure report: each failing dance traced figure by figure, mismatches
classified, failures grouped by cause, and a page to browse them in
(`docs/implementation.md`, the harness paragraph in §12).

The per-figure table uses the same `DanceRun` results, canonicalizes aliases
through `compendium_core`'s contra taxonomy, and counts each dance once for
each canonical figure it contains. It additionally parses the first
`figureRefused` result to populate the **At figure** attribution column.
