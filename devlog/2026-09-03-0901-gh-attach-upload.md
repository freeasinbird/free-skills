# Upload visual evidence with gh --attach, keep gh-imgup as the fallback

Issue #230. GitHub CLI 2.99.0 (2026-09-01) added a repeatable `--attach` flag
to `gh pr create`, `gh pr edit`, `gh pr comment`, and the three `gh issue`
equivalents. It uploads to GitHub's own `user-attachments` endpoint and
rewrites Markdown references in the body to the hosted URLs. Until now
visual-evidence uploaded only through gh-imgup, ending in a pinned
`npx -y @freeasinbird/gh-imgup@0.1.3` download. This note revises three
earlier notes and covers a credential-leak surface, which the project's
mandatory-note list includes.

## Decision

Chose a generic upload step with a decision order over a gh-imgup section
with a gh addendum (user, 2026-09-03 chat). The order:

1. `gh --attach` when gh is 2.99.0 or newer, the token is a user token, and
   the host is GitHub.com or GitHub Enterprise Cloud.
2. gh-imgup when it is already installed, recommended but not required. It is
   the only zero-secret path under the Actions `GITHUB_TOKEN` and the path on
   older gh.
3. Stop at local files and say so at handoff.

Dropped the pinned download. The 2026-09-01 note kept it so an agent without
the CLI still had an upload path. gh is now that path on any current
interactive setup, and the download's remaining niche, CI without gh-imgup, is
better served by installing gh-imgup in the workflow or supplying a PAT.

Excluded SVG in prose. gh accepts it by extension, but SVG can carry scripts,
and gh-imgup refused it for that reason. A prose skill is the only place the
exclusion can now live.

Accepted the loss of gh-imgup's SHA-256 round-trip. gh compares no digest
after upload and a prose skill can't add one.

Moved review ownership. The 2026-07-24 note kept ownership of the pre-upload
secret review with gh-imgup and treated the local copy as a duplicate. On the
gh path no gh-imgup runs, so the review is now this skill's own mandatory
gate. The checklist text is unchanged and still held at gh-imgup's bar; the
review still precedes the first runnable command, as that note requires.

Reduced the 2026-06-26 note's one-directional dependency on gh-imgup to a
named fallback. The skill still names the concrete tool it may run.

Collapsed the forge-record and SSH-alias slug paragraphs to one rule: pass
`-R owner/repo` to gh, or `--repo owner/repo` to gh-imgup, when the checkout's
remote doesn't resolve to the target. gh resolves ordinary remotes itself, and
the project's forge record already tells an agent the slug when the remote
can't.

Added one allow-rules bullet, gated on platforms with a command allowlist. It
names the four gh commands and `gh-imgup`, with the Claude Code
`Bash(gh pr create *)` pattern as one example. No classifier prose for the gh
path, since gh is a known tool.

Kept the detail an agent needs only after the first command in
`references/gh-attach.md`: the per-command table, the four gates with their
exact error strings, the rewrite rules, and the video note. SKILL.md carries
only what must be read before running anything.

## Rejected Options

- **A gh-imgup section with a gh addendum.** It would keep the retired path
  as the frame and bury the path most agents should take.
- **Keeping the pinned download as a third path.** Every agent with a current
  gh has a first-party path, and an approval reviewer still has to trust a
  network fetch with token access for the rest.
- **Stating the limits and rewrite rules in full in SKILL.md.** The section
  would exceed the paragraph and readability caps, and the agent needs most
  of that detail only when a rewrite surprises it.

## Refute-First Findings

The session's approval classifier blocked opening the scratch PR the issue
planned, so the body-rewrite checks ran against gh's own code instead: a
shallow clone of `cli/cli` at `v2.99.0`, with a throwaway package test that
fed the planned scratch body through `newAttachableMarkdown` and
`attachAssetsToMarkdown`. That exercises the rewrite exactly as 2.99.0 ships
it, but not the upload or the server side.

- **Confirmed: `![]()` inside a GFM table cell is rewritten.** Both cells of
  the two-column table came back with hosted URLs.
- **Confirmed: a raw `<img src="./x.png">` is not rewritten.** The tag stayed
  as written and the file was reported for appending.
- **Confirmed: a reference-style image is rewritten at its definition.**
  `![Before ref][b]` stayed as written and `[b]: ./ref.png` became the URL.
- **Confirmed: in-body alt text wins.** `![In-body alt](./alt.png)` kept its
  text when the flag also named `#Flag alt`. gh's own test suite pins the
  same case.
- **Confirmed from source: `gh pr edit --attach` is not idempotent.**
  `UploadAndAttach` uploads every asset on every run with no lookup of what
  the body already holds. After the first run the body holds URLs, so a
  second run with the same file finds nothing to rewrite and appends a
  duplicate. The skill now says to attach each file once.
- **Accepted from source, not run: the Actions-token error text.**
  `checkUploadTokenType` allows OAuth, classic PAT, and fine-grained PAT and
  returns `unsupported authentication type` for anything else. No workflow
  run was made.
- **Confirmed from source: data-residency tenants pass the host gate.**
  `checkHost` refuses only hosts that `auth.IsEnterprise` reports, which is
  false for `ghe.com`.
- **Confirmed: the help text is inconsistent, the code is not.** `gh pr create
--help` says the file is appended and then describes the rewrite; `gh pr
comment --help` says the reverse. One code path rewrites references and
  appends only unreferenced files. SKILL.md states the rule, not the help.
- **Read, not run: the video rules in the reference.** They come from the
  rewrite table in `references.go` and its tests, not from a run.
- **Confirmed: gh-imgup can't stand in for gh on GitHub Enterprise Cloud.**
  A fresh-context reviewer found that the rewrite dropped the old
  `github.com`-only stop. gh-imgup uploads only there, so the fallback path
  now sends a GitHub Enterprise Cloud agent with old gh or the Actions token
  straight to local files.
- **Not run: the two-column layout at the 830 px body width.** GitHub sizes
  an image from its file pixels whatever host serves it, so the 600 px
  guidance stays; the example now shows local paths, since gh rewrites them.

Revisit when a gh release changes `--attach` semantics, adds deduplication or
an integrity check, or accepts the Actions token; or when gh-imgup's own
repositioning changes what the fallback is called or how it installs.
