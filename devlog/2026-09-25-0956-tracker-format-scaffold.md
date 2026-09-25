# Scaffold the Tracker Format as a Verbatim Copy

Chose to ship the canonical tracker-issue format as one whole file,
`skills/agent-setup/references/tracker-format.md`, copied verbatim into a
project as `docs/tracker-format.md`, over a project pointer back to the skill
and over inlining the text in `references/scaffolding.md`.

A pointer was rejected because the readers are the project's own agents:
whoever plans a wave, plans a work unit, or runs merge cleanup there, on any
platform, with or without this skill installed. `docs/agent-workflow.md` is
copied for the same reason, and merge-cleanup reads a project's mechanics
document from the repository at the base tip, never from a skill directory.

Inlining the body in `references/scaffolding.md` was rejected because the
template nests a Mermaid fence inside a Markdown fence, which would need a
third fence level in the scaffolding file. `references/scaffolding.md`
§tracker-format names the target and the source file instead, so the drift
rule in `references/managed-blocks.md` §scaffold-files still applies (compare
whole files, offer to refresh).

The format's section headings are lowercase slugs (`## status`, `## refresh`)
like `docs/agent-workflow.md`, so a project's AGENTS.md and its post-merge
record can cite `docs/tracker-format.md §refresh` exactly.

The owner decided the tracker carries start order only, so merge-cleanup no
longer requires a **Mergeable next** field. It refreshes the fields the
project's mechanics list; a project that still records merge order keeps it a
separate field, and cleanup never adds one.

Two states the exemplar never reaches got a rule on review. A fenced unit
whose prerequisites have merged is not startable until the fence lifts, so it
never carries `startable` beside **Fenced**. When nothing is startable, the
**Startable now** bullet stays and states why in a few words; it is the one
bullet that carries an empty value, since the no-"none" rule exists to drop
optional bullets, not the required one.

A claimed unit stays startable until its PR merges, as the exemplar project's
mechanics (`docs/post-merge-tracker.md`) state. Dropping in-progress units
from **Startable now** was rejected because the tracker carries no claim
signal, so cleanup couldn't recompute the bullet from the page and the
dependency fields alone.

Revisit when a second project needs a section the shared format lacks, or
when a scaffolded copy drifts from the reference because a project edited the
rules locally rather than proposing the change here.
