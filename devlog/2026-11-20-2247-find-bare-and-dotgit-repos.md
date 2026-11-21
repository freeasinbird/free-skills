# Find Bare and .GIT Repositories in the Worktree Sweep

The merge-cleanup worktree sweep now detects nested bare repositories and
case-variant `.git` entries (such as `.GIT`) in `holds_repository()` and
`own_star_ignored()`. Issue #437 carries the contract. Previously,
`holds_repository()` ran `find "$path" -mindepth 2 -name .git -prune`, which
missed bare repositories and `.GIT` directories, letting
`--remove --remove-dirty` delete them.

## Decisions

- **Chose unconditional `.[gG][iI][tT]` matching over filesystem case
  probing.** Matching all 16 case variants on both case-insensitive and
  case-sensitive disks mirrors `bad_entry()`'s `.[gG][iI][tT]` rule and avoids
  fragile disk-case detection. In `holds_repository()`, `find` runs from inside
  the worktree (`cd -- "$path" && find . -mindepth 1`), prunes every
  `.[gG][iI][tT]` entry, and skips only the worktree's own `./.git`. Pruning
  before descending keeps unreadable `objects/` inside a nested `.GIT`
  repository from failing `find`.
- **Chose a pure-shell on-disk shape check in `is_bare_repo()` over running
  `git --git-dir`.** Invoking `git` against an untrusted nested directory can
  read arbitrary repository config or trip `safe.directory`. Instead,
  `is_bare_repo()` checks git's `is_git_directory()` layout directly:
  `objects/` plus either `refs/` or `reftable/`, and a `HEAD` that is a
  `refs/*` symlink, an unreadable regular file (fail-safe), or a regular file
  whose first line starts with `ref:` or holds a 40- or 64-character hex OID.
  Line reads allow optional `\r` and missing trailing newlines. On a
  case-insensitive disk, statting `HEAD`, `objects`, and `refs` folds case
  automatically, matching git without causing false positives on lowercase
  `head` files on case-sensitive Linux disks.
- **Chose to extend `own_star_ignored()` with `has_dot_git()` and
  `is_bare_repo()`.** `own_star_ignored()` already refused lowercase `.git` at
  a declared disposable directory so a `*` in a repository's own `.gitignore`
  could not make its commits disposable. Adding both helpers preserves that
  invariant for bare and `.GIT` repositories. Checking `[ -r "$wt/$dir" ]`
  also prevents `has_dot_git()`'s glob from failing silently on search-only
  (`0111`) directories, and checking `case "${e##*/}" in .[gG][iI][tT])` avoids
  a false positive on a literal file named `.[gG][iI][tT]`.
- **Chose to let unreadable `objects/` inside a bare repository fail closed via
  `LOOKUP_FAILED find`.** Unlike `.git` and `.GIT`, which `-prune` skips before
  descending, `find` must enter a bare repository to see `HEAD` and also visits
  `objects/`. Pruning arbitrary directories named `objects/` would hide real
  nested repositories inside an ordinary project directory named `objects/`.
  Failing closed keeps the worktree and deletes nothing.
- **Chose never to attach `-quit` to the `HEAD` branch of `find`.** When no
  disposables file is present, a `.git`/`.GIT` match can still `-quit`
  immediately, but an ordinary non-repository `HEAD` file must not abort the
  search before a real nested repository later in the tree is visited.

## Refute-First Verification

Because `worktree-sweep.sh` sits on a destructive cleanup path, adversarial
inputs were tested in a standalone harness under macOS `/bin/bash` (bash 3.2)
before committing:

- **Confirmed and fixed during design:** `IFS= read -r -n 100` returns exit 1
  when `HEAD` has no trailing newline even though it reads the line; adding
  `|| [ -n "$line" ]` kept valid newline-free `HEAD` files from being missed.
- **Confirmed and fixed during design:** a literal file named `.[gG][iI][tT]`
  would match an unexpanded glob in `has_dot_git()`; guarding the basename with
  `case "${e##*/}" in .[gG][iI][tT])` eliminated that false positive.
- **Confirmed and fixed during design:** skipping `./.[gG][iI][tT]` instead of
  `./.git` would miss a depth-1 `.GIT` directory beside `./.git` on a
  case-sensitive disk; skipping only `./.git` and checking depth only on the
  `HEAD` branch protects depth-1 `.GIT` entries too.
- **Disproved risks (verified safe):** broken `HEAD` symlink to
  `refs/heads/main` (held as bare repo); broken `HEAD` symlink to
  `/nonexistent` (not held); direct FIFO and symlink-to-FIFO named `HEAD` in
  both `holds_repository()` and `own_star_ignored()` (no hang, rejected by
  `[ -f ]`); symlink to an external bare repository (not followed by `find`).
- **Disproved path and format risks (verified safe):** paths with spaces,
  newlines, leading `-`, leading `:`, and glob characters (`*`, `[0]`) for both
  bare and `.GIT` repositories (all held); unreadable `HEAD` (`chmod 000`, held
  fail-safely); unreadable `.GIT/objects` (`chmod 000`, pruned and held without
  `LOOKUP_FAILED`); copied `.git` directory with `core.bare=false` in both
  `holds_repository()` and `own_star_ignored()` (held); detached 40- and
  64-character hex `HEAD` with LF, CRLF, or no newline (held).
- **Disproved negative and interaction risks (verified safe):** invalid `HEAD`
  shapes (39, 41, or 100 hex chars, non-hex, empty, blank line 1, leading
  spaces: all rejected); case-folded `head`/`OBJECTS`/`REFS` on macOS APFS
  (held); bare repository in a directory literally named `HEAD` (held); and a
  bare repository inside an own-`*` directory (`.venv/src/store.git`, stays
  disposable).
- **Accepted risk:** unreadable `bare.git/objects` (`chmod 000`) exits 4 with
  `LOOKUP_FAILED find` and keeps the worktree, as designed above.
- **Accepted risk:** a tracked git-shaped test fixture containing `objects/`,
  `refs/`, and a valid `HEAD` would classify every worktree as
  `holds-repository`, keeping it safely.
- **Accepted risk:** a corrupted bare repository whose `HEAD` is missing or
  invalid is not recognized as a repository, matching git's own
  `is_git_directory()` rule; accepting missing or invalid `HEAD` would trigger
  false positives on ordinary directories named `objects/` and `refs/`.

## Pre-Push Review

One fresh-context reviewer (Claude Opus 5.5, high effort) reviewed commit
`0677c58` and reported no blocking findings, plus three non-blocking notes:

- **Fixed (devlog update):** replaced the pending-review placeholder in this
  note with the final review outcomes and added the missing/invalid `HEAD`
  accepted risk above.
- **Accepted (missing or invalid `HEAD`):** confirmed that `find` and
  `is_bare_repo()` require a valid-looking `HEAD`, matching git's own
  `is_git_directory()`.
- **Accepted (tracked bare-shaped fixture):** already recorded above as a
  fail-safe tradeoff.

Revisit when git adds another ref-storage directory beside `refs/` and
`reftable/`, or if projects start committing git-shaped test fixtures that
need an explicit exemption.
