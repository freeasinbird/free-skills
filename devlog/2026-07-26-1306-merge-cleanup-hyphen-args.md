# Which input-handling layers merge-cleanup adopts

PR #83 found that untrusted names need three defences at three layers, not one
rule (`2026-07-24-2311-self-merge-resync-guards.md`): quoting for shell
metacharacters, binding for a value quoting cannot carry, and an option
terminator for git's own argument parsing. merge-cleanup carried the first and
answered the second with a stop; the third was missing entirely. #89 asked
which of the three this skill needs, with a recorded reason, and explicitly
left copying self-merge's bind-don't-paste rule as a non-goal rather than a
requirement.

## Decisions

- **Layer 2 keeps the stop; self-merge's bind is not imported** (owner's call,
  chosen against the bind option with its diff shape shown). Single-quoting
  already neutralizes `$`, `;`, and command substitution, so the residue is a
  name containing a single quote, where merge-cleanup stops and `self-merge.sh`
  binds. The asymmetry is not drift: self-merge is a script that has to run on
  whatever it resolves, while merge-cleanup's commands are templates a reader
  substitutes into. Binding there would put a capture step in front of every
  example, and would trade a rare, safe, loud stop for a shape change across
  the whole skill. The rule now states that reason rather than leaving the
  divergence unexplained.
- **Layer 3 is terminators everywhere plus one command substitution, and no
  stop at all.** Every command taking a positional remote or bare ref gets `--`
  (`ls-remote`, `push`, both fetches, the prune, `branch -d`, and the worktree
  removal), and step 2 lands on a hyphen-leading base branch with
  `git switch --no-overwrite-ignore -- '<base-branch>'`, the one place
  `git checkout` cannot spell the name.
  **This reverses a decision that shipped in the first push of #99**, where the
  same rule made such a branch a stop. The claim it rested on, that the base
  branch is _forced_ to stop because `--` means pathspec to checkout, was true
  of checkout and false of git: the automated review pointed at `git switch`,
  and the reproduction below confirms it attaches, keeps the ignored-file
  refusal identically, refuses a same-named tag instead of detaching, and
  refuses a worktree-held branch. A stop that denies cleanup for a shape git
  can still express is a defect, not a conservative default, and the head-branch
  half was already only a simplification (`git branch -d -- '-x'` works).
- **`git checkout` stays everywhere else.** `git switch` is documented as
  experimental as of git 2.50.1, and merge-cleanup's checkout recipe is shared
  wording with `skills/self-merge` and the canonical resync section, so a
  second switching command earns its place only where the first cannot express
  the name. That confines the divergence to one sentence in step 2 rather than
  reopening the switch-versus-checkout question in three texts at once.
- **Remote names get no stop.** Every command merge-cleanup points a remote at
  accepts `--`, so the terminator covers them; `self-merge.sh` rejects
  hyphen-leading remote names at its CLI boundary instead, which is a script's
  answer to an argument it parses itself, not a rule this skill needs.

## Verification findings

Reproduced in scratch repos on git 2.50.1 (Apple Git-155) before the prose was
written; the section that cites them is
`skills/merge-cleanup/references/hazards.md` §leading-hyphen-args.

- The shape is reachable despite `git branch` refusing it:
  `check-ref-format refs/heads/-x` accepts, `update-ref` creates, and
  `branch --list` then shows it like any other branch.
- `git checkout` has no safe spelling: the bare form is an unknown switch
  (exit 129), `--` makes the name a pathspec (exit 1), and the qualified form
  detaches. `HEAD` stayed on `main` through both failures, so the hazard is an
  unswitchable base, not a silent wrong switch. `checkout -b -x main` consumes
  the name as `-b`'s argument and then rejects it (exit 128).
