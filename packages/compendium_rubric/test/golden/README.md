# Golden end-to-end fixtures

Each `*.json` file here is a full **compile request** plus its expected outcome — a
hand-verified reference dance used to guard the compiler end-to-end.

Two kinds of fixture live here, and the difference matters when reading them:

- **Curated fixtures** carry the hand-verified expectation blocks described below. They are
  hand-built references, and the compiler is expected to reproduce them exactly.
- **Imported records** are real dances exported from the ContraDB / Caller's Box corpora,
  verbatim apart from the corrections noted per dance. They carry no expectation block; what
  they assert is asserted in `golden_dances_test.dart`. Their value is precisely that nobody
  wrote them with this compiler in mind.

## Fixture format

| Field | Meaning |
|---|---|
| `name` / `description` | human label + summary |
| `formation` | input formation type (e.g. `duple_improper`) |
| `success` | success criterion (e.g. `{ "criterion": "progression", "count": 1 }`) |
| `operations` | the ordered op list (same JSON as a live request; `progression` is a top-level op field) |
| `expectedResult` | `Compiled` \| `Mismatch` \| `Error` |
| `expected.decimal` | expected final matrix (authoritative — bitmask decimals, `0` = empty) |
| `expected.rolesNotation` | human-readable rendering of the same state |
| `trace` | per-op intermediate states (reference/debugging) |
| `sourceCorrections` | any typos fixed from the originally-submitted input |

## Curated fixtures

- **`the_baby_rose.json`** — a valid single-progression Duple Improper dance
  (swing · circle · do_si_do · swing · chain · star+progression) ⇒ **Compiled**.
- **`the_judge.json`** — a valid single-progression **Becket CW** dance, "The Judge"
  (circle · swing · right_left_through · chain(left_diagonal) · petronella · petronella+progression · swing)
  ⇒ **Compiled**. Regression-guards the corrected progression model: a progression-flagged
  figure runs the **default DI-style** end-normalization even for Becket, and the remaining
  figures place dancers back onto their Becket sides.

## Imported records

Paired fixtures — `*_upstream.json` alongside a curated twin — exist where the imported record
differs from a compilable dance by exactly one editorial judgement, so that the judgement itself
is under test rather than assumed.

| Fixture | What it is here to prove |
|---|---|
| `the_baby_rose_upstream.json` | The record with none of the hand-added params the curated twin carries. Reaching the same state proves the parser's **defaults** match the taxonomy's. |
| `sleepless_at_pinewoods.json` | The dance that settled the **reaching model**: a grand right and left out to the fourth neighbours and back. Sizes to **five** hands four. |
| `sleepless_at_pinewoods_upstream.json` | The same record verbatim — it flags **no** progression, so it is refused up front (`unperformedProgression`) rather than run and blamed. |
| `beckys_brouhaha.json` | First worked example of `prevNeighbors` — a set reached *against* the direction of travel. Two stray A1 progression flags removed as a notation artifact. |
| `jet_lag.json` | The same reach, but it *swings* the previous neighbours, so the resolution has a visible effect rather than only a pass/refuse one. |
| `airpants.json` | The dance that caught the missing **Flexible-facing** contract (circle → pass through), and the worked example for the **absolute** reading of the distance sets. Sizes to **two**, not three. |
| `the_nice_combination.json` | Carried a stray A1 `progression` flag against a single-progression criterion; removed, as in Becky's. With it restored the dance **runs and lands one grouping along** — a Mismatch, not a refusal. |
| `poetry_in_motion.json` | Compiles to a single progression. The imported record carried `turn: 1.25` on the A2 `allemande`, a **notation fault in the source** — user-ruled to `1.5`. Sizes to **three**: its A2 names `nextNeighbors` before anything has progressed, so the reach is real. |
| `march_for_andrea.json` | **Becket + a distance set**, and the corpus's one **data** fault. Two edits, both curated: the B1 `california_twirl` is marked as the progression (the record flags nothing), and the `roll_away` that read `who: nextNeighbors` — actor context, no positional effect, leaving `whom` on its `partners` default — is corrected to `who: role1s, whom: nextNeighbors`. It then compiles. Sizes to **two**: the set is named *after* the progression, so under the absolute reading the gap is already closed. |
| `harmony_supper_line.json`, `cinnamon_rolls.json`, `a_crafty_wave.json`, `heartbeat_contra.json`, `frederick_contra.json`, `mirror_mirror.json` | Imported records that compile unaltered. Between them they exercise the figure registry outside the deferred list, on choreography written by people who had never heard of this compiler. |
| `united_we_dance.json` | The **long-wave** half of the `rory_o_more` evidence: dancers facing *across* the hall slide toward their own sides, which carries them *along* the set (ranks trade within each hands four) rather than across it. Its two slides are inverses, and the slide the wave cannot take is refused rather than silently held. |
| `united_we_dance_upstream.json` | The same record with the source's own `"shape": "other"`, which this compiler does not model. It is **warned about and read as Duple Improper**, not refused, and reaches the same state as the curated twin — which is what makes the fallback a reading rather than a guess. |
| `apples_and_caramel.json` | The **short-wave** half, and the first golden that **ends standing in a wave** -- its last figure is a quarter-turn `do_si_do` to short waves. The success comparison settles wave offsets (`architecture.md` §3.5), so the dance compiles while the reported end state is still the wave it left people in. |