# Promote the parse-safe frontmatter convention to AGENTS.md

Closes the "To promote (AGENTS.md)" item flagged in
`2026-06-26-1802-visual-evidence-skill.md`. A P1 Codex review on the
visual-evidence PR found that an unquoted (plain) folded `description`
containing a colon-then-space (`proactively: the`) fails YAML parsing, so skill
indexers silently can't load the skill. The fix there was a `>-` block scalar;
the general lesson belongs in AGENTS.md so it doesn't recur.

## Change

- AGENTS.md **Conventions**: new bullet — `SKILL.md` frontmatter must parse as
  YAML; write `description` as a `>-` block scalar (plain scalars break on a
  colon-then-space, a leading `#`, etc.). Existing plain-scalar descriptions are acceptable
  while parse-safe; converting them is welcome hardening.
- AGENTS.md **Definition of done**: the "valid `SKILL.md`" check now names
  parse-safe YAML frontmatter explicitly.

## Decisions

- **Convention, not a sweep.** The three existing skills (agent-setup,
  license-philosopher, self-merge) use plain scalars but contain no
  colon-then-space, so they parse today — grandfathered as parse-safe rather
  than force-converted in this PR. The bullet steers new skills to `>-` and
  invites conversion as optional hardening. Keeps this PR a focused docs change.
- **Separate PR off `main`.** Repo-wide policy, independent of the
  visual-evidence skill (#20) and the install-docs change (#21); the devlog
  there records the discovery, this commit promotes it ("follow-up commit
  promotes it").

## Verification

Markdownlint + prettier --check before PR. (No behavior to exercise; this is a
contributor-guide change.)
