# merge-cleanup skill

New skill from reflection-notes candidate 1: "PR merged, please clean up"
recurred in 27 sessions across five repos, and the sequence lived in
AGENTS.md with no trigger. The skill adds the trigger plus two asks that
never landed: verifying close-keyword issues actually closed (surface,
never auto-close; consistent with the 2026-06-20 decision that rejected a
post-merge comment step, this only verifies and only when cleanup was
requested) and shutting down a stale review watch (gated; await-pr-review's
watcher has no stop mechanism and self-terminates, so the no-capability
fallback wording states that).

## Decisions

- Draft-only scope, user's call: no trigger evals, description
  optimization, or behavioral evals this session.
- self-merge left untouched; its "Merging and cleanup" section duplicates
  the resync steps. Both skills stay self-contained (installed separately).

## Refute-first pass (destructive path)

One fresh-context lens prompted to disprove safety. Confirmed and fixed:
the no-tool fallback validated branch identity instead of merge status (the
data-loss hole; now: no remote delete without merge confirmation, hand the
user the command); no default-branch tripwire (`git branch --merged` output
could resolve `<branch>` to `main`; now a hard abort); stacked-PR check was
an unmandated conditional (now an explicit `gh pr list --base` step with a
no-CLI ask-the-user fallback); squash/rebase repos dead-ended verification
and `-d` (now: forge `MERGED` is the verification there, `-D` permitted
only with `headRefOid` match); dirty-tree guard sat after a checkout that
can succeed over changes (now a `git status --porcelain` pre-check);
non-default-base PRs verified/resynced the wrong branch (now `baseRefName`
aware). Rejected by verification, don't re-raise: -d-to--D escalation
wording, force/reset on diverged default, auto-closing issues, silent
stash, deleting the checked-out branch, wrong-but-merged PR number (binds
deletion to the verified PR's own head, so annoying, not destructive).

## Review round (PR 52)

Codex round 1: two P2s, both the non-default-base class that the refute
pass's finding six patched too narrowly (step 1 retargeted stacked PRs to
the default branch instead of the merged PR's base; step 2 still checked
out the default branch, so pull and `-d` validated against a branch that
hadn't moved). Second member of a class already swept once, so the
boundary was widened: the sequence, intro, and description are now
base-branch-aware throughout, with the default branch mentioned only as
the usual case. Folded into the skill commit.

Codex round 2: one P1, remote deletion deleted whatever the ref currently
pointed at after verifying only that the old PR merged, so a branch reused
or advanced post-merge could lose unmerged work. Step 1 now requires the
`git ls-remote` OID to match the PR's `headRefOid` before the remote
delete, or stops. This partially disproves the round-zero rejected-finding
rationale "binds deletion to the verified PR's own head": that held for
the local `-d`/`-D` path, not the remote one; the rejected list stands
otherwise. Folded into the skill commit.

Codex round 3: one P2 against round 1's own fork-remote sentence, which
made `origin` stand for the head remote and so pointed merge verification
and resync at a fork's stale base branch. The identify section now splits
the roles: head remote for existence check and deletion, base remote for
verification and resync. Folded into the skill commit.

## Deferred

- Trigger-eval set + description optimization; when run, use a scratch
  `CLAUDE_CONFIG_DIR` so probes don't flood `~/.claude/projects`.
- Behavioral sandbox evals (fixture git repo) for the cleanup sequence.
- await-pr-review has no watch-stop mechanism; possible follow-up there.
