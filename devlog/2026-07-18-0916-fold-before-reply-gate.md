# Fold-before-reply is a gate, not a preference

Agents running the await-pr-review loop kept appending standalone
review-fix commits and replying with those SHAs, instead of folding
fixes into their originating commits per the Commits convention. The
root cause was in the prompts, not the agents: the skill's step 4
"Reply and resolve" essential said "reply with the fixing commit SHA"
with no fold step, restating a weaker version of the project
convention (the thing the skill's own header forbids), and the
fold-then-reply ordering existed in the conventions only as a
parenthetical justifying the commit-map design ("that reply is written
once, post-fold"), not as an operational rule.

## Decisions

- **The ordering is now an explicit gate in both layers.** The skill's
  step 4 spells out fix, fold, push, verify, reply, resolve, in that
  order, binding a multi-finding round as one unit (all folds, one
  push, verify every SHA against that final head, then all replies:
  per-finding replies let the next fold rewrite an already-cited SHA,
  while cross-round churn stays accepted as point-in-time records),
  gated on the project having a fold convention (a cross-project
  skill cannot assume force-pushing PR branches is allowed; the
  append-commit convention is the explicit other branch). Verification
  is against the pushed ref, never local state: a botched fold
  (`reset --soft` dropping unstaged edits) once shipped a "Fixed in
  SHA" reply whose commit lacked the fix. Step 6 gains the matching
  handoff blocker (no leftover autosquash subjects, `fixup!`, `squash!`,
  or `amend!`, and no standalone review-fix commits on the pushed
  branch), and the
  delegated fixer's report contract binds its SHAs to the same gate.
  The canonical Commits fold bullet and the pull-requests "Responding
  to automated review" bullet (canonical-sections.md plus the AGENTS.md
  managed blocks) state the same rule for agents that follow the
  conventions without loading the skill; the response bullet matters
  because it is the operational instruction agents act from, and
  leaving it fold-silent would keep teaching the pre-fold reply.
- **Rejected: mandating `fixup!` commits + autosquash as the fold
  mechanism** (the proposal that prompted this). It would overturn the
  recorded "mechanism (reset/amend/rebase) is your judgement" decision,
  which stands (Ben confirmed); autosquash across a merge-from-main
  branch update needs `--rebase-merges` and rewrites the merge; and it
  misses the observed failure anyway, since an agent that forgets to
  fold also forgets to create `fixup!` commits. `fixup!` + autosquash
  is named as one permitted mechanism.
- **Rejected: a mechanical "no review-fix commits in
  `origin/main..HEAD`" handoff check.** The base is not always
  `origin/main`, and "review-fix commit" is a judgment call, so a
  script would false-negative on exactly the forgot-entirely case it
  exists to catch. The checkable parts (cited SHA reachable from the
  pushed head; no `fixup!`/`squash!` leftovers) are stated as prose
  gates instead.

Review rounds two and three serialized edge cases of the
fixup!/autosquash example one per round, so the guidance was closed by
enumerating its input space once: subject prefixes (`fixup!`,
`squash!`, `amend!`), interactivity (plain `--autosquash` squashes
without `-i` only on Git 2.44+; older Git needs a no-op sequence
editor), topology (a merge in the range needs `--rebase-merges` or the
rebase silently flattens it, reproduced on a scratch repo), and base
selection (the base must precede `<target>`). Every embedded command
was executed against a scratch repo before commit. One correction to
an earlier verification claim: a candidate "`squash!` opens a message
editor" hazard did not reproduce on Git 2.50 (the squash completed
with `core.editor=false`) and was first kept out as refuted, but the
reviewer then reproduced it on Git 2.43 ("Terminal is dumb, but EDITOR
unset"), so the refutation was version-scoped, not general: the hazard
is real on the same pre-2.44 path that needs `-i`, and the fallback
now adds `-c core.editor=true` for a `squash!`-bearing range.

Revisit when: a downstream project adopts an append-fix-commits
review convention (the skill's other branch gets its first real
exercise), or agents keep missing the fold despite the gate, which
would argue for tooling (a handoff check script) over prose after all.
