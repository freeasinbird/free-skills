# Rewrite the merge-cleanup skill and references in plain English

Issue #165 required rewriting `skills/merge-cleanup/` (SKILL.md, hazards.md,
project-obligations.md) to the readability bar in tracker #171, with meaning
and effect unchanged. This is a destructive-path skill (git ref deletion,
tracker mutation), so preserving every guard, refusal condition, ordering
rule, and observed git fact was the hard constraint, not a nicety.

## Decisions

- **Section shape chosen per file, not templated.** Following the rule-map
  format note (`2026-08-21-1617-readability-rule-map-format.md`): SKILL.md
  gained a layered opening (what, when, a seven-step procedure) above the
  existing workflow headings, and its five-step script sequence became five
  short leads with one guard per sub-bullet. hazards.md kept its 11 sections
  and grouped the long §leading-hyphen-args and §worktree-remove-destroys
  evidence under `###` sub-headings. project-obligations.md kept its 7
  sections and turned the dense §state-machine and §failures paragraphs into
  ordered and grouped lists.
- **Lists, not tables, for §state-machine and §failures.** The implementation
  plan suggested a state/transition table and a failure/disposition table.
  Rejected: the write-attempt protocol is an ordered sequence (pre, guard
  complete, attempt, verify, recheck, post) with many conditional
  dispositions, and a fixed-column table cannot carry that ordering or the
  per-condition nuance without losing precision. Used a numbered list for the
  write order and grouped bullet lists for the conditions, preserving the
  safety-critical reread ordering verbatim in meaning.
- **No bold sentence-leads.** An early hazards.md draft used `**Lead.**`-style
  bold leads. The readability report counts a period-before-`**` as
  mid-sentence, so each lead merged into the next sentence and inflated the
  "sentences over 40 words" count. Dropped bold leads for plain front-loaded
  first sentences.
