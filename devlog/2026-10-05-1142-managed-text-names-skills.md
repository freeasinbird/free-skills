# Name the Skills in the Managed Text

Chose to name `await-pr-review` in the text agent-setup writes, over
describing a review-watch skill by function only. The owner decided this on
2026-10-05, in issue #288, which carries the contract for #286 too.

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

The managed text is the only place a skill name can survive, so the name
goes there.

## Decisions

- **Name the skill as an example, with a fallback.** The text says "such as
  `await-pr-review`" and "when one exists". A project without the skill keeps
  the earlier path: a tool or automation, then a background poll or wake-up.
  This keeps the one-way dependency the 2026-06-27 note wanted in practice: no
  instruction requires the named skill.
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

## Rejected Alternatives

- **Describe the skill by function only.** Rejected because the text already
  did that, and the agent in the incident still didn't look.
- **#286's precedence sentence.** Rejected by the owner, as above.
- **Leave the host question out.** Rejected because the incident turned on
  it: the agent found a host monitor and stopped looking.
- **Drop "tool, or automation" from the fallback,** as #286's suggested text
  did. Rejected because a project with no such skill should still be able to
  use the host's monitor.

## Verification

No eval was added. `skills/agent-setup/evals/evals.json` tests how
agent-setup sets a project up, not how a later session follows the text it
wrote. An eval definition also can't remove the skill listing from the
session it runs in. The PR reports a cold read instead: a fresh agent given
only `AGENTS.md` and `docs/agent-workflow.md`, with no skill listing.

## Revisit When

- A host starts re-sending skill listings after compaction.
- A named skill is renamed or removed.
