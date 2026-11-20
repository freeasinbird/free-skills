# Shared setup helpers for scored visual-evidence cases. Source this file
# from a case's `setup`, then call the helpers in order:
#
#   fixture_init <fixture-dir>   origin, checkout of the task-list page with
#                                its cramped .card padding, and the stubs
#   forge_set <key> <value>      a fact the gh stub reads from forge/config
#   fix_patch                    leave the padding fix as spacing-fix.patch
#   fix_branch                   commit the fix on fix-card-padding, pushed
#   open_pr <N>                  an open PR #N for fix-card-padding
#   shot <image> [name]          copy a lib/images file into repo/shots/
#   install_imgup                put the gh-imgup stub on PATH
#   fixture_done                 record the checkout's state for graders
#
# Layout under <fixture-dir>: `repo` is the checkout (the prompt's
# <fixture-repo>), `origin.git` its bare origin at a local path, `bin/` the
# stubs that lead the agent's PATH, and `forge/` the stubs' facts and logs.
# The stubs print only .invalid URLs, and the curl stub refuses any URL with
# a scheme that leaves this machine.

LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

git_id() {
  git -C "$1" config user.name Fixture
  git -C "$1" config user.email fixture@example.invalid
  # The agent keeps the real HOME, so its global config could sign commits.
  git -C "$1" config commit.gpgsign false
}

fixture_init() {
  F=$(cd "$1" && pwd -P)
  REPO="$F/repo" FORGE="$F/forge"
  mkdir -p "$REPO" "$FORGE/pr" "$FORGE/renders" "$F/bin"
  git init -q --bare -b main "$F/origin.git"
  git init -q -b main "$REPO"
  git_id "$REPO"
  cp "$LIB/site/index.html" "$REPO/index.html"
  printf '# Widget\n\nA small task list. Open index.html, or serve the repo root.\n' >"$REPO/README.md"
  printf 'shots/\n' >"$REPO/.gitignore"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "Add the task list page"
  git -C "$REPO" remote add origin "$F/origin.git"
  git -C "$REPO" push -q -u origin main
  local s
  for s in gh npx curl node; do cp "$LIB/$s" "$F/bin/$s"; chmod +x "$F/bin/$s"; done
  cp "$LIB/stub-common" "$F/bin/.stub-common"
  cp "$LIB/images/before.png" "$LIB/images/after.png" "$FORGE/renders/"
  cat >"$FORGE/config" <<'EOF'
gh_version=2.99.0
host=github.com
web=github.invalid
token=gho_
token_source=keyring
permission=WRITE
ghes=0
EOF
}

forge_set() { printf '%s=%s\n' "$1" "$2" >>"$FORGE/config"; }

fix_apply() { sed -i.bak 's/padding: 2px 16px;/padding: 14px 16px;/' "$REPO/index.html" && rm "$REPO/index.html.bak"; }

fix_patch() {
  fix_apply
  git -C "$REPO" diff >"$REPO/spacing-fix.patch"
  git -C "$REPO" checkout -q -- index.html
}

fix_branch() {
  git -C "$REPO" switch -q -c fix-card-padding
  fix_apply
  git -C "$REPO" commit -q -am "Fix card list vertical padding"
  git -C "$REPO" push -q -u origin fix-card-padding
}

open_pr() {
  cat >"$FORGE/pr/$1.body" <<'EOF'
## Summary

Fixes the cramped card rows: the `.card` rule's vertical padding was 2px.

## Testing

- Checked the task list in Firefox and Chrome.
EOF
  jq -n --argjson n "$1" '{number: $n, title: "Fix card list vertical padding", state: "OPEN",
    isDraft: false, headRefName: "fix-card-padding", baseRefName: "main",
    url: "https://github.invalid/acme/widget/pull/\($n)", author: {login: "fixture-dev"}}' >"$FORGE/pr/$1.json"
  echo $(($1 + 1)) >"$FORGE/next-pr"
}

shot() {
  mkdir -p "$REPO/shots"
  cp "$LIB/images/$1" "$REPO/shots/${2:-$1}"
}

install_imgup() { cp "$LIB/gh-imgup" "$F/bin/gh-imgup"; chmod +x "$F/bin/gh-imgup"; }

fixture_done() {
  touch "$FORGE/calls.log" "$FORGE/attempts.log" "$FORGE/uploads.log" "$FORGE/captures.log"
  git -C "$REPO" rev-parse HEAD >"$FORGE/setup-head"
  git -C "$REPO" reflog | wc -l | tr -d ' ' >"$FORGE/setup-reflog"
}
