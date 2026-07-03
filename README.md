# free-skills

Open, platform-agnostic prompt skills for AI coding agents.

Skills are self-contained prompt instructions that teach an agent how to
perform a specific task: reviewing code, setting up a project, running a
deploy checklist, etc. Each skill is a directory under `skills/` with a
`SKILL.md` entry point that any compatible agent can load and execute. They
work with [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[Codex](https://openai.com/index/introducing-codex/), and other agents that
load `SKILL.md` prompts.

## Quick install

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

| Skill                                              | Description                                                                                                                                                                                                                                   |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [agent-setup](skills/agent-setup/)                 | Set up a project for agent-driven development: generates AGENTS.md with managed workflow sections, devlog, PR template, and repo scaffolding                                                                                                  |
| [await-pr-review](skills/await-pr-review/)         | Wait (non-blocking where supported) for an automated PR reviewer such as Codex, then auto-address clear-cut findings and surface judgment calls, converging without nitpicking                                                                |
| [license-philosopher](skills/license-philosopher/) | Apply the Free as in Bird licensing philosophy: suggests and adds the appropriate copyleft license (CC BY-SA 4.0, LGPL-3.0, MPL-2.0, GPL-3.0, or AGPL-3.0) based on the project type                                                          |
| [prompt-crafter](skills/prompt-crafter/)           | Write, edit, and review reusable agent prompt payloads (CLAUDE.md / AGENTS.md content, pasteable chat instructions) for Claude and ChatGPT/Codex: taxonomy-driven audits, cross-tool variant alignment, and a mechanical verification battery |
| [self-merge](skills/self-merge/)                   | Opt-in override of the safe default: lets an agent merge its own PR and clean up, with guardrails, only when the user or project policy explicitly allows it                                                                                  |
| [visual-evidence](skills/visual-evidence/)         | Capture tight, deterministic before/after screenshots of a UI change for PR reviewers, then hand off to the gh-imgup skill to upload and attach them                                                                                          |

## Installation

A skill is just a `SKILL.md` directory, so installing one means putting it
where your agent looks for skills:

- **Claude Code**: `~/.claude/skills/<name>/`
- **Codex**: `~/.agents/skills/<name>/`

The [quick install](#quick-install) above is the easiest path; use the methods
below for manual setup or a git-tracked local clone.

### Manual install

Place the skill yourself: copy or symlink its directory into the agent's
skills location (symlink it from a clone if you want it to track upstream),
or point your agent at the skill's `SKILL.md` and ask it to follow it. For
example, to symlink one skill into Claude Code from a clone (the skills
directory may not exist yet on a fresh setup, so create it first):

```sh
mkdir -p ~/.claude/skills
ln -s "$PWD/skills/license-philosopher" ~/.claude/skills/license-philosopher
```

### Convenience: link every skill from a clone (macOS / Linux)

If you'd rather not use Node, or you keep a local clone and prefer
git-tracked symlinks, the `link-skills.sh` helper installs all skills into
both Claude Code and Codex from a clone and keeps them current. It symlinks
every skill into `~/.claude/skills` and `~/.agents/skills`, so a single
`git pull` refreshes them all:

```sh
git clone https://github.com/freeasinbird/free-skills.git
cd free-skills
scripts/link-skills.sh --dry-run   # preview the changes
scripts/link-skills.sh             # create the symlinks
```

Re-run it after a `git pull` that adds or removes skills. Pass `--adopt` to
replace an earlier copied install with a tracking symlink; see
`scripts/link-skills.sh --help` for all options.

## Repository layout

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
