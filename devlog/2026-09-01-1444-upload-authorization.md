# Visual-evidence upload: prefer the installed CLI and authorize the upload

Issue #204 came from the 2026-09-01 transcript audit. Six Codex sessions
ended with the user forcing the gh-imgup upload by hand. The gh-imgup skill
was not installed, so visual-evidence fell back to an unpinned
`npx -y @freeasinbird/gh-imgup` download. Codex's approval reviewer blocks
that as an unknown package with credential access. The CLI was on `PATH` the
whole time.

## Decision

Order the upload paths: the loaded gh-imgup skill, the `gh-imgup` binary on
`PATH`, a package already installed via `npx --no-install`, then a download
pinned to `@freeasinbird/gh-imgup@0.1.3` as the last resort. Forbid an
unpinned download.

State that invoking visual-evidence authorizes the upload once every image
passes the mandatory sensitive-data review. The user decided this in #204:
invoking the skill already grants the upload, and asking again is the failure
the audit found. The one decision left to the user is an image the review
flags. The review itself is unchanged and still precedes every upload, because
there is no un-publish.

The pinned version lives in `SKILL.md` prose. Bump it there when gh-imgup
releases; no script reads it.

## Rejected Options

- **Keep asking before every upload.** The audit shows this is the defect. The
  user granted the upload by invoking the skill and had to repeat the grant in
  six sessions.
- **Pin the download but keep it first.** Even pinned, a download asks an
  approval reviewer to trust a network fetch with token access while the
  binary is already installed. The installed binary needs no fetch.
- **Drop the download path entirely.** An agent without the CLI would then
  have no upload path. A pinned last resort keeps the skill usable and lets a
  reviewer inspect exactly what runs.
- **Track the version in a machine-readable file.** One value in one skill
  doesn't justify a resource file and a check. A script is the next step if
  the pin drifts from the published version.

## Refute-First Findings

These checks tried to prove the change wrong, per `docs/agent-workflow.md`
§refute-first.

- **Disproved: the pin might not exist.** `npm view` lists `0.1.3` as the
  latest published version, matching the local `gh-imgup --version`.
- **Disproved: `npx --no-install` might miss a global install.** From an empty
  directory it resolved the global `gh-imgup` and printed `0.1.3`. With the
  package absent it exits on an npm 404 and installs nothing.
- **Allowed: `npx --no-install` still queries the registry before failing.**
  That is a metadata read with no package execution, so it stays acceptable
  as the second path.
- **Disproved: the Authorization bullet over-grants.** A fresh-context
  reviewer read it against the CLI's `--help`. Authorization is gated on the
  review and carves out a flagged image. `--pr` and `--issue` need a token
  scope beyond upload, so "the upload" can't stretch to posting a comment.
- **Disproved: an unpinned `npx -y` remains.** A grep of the whole file finds
  only the pinned form and the sentence that explains its `-y` flag.
- **Disproved: a factual claim is wrong.** `command -v` finds the binary, the
  CLI's help shows positional files with optional `--pr` and `--issue`, and
  the Node 22+ claim matches the runtime that ran it.
- **Confirmed: the authorization ignored an explicit local-only request.**
  Codex found that every bundled eval forbids uploading. The bullet now yields
  to a request to keep the images local, which ends the work at the files.
- **Confirmed: `command -v` is POSIX-only.** The README advertises Windows
  install, so the PATH check now names the PowerShell equivalent too.
- **Allowed: the fenced example shows only the binary form.** The list above
  it spells out both npx invocations, and the text says images are positional
  arguments, so a second example would repeat that.

Revisit when gh-imgup ships its own skill install path that makes the CLI
order moot, or when an approval reviewer starts blocking the pinned download
too.