- **`git switch --no-overwrite-ignore -- '-x'` attaches `HEAD` (exit 0).** `--`
  is end-of-options to switch, not a pathspec marker, and the flag is accepted.
  Its guards match checkout's rather than trading them away: plain
  `git switch` overwrote an ignored file the target branch had started
  tracking while the `--no-overwrite-ignore` form aborted (exit 1) with file
  and `HEAD` intact, exactly as checkout did; it refuses a same-named tag ("a
  branch is expected, got tag", exit 128) where checkout detaches; and it
  refuses a worktree-held branch (exit 128). `switch -c` still rejects the name
  (exit 128), so the missing-local-branch path fetches `refs/heads/-x` straight
  into itself, which worked and left the branch switchable.
- **`git branch -d -- '-x'` deletes (exit 0).** This corrected the working
  assumption that the local delete was unterminable like the checkout.
- With a remote named `-x`, `ls-remote`, `fetch`, and `fetch --prune` all fail
  as unknown switches (exit 129) and all three succeed with `--`.
  `git worktree remove -- -wt` removes a hyphen-named worktree.
- The terminator is behaviour-neutral for ordinary names, and the delete's
  lease still refuses stale info (exit 1) with `--` present.
- A degraded copy of `worktree-inventory.sh` without its option-shaped-path
  refusal reports `OK inventory` for such a path rather than failing: `git -C`
  takes it as a value, so the script would release a removal whose own path git
  then reads as an option. The refusal was untested before this work unit; it
  is now a matrix case (40 -> 43 assertions) that fails against that copy.

## Not swept

The canonical resync recipe
(`skills/agent-setup/references/canonical-sections.md`, and its managed twin in
this repo's AGENTS.md) passes a positional remote with no terminator. Left
alone deliberately: those names are the project's own default branch and a
remote the user configured, not values a PR supplies, so applying an
untrusted-input rule there is a separate call about a different threat model,
not this unit's class sweep. `skills/self-merge` needed no sweep; its prose and
script already terminate every positional site.

## Review findings

Confirmed and fixed:

- The leading-hyphen stop was over-broad (P2, automated review, round 1).
  `git switch` gives the base branch a safe attached switch, so the "forced
  stop" premise was wrong; the finding was reproduced here before acting, and
  the reproduction went further than the finding claimed, since switch also
  preserves the ignored-file refusal and closes the tag-detach hazard the
  checkout path needs a separate confirmation for. The stop is gone in both
  halves and the Decisions section above records the reversal.

- Both round-2 findings on the `switch` path itself, and both confirmed. The
  first: `git switch` arrived in git 2.23, so on an older git step 2 would fail
  _after_ step 1 deleted the remote branch. Availability is now probed before
  step 1, which is where this skill already puts every check whose failure
  would strand cleanup half-done. The second: the fetch-into-the-local-ref
  creation path leaves the new base branch with no upstream, where the ordinary
  `checkout -b` path configures one, and a later plain `git pull` then fails.
  Both fixed in the same push.
- **Round 4 overturned round 2's reasoning about the same rule, and the
  measurement is why.** Round 2 concluded that
  `git branch --set-upstream-to` refusing in a single-branch or sparse clone
  was "nothing to fix", since `checkout -b` leaves the branch untracked there
  too: parity with the ordinary path was the yardstick. Round 4 pointed at the
  consequence instead, and it holds. In a `--single-branch --branch main`
  clone, a bare `git pull` on the untracked base follows the clone's configured
  refspec rather than the branch: diverged, it aborts; with the branch an
  ancestor of `main`, it fast-forwards the local branch onto main's tip at exit
  0 while the remote branch stays put. An untracked base branch is a hazard,
  not a cosmetic gap, so the recipe now writes `branch.<name>.remote` and
  `.merge` directly, which works in every clone shape. Parity was the wrong
  test: the ordinary path has the same gap, which makes it a second instance to
  fix, not a licence to leave the first.
- That correction is also why the check now applies to **both** landing paths
  rather than only the hyphen one. The class is "the base branch is left
  untracked", and its other instance is `checkout -b` in a single-branch or
  sparse clone, which this PR would otherwise have walked past twice.
- The upstream finding took two rounds of measurement to confirm, and the first
  measurement said the opposite. In a single-branch clone neither path sets an
  upstream and the pull succeeds anyway, so the asymmetry vanished; in an
  ordinary clone the asymmetry is real and the pull fails with "There is no
  tracking information for the current branch". The fix is
  configuring the tracking explicitly. Round 2 shipped
  `git branch --set-upstream-to` for this and treated its refusal as benign;
  round 4 replaced it with the direct config writes for the reason recorded
  above.

- Round 3 caught an incomplete sweep of mine, not a new class: step 4's forced
  deletion appeared only as a bare `-D` flag mention, so terminating the `-d`
  command left the reader to construct the `-D` one without `--`
  (`git branch -D -x` is an unknown switch, `git branch -D -- -x` deletes).
  Fixed by showing the terminated command. The lesson for the sweep is that a
  flag named in prose is a command site too, which a grep for backticked git
  command spans (the word git followed by a space, inside backticks) does not
  catch.

- Round 5 caught the repair check reading one of the two tracking keys, so a
  half-configured pair passed it. Confirmed in both directions on 2.50.1: with
  `remote` set and `merge` absent, and with `merge` set and `remote` absent, the
  bare pull still fast-forwarded the local branch onto main's tip at exit 0. The
  check now reads both keys and writes both where either is missing, and leaves
  a complete pair alone whatever it names, since overwriting a deliberate
  upstream is a different failure.

**Five rounds, one surface.** Rounds 1, 2, 4, and 5 all landed on the
hyphen-base escape hatch added in round 1, and three of them corrected
_reasoning_ rather than an oversight (a false "forced stop" premise, parity
used in place of consequence, a one-key check for a two-key invariant). That is
the fix-begets-finding shape the #98 note names as the signal that prose has met
an execution space, and it fired here on a path where each step is a decision
about git's actual behaviour rather than a stop on one observable. The findings
were worth taking and each fix is verified, but the pattern is the durable
finding, not any single round. Filed as issue #100 rather than resolved here,
since resolving it means either making this path executable or dropping it, and
both are larger than #89's scope.

Class swept, not just the cited line: the finding's class is a rule refusing a
shape git can still express, so the other two refusals were re-examined. The
inventory script's option-shaped-path refusal stands, because
`git worktree list` reports absolute paths, making such an argument a mistyped
invocation rather than a reachable worktree (SKILL.md now says so). The layer-2
stop also stands, but on different footing: it refuses a shape that _is_
expressible, by binding, and that is the owner decision recorded above about the
skill's form, not a premise about what git can do.

Accepted by decision, against the wider reading the findings invited:

- The round-1 finding's "use `switch`, with a stop fallback for Git versions
  lacking it" would replace checkout in step 2 outright. Kept narrower: switch
  appears only where checkout cannot express the name, for the
  experimental-command and three-texts reasons in Decisions.
- No alternative path is written for a git older than 2.23; the round-2 fix
  makes that case a stop _before_ any deletion instead. The combination it
  covers (a git without `switch`, and a hyphen-leading base branch) cannot be
  reproduced or verified here, and inventing an unverified fallback for a
  destructive sequence is worse than stopping in front of it.
- The class behind the round-2 ordering finding was swept rather than patched:
  every other command the sequence runs after step 1 predates 2.23 by years
  (`checkout --no-overwrite-ignore` is the newest at 2.5), so `git switch` is
  the only availability probe this sequence needs, which SKILL.md now states
  rather than leaving the reader to wonder about the rest.

## Revisit when

- merge-cleanup ships an executable of its own. At that point the layer-2 stop
  costs nothing to replace: a script binds values as a matter of course, and
  the reason recorded above (templates, not code) stops applying.
- `git switch` loses its experimental notice, or a second hazard turns up that
  only switch's semantics avoid (the tag refusal is already one). Then the
  question is whether step 2 should switch by default in all three texts, not
  just where checkout cannot spell the name.
