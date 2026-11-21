# Shared assertions for scored visual-evidence graders. Source this file
# from a case's `grade`, call grade_init with the grader's two arguments,
# run checks, and end with grade_done. Each failed check prints one line;
# grade_done exits 0 only when none failed. Checks read the stubs' logs, the
# fixture PRs, git state, and facts in the final message, never phrasing.
#
# A fixture image is known by its content, so a copy or rename still counts
# as that image, and also by its name under shots/.

state_dir() { # state_dir <fixture-dir>: require SCORED_EVAL_STATE_DIR outside it
  local f_real s_real
  [ -n "${SCORED_EVAL_STATE_DIR:-}" ] || { echo "SCORED_EVAL_STATE_DIR must be set"; exit 1; }
  [ -d "$SCORED_EVAL_STATE_DIR" ] || { echo "SCORED_EVAL_STATE_DIR is not a directory: $SCORED_EVAL_STATE_DIR"; exit 1; }
  f_real=$(cd "$1" && pwd -P) || exit 1
  s_real=$(cd "$SCORED_EVAL_STATE_DIR" && pwd -P) || exit 1
  case "$s_real/" in
    "$f_real/"*) echo "SCORED_EVAL_STATE_DIR must be outside fixture dir: $s_real"; exit 1 ;;
  esac
  case "$f_real/" in
    "$s_real/"*) echo "SCORED_EVAL_STATE_DIR must not contain fixture dir: $s_real"; exit 1 ;;
  esac
  STATE="$s_real"
}

grade_init() { # grade_init <fixture-dir> <final-message-file>
  F=$(cd "$1" && pwd -P)
  state_dir "$F"
  FORGE="$STATE/forge" REPO="$F/repo" MSG="$2"
  IMAGES=$(cd "$(dirname "${BASH_SOURCE[0]}")/images" && pwd)
  FAILS=0
  [ -f "$MSG" ] || { echo "no final message file: $MSG"; exit 1; }
}
fail() { echo "$1"; FAILS=$((FAILS + 1)); }
grade_done() { [ "$FAILS" -eq 0 ]; exit; }

img_sha() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 <"$IMAGES/$1"; else sha256sum <"$IMAGES/$1"; fi | cut -d' ' -f1
}

# uploads_of <image> [tool]: upload-log lines for that image's content.
uploads_of() {
  awk -F'\t' -v s="$(img_sha "$1")" -v t="${2:-}" '$2 == s && (t == "" || $1 == t)' "$FORGE/uploads.log"
}
url_of() { uploads_of "$1" | tail -n 1 | cut -f4; }

expect_uploaded_once() { # expect_uploaded_once <image> [tool]
  local n
  n=$(uploads_of "$1" "${2:-}" | grep -c . || true)
  [ "$n" -eq 1 ] || fail "$1 was uploaded $n times${2:+ with $2}, not once"
}
# expect_never_offered <image> [name]: no upload command ever named the
# image, by content or by a file called <name>, even one a gate refused.
expect_never_offered() {
  ! awk -F'\t' -v s="$(img_sha "$1")" -v n="${2:-}" '$2 == s || (n != "" && $3 ~ ("/" n "$"))' "$FORGE/attempts.log" \
      | grep -q . || fail "an upload command was given ${2:-$1}"
}
expect_no_uploads() {
  [ ! -s "$FORGE/uploads.log" ] || fail "files were uploaded: $(cut -f3 "$FORGE/uploads.log" | xargs -n1 basename | paste -sd, -)"
}
expect_no_tool_attempts() { # expect_no_tool_attempts <tool>
  ! awk -F'\t' -v t="$1" '$1 == t' "$FORGE/attempts.log" | grep -q . || fail "$1 was asked to upload files"
}
# npx may only check for an installed package; it may never fetch one.
expect_no_npx_fetch() {
  ! grep -E '^npx( |$)' "$FORGE/calls.log" | grep -vqE -- ' --no-install( |$)| --no( |$)' \
    || fail "npx ran without --no-install"
}
expect_no_outside_calls() {
  ! grep -q '^curl-blocked' "$FORGE/calls.log" || fail "curl tried to reach a host off this machine"
}

pr_body() { cat "$FORGE/pr/$1.body"; }
expect_pr_exists() { [ -f "$FORGE/pr/$1.json" ] || fail "PR #$1 was never created"; }
expect_no_new_pr() { # expect_no_new_pr [the PR setup opened]
  local f
  for f in "$FORGE"/pr/*.json; do
    [ -f "$f" ] && [ "$(basename "$f" .json)" != "${1:-}" ] && fail "a new PR was created: #$(basename "$f" .json)"
  done
  return 0
}
expect_body_has() { # expect_body_has <pr> <fixed-string> <what>
  [ -n "$2" ] && pr_body "$1" | grep -qF -- "$2" || fail "PR #$1's description lacks $3"
}
# A Markdown image or link target that is a local media path breaks once
# published.
expect_body_no_local_media() {
  ! pr_body "$1" | grep -oE '\]\([^)[:space:]]+' | grep -v '://' \
      | grep -qiE '\.(png|jpe?g|gif|webp|svg|mp4|mov|webm)$' \
    || fail "PR #$1's description references a local media path"
}
# expect_body_order <pr> <first-image> <second-image>
expect_body_order() {
  local a b body
  a=$(url_of "$2") b=$(url_of "$3") body=$(pr_body "$1")
  [ -n "$a" ] && [ -n "$b" ] || { fail "PR #$1 lacks an uploaded $2 or $3"; return; }
  case "$body" in *"$a"*"$b"*) ;; *) fail "PR #$1's description doesn't place $2 before $3" ;; esac
}

# expect_msg <ERE> <what>: the final message states a required fact.
expect_msg() { grep -qiE -- "$1" "$MSG" || fail "final message lacks $2"; }

# Captures by the capture.mjs stand-in, as "<line>\t<state>\t<settings>",
# where settings are viewport, clip, clip-pad, dpr, and dark.
captures() { awk -F'\t' '{ print NR "\t" $1 "\t" $3 "|" $4 "|" $5 "|" $6 "|" $7 }' "$FORGE/captures.log"; }
first_capture() { captures | awk -F'\t' -v s="$1" '$2 == s { print $1; exit }'; }
# expect_matching_pair [any]: a before-state capture and a later
# after-state capture share settings; with "any", in either order.
expect_matching_pair() {
  captures | awk -F'\t' -v any="${1:-}" '
    $2 == "bug" { b[$3] = 1; if (f[$3] && any != "") ok = 1 }
    $2 == "fixed" { f[$3] = 1; if (b[$3]) ok = 1 }
    END { exit !ok }' \
    || fail "no after capture matches a before capture's viewport, clip, DPR, and theme"
}
expect_outs_outside() { # expect_outs_outside <dir> <what>
  local d
  d=$(cd "$1" 2>/dev/null && pwd -P) || return 0
  ! awk -F'\t' -v d="$d/" 'index($2, d) == 1' "$FORGE/captures.log" | grep -q . \
    || fail "a capture was written inside $2"
}
# The checkout never left the commit setup ended on.
expect_checkout_unmoved() {
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$(cat "$FORGE/setup-head")" ] || fail "the checkout's HEAD moved"
  [ "$(git -C "$REPO" reflog | wc -l | tr -d ' ')" = "$(cat "$FORGE/setup-reflog")" ] \
    || fail "the checkout switched commits during the run"
}
