# Uploading With `gh --attach`

GitHub CLI 2.99.0 (2026-09-01) added a repeatable `--attach` flag to six
commands. It uploads each file to GitHub's own `user-attachments` endpoint and
returns a `https://github.com/user-attachments/assets/<uuid>` URL, the same
form the web UI's drag-and-drop produces. Those assets have no public index.

Sources, read at the implementing diffs: cli/cli#14178 (file validation),
cli/cli#14179 (body rewrite), cli/cli#14180 (token, permission, and host
checks), and cli/cli#14289 (the 50-file cap).

## §commands

| Command                     | Attaches to              | Use it for                                  |
| --------------------------- | ------------------------ | ------------------------------------------- |
| `gh pr create --attach`     | The new PR's description | Evidence composed with the PR               |
| `gh pr edit --attach`       | An open PR's description | Adding evidence to a PR that already exists |
| `gh pr comment --attach`    | A new PR comment         | A later addition                            |
| `gh issue create --attach`  | The new issue's body     | Filing a visual bug with its screenshot     |
| `gh issue edit --attach`    | An open issue's body     | Adding evidence to an issue that exists     |
| `gh issue comment --attach` | A new issue comment      | A later addition                            |

`gh pr edit` and `gh issue edit` start from the current body when no `--body`
or `--body-file` is given. A file the current body doesn't reference by local
path is appended; to place it, pass `--body-file` with the reference in it.

Every command checks four gates before uploading and stops with the quoted
error when one fails:

- **Version:** The flag exists from 2.99.0. Older gh rejects it as an unknown
  flag.
- **Token type:** Only OAuth (`gho_`), classic PAT (`ghp_`), and fine-grained
  PAT (`github_pat_`) tokens can upload. The GitHub Actions `GITHUB_TOKEN` is
  a server-to-server token and fails with `unsupported authentication type`.
- **Permission:** gh reads the viewer's permission on the target repository
  over GraphQL and requires `WRITE`, `MAINTAIN`, or `ADMIN`. Otherwise:
  `attaching files requires write access to the repository`.
- **Host:** GitHub.com and GitHub Enterprise Cloud, including data-residency
  tenants on `ghe.com`, work. GitHub Enterprise Server fails with
  `attaching files is not supported on GitHub Enterprise Server`.

Uploads run in argument order and stop at the first failure. Files already
uploaded stay in the body, since there is no endpoint to delete an upload, and
the command exits non-zero. `gh pr create` with nothing uploaded creates no PR,
but the branch is already pushed by then.

## §body-rewrite

gh parses the body as Markdown and walks its image and link nodes. Verified
against the 2.99.0 rewrite code with a scratch body:

- **Inline references are rewritten in place.** `![alt](./file.png)` and
  `[text](./file.png)` both become the hosted URL, including inside a GFM
  table cell.
- **Reference-style links are rewritten at the definition.** For
  `![Before][b]` with `[b]: ./before.png`, the definition line changes and
  every use of `[b]` follows.
- **Raw HTML is not a Markdown node.** `<img src="./file.png">` is left as
  written, and the file is appended at the end as a new paragraph. The same
  goes for a path inside a code span or fence.
- **Paths match by absolute path.** `./before.png` in the body matches
  `--attach ./before.png` and `--attach before.png` alike.
- **In-body alt text wins.** A reference already in the body keeps the alt
  text written there. The `#alt` suffix on `--attach` names only an appended
  file; without it, the filename is the alt text.
- **Nothing is deduplicated.** Every run uploads every `--attach` file. After
  the first run the body holds URLs, not local paths, so a second run with
  the same file finds nothing to rewrite and appends a duplicate.
- **No integrity check.** gh doesn't compare a digest after upload. gh-imgup's
  SHA-256 round-trip has no equivalent here.

Write the body with Markdown image syntax and local paths, attach the same
files, and let gh do the placement. Write the URLs by hand only on the
gh-imgup path, where the CLI prints them.

## §video

gh accepts `mp4`, `mov`, and `webm` up to 100 MB under the same gates. A video
reference alone in its paragraph becomes a bare URL, which GitHub renders as a
player. Anywhere else it becomes a plain link. A video written as a
reference-style image is refused with
`cannot embed a video as a reference-style image`. Video has no alt text. Capturing
video is outside this skill's procedure; the note is here so an agent that
receives one knows what gh will do with it.
