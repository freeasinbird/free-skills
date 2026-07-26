# Guarding the canonical resync, the last unsafe copy

The canonical merge recipe told every downstream project seeded from it to
resync with `git checkout main && git pull --ff-only`. Three hazards in that
line were reproduced during #74, which hardened `self-merge` on that
evidence; the canonical text (and this repo's mirrored `pull-requests`
managed block) was the last place still recommending it. #82 asked for the
call: harden, or record why it stays.

## Decisions

- **Chose hardening the recipe over recording why the short form stays**
  (owner's call, offered as an explicit option). The brevity argument that
  kept the short form is real, but it was made when the ignored-file
  overwrite was an unverified refinement. It is now reproduced, and the
  repo's own `merge-cleanup` documents the command as data-losing, so
  canonical text that seeds downstream agents can't keep recommending it.
- **Chose prose over a fenced command block** (owner's call). The guarded
  sequence is three commands and fits inline in backticks, the managed
  blocks are otherwise homogeneous prose, and a fence would be a larger
  structural change to a block that lands verbatim in every downstream
  AGENTS.md.
- **Chose splitting the one paragraph into three over compressing the
  hazards to fit one.** `check-skill-structure.sh` caps a plain-prose
  paragraph at 15 lines and the merged paragraph would run ~19. The split
  falls on the natural seams (merge and cleanup steps, the guarded resync,
  the worktree case), so no hazard had to be dropped to fit a ceiling.
- **Chose acting on the tag-detach hazard over only naming it** (reversed
  under review, see below). The recipe now fetches first, then splits on
  `git show-ref --verify --quiet refs/heads/main`: checkout the local branch
  when it exists, `checkout -b main FETCH_HEAD` when it doesn't. Fetching
  first is what keeps that two-line, rather than importing
  `merge-cleanup`'s explicit tracking-ref refspec: `FETCH_HEAD` is already
  the branch tip the create needs.

## Decisions this revises

- `devlog/2026-07-05-1041-worktree-merge-cleanup.md` kept the fix
  self-contained per recipe and put "remote-scoped prune / ignored-file
  safety" out of scope as richer refinements belonging to `merge-cleanup`.
  What changed: the ignored-file overwrite stopped being a refinement when
  it was reproduced. The self-contained half of that decision **stands**:
  this change still doesn't point downstream at `merge-cleanup`, because a
  project seeded from the canonical text may not install it.
- `devlog/2026-07-24-2311-self-merge-resync-guards.md` deferred this
  instance to a separate work unit because a managed-block edit propagates
  to every downstream project that syncs it. That deferral is discharged
  here; its "compare the two texts for drift, not merge them" boundary is
  kept (see Revisit when).

## Rejected

- **Pointing at `merge-cleanup` or `self-merge` instead of restating the
  guards.** Downstream projects get the canonical prose without the skills.
- **Porting `merge-cleanup`'s full sequence** (explicit
  `refs/heads/<base>:refs/remotes/<remote>/<base>` refspec into the tracking
  ref, post-checkout `symbolic-ref` confirmation, dirty-tree probe). Correct,
  but it is a 30-line recipe; the canonical text is a handoff paragraph. Its
  `show-ref` probe is the one piece that came across, and only because the
  review showed the recipe was incomplete without it.
- **Recording the short form as deliberate.** Would leave the repo shipping
  one recipe it documents as unsafe and one hardened against it.

## Verification findings

Every claim the new text makes was executed against scratch repos rather
than argued from the prior notes, on git 2.50.1 (Apple Git-155). The harness
was written to falsify each claim, and two of its checks changed the result:

- **Confirmed**: plain `pull --ff-only` overwrites an ignored file the base
  has started tracking (workspace `.env` reported clean by
  `status --porcelain` beforehand); `git pull` rejects
  `--no-overwrite-ignore`; `git merge` accepts it and aborts, leaving the
  branch unmoved rather than partially applied; a plain `git checkout`
  clobbers the same file while `checkout --no-overwrite-ignore` aborts and
  stays put; a bare checkout with no local branch and a same-named tag
  detaches `HEAD` at the tag, not at the moved `origin/main`; a bare pull in
  a fork clone follows the fork's stale copy while the named remote plus
  `refs/heads/main` refspec reaches the repository that moved.
- **Corrected by verification**: the first harness asserted the aborted
  merge left `HEAD` equal to `origin/main`. It doesn't: `fetch` updates the
  tracking ref opportunistically, so the correct assertion is against the
  pre-merge `HEAD`. The abort behavior held; the test's expectation was
  wrong.
- **Changed the recipe's wording**: a bare `main` refspec was expected to be
  merely unqualified. Against a remote holding both a branch and a tag named
  `main`, `git fetch origin main` wrote the **tag** to `FETCH_HEAD`. That is
  why the text says `git fetch <remote> refs/heads/main` and not
  `git fetch <remote> main`; without the qualification the guarded form
  would fast-forward to a tag and report success.

Checks: markdownlint, prettier, prose-tics, skill-structure (the three-way
split clears the 15-line ceiling), and managed-sync (the canonical block and
the `AGENTS.md` mirror are byte-identical) all clean.

## Review dispositions

- **Accepted (P2, Codex): a warning is not a guard.** The first draft named
  the tag-detach hazard but still handed the agent a command that detaches
  under it; `--no-overwrite-ignore` governs ignored files, not branch
  selection. The reasoning that had ruled the else-branch out (the primary
  checkout always has a local `main`) was an assumption the text asserted
  and then declined to enforce, which is the weaker half of "explicit over
  implicit". Reversed: the branch-existence split is now in the recipe, at
  a cost of two lines because the reordered fetch supplies `FETCH_HEAD`.
- **Verified, not assumed**, by running the revised sequence against the
  flagged case: with no local `main` and a same-named tag it lands on
  `refs/heads/main` holding the moved base tip, and the ordinary,
  ignored-file, and fork-clone cases still behave as before. Incidental
  finding: with a same-named tag present, `git symbolic-ref --short HEAD`
  disambiguates to `heads/main`, so a caller that string-compares against
  `main` to confirm it is on the branch gets a false negative. The recipe
  doesn't do that; `merge-cleanup`'s post-checkout confirmation uses
  `symbolic-ref -q HEAD` (unabbreviated), so it is unaffected.

## Revisit when

The canonical recipe and `self-merge`'s `cleanup-sequence.md` disagree about
a guard. They are deliberately separate texts at different lengths, so
compare them for drift rather than merging them; the shared claims (the
three hazards and the command shapes above) are the part that must not
diverge.
