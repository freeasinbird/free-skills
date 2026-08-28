# Rewrite self-merge guidance in plain English

Issue #166 required rewriting `skills/self-merge/SKILL.md` and
`references/cleanup-sequence.md` to the readability bar in tracker #171.
Meaning and behavior had to stay unchanged. This is a destructive path because
cleanup can rewrite a checkout and delete a remote branch, so preserving every
guard, stop, and ordering rule was the hard constraint.

## Decisions

- **Layer the skill around a seven-step procedure.** The opening now states
  what self-merge does, when it applies, and what the agent does from
  authorization through reporting. Detailed script behavior stays below the
  invocation block. This removes the old 143-word phase paragraph without
  duplicating the full prose specification.
- **Keep the reference's seven numbered steps.** The rewrite adds short
  subsections inside the steps. It doesn't move a rule across the destructive
  sequence. Consumer checks, queue checks, workspace checks, worktree checks,
  landing, resync, remote deletion, and local preservation remain ordered.
- **Use lists for remote identity.** A component table would hide qualifiers
  about order, transport, userinfo, path case, local paths, and forge checks.
  Grouped lists keep one rule per unit while preserving the distinctions.
- **Keep exact literals as anchors.** The frontmatter, invocation block, exit
  table, flags, phase names, result tokens, commands, config keys, refs, git
  version, and every old inline code span remain byte-identical where they
  appear. Plain prose around them carries the rewrite.

## Preservation Record

The PR rule map accounts for every old normative statement. No statement is
marked `dropped`.

Mechanical checks support that map:

- **Locked blocks:** the frontmatter, fenced invocation, and five-row exit
  table compare byte-for-byte with `origin/main`.
- **Inline spans:** the old multiset has no missing entry in either file.
- **Required structure:** all seven numbered reference steps remain in order.
  Every script flag and locked result token still appears.
- **Scripts:** `skills/self-merge/self-merge.sh` and
  `scripts/test-self-merge.sh` have no diff from `origin/main`.
- **Long-word survival:** the reference has no old sentence below the 55
  percent signal. Four skill sentences fall below it because the rewrite
  splits or simplifies them. Manual review confirmed the same rules remain:
  the git-only limitation, the unclear-permission stop, the PR-files
  self-review, and the reversible low-blast-radius gate.
- **Canonical drift:** the tag-shadowing guard, ignored-file protection, and
  fork-upstream protection still agree with `docs/agent-workflow.md`
  §merge-and-resync. The direct-ref lookup, guarded checkout, post-landing
  remote check, explicit fetch, and guarded fast-forward keep the same shapes.

## Refute-First Findings

Per `docs/agent-workflow.md` §refute-first, a fresh-context reviewer compared
both old and new files and tried to find weakened destructive-path rules.

- **Confirmed and fixed:** the short cleanup summary placed the fork-network
  keep decision after remote deletion. The detailed reference kept the safe
  order. The summary now decides to keep a fork branch before any delete.
- **Confirmed and fixed:** the hidden-file section kept the inventory rules
  but lost the fact that worktree removal can destroy an
  `assume-unchanged` or `skip-worktree` file and still exit 0. That fact is
  restored beside the inventory lead.
- **Disproved:** the rewrite dropped or changed a locked block, inline code
  span, numbered step, script file, or shared resync guard. Byte comparisons,
  the span check, file diffs, and an old-versus-new read all rejected the
  concern.

The scripts are unchanged, so the behavior-comparison instruction for code
refactors doesn't apply. The prose and its rule map are the changed trust
surface.

## Rejected Alternatives

- **Merge the reference with the canonical resync recipe:** rejected because
  the two texts serve different scopes. The reference specifies the full
  self-merge cleanup. The canonical recipe must stand alone in projects that
  don't install this skill. Only their shared hazards and command shapes need
  to agree.
- **Compress remote identity into one table:** rejected because several rules
  depend on sequence or scheme-specific exceptions. A compact table would
  make those conditions harder to audit.
- **Change the script while rewriting its prose:** rejected because issue #166
  is behavior-preserving. The existing regression matrix tests the script;
  this unit changes only the guidance around it.

## Verification Findings

Readability report, before to after:

- `SKILL.md`: 1,466 to 1,376 words; max sentence 61 to 23; sentences over 40
  words 7 to 0; max paragraph 143 to 57.
- `cleanup-sequence.md`: 3,028 to 2,948 words; max sentence 73 to 26;
  sentences over 40 words 22 to 0; max paragraph 503 to 57.

The final verification set is recorded in the PR. It includes markdown lint,
formatting, prose tics, skill structure, managed sync, the self-merge matrix,
commit-message checks, the locked-content checks, and the full diff review.

## Revisit When

- The owner's later tone pass changes either file.
- `self-merge.sh` changes a guard, result, flag, or cleanup order.
- The canonical merge-and-resync recipe changes one of the shared hazards or
  command shapes.
- Tracker #171 adopts another rule-map format.
