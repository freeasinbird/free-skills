# List a Matched Ignored Directory Once in the Worktree Sweep

The merge-cleanup worktree sweep now reads status with
`--ignored=matching`, so an ignored directory that a pattern matches comes
back as one `dir/` record, and its JSON escaping no longer forks per
character. Issue #471 carries the contract. One rare case moves from clean
to dirty; nothing moves the other way.

## Evidence

`merge-cleanup.sh --pr 239` in teloleo ran over 25 minutes inside the sweep's
read-only inventory before it was stopped. The merged worktree held an
undeclared uv `.venv`: `status -uall --ignored` listed 36,155 paths, 3.1
million characters, and `json_escape` spent a subshell (about 1 ms) on each
character. `json_add` also copied the whole list string once per path.

## Decisions

- **Chose `--ignored=matching` over dropping `-uall`.** Without `-uall`, git
  would also collapse untracked directories, and a directory no pattern
  matches but whose files are all ignored (`docs/` holding only `.DS_Store`)
  would come back as `docs/`, which the built-in `.DS_Store` rule can't see.
  `matching` collapses only a directory an ignore pattern matches, keeps
  untracked files one per line, and still enters a directory that holds a
  tracked file. The explicit `-uall` also still overrides
  `status.showUntrackedFiles=no`, the inventory's reason for it.
- **Accepted one clean-to-dirty change.** A declared disposable inside an
  undeclared ignored directory is no longer seen alone. With `out/` ignored,
  `__pycache__/` declared, and only `out/__pycache__/x.pyc` present, the
  worktree read clean before; now `out/` is listed as ignored and the
  worktree is kept. An ignored directory holding only `.DS_Store` files
  behaves the same way. The report names `out/`, which is what removal would
  delete, and a project that wants it gone can declare it.
- **Chose to skip an empty ignored directory over accepting a second
  change.** `matching` also lists an ignored directory that holds only empty
  directories, which the per-file listing never showed, so an empty
  `build/` would have turned a clean worktree dirty. The sweep now drops an
  undeclared `dir/` record when `find` sees no non-directory under it; a
  `find` error keeps the record. Removing such a directory deletes no file.
  A declared empty directory now appears in `disposable`, which changes the
  report but not the verdict.
- **Chose a narrow own-`*` rule over checking with a trailing slash.** The
  owner added this to #471 after teloleo's cleanup: Hypothesis and uv ignore
  their own directory with a `*` in a `.gitignore` inside it, so
  `check-ignore ./.hypothesis` says not ignored and a declared
  `.hypothesis/` never matched. Asking with the slash would fix that, but an
  earlier review confirmed that form lets a `*` in a nested repository's own
  `.gitignore` make the repository read as ignored, and `--remove-dirty`
  then deletes its commits. The sweep now accepts a declared directory as
  ignored only when `check-ignore -v ./<dir>/` names `<dir>/.gitignore` and
  the pattern `*`, that file holds nothing but `*`, comments, and blank
  lines, and `<dir>` holds no `.git`. With no `!` line, nothing under the
  directory can be re-included, so a repository inside it is disposable,
  as one under a declared `.build/` already was (a pip editable install
  under `.venv/src/`). A root `cache/*` still doesn't answer for `cache/`;
  the owner asked only for the own-`*` shape.
- **Left `--remove-head` reading no disposables.** Passing it the pinned base
  is a separate contract change on the deletion path, filed as #476.
- **Chose a fast path plus `printf -v` over a different escaper.** Printable
  ASCII needs only `\` and `"` escaped, so two pattern substitutions handle
  it; any other string keeps the per-byte loop with `printf -v` instead of a
  command substitution. Keeping the rules unchanged let an exhaustive
  comparison prove the output identical, which a new escaper would have to
  earn from scratch.
- **Added `json_escape_to`, which sets a variable.** The plan had `json_add`
  collect escaped strings in arrays, but calling `json_escape` through `$( )`
  still costs one fork per path, about 20 seconds for 20,000 paths. The
  printing `json_escape` now wraps it, so every other caller is unchanged.

## Why No Worktree Moves from Dirty to Clean

A directory record is disposable only when its files would have been. git
collapses a directory only when an ignore pattern matches the directory
itself, and git never re-includes anything under an excluded directory, so
every file under it was ignored before too. `match_declared` answers for the
`dir/` record from the same leading components it used for each file.

## Refute-First Findings

- **Escaping equivalence: disproved any difference by a check.** The old and
  new `json_escape` ran over 83,104 inputs: all 255 single bytes, all 65,025
  two-byte strings, overlong, surrogate, out-of-range, and truncated 3- and
  4-byte sequences, and 4,000 random strings. Output was byte-identical
  under `/bin/bash` 3.2.57 and bash 5.3.
- **Empty ignored directory read dirty: confirmed, then fixed.** A
  fresh-context reviewer reproduced it; the decision above restores the old
  verdict, and a matrix case covers it.
- **Dirty-to-clean moves: disproved by a check.** The reviewer ran old and
  new sweeps side by side on eleven fixtures: empty and declared empty
  directories, a `cache/*` contents pattern, an ignored directory holding a
  tracked file, a uv `.venv`, nested repositories inside declared and
  undeclared ignored directories, an anchored entry, and an ignored
  symlink to a directory. No verdict moved toward clean, and
  `git check-ignore` confirmed every collapsed directory was ignored.
- **A `!` line under an own `*` let a repository read as disposable:
  confirmed, then fixed.** The second reviewer's case: `cache/` declared,
  `cache/.gitignore` holding `*` then `!sub`, and a repository at
  `cache/sub`. The first own-`*` rule trusted check-ignore's answer for
  `cache/`, so `--remove-dirty` deleted the repository. Requiring the file
  to hold only `*` closes it, and a matrix case covers it.
- **Own-`*` source and pattern: disproved by a check.** The second reviewer
  found `cache/*` at the root, `/*`, `**`, `.git/info/exclude`, a gitdir
  file, a symlinked directory, and odd names all refused or held.

Revisit when git changes what `--ignored=matching` collapses, or when the
sweep's minimum git version drops below 2.16.
