# Managed Block Procedure

Use this reference at the SKILL.md init and update steps that point here. It
holds the marker format and validation rules, profile discovery, the write
check, the comparator invocation, scaffold drift rules, and the automated
reviewer record audit.

## §markers

Each canonical section is wrapped with HTML comment markers:

```markdown
<!-- agents-md:managed:KEY -->

## Section Heading

Content...

<!-- /agents-md:managed:KEY -->
```

Keys: `devlog`, `finish-line`, `context`, `communication`, `branches`,
`pull-requests`, `commits`, `done`.

The `communication` section's research basis (reading behavior, attention
limits, warning habituation, AI over-reliance) is summarized in
`references/writing-for-humans.md`. That file ships with the skill for
maintainers revising the section; it's never copied into projects.

To opt a section out of management, remove its markers. Update mode notes it as
missing and offers to re-add it, but won't force it. Opting out `done` this way
leaves the nested `project:done-checks` markers behind as plain project content;
that's expected and fine. An absent `devlog` block under Standard is that
project's profile rather than an opt-out (see Profiles).

## §marker-validation

Validate the markers before touching anything. Check every one of these:

- Every opening `<!-- agents-md:managed:KEY -->` has a matching close after
  it.
- No KEY appears twice.
- Every KEY is a known one.
- No two blocks overlap. A block that opens inside another's range crosses a
  boundary even though both keys pair correctly.
- No line merely resembles a managed marker or the nested
  `project:done-checks` marker. An indentation, case, or spacing variant, a
  mistyped or unknown key, or a marker's text carried inside a longer line is
  a malformation.
- The nested `project:done-checks` markers are either absent or exactly one
  correctly ordered pair.
- When a managed `done` block is present, that pair sits inside it. (One
  exact pair with no managed `done` block is the documented opt-out, not a
  malformation; see §markers.)

On any malformation, stop and report it; never refresh. A broken boundary
would pull project-specific text into the managed region, and the refresh
would delete it. Nothing below reads the file for meaning until its
boundaries are trusted, so this precedes the profile discovery that can
negotiate a migration with the user.

## §profile-discovery

Update step 4 reads the `Agent-setup profile:` line and applies the matching
case:

- **Recorded:** preserve it and scope the steps below to it (see Profiles for
  what Standard's absent `devlog` block means). Never switch a recorded
  profile without the user's explicit choice.
- **Absent, but a legacy setup exists** (a managed `devlog` block, a
  `devlog/` scaffold, or a session-bookend protocol): offer migration to
  Decision-log, or High-assurance when the user names mandatory change
  classes. Show the resulting managed-block and scaffold diffs before
  applying anything. On acceptance, the block and scaffold changes and the
  new profile line land through the normal steps below. On decline, change
  and record nothing; the offer recurs on the next update run. Never delete
  an existing devlog or switch the project to Standard without the user's
  explicit choice; the historical entries stay untouched either way.

  When migrating a queue-era devlog, walk the apparently open queue items
  (`## To promote` bullets, deferrals, needs-human notes without a drain
  record) once, in prose with the user. An item already resolved or promoted
  needs nothing. A still-actionable item gets an existing or new tracker
  issue linked. An only-conditionally-relevant item stays as a historical
  observation. Never automate this by parsing or mutating old entries.

- **Absent with no devlog anywhere:** treat as Standard and offer to record
  the line.

## §init-write

Init step 5 settles `docs/agent-workflow.md`, writes AGENTS.md once, and
verifies the write.

Settle the reference first: the blocks carry `§slug` pointers into it. If a
copy already exists and can't be created or refreshed to the template (step
6), say so and leave the dependent blocks out, rather than writing pointers
the project can't follow.

Then write AGENTS.md once, in the conventional section order (see below):

- Each canonical section wrapped in its markers (the `devlog` block only
  under Decision-log or High-assurance).
- Project-specific content or placeholders in place.
- The `Agent-setup profile:` line, plus the High-assurance mandatory-note
  list and any justified coordination or work-unit stage record, in an
  unmanaged section.

Verify that write before moving on. Init pastes the managed blocks by hand,
and every comparison update mode makes depends on their byte-exactness.

- Where the running agent can execute shell scripts, run the comparator
  described in §comparator. Under Decision-log or High-assurance, pass
  `--require-all` and require exit 0. Under Standard, drop the flag: the run
  must exit 0 with `missing: devlog` as its only missing line and every
  other key reporting `ok:`.
- Without shell access, make the comparator's comparison by hand: read each
  managed block's whole text back against `references/canonical-sections.md`,
  excluding the nested `project:done-checks` payload from both sides as update
  step 6 does.

A dropped or reworded sentence inside a block is exactly the drift this check
exists to catch; the project's own checks in the nested block are not drift.

## §scaffold-files

Init step 6 creates these scaffolding files:

- `devlog/README.md`: content in `references/scaffolding.md` §devlog-readme
  (Decision-log and High-assurance profiles only)
