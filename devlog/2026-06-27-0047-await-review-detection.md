# await-pr-review: record reviewer identity so the skill can wait on it

Started from "should agent-setup manage whether await-pr-review is on by
default?" Converged to a smaller contract: **a repo records its automated
reviewer with enough identity to match the reviewer's future reviews, and the
skill resolves the reviewer from that record first, detection only as fallback.**

## Decisions (with user)

- **No toggle.** The skill already self-gates (no reviewer → don't engage); a
  config knob duplicates that gate.
- **agent-setup must NOT name the skill.** Canonical sections propagate into
  arbitrary downstream AGENTS.md run by arbitrary agents (invariant #2). The
  dependency is one-way: skill → convention, never convention → skill.
- **Record identity, never absence.** The record carries the fields needed to
  match future reviews — name, login/account identity (incl. the API-specific
  form, e.g. REST `[bot]` suffix), and trigger — and lives in unmanaged,
  project-specific AGENTS.md content so agent-setup syncs don't erase it. Two
  senses of "presence" got conflated early: never-record-absence (kept) vs
  record-a-bare-boolean (wrong, a boolean can't be matched on). Recording
  absence is the dangerous one — a stale "none" silently skips a reviewer added
  later; a stale "present" only costs a capped wait.
- **Detection is the fallback, not the architecture.** Recorded identity first;
  else scan recent PRs for a bot-authored review (learns the login); if >1 bot,
  ask; human assertion counts only if it names the reviewer enough to match. A
  detected login is not a complete reviewer config until the trigger is also
  known, derived, or requested.

## Codex review (dogfooded — the skill watched its own PR)

Six rounds, all the **same underspecified contract** (identity to match on):

1. Multi-bot: "a bot review = the reviewer" can latch onto the wrong bot, then
   step 3's login filter rejects the real one. Guarded: >1 bot → ask, don't pick.
2. Record the login, not bare presence — the fast path matches on it.
3. Human assertion must include identity/login too, else step 3 can't filter.
4. Put durable reviewer records outside managed blocks, or agent-setup update
   mode can remove the local record it is supposed to preserve.
5. Detection learns who reviewed but not necessarily what triggers a fresh
   review; derive/ask for the trigger before waiting out a doomed poll.
6. Audit ordering + preservation: the new reviewer-record audit sat at
   update-mode step 8, _after_ step 3 refreshes managed blocks — so a record
   misplaced inside a managed block would be deleted by an accepted refresh
   before the audit could flag it. Fixed: the location guard now runs as update
   step 3, before any managed-block refresh, and relocation is an explicit
   offer to move the record verbatim; if declined, skip that managed-block
   refresh and report the conflict. The step-9 audit only checks presence.

Lesson: I committed before the contract was crisp and patched reactively across
rounds. The narrowing (record enough identity; detect as fallback) is the fix.

## Split out: watch-by-default

Round 1 also surfaced that I _ask permission_ to run the watch (the finish-line
"guidance, not mandated automation" hedge + the skill's "want the agent to
watch" framing license it). Making the watch the default is real but it is
**workflow policy, separate from reviewer identity** — moved to its own
follow-up PR (stacked on this branch) so this PR holds one contract.

## Rejected

Per-repo toggle; init-time detect-and-record; recording absence; a fire-on-open
hook; folding watch-by-default into this PR.

## Verification

Markdownlint clean; prettier --check clean; managed record bullet
diff-identical across canonical + AGENTS.md; watch-activity unchanged from main;
SKILL.md frontmatter a parse-safe `>-` block scalar.
