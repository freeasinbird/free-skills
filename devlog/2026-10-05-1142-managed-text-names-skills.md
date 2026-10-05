# Name the Skills in the Managed Text

Chose to name `await-pr-review` and `visual-evidence` in the text agent-setup
writes, over describing each skill by function only. The owner decided this
on 2026-10-05, in issue #288, which carries the contract for #286 too.

This revises one decision in `2026-06-27-0047-await-review-detection.md`:
"agent-setup must NOT name the skill". That note's other decisions stand,
including the reviewer record and detection as the fallback.

## What Changed

The earlier decision assumed a skill triggers from its listing, so the
convention never needed to point at it. Session transcripts from two
downstream projects since 2026-09-03 contradict that:

- **The skill listing does not survive compaction.** Across 132 compactions
  in sessions that began with a listing, none was followed by a new one. The
  host does re-send project instructions, the agent list, and tool lists.
- **The managed text is then all an agent has.** In one session the listing
  was gone before `gh pr create`. The only guidance left in context was
  "Prefer a review-watch skill, tool, or automation".
- **A specific host rule beat the generic one.** The host's system prompt
  told the agent to use the host's PR tools and offer its monitor. The agent
  did, handed the PR back with review pending, and handled the first finding
  by hand.

The screenshot path failed the same way:

- **Compacted sessions rarely reach `visual-evidence`.** In desktop sessions
  that uploaded screenshots, 1 of 7 compacted sessions invoked the skill
  first, against 7 of 13 uncompacted ones.
- **Stuck agents search the managed text and find nothing.** Two sessions
  searched `AGENTS.md` and `docs/agent-workflow.md` for "upload" and "attach"
  at PR-body time. One gave up and left the section pending. The other fell
  back to a gh extension it found by listing extensions.
- **A body refresh broke hosted images.** One session re-sent its original
  body file, which still held local paths, and replaced every hosted URL.

The managed text is the only place a skill name can survive, so the names
go there.

## Decisions

- **Name each skill as an example, with a fallback.** The text says "such as
  `await-pr-review`" and "when one exists". A project without the skill keeps
  the earlier path: a tool or automation, then a background poll or wake-up.
  This keeps the one-way dependency the 2026-06-27 note wanted in practice: no
  instruction requires a named skill.
- **Tell the agent to look, and say why.** `## handing-off` step 1 tells the
  agent to list the available skills or look in the platform's skill
  directories, even when it recalls none. It gives the reason, because an
  agent that recalls no skill otherwise has no cause to check.
- **Say who owns the review watch.** An installed review-watch skill owns the
  watch even when the host offers its own PR or CI monitor. The owner chose
  this over the sentence #286 suggested, which said an installed skill
  outranks a host default. The narrower claim covers the incident without
  setting a general rule the text can't back.
- **Put the cue in both layers.** The core "Handing Off the PR" step 1 gets
  one sentence, because it is always in context. The reference step carries
  the procedure and the reason.

### Screenshots

- **Point at `visual-evidence` for images that already exist too.** In a
  project with its own capture tooling, every image exists by PR time. The
  pointer is accurate only once #287 lands, because the skill turned that
  case away before it. This change merges after #287.
- **Name `gh --attach` behind a gate.** The fallback names GitHub and gh
  2.99.0 or newer. gh reports its other failed gates itself, such as a token
  type it can't use. The "say what you tried and the error" rule then carries
  that message to the user.
- **Keep the image review in the fallback, with its stop rule.** The skill
  makes a review mandatory before upload and says to stop on a finding. The
  fallback says not to upload an image that shows a secret, personal data, or
  an internal host or URL, so skipping the skill is not a way around the
  review. A fresh-eyes review found that the first draft said only "check",
  with no stop rule, and an upload can't be deleted.
- **Carry one gh pitfall into the fallback.** "Attach each file once" comes
  from the skill. Without it, an agent that adds one image later attaches
  every file again, and gh appends duplicates.
- **Cue the before capture in the finish-line block.** That block is always
  in context. §pr-body is read when the body is written, after the change
  has destroyed the before state.
- **Put the live-body rule in "Keep the PR body current".** That rule prompts
  the later edit, and it is always in context. §pr-body gives the reason.
- **Ask what was tried before asking the user.** The "can't attach" sentence
  now requires the agent to say what it tried and the error it gave. Before,
  nothing asked the agent to try first. `skills/self-merge/SKILL.md` carries
  the rule in its own words, because it may run without agent-setup.

The managed blocks grow from 18,179 to 18,450 bytes of 20,000.

## Rejected Alternatives

- **Describe the skill by function only.** Rejected because the text already
  did that, and the agent in the incident still didn't look.
- **#286's precedence sentence.** Rejected by the owner, as above.
- **Leave the host question out.** Rejected because the incident turned on
  it: the agent found a host monitor and stopped looking.
- **Drop "tool, or automation" from the fallback,** as #286's suggested text
  did. Rejected because a project with no such skill should still be able to
  use the host's monitor.
- **Leave `gh --attach` out.** Rejected because a session with no skill then
  has nothing to go on. Such sessions gave up or improvised an upload.
- **Put the before-capture cue in §pr-body.** Rejected because that section
  is read too late, as above.

## Verification

No eval was added. `skills/agent-setup/evals/evals.json` tests how
agent-setup sets a project up, not how a later session follows the text it
wrote. An eval definition also can't remove the skill listing from the
session it runs in. The PR reports a cold read instead: a fresh agent given
only `AGENTS.md` and `docs/agent-workflow.md`, with no skill listing.

## Revisit When

- A host starts re-sending skill listings after compaction.
- A named skill is renamed or removed.
- gh changes `--attach` or the version that carries it.
