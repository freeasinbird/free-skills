---
name: license-philosopher
description: >-
  Apply the Free as in Bird licensing philosophy to a repository: selecting
  and adding the appropriate copyleft license (CC BY-SA 4.0, LGPL-3.0, MPL-2.0,
  GPL-3.0, or AGPL-3.0) based on the type of work. Use this skill when the
  user asks to "add a license", "set up licensing", "apply the licensing
  philosophy", "add LICENSING-PHILOSOPHY.md", "choose a license for this
  project", or wants to license a project under a copyleft license matched
  to whether it's a knowledge artifact, library, application, or network
  service. Also use when the user mentions "Free as in Bird licensing" or
  asks about which copyleft license fits their project type.
---

# License Philosopher

Apply the Free as in Bird licensing philosophy to a repository. The
philosophy matches the license to the type of work: knowledge stays
free, and what you build with it is yours. This skill adds three things:

1. A `LICENSE` file with the full text of the appropriate license
2. A `LICENSING-PHILOSOPHY.md` explaining why this license was chosen
3. A license section in the README linking to both

## License selection criteria

Analyze the repository to understand what type of work it is. The
license follows from the project type:

| Project type                 | License      | SPDX identifier | Signals                                                                                                             |
| ---------------------------- | ------------ | --------------- | ------------------------------------------------------------------------------------------------------------------- |
| Knowledge artifacts          | CC BY-SA 4.0 | `cc-by-sa-4.0`  | Mostly markdown, prompts, documentation, patterns, agent skills, templates, educational content                     |
| Libraries (dynamic-link)     | LGPL-3.0     | `lgpl-3.0`      | Imported as a dependency in a dynamic-link or import-based ecosystem (Python, JVM, C/C++); relinking is satisfiable |
| Libraries (static-link)      | MPL-2.0      | `mpl-2.0`       | Imported as a dependency where static linking or bundling is the norm (Rust, Go, bundled JavaScript, mobile SDKs)   |
| Local applications and tools | GPL-3.0      | `gpl-3.0`       | CLI entry point, desktop app, local tool; users download and run it on their machine                                |
| Network services             | AGPL-3.0     | `agpl-3.0`      | Server entry point, HTTP routes, WebSocket handlers, deployed and accessed over a network                           |

For libraries, the rule is to use the strongest weak-copyleft license the
target ecosystem can actually honor. LGPL-3.0 is the default, but its
relinking obligation is unworkable where static linking or bundling is the
norm (Rust, Go, bundled JavaScript, mobile SDKs), and an unenforceable
copyleft protects nothing. There, MPL-2.0 is the strongest weak copyleft that
actually functions. Default to LGPL-3.0; override to MPL-2.0 only for those
static-link / bundled ecosystems.

When classifying, look at:

- The repository's README and stated purpose
- File types and directory structure
- Package manifests (package.json, Cargo.toml, pyproject.toml, go.mod, etc.)
- Entry points (main files, bin scripts, server files)
- How users are expected to consume the project

## Steps

### 1. Check for existing license

Look for existing license files: `LICENSE`, `LICENSE.md`, `LICENSE.txt`,
`COPYING`, or similar. If any exist, note what's there; this context
informs the suggestion in the next step and tells you whether you'll need
the user's permission to replace.

### 2. Suggest a license

Analyze the repository and present your recommendation:

- What type of project you think this is, and why
- Which license that maps to
- A brief note on what the license means in practice for this project
- If an existing license was found, mention it and how your suggestion
  compares

Then present all five options and ask the user which they'd like to use.
Frame your analysis as a suggestion; the user may have context you don't
(e.g., a library that will soon become a standalone tool, or a CLI that's
really a network service wrapper). Accept their choice without pushback.

If an existing license file will be replaced, confirm that's acceptable
before proceeding.

**Short-circuit rule**: If the repo already has a license that isn't one of
the five supported by this philosophy, and the user doesn't want to change
it, stop here: the philosophy file would be incoherent with the actual
license. Let the user know why and end gracefully. If the existing license
_is_ one of the five and the user wants to keep it, skip the LICENSE write
step but continue with the philosophy file and README section.

### 3. Write the LICENSE file

Fetch the license text using this priority order:

1. **GitHub API** (preferred: canonical and current):

   ```sh
   gh api /licenses/<spdx-id> --jq .body
   ```

   where `<spdx-id>` is one of: `cc-by-sa-4.0`, `lgpl-3.0`, `mpl-2.0`,
   `gpl-3.0`, `agpl-3.0`

2. **Bundled fallback**: Read from `references/licenses/<spdx-id>.txt`
   in this skill's directory

Write the result to `LICENSE` in the project root.

**Copyright notice**: GPL-3.0, LGPL-3.0, and AGPL-3.0 include a preamble
suggesting how to apply the license to your work. After writing the LICENSE
file, if the license recommends a copyright/program notice (as GPL, LGPL,
and AGPL do at the end of their text), note this to the user; they may
want to add the suggested notice to their source files. The LICENSE file
itself is the canonical license text and should not be modified.

**LGPL-3.0 note**: The LGPL-3.0 is a set of additional permissions on top
of GPL-3.0. A project using LGPL-3.0 needs both texts. Write the GPL-3.0
text as `LICENSE` and the LGPL-3.0 additional terms as `LICENSE.LESSER`.

**MPL-2.0 note**: MPL-2.0 is self-contained file-level copyleft: its text
stands alone, so write it as a single `LICENSE` with no companion file
(unlike LGPL-3.0 above). MPL also carries a per-file source-code notice
(Exhibit A, "This Source Code Form is subject to the terms of the Mozilla
Public License, v. 2.0…"). Because the copyleft attaches per file, point the
user to add that notice to their covered source files, the same
manual-notice step as the copyright notice above, not an edit to the
canonical `LICENSE` text.

### 4. Add LICENSING-PHILOSOPHY.md

Read `references/LICENSING-PHILOSOPHY.md` from this skill's directory and
write it verbatim to `LICENSING-PHILOSOPHY.md` in the project root. Do not
modify the content.

### 5. Update the README

Add a license section to the project's README.md (or README if no .md
variant exists). If no README exists at all, note this to the user and
suggest they create one; don't create a README just for the license
section.

If a license section already exists (a heading containing "License" or
"Licensing"), replace its content. Otherwise, add the section near the end
of the file: before any final footer or "acknowledgments" section if one
exists, otherwise at the very end.

Use this format:

```markdown
## License

This work is licensed under [LICENSE_NAME](./LICENSE_PATH).

See [LICENSING-PHILOSOPHY.md](./LICENSING-PHILOSOPHY.md) for why we chose
this license.
```

Where `LICENSE_NAME` and `LICENSE_PATH` are:

- `CC BY-SA 4.0` → `./LICENSE`
- `MPL-2.0` → `./LICENSE`
- `GPL-3.0-or-later` → `./LICENSE`
- `AGPL-3.0-or-later` → `./LICENSE`

For LGPL-3.0, link to both files since they form the complete license:

```markdown
This work is licensed under
[LGPL-3.0-or-later](./LICENSE.LESSER) ([GPL-3.0](./LICENSE)).
```

### 6. Report

Summarize what was done:

- The classification and reasoning
- Files created or modified
- Any remaining manual steps (e.g., adding per-file copyright notices)
