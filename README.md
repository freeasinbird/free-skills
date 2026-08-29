# free-skills

free-skills provides open, platform-agnostic prompt skills for AI coding
agents.

Each self-contained skill teaches an agent a task, such as reviewing code or
setting up a project. A skill lives under `skills/` and uses `SKILL.md` as its
entry point. [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[Codex](https://openai.com/index/introducing-codex/), and other compatible
agents can load and run these prompts.

## Quick Install

The [`skills` CLI](https://github.com/vercel-labs/skills) installs straight
from this repo (no clone) on macOS, Linux, and Windows:

```sh
npx skills add freeasinbird/free-skills                              # pick from the list
npx skills add freeasinbird/free-skills --skill license-philosopher  # a named skill
npx skills add freeasinbird/free-skills --skill '*'                  # every skill
```

It symlinks into your agent's skills directory; `npx skills update` keeps them
current, and `npx skills add --help` lists scope flags (`-g`, `-a`, `--copy`).
For manual setup or linking every skill from a clone, see
[Installation](#installation).

## Skills

<!-- Listed alphabetically by skill name. Insert new skills in order. -->

| Skill                                              | Description                                                                                                                                                                                                                                      |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [agent-setup](skills/agent-setup/)                 | Set up a project for agent-driven development: generates AGENTS.md with managed workflow sections, PR template, and repo scaffolding, with optional decision records (devlog) per profile                                                        |
| [await-pr-review](skills/await-pr-review/)         | Delegate an automated-review exchange to a conductor where supported, then wait for the reviewer, auto-address clear-cut findings, surface judgment calls, and converge on a severity bar that rises with the rounds                             |
| [license-philosopher](skills/license-philosopher/) | Apply the Free as in Bird licensing philosophy: suggests and adds the appropriate copyleft license (CC BY-SA 4.0, LGPL-3.0, MPL-2.0, GPL-3.0, or AGPL-3.0) based on the project type                                                             |
| [merge-cleanup](skills/merge-cleanup/)             | Run the post-merge cleanup when the user reports a PR merged: resync safely, delete the remote branch if auto-delete didn't, prune, verify close-keyword issues closed, and stop any stale review watch                                          |
| [plan-work-unit](skills/plan-work-unit/)           | Turn an assigned issue into a workable unit: complete the authoritative work-contract record and one code-grounded implementation plan, then stop before claiming or implementing it                                                             |
| [prompt-crafter](skills/prompt-crafter/)           | Write, edit, and review reusable agent prompt payloads (CLAUDE.md / AGENTS.md content, pasteable chat instructions) for Claude and ChatGPT/Codex: taxonomy-driven audits, cross-tool variant alignment, and a mechanical verification battery    |
| [self-merge](skills/self-merge/)                   | Opt-in override of the safe default: lets an agent merge its own PR and clean up, with guardrails, only when the user or project policy explicitly allows it                                                                                     |
| [visual-evidence](skills/visual-evidence/)         | Capture tight, deterministic before/after screenshots of a UI change for PR reviewers, then hand off to the gh-imgup skill to upload and attach them                                                                                             |
| [write-plainly](skills/write-plainly/)             | Write prose a busy reader understands on the first pass: lead with the point, short concrete sentences, ordinary words and contractions, direct about disagreement and uncertainty; for replies, PRs, issues, plans, reviews, handoffs, and docs |

## Installation

Install a skill by putting its `SKILL.md` directory where your agent looks for
skills:

- **Claude Code**: `~/.claude/skills/<name>/`
- **Codex**: `~/.agents/skills/<name>/`

The [quick install](#quick-install) above is the easiest path; use the methods
below for manual setup or a git-tracked local clone.

### Manual Install

Copy or symlink the skill directory into your agent's skills location. A
symlink from a clone will track upstream changes. You can instead point your
agent at `SKILL.md` and ask it to follow the file.

This example links one skill into Claude Code from a clone. Create the skills
directory first because a fresh setup may not have one:

```sh
mkdir -p ~/.claude/skills
ln -s "$PWD/skills/license-philosopher" ~/.claude/skills/license-philosopher
```

### Convenience: Link Every Skill From a Clone (macOS / Linux)

Use `link-skills.sh` if you don't want Node or prefer symlinks from a local
clone. The helper links every skill into Claude Code and Codex. It uses
`~/.claude/skills` and `~/.agents/skills`, so one `git pull` refreshes both:

```sh
git clone https://github.com/freeasinbird/free-skills.git
cd free-skills
scripts/link-skills.sh --dry-run   # preview the changes
scripts/link-skills.sh             # create the symlinks
```

Re-run it after a `git pull` that adds or removes skills. Pass `--adopt` to
replace an earlier copied install with a tracking symlink; see
`scripts/link-skills.sh --help` for all options.

## Repository Layout

```text
skills/
  <skill-name>/
    SKILL.md             # Skill prompt (required entry point)
    references/          # Supporting material (optional)
    ...
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

This work is licensed under [CC BY-SA 4.0](./LICENSE).

See [LICENSING-PHILOSOPHY.md](./LICENSING-PHILOSOPHY.md) for why we chose this license.

---

A [Free as in Bird](https://freeasinbird.com) project.
