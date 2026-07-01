# visual-evidence: canonical `npx -y` for the gh-imgup handoff

Branch `docs/gh-imgup-npx-flag`. Spun off from a gh-imgup-repo session that
canonicalized the tool's invocation on `npx -y @freeasinbird/gh-imgup …` (the
`-y` skips npx's interactive first-run prompt, which otherwise hangs a
non-interactive agent/CI).

## Change

- `skills/visual-evidence/SKILL.md` "Compose & attach" fallback previously said
  "run it with `npx`"; now names the full `npx -y @freeasinbird/gh-imgup`
  command with a one-clause reason for `-y`. This is the fallback path used only
  when the gh-imgup skill isn't loaded, so it's the one place visual-evidence
  spells the command itself.

## Notes / rejected

- Kept it platform-agnostic (invariant 2): `-y` is a plain npx flag, not a
  Claude-Code-ism. Did **not** import gh-imgup's Claude-Code allowlist guidance
  here — that lives in the gh-imgup README, and visual-evidence delegates the
  upload to the gh-imgup skill.
- Didn't drain the pre-existing `## To promote` queue — those items are
  agent-setup-learnings, unrelated to this one-line skill fix.

## Verification

- markdownlint-cli2 + prettier --check on the file: clean.
