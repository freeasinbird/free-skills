# Document `npx skills add` as the recommended install path

The README's only convenience installer was `scripts/link-skills.sh` (clone +
symlink all, macOS/Linux). The `skills` CLI (vercel-labs/skills) — the same
ecosystem installer the gh-imgup skill documents — is a better default:
no clone, cross-platform (incl. Windows), per-skill or `--all`, symlink by
default, and `skills update` to stay current.

## Change

- README Installation restructured into three subsections:
  1. **Quick install (recommended)** — `npx skills add freeasinbird/free-skills`
     (`--skill <name>` / `--all`), with the `--copy` / `-a` / `-g` flags noted.
  2. **Manual install** — the existing copy/symlink + `ln -s` example, retitled.
  3. **Convenience: link every skill from a clone** — `link-skills.sh`, kept but
     reframed as the no-Node / git-tracked-clone fallback.

## Decisions

- **Primary + keep the script (owner's call).** `npx skills add … --all` largely
  supersedes link-skills.sh (all skills, both agents, stay-current) and is
  cross-platform, so it leads. link-skills.sh stays for the no-Node / local-clone
  niche rather than being retired — lowest-risk, nothing removed.
- **Verified before documenting.** `npx skills add freeasinbird/free-skills
--list` cloned the default branch and found the 3 skills; `--skill <name>`
  installs one. Flags (`--copy`, `-a '*'`, `-g`, `update`) confirmed via
  `skills --help`.
- **Default-branch caveat stated.** `skills add` reads the default branch, so a
  skill is installable this way only after it merges to `main` — noted in the
  README (visual-evidence won't appear until PR #20 lands).

## Scope

Docs-only; preserves the markdown-only project identity (no installer built —
`skills` is an existing third-party tool). Separate from the visual-evidence
work (PR #20) and the gh-imgup delineation (its own repo PR).
