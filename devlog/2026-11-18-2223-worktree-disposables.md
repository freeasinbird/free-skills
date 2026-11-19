# Let the Worktree Sweep Delete Declared Disposables

The merge-cleanup worktree sweep now treats a worktree as clean when its only
leftovers are ignored paths the project lists in a committed
`.worktree-disposables` file, or an ignored `.DS_Store`, which is built in.
agent-setup offers the file for ignored build output. Issue #405 carries the
contract, revised on 2026-11-19 after the redesign below; its handoff half
landed separately with the rule that agents write scratch outside the
checkout.

## Evidence

On 2026-11-18 the sweep found 0 clean candidates among 38 worktrees in
freeside. SwiftPM checkouts (`.build/checkouts/*/.git`) made 18 of them
`holds-repository`. Ignored `.DS_Store` files and build output made most of
the rest dirty. After those were deleted by hand, 29 of 31 candidates were
clean. The sweep's safety rules were right; it had no way to tell ignored
build output from an ignored `.env`.

## Decisions

- **Chose a declared list over trusting every ignored file.** `.gitignore`
  also covers secrets and local settings, which removal must not delete
  silently. Only the project knows which ignored paths are disposable, so
  it names them. Without the file, every result except the `.DS_Store` rule
  is unchanged.
- **Chose a plain file over an AGENTS.md record.** The first design kept the
  list in one Markdown bullet. Six review rounds kept finding layouts
  (fences, HTML blocks and comments, front matter, list continuation, a
  symlinked AGENTS.md) where the sweep's line scan read a record the
  rendered page doesn't show, or missed one it does. The risk came from
  parsing Markdown, not from the feature. A two-member council (Fable and
  Sol 6.1) recommended a committed plain file, one literal entry per line,
  and the owner chose it. The owner also rejected keeping the list in git
  config.
- **Chose a built-in `.DS_Store` rule over a declared entry.** Finder writes
  one in any folder a user opens, so whether it appears depends on the
  user, not the project. The owner didn't want it in each repository. Only
  an ignored file named exactly `.DS_Store` counts; an untracked one, or a
  directory of that name, still keeps the worktree.
- **Chose literal entries over globs.** Literal names and anchored paths
  cover every blocker found. A glob that matches more than intended deletes
  real work. The grammar refuses globs, `.`, `..`, any `.git` component in
  any case, absolute paths, surrounding whitespace, a carriage return, and a
  NUL byte, and a bad file stops the run before any worktree is read.
- **Chose to read the file at the base commit, never a worktree.** A branch
  could otherwise widen what removal deletes before review sees it. Only a
  regular file counts, since a symlink's blob is its target's name.
  `--remove-head`, merge-cleanup's own call from #433, has no base, so it
  reads no file and applies only the `.DS_Store` rule. Reading the merged
  head's copy could restore an entry the base has since dropped; the owner's
  sweep clears declared build output instead.
- **Chose to accept the inventory's `STOP dirty` in the sweep over changing
  the inventory.** merge-cleanup also runs `worktree-inventory.sh` directly,
  where every ignored file must still stop removal. The sweep accepts that
  stop only when its own reads, the flag read included, found disposables
  and nothing else.
- **Chose to require that the part of a path an entry matches be ignored
  itself.** A package manager's checkout under an ignored `.build/` is
  disposable, nested repository and all. Declaring `notes/` while only
  `notes/private/` is ignored covers nothing, since the owner may keep work
  there. An untracked repository under a declared directory the project
  forgot to ignore is never disposable, since `--remove-dirty`'s `--force`
  would delete its commits.
- **Chose no default entry in agent-setup.** It offers the file only for
  ignored output a build tool in use creates, shows each entry's evidence,
  and warns that removal deletes everything under an entry. An accepted file
  gets a one-line unmanaged pointer in AGENTS.md so readers find it.

## Review Findings That Still Shape the Matcher

Reviews ran in six rounds on the Markdown design: a council (Codex
gpt-6.2-astra and Claude Opus 5.5) for rounds 1 to 3, then one fresh-context
reviewer under the pre-push rule from #431. Every finding was confirmed by
reproduction or trace, with a matrix case that fails against the unfixed
code. The Markdown-scan findings no longer apply. These still shape the
sweep:

- **A leading `:` in a directory name read as pathspec magic** in
  `check-ignore`, so an untracked nested repository passed as ignored and
  `--remove-dirty` deleted it. Paths are passed as `./<dir>`.
- **The nested-repository probe asked about the wrong path.** With a
  trailing slash, a pattern for a directory's contents (`cache/*`, or a `*`
  in the nested repository's own `.gitignore`) answered for an untracked
  repository. The probe asks about the matched directory without its slash.
- **Ignored files under a declared but unignored directory counted,**
  including a bare repository and, on macOS, one whose `.git` was named
  `.GIT`. This produced the ignored-part rule above, checked against every
  matching entry, so the narrower of `notes/` and `notes/private/` applies.
- **A failed read counted as no entries.** The sweep lists the file with
  `git ls-tree --full-tree`, which also finds it when run from a
  subdirectory, and stops with `LOOKUP_FAILED record` on any failed read.
- **A path holding a newline could read another path's answer** from the
  newline-delimited ignore cache. A prefix holding a newline is never
  disposable; a newline below a matched directory is fine.
- **The NUL check compares two files, not a pipe.** Through a pipe, `cmp`
  could exit at the first difference and kill `tr`, so a NUL byte read as a
  failed read.

The nested-repository search looks only for `.git`, so outside a declared
entry a bare repository, or a `.GIT` one on a case-insensitive disk, is
untracked or ignored rather than held. That predates this change; #437
tracks it.

## Pre-Push Review of the File Form

One fresh-context reviewer (Codex gpt-6.2-astra) reviewed the redesign.

- **Fixed: agent-setup suggested `.swiftpm/`.** SwiftPM keeps package
  configuration such as mirrors there, so declaring it would delete
  settings. The examples now name only `.build/`, and the guidance warns
  against `.swiftpm/`.
- **Fixed: a comment with surrounding space passed.** The contract refuses
  surrounding whitespace on any line, so the check now runs before comments
  are skipped.
- **Fixed: the help said a stale base only keeps more worktrees.** A stale
  base can still hold an entry the project has since dropped, so its
  paths can be deleted. The help and the skill now say so.
- **Fixed: a `.DS_Store` under a declared directory split the report.** The
  built-in rule ran first, so the `disposable` list repeated the directory.
  Entries now match first.
- **Declined: a newline in a parent directory hides an any-depth entry
  below it.** The guard keeps such a worktree, the safe direction, and a
  newline in a directory name is rare enough that the extra code isn't
  worth it.

A fix check confirmed all four fixes. It added a gap in `--help`, which
didn't say that a dry run and then `--remove --remove-dirty` clear
leftovers; that is fixed. It also found that a declared directory whose
name the disk stores decomposed (`e` plus a combining accent, where
`core.precomposeUnicode` reports `é`) keeps a worktree holding a nested
repository there as `holds-repository`. That is declined for the same
reason as the newline case: it keeps the worktree.

## Assumptions

- **Plain `git worktree remove` deletes ignored files and nested
  repositories inside ignored directories,** and `status -uall --ignored`
  prints such a repository as `dir/`. Both were checked on git 2.54 only. The
  sweep matrix pins both.

Revisit when a project needs a pattern the literal grammar can't express, or
when git changes what `worktree remove` deletes without `--force`.
