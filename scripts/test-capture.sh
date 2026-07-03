#!/usr/bin/env bash
# Validation-matrix regression test for the visual-evidence capture script.
# Offline and deterministic: CHROME points at a nonexistent binary, so any
# input that passes validation dies at the missing-Chrome preflight (exit
# 69, on Node < 22 the equivalent missing-WebSocket gate); any rejected
# input must exit 64 before Chrome discovery or launch. Launch-path cases
# use fake-binary shims, and a final live smoke runs only where a real
# Chrome and Node 22+ exist (SKIP otherwise, never FAIL). Grown one
# adversarial case per review finding; add a case with every future
# validation fix so the class stops recurring one finding at a time.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/skills/visual-evidence/capture.mjs"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }
command -v node >/dev/null 2>&1 || {
  echo "node not found on PATH; cannot run the capture validation matrix" >&2
  exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

VALID="--url https://example.invalid/x --out $TMP/out.png"

pass=0; fail=0
t() {
  expected="$1"; desc="$2"; shift 2
  CHROME=/nonexistent/chrome node "$SCRIPT" "$@" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ($got != $expected): $desc: $*" >&2
  fi
}

# Valid inputs pass validation and die at the missing-Chrome preflight (69).
t 69 "minimal valid invocation" $VALID
t 69 "viewport matrix with mobile width" $VALID --viewport 1280x720,390x844
t 69 "the full option surface" $VALID --viewport 390x844 --wait-for '#x' \
  --clip '#x' --clip-pad 8 --settle-ms 250 --dpr 1 --dark \
  --timeout-budget 30 --attempt-timeout 10 --retries 0
t 69 "chrome-flag passthrough" $VALID --chrome-flag --no-sandbox
t 69 "file URL" --url file:///tmp/fixture.html --out "$TMP/out.png"
# The 69 report must route the caller to the skill's prose fallback.
msg=$(CHROME=/nonexistent/chrome node "$SCRIPT" $VALID 2>&1 >/dev/null)
case "$msg" in
  *prose*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL: exit-69 message must mention the prose fallback: $msg" >&2 ;;
esac

# Parser: options without values are usage errors; unknown options too.
t 64 "no arguments at all"
t 64 "missing --url" --out "$TMP/out.png"
t 64 "missing --out" --url https://example.invalid/x
t 64 "trailing bare --url" --out "$TMP/out.png" --url
t 64 "trailing bare --chrome" $VALID --chrome
t 64 "unknown option" $VALID --bogus x
t 64 "--dark takes no value" $VALID --dark on

# --url: http, https, or file only, and must parse as a URL.
t 64 "url ftp scheme" --url ftp://example.invalid/x --out "$TMP/out.png"
t 64 "url javascript scheme" --url 'javascript:alert(1)' --out "$TMP/out.png"
t 64 "url data scheme" --url 'data:text/html,hi' --out "$TMP/out.png"
t 64 "url unparseable" --url '://nope' --out "$TMP/out.png"

# --out: .png in a directory that exists.
t 64 "out without .png" --url https://example.invalid/x --out "$TMP/out.txt"
t 64 "out directory missing" --url https://example.invalid/x --out "$TMP/nodir/out.png"

# --viewport: comma list of WxH, each dimension 16-8192.
t 64 "viewport missing height" $VALID --viewport 1280
t 64 "viewport dangling x" $VALID --viewport 1280x
t 64 "viewport missing width" $VALID --viewport x720
t 64 "viewport zero width" $VALID --viewport 0x720
t 64 "viewport three dims" $VALID --viewport 1280x720x2
t 64 "viewport non-numeric" $VALID --viewport abcxdef
t 64 "viewport empty list item" $VALID --viewport 1280x720,
t 64 "viewport absurd width" $VALID --viewport 99999x1
t 64 "viewport below minimum" $VALID --viewport 8x8

# --dpr: integer 1-4.
t 64 "dpr zero" $VALID --dpr 0
t 64 "dpr five" $VALID --dpr 5
t 64 "dpr fractional" $VALID --dpr 1.5
t 64 "dpr non-numeric" $VALID --dpr abc

# Timing knobs: positive integers (retries and clip-pad: non-negative).
t 64 "budget zero" $VALID --timeout-budget 0
t 64 "budget negative" $VALID --timeout-budget -5
t 64 "budget non-numeric" $VALID --timeout-budget abc
t 64 "attempt-timeout zero" $VALID --attempt-timeout 0
t 64 "settle zero" $VALID --settle-ms 0
t 64 "settle negative" $VALID --settle-ms -1
t 64 "retries negative" $VALID --retries -1
t 64 "retries non-numeric" $VALID --retries abc

# Selector options: non-empty, and --clip-pad only rides with --clip.
t 64 "empty wait-for" $VALID --wait-for ''
t 64 "empty clip" $VALID --clip ''
t 64 "clip-pad without clip" $VALID --clip-pad 5
t 64 "clip-pad negative" $VALID --clip '#x' --clip-pad -1

# --chrome-flag values must look like flags.
t 64 "chrome-flag without dash" $VALID --chrome-flag no-sandbox

# Launch-path failures must fail fast (exit 1 inside the budget), never
# hang into a shell cap. Needs a WebSocket-capable Node (22+); on older
# Node the gate above already covers these inputs, so SKIP.
if node -e 'process.exit(typeof WebSocket === "function" ? 0 : 1)'; then
  printf '#!/bin/sh\nexit 1\n' > "$TMP/dead-chrome"
  printf '#!/bin/sh\nsleep 60\n' > "$TMP/mute-chrome"
  chmod +x "$TMP/dead-chrome" "$TMP/mute-chrome"
  for shim in dead-chrome mute-chrome; do
    CHROME="$TMP/$shim" node "$SCRIPT" $VALID --timeout-budget 3 >/dev/null 2>&1
    got=$?
    if [ "$got" -eq 1 ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL ($got != 1): $shim launch failure must exit 1 fast" >&2
    fi
  done
else
  echo "SKIP: launch-path cases (Node without built-in WebSocket)"
fi

echo "capture validation matrix: $pass passed, $fail failed"

# Live smoke: end-to-end capture against a local fixture, only where the
# script's own discovery finds a real Chrome (and Node has WebSocket).
# A missing browser SKIPs; a present browser that fails to capture FAILs.
cat > "$TMP/fixture.html" <<'EOF'
<!doctype html>
<html><head><style>
body { margin: 0; font-family: sans-serif; }
#target { width: 300px; margin: 40px auto; padding: 20px; border: 2px solid steelblue; }
#late { display: none; }
</style></head>
<body>
<div id="target"><h2>Card</h2><p>Fixture card body.</p><div id="late">Late content</div></div>
<script>setTimeout(() => { document.getElementById('late').style.display = 'block'; }, 300);</script>
</body></html>
EOF

png_dims() {
  node -e 'const b = require("fs").readFileSync(process.argv[1]); console.log(b.readUInt32BE(16) + "x" + b.readUInt32BE(20));' "$1"
}

env -u CHROME node "$SCRIPT" --url "file://$TMP/fixture.html" --out "$TMP/smoke.png" \
  --viewport 1280x720,390x844 --dpr 1 --wait-for '#late' --timeout-budget 60 >/dev/null 2>&1
got=$?
if [ "$got" -eq 69 ]; then
  echo "SKIP: live smoke (no Chrome or no Node 22+ on this host)"
  [ "$fail" -eq 0 ]
  exit
fi
smoke_pass=0; smoke_fail=0
if [ "$got" -ne 0 ]; then
  smoke_fail=$((smoke_fail + 1))
  echo "FAIL: live smoke capture exited $got" >&2
else
  for want in "$TMP/smoke-1280x720.png:1280x720" "$TMP/smoke-390x844.png:390x844"; do
    f="${want%%:*}"; dims="${want##*:}"
    if [ -f "$f" ] && [ "$(png_dims "$f")" = "$dims" ]; then
      smoke_pass=$((smoke_pass + 1))
    else
      smoke_fail=$((smoke_fail + 1))
      echo "FAIL: expected $f at $dims, got $([ -f "$f" ] && png_dims "$f" || echo missing)" >&2
    fi
  done
  # A clipped capture must be meaningfully smaller than the viewport.
  env -u CHROME node "$SCRIPT" --url "file://$TMP/fixture.html" --out "$TMP/clip.png" \
    --dpr 1 --wait-for '#late' --clip '#target' --timeout-budget 60 >/dev/null 2>&1 \
    && clip_w=$(png_dims "$TMP/clip.png" | cut -dx -f1) && [ "$clip_w" -lt 640 ]
  if [ $? -eq 0 ]; then
    smoke_pass=$((smoke_pass + 1))
  else
    smoke_fail=$((smoke_fail + 1))
    echo "FAIL: clipped capture missing or not tighter than the viewport" >&2
  fi
fi
echo "capture live smoke: $smoke_pass passed, $smoke_fail failed"
[ $((fail + smoke_fail)) -eq 0 ]