- `.github/pull_request_template.md`: content in `references/scaffolding.md` §pr-template
- `CONTRIBUTING.md`: content in `references/scaffolding.md` §contributing
- `CLAUDE.md`: content in `references/scaffolding.md` §claude-md
- `docs/agent-workflow.md`: content in `references/scaffolding.md`
  §agent-workflow (the step-local procedure the managed blocks point at by
  `§slug`; without it those pointers dangle)

For any that already exist, don't recreate them. Compare against the template
and, on drift, show the diff and offer to refresh; never overwrite silently.
This is the same rule as update-mode step 9, including its
`docs/agent-workflow.md` exception, where the pointers in the blocks make a
stale copy drift to fix rather than an offer.

Watch `devlog/README.md` especially: the managed `devlog` block points to it
as the protocol, and a stale copy contradicts a freshly-synced block.

`docs/agent-workflow.md` is the exception to "offer". The managed blocks read
it by path and `§slug` at the steps that need it, so a missing or stale copy
beside synced blocks is a dangling-pointer state: the conventions the blocks
point at are unreachable. Report it as drift and create or refresh the file
as part of the same sync, not as an optional offer. Local additions do not
exempt it, because the blocks depend on its canonical text: restore or
refresh that text and keep the project's own sections alongside it, rather
than leaving the file as it stands.

Settle that file with the blocks, never after them. Any write or refresh of a
block carrying `§slug` pointers shows this file's state next to that change,
so the project accepts or refuses both together. That covers every such write
in this skill: init step 5, update steps 6 and 8, and the reviewer-record
refresh. When the reference cannot be created or refreshed, those blocks hold
at their existing text, or stay out of a new AGENTS.md. A project that takes the
blocks anyway is left pointing at procedure it does not have, so record that
decline in the report.

An existing file that holds substantive content the template doesn't is not
drift to refresh (except `docs/agent-workflow.md` above): refreshing it would
delete material the project relies on. Report the difference and leave such a
file as it stands unless the user asks otherwise. `CONTRIBUTING.md` and the
PR template are meant to be customized, so a fuller local copy is the
project's own documentation, not drift to reduce.

`CLAUDE.md` is the one file that gets a further offer. Its template is a
five-line pointer to AGENTS.md as the single source, so any CLAUDE.md
carrying real guidance diffs as a total rewrite. For that file, offer
migrate-then-reduce: move the durable, tool-agnostic instructions into the
matching project-specific AGENTS.md sections (never into a managed block),
keep anything genuinely Claude-specific below the `@AGENTS.md` import, and
only then reduce the file toward the template. Never delete the content, and
on decline leave the file as it stands and report it.

## §comparator

Where the running agent can execute shell scripts, run this skill's
`scripts/compare-managed-blocks.sh` **from the project root**, giving it
the script's path inside the skill directory and the project's AGENTS.md
path (which defaults to `AGENTS.md`):

```sh
/path/to/agent-setup/scripts/compare-managed-blocks.sh AGENTS.md
```

The script resolves the canonical sections relative to itself, so it runs
from any working directory. The AGENTS.md argument resolves from the caller's
directory instead: run it from the skill directory and a relative project path
resolves inside the skill, not the project. It performs steps 3 and
6's mechanical parts in one deterministic pass, validating markers and
printing a per-block diff that excludes the nested block, with one
`ok:`, `drift:`, or `missing:` line per key.

A missing block is tolerated
as the documented opt-out, unless `--require-all` is passed, which turns
it into a failure. That flag fits a note-keeping profile (and init's
post-write check), not a Standard project, whose absent `devlog` block
would fail it (see Profiles). Review its diffs with the user as step 6
describes. Without shell access, follow the steps manually as written.

## §reviewer-record-audit

The managed `pull-requests` section tells agents to record a noticed
automated reviewer so a review-watch can resolve who to wait on without
re-detecting (the "record a noticed automated reviewer" convention).
During init and update, check whether the project carries such a record. It's
typically an "Automated reviewer" entry in a project-specific (unmanaged)
AGENTS.md section naming the reviewer, its login/account identity (and the
API-specific form when it differs), its trigger, and any observed status
signals.

A status signal is an in-progress or clean-pass indicator, such as a
reaction on the PR description; without a recorded clean-pass signal, a
review-watch can only time out on a reviewer that posts no review when a pass
is clean.

Treat this as **detect → report, never fabricate**. A reviewer is usually
configured after agent-setup first runs, so absence is expected and fine; do not
infer or invent one. If none is recorded, note that one should be added once a
reviewer is configured.

The record is durable project state; a managed-block sync must not delete or
rewrite it silently. If a record sits inside an `agents-md:managed:*` block,
flag it before any managed-block refresh and offer, in order:

1. Relocate the record verbatim to an unmanaged, project-specific section,
   then refresh the block.
2. If relocation is declined: refresh the block and re-insert the record
   verbatim at its prior position, flagged for later relocation.
3. If both are declined: skip refreshing that block and report the conflict.

A refresh here writes the block outside update step 6's loop, so it settles
`docs/agent-workflow.md` in the same decision when the block carries `§slug`
pointers; see §scaffold-files.
