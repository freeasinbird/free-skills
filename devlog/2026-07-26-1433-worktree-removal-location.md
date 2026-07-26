# Naming the worktree that `git worktree remove` runs from

merge-cleanup's worktree preflight opens by stating that cleanup is running in
the feature branch's worktree, then told the agent to `git worktree remove`
that same worktree without saying where the removal runs from. Of the four
worktree interactions the preflight touches, three refuse when the layout is
wrong; this is the one that fails open. Aimed at the caller's own worktree it
succeeds, exits 0, and deletes the working directory out from under the session
(#90).

## Decisions

- **Chose to put the location on the remedy bullet, over leaving it where
  PR #98 put it.** #98 landed the rule as a trailing sentence of the inventory
  bullet ("Run the removal from outside that worktree too"), noting it was
  "cheap to state in the same bullet as the inventory, so it went in"
  (2026-07-26-1047 note). That placement was opportunistic, not reasoned: the
  bullet an agent executes when it relocates the sequence is the first one, and
  this repo's own retrievability principle says a rule buried in a long bullet
  about something else is the first one dropped. The sentence moved rather than
  duplicated; the inventory bullet keeps its own two location rules (run the
  _script_ from outside the worktree it names, terminate the removal's path
  with `--`), which are its concern.
- **Chose to phrase the rule as leaving the worktree, over naming a directory
  to run the command from.** "From outside that worktree" leaves the agent to
  pick, and the obvious wrong pick is the worktree it is about to delete.
  Naming a directory is not enough either: a location clause constrains the
  command, and the hazard is the session's own working directory, which
  `git -C` does not move (verified). So the operative instruction is to leave,
  with the destination taken from where the relocated resync already put the
  agent.
- **Chose to fix the canonical convention too, not just merge-cleanup**
  (owner's call). The managed cleanup sentence attaches "in the primary
  checkout" to the resync alone, and merge-cleanup inherited its wording from
  there (2026-07-05 note). Fixing only the child leaves the parent re-seeding
  the defect into every downstream AGENTS.md that syncs. The canonical text
  gets the clause and a one-line consequence, no repro: canonical sections
  carry conventions, not evidence.
- **Chose to record the contrast in `§worktree-refusals`, not only in
  `§worktree-remove-destroys`.** The refusals section is where a reader goes to
  learn what git will stop; a section that lists three refusals and omits the
  neighbouring non-refusal teaches the wrong generalization. The repro stays in
  `§worktree-remove-destroys`, which already carried it, and the new paragraph
  points there.
- **Rejected automating the cross-worktree operation** (issue non-goal). The
  preflight's detect-and-guide shape stands (2026-07-02 note, round 22); this
  is a clause, not machinery.

## Verification

`git worktree remove` aimed at the caller's own worktree, git 2.50.1: exit 0,
directory gone, `pwd` still naming the deleted path, and the next git command
in that shell dying with "Unable to read current working directory". The
absolute path, `.`, and a symlink to the same worktree all behave that way, and
so does `git -C <base-worktree> worktree remove <feature>` issued from a cwd
inside the target, which is why the rule is to leave rather than to aim the
command elsewhere. The boundary: a dirty target refuses at exit 128 identically
from inside and from outside, and `--force` takes it from inside at exit 0, so
what fails open is a removal that would have succeeded anyway. Control: the
same removal run from the worktree holding the base branch leaves that caller
working, and step 4's branch delete then succeeds.

The removal itself has no machine guard, which is what makes the clause
load-bearing. `worktree-inventory.sh` does stop on `self-target` when it is
pointed at the worktree it is running in (inode comparison, so a symlinked or
differently spelled path cannot slip past), but that backstop only fires on the
script path, one bullet earlier, and the skill's own fallback for a platform
that cannot run the script is prose. `git worktree remove` is a bare git
command either way.

## Refute-first pass (destructive path)

Two independent fresh-context lenses, read-only, per the finish line's
requirement for destructive paths. Lens A walked the revised preflight as a
literal executing agent in the dedicated-worktree layout, hunting for a step
whose working directory the edit left ambiguous or contradicted, and for what
the deleted inventory sentence might no longer cover. Lens B tried to break the
"three refuse, one fails open" inventory by execution (forced and relative
spellings, subdirectories, the main worktree) and swept the repo for other
instructions that mutate a checkout without naming where they run.

Confirmed and fixed:

- **The first draft's warning was shaped like the instruction it warns
  against.** "Run from inside the worktree it names, the removal does not
  refuse" opens exactly like its sibling rules in the same list ("Run the
  script by path, from outside ..."), and a literal agent reads the fronted
  participle as the imperative, doing the one thing the clause exists to
  prevent. The participial reading is only recoverable after the comma. Both
  lenses' prose now leads with the safe action ("Leave the feature worktree
  before removing it") and never opens a sentence with the hazardous form.
- **"From that same worktree" constrained the command, not the session.**
  Nothing in the preflight tells the agent to move, so a removal spelled with
  `git -C` aimed at the base worktree satisfies the wording from a cwd inside
  the target and still strands the session (verified: exit 0, directory gone,
  the next command fatal). The text now says to leave the worktree, and says
  `-C` does not spare the caller's own directory.
- **"Does not refuse" was false as an unconditional claim**, and contradicted
  §worktree-remove-destroys two sections later, which opens by stating that
  removal _does_ refuse on modified or untracked files. Both lenses hit this
  independently. Verified: a dirty target refuses at exit 128 identically from
  inside and from outside, and `--force` removes it from inside at exit 0. The
  claim is now scoped to what is actually true: git weighs the target's
  contents, never the caller's location, so the removal fails open on the
  caller's account only.
- **The canonical text claimed exclusivity it could not support.** "The one
  step here git will not stop" is wrong: `git merge --ff-only` run from the
  feature worktree fast-forwards the feature branch at exit 0, reachable only
  out of the prescribed order but real. The claim is gone.
- **The class sweep found the instance this change missed**, in the Branches
  section of the same managed convention ("Remove the worktree once its branch
  merges"), which is where a reader looks for worktree lifecycle and which
  downstream repositories copy verbatim. It now carries the same clause, in
  both the canonical source and this repo's mirrored block.

Rejected by verification, so they are not re-raised:

- **Spellings that bypass the three refusals do not weaken the inventory.**
  `checkout --ignore-other-worktrees`, `fetch --update-head-ok`, and
  `branch -M` each defeat a refusal at exit 0, and a linked worktree at
  detached HEAD dissolves all three. None is a spelling this sequence issues,
  and the detached case does not trigger the preflight at all.
- **Duplication between the two hazard sections.** The refusals section states
  the contrast and its scope; the repro stays in §worktree-remove-destroys,
  which already carried it. The alternative, a bare pointer, would make a
  reader of the refusal list leave the page to learn that the list is not
  exhaustive, which is the misreading the section exists to prevent.

Accepted by decision:

- **The remedy still names the base branch's worktree as the place to stand,
  which has no referent when the base branch is checked out nowhere.** The
  wording routes around it ("remove it from wherever the resync left you"),
  since step 2 creates that checkout, and inventing a separate branch of the
  remedy for a layout the preflight barely reaches would cost more than it
  buys.
- **`git worktree remove` keeps no machine guard of its own.** The inventory
  script's `self-target` stop is the only executable check, and it is one
  bullet upstream.

Revisit when: an instruction in this repo has to remove a worktree the agent
cannot leave first, which is the case this clause assumes away.
