# Verification and red runs

Load this chapter before any red-run that mutates the working tree, and when
deciding what a new guard test should be falsified against.

## Prove a new guard test can fail

Run it against the unfixed code and watch it go red before making it green. A
test can be structurally incapable of failing and still read as rigorous — one
surrogate-pair test was both backwards *and* unreachable (its fixture exceeded a
regex's length cap, so the code under test never ran), and still passed review.

## Choose the right thing to falsify against

"Does it fail if I undo my work?" is the wrong question; ask **"what mutation
would this test catch?"**

- For a *regression* guard, reverting the fix is the right target — but make
  sure the revert still **builds**. A revert that fails to compile proves
  nothing, and will happen if the fix and the helpers it needs are in one
  commit. Split commits so the revert target is buildable.
- For a guard on a hazard introduced by *new* behaviour, revert is the wrong
  target: the old code cannot exercise the hazard at all, so the test goes red
  for an incidental reason. Instead **mutate out the guard** — implement the
  naive version a future simplification would produce — and confirm the test
  catches that.

## Never `git stash` in a worktree

All worktrees of a repository share **one stash stack** — `refs/stash` lives in
the common git directory (`git rev-parse --git-common-dir`), not the per-worktree
one. A `git stash push` in one worktree is visible to, and poppable by, every
other, so a stash/pop pair that looks local is not.

This has caused a real near-miss: a `git stash push -- <path>` on an
already-committed file was a silent no-op, and the paired `pop` therefore popped
an entry belonging to a different worktree.

For red-run verification, restore from a ref instead — it is scoped to the
worktree and cannot touch anyone else's state.

### Commit before you mutate, and restore from *that commit* — not `HEAD`

The rule above names the mechanism (a ref, not the stash) but not the referent,
and the referent is where it bites. `git checkout HEAD -- <path>` **discards
uncommitted work**: if the change under test has not been committed yet, `HEAD`
is the state *before* it, so the "restore" wipes the file instead of removing the
mutation. The command succeeds, prints nothing, and leaves a tree that still
compiles — so the next test run reports on code that is no longer the change.

This has happened, mid-red-run, on work that was otherwise complying with the
rule. What caught it was `git status` showing the file no longer modified; a
rule fully complied with that still permits the damage is a defective rule, not
a user error.

So: **commit the change first, then mutate, then restore from that commit's
SHA.**

```sh
git commit -m "..."               # the change under test now has a SHA
# ...apply the mutation, run the test, watch it go red...
git checkout <that-sha> -- <path> # removes the mutation, keeps the change
```

Verify the restore rather than assuming it: `grep` for the mutation marker and
confirm the file still contains the change, because "the mutation is gone" and
"the change is still there" are different facts and only the first is obvious.

## Do not use line-window greps to ask whether a declaration contains something

`ParamSpec` and `MoveDef` declarations span lines, so `grep -A3` under-reports
and a non-greedy regex can run past a short declaration and capture a later
one's field. The same question answered three ways gave 0, 5, and (walking
balanced parens) the truth. Walk the delimiters.

## Run the gates locally before pushing

```sh
python3 tools/preflight.py
```

One entry point for the gates CI runs, including
`packages/compendium_core/tool/check_fixture_validity.dart`, which `dart test`
does **not** run over the real suites — an invalid figure param renders
literally and every test still passes, so a drifted fixture is invisible
locally. See [incidents.md](incidents.md#747-drifted-figure-fixtures-were-invisible-to-dart-test).