- **Retargeted every "Relied on by" citation in hazards.md.** The old lines
  cited a pre-orchestrator SKILL.md structure ("the identify section", "the
  verify section", "step 1-5") that no longer exists. Each was repointed to
  the current SKILL.md step or the script that implements the guard, confirmed
  against `merge-cleanup.sh`, `base-landing-plan.sh`, and
  `worktree-inventory.sh`.
- **§branch-d-upstream has no current consumer, and says so.** Confirmed at
  the grounding revision that `merge-cleanup.sh` deletes the local head with
  `git update-ref -d refs/heads/<branch> <oid>` (an OID lease), not
  `git branch -d`, so the `git branch -d` upstream/HEAD check this section
  documents gates no current command. Per the issue non-goal ("a hazard that
  nothing current relies on is reported ... not silently dropped or
  re-justified"), the section stays byte-stable and its "Relied on by" line
  now states this honestly (the OID-lease deletion replaces `git branch -d`;
  the section is the evidence for that choice) rather than being dropped or
  given a fabricated new consumer. §merged-not-ancestor was likewise repointed
  to the forge merge check (`mergedAt`) and the OID-lease deletions, since no
  current command runs `git branch --merged` or `-D`.

## Preservation record

No normative statement was dropped. The PR rule map places every old statement
(SKILL.md S1-S71, the hazards findings, project-obligations P0-P71) in the new
text.

Three independent mechanical checks back the claim:

- **Quoted git messages:** an identical multiset before and after in all three
  files (hazards.md 20 unique, SKILL.md 5, project-obligations.md 0).
- **Inline code spans:** every old span survives. The three bare tokens
  `--merged`, `-D`, and `ls-remote` now sit inside fuller spans
  (`git branch --merged`, `git branch -D`, `git ls-remote --heads`); the only
  added spans are the intentional retarget references.
- **Long-word survival:** every old sentence keeps at least 55% of its
  distinctive (six-plus-character) words in the new file. The only sub-78% old
  sentences are the two retargeted "identify section" citations, missing
  exactly "identify", "exception", and "confirmation".

Locked contracts held: the 11 hazards and 7 obligations `## §slug` headings
byte-identical; all 18 SKILL.md pointers; the fenced invocation block and
record template byte-identical; the Contents list byte-identical; every script
flag; the ledger line forms, exit codes, 16 JSON field names, three
`*_config_retained` values, and `RESULT complete`. The 28 evals in
`evals/README.md` still describe the rewritten text (spot-checked the
freshness and ordering evals 10, 12-16, 22, 24, 26-28).

## Refute-first findings

Per `docs/agent-workflow.md` §refute-first. The scripts are untouched, so the
old-versus-new code comparison does not apply and prose is the surface.

- **Rule map complete:** no old normative statement is unaccounted for; every
  retargeted row carries its reason.
- **Mechanical miss-detectors** (above): quoted-message multiset identical,
  code spans preserved, long-word survival clean.
- **Independent review:** a fresh-context reviewer read old versus new for all
  three files and checked the scripts. Verdict: no drops or weakenings. Every
  guard, refusal condition, ordering rule, exit code, git version, quoted
  message, and literal token survives, and each destructive-path retarget
  matches the script (the `update-ref -d` OID lease, `--force-with-lease`, the
  `mergedAt` gate, the `ls-remote` read, the HEAD-attach confirmation, the
  two-key upstream check, and `--git-common-dir`). The reread ordering in
  §state-machine and §failures is intact.
- **One citation tightened from that review.** The reviewer noted that three
  worktree/status "Relied on by" lines implied the step 2 preflight runs
  `worktree-inventory.sh`, but `merge-cleanup.sh` never invokes it: its
  preflight inlines `git status -uall --porcelain` and `worktree_scan`, then
  stops for the owner to remove a linked head worktree. The imprecision was
  inherited from the old text (which said "the worktree preflight ... runs that
  script"). Fixed and folded into the hazards commit: §worktree-remove-destroys
  now credits `worktree-inventory.sh` as the implementer, §worktree-refusals
  credits step 2's `worktree_scan`, and §status-config names the three explicit
  `-uall` readers. No guard changed.

## Rejected alternatives

- **Force every hazards section into Trigger/Check/Refusal bullets:** rejected
  because several sections (for example §merged-not-ancestor,
  §worktree-remove-destroys) document a git mechanic and its verification, not
  a clean triad; the template would distort meaning. Each section keeps a
  front-loaded mechanic statement, its evidence, and its retargeted "Relied on
  by" line.
- **Reorder §leading-hyphen-args bullets freely:** done cautiously and tracked
  per finding in the rule map, keeping cross-referencing findings adjacent
  (the case-fold group, and the "correction to the finding above" pair in
  §worktree-remove-destroys).
- **Drop §branch-d-upstream as dead code:** rejected per the issue non-goal;
  retained as evidence with an honest no-consumer note.

## Verification findings

Readability report (before to after):

- SKILL.md: max sentence 49 to 29, sentences over 40 words 2 to 0, max
  paragraph 128 to 61.
- hazards.md: max sentence 79 to 52, sentences over 40 words 18 to 9, max
  paragraph 214 to 102.
- project-obligations.md: max sentence 56 to 43, sentences over 40 words 3 to
  1, max paragraph 173 to 87.

The remaining long units are dense git evidence (hazards.md) and the
safety-critical reread protocol (project-obligations.md), consistent with the
owner's stated tolerance in the 2026-08-21 rule-map note (that pilot landed at
max paragraph 101). Green: markdownlint, prettier, check-prose-tics,
check-skill-structure, check-managed-sync, and all four `test-merge-cleanup*`
matrices.

## Revisit when

- The owner's tone pass (after merge, not part of this unit) reshapes any of
  the three files.
- `merge-cleanup.sh` changes which command deletes the local head, restoring a
  `git branch -d` consumer for §branch-d-upstream, or #171 records a different
  rule-map format.
