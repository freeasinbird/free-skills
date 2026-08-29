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

Use this skill when a repository needs a license under this philosophy or the
user asks for one.

Follow six steps:

1. Check for an existing license.
2. Suggest a license and ask the user to choose.
3. Write the `LICENSE` file.
4. Add `LICENSING-PHILOSOPHY.md`.
5. Update the README.
6. Report what changed.

## License Selection Criteria

Analyze the repository to understand what type of work it is. The
license follows from the project type:

| Project type                 | License      | SPDX identifier | Signals                                                                                                             |
| ---------------------------- | ------------ | --------------- | ------------------------------------------------------------------------------------------------------------------- |
| Knowledge artifacts          | CC BY-SA 4.0 | `cc-by-sa-4.0`  | Mostly markdown, prompts, documentation, patterns, agent skills, templates, educational content                     |
| Libraries (dynamic-link)     | LGPL-3.0     | `lgpl-3.0`      | Imported as a dependency in a dynamic-link or import-based ecosystem (Python, JVM, C/C++); relinking is satisfiable |
| Libraries (static-link)      | MPL-2.0      | `mpl-2.0`       | Imported as a dependency where static linking or bundling is the norm (Rust, Go, bundled JavaScript, mobile SDKs)   |
| Local applications and tools | GPL-3.0      | `gpl-3.0`       | CLI entry point, desktop app, local tool; users download and run it on their machine                                |
| Network services             | AGPL-3.0     | `agpl-3.0`      | Server entry point, HTTP routes, WebSocket handlers, deployed and accessed over a network                           |

For libraries, use the strongest weak-copyleft license the target ecosystem
can honor. Default to LGPL-3.0. Use MPL-2.0 only where static linking or
bundling is the norm (Rust, Go, bundled JavaScript, mobile SDKs), because an
unenforceable copyleft protects nothing.

When classifying, look at:

- The repository's README and stated purpose
- File types and directory structure
- Package manifests (package.json, Cargo.toml, pyproject.toml, go.mod, etc.)
- Entry points (main files, bin scripts, server files)
- How users are expected to consume the project

## Steps

### 1. Check for Existing License

Look for existing license files: `LICENSE`, `LICENSE.md`, `LICENSE.txt`,
`COPYING`, or similar. If any exist, note what's there; this context
informs the suggestion in the next step and tells you whether you'll need
the user's permission to replace.

### 2. Suggest a License

#### Recommendation

Analyze the repository and recommend a license. Include:

- What type of project you think this is, and why
- Which license that maps to
- A brief note on what the license means in practice for this project
- If an existing license was found, mention it and how your suggestion
  compares

#### Ask the User

Present all five options and ask the user which they'd like to use. Frame your
analysis as a suggestion. The user may have context you don't, such as a
library that will soon become a standalone tool or a CLI that's really a
network service wrapper.

Accept their choice without pushback. Confirm before replacing an existing
license file.

#### Short-circuit

- **Unsupported license kept:** Stop if the existing license isn't one of the
  five and the user keeps it. Explain that the philosophy file would conflict
  with the actual license.
- **Supported license kept:** Skip the `LICENSE` write if the existing license
  is one of the five and the user keeps it. Continue with the philosophy file
  and README section.

### 3. Write the LICENSE File

#### Fetch Order

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

#### License Files and Notices

| License      | Files written                                                              | Manual notice                                                                                                                           |
| ------------ | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| CC BY-SA 4.0 | `LICENSE`                                                                  | None                                                                                                                                    |
| LGPL-3.0     | `LICENSE` with GPL-3.0 text and `LICENSE.LESSER` with LGPL-3.0 permissions | Point the user to the copyright/program notice recommended at the end of the license text                                               |
| MPL-2.0      | One `LICENSE`                                                              | Point the user to the Exhibit A per-file notice: "This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0…" |
| GPL-3.0      | `LICENSE`                                                                  | Point the user to the copyright/program notice recommended at the end of the license text                                               |
| AGPL-3.0     | `LICENSE`                                                                  | Point the user to the copyright/program notice recommended at the end of the license text                                               |

- The `LICENSE` file is the canonical license text. Never modify it.
- For GPL-3.0, LGPL-3.0, and AGPL-3.0, point the user to the recommended
  copyright/program notice for source files.
- LGPL-3.0 adds permissions to GPL-3.0, so a project needs both texts.
- MPL-2.0 is self-contained file-level copyleft, so it needs no companion
  file.
- The MPL-2.0 notice is a manual step for covered source files. Don't add it
  to `LICENSE`.

### 4. Add LICENSING-PHILOSOPHY.md

Read `references/LICENSING-PHILOSOPHY.md` from this skill's directory and
write it verbatim to `LICENSING-PHILOSOPHY.md` in the project root; don't
modify it.

### 5. Update the README

#### Placement

- **README.md exists:** Add the license section there.
- **Only README exists:** Add the license section there when no .md variant
  exists.
- **No README exists:** Tell the user and suggest they create one. Don't create
  a README just for the license section.
- **A license section exists:** Replace the content under a heading containing
  "License" or "Licensing".
- **No license section exists:** Add one near the end. Put it before a final
  footer or "acknowledgments" section when one exists. Otherwise, put it at
  the end.

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
