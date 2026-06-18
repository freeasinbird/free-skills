# License philosopher skill

## What landed

- New `license-philosopher` skill that applies the Free as in Bird
  licensing philosophy to a repository — analyzes the project type,
  suggests the appropriate copyleft license, and adds LICENSE,
  LICENSING-PHILOSOPHY.md, and a README license section.

## Decisions

- **Suggest, don't decide.** The skill presents its analysis and all
  four options, letting the user pick. The agent's classification is a
  recommendation, not a determination.
- **Check existing license first.** Existing license informs the
  suggestion and triggers a confirmation flow before replacement.
  Non-supported licenses short-circuit the operation (philosophy file
  would be incoherent with the actual license).
- **LGPL uses LICENSE + LICENSE.LESSER.** Following the FSF convention
  of separate files rather than a combined LICENSE. README links to
  both since they form the complete license.
- **Fetch with bundled fallback.** License text fetched from GitHub API
  (`gh api /licenses/<spdx-id>`), with bundled copies as fallback.
- **LICENSING-PHILOSOPHY.md is always verbatim.** Not tailored per
  repo — the philosophy applies universally.
- **No README creation.** If no README exists, the skill notes it to
  the user rather than creating one just for the license section.

## Deferred

- Automated testing of license classification accuracy (subagent
  permission issues blocked independent eval runs this session).
