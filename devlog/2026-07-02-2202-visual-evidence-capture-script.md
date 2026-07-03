# Visual-evidence capture hardening: reference script

Field feedback from freeasinbird-com and gh-imgup sessions drove this: 5
capture timeouts at the 2-minute shell cap, manual desktop-vs-mobile
verification three times over, and 24 full-page images in one session,
each re-read into context every later turn. The skill's capture craft was
prose-only; this session made the mechanics executable
(`skills/visual-evidence/capture.mjs`) and wove the missing guidance into
SKILL.md (timeout budgeting, viewport matrix for responsive changes, the
context-cost rationale for tight crops).

## Decisions

- **Raw CDP over Node 22's built-in WebSocket, zero npm deps.** Chosen
  explicitly for auto-approve/autonomous agent environments: one
  allowlistable local command, nothing downloaded on the capture path, no
  interactive prompts, and machine-branchable exit codes (0 ok, 1 failed
  after retries/budget, 64 usage, 69 no Chrome/Node with the prose
  fallback named). Rejected: an `npx playwright screenshot` wrapper (puts
  a package download on the critical path, the exact timeout pain being
  fixed; its CLI also can't clip to an element) and plain
  `chrome --headless=new --screenshot` flags (no real readiness waits, no
  selector wait, no clip; silent blank-image failures are worse for an
  agent than loud timeouts).
- **The script owns its deadline.** Total budget default 90s (under the
  ~120s shell cap), every wait raced against
  min(attempt deadline, global deadline), plus a watchdog at budget+2s.
  Getting killed by the shell cap is the worst agent outcome (nothing
  returned, hang indistinguishable from slowness); the script always
  exits on its own terms with a legible message.
- **Invariant 2 gate.** The script is Chrome+Node-specific, so SKILL.md
  gates it ("where headless Chrome and Node 22+ are available") and names
  the fallback: the existing prose is the specification. The script's own
  exit 69 message routes to the prose fallback too. Node 22+ matches the
  skill's existing gh-imgup assumption.
- **Always pin the color scheme** (light unless `--dark`). Live
  verification on a dark-mode Mac showed headless Chrome inherits the
  host OS theme: an unpinned "light" capture was silently dark. An
  unpinned scheme breaks the identical-conditions invariant across
  machines.
- **Clip rects clamp to the layout viewport, not the emulated device
  size.** Mobile emulation lays a viewport-meta-less page out at ~980px;
  clamping the clip to the 390px device width truncated the element
  (caught live: a 736px-wide expected crop came back 168px). The clip
  measures document coordinates and uses `captureBeyondViewport` so tall
  elements aren't cut at the fold.
- **Test matrix follows watch-review's pattern**, with host-capability
  SKIPs: launch-path cases need a WebSocket-capable Node, the live smoke
  needs a real Chrome; both SKIP (never FAIL) where absent, so the matrix
  is deterministic on any machine. Registered as a conditional
  done-check in AGENTS.md's `project:done-checks` block.

## Non-goals

- `skills/visual-evidence/evals/` untouched, no benchmark re-run: the
  script changes capture mechanics, not triggering, and the frontmatter
  description is unchanged.
- No README table change; the row's description still holds.
- No legacy-headless support (Chrome < 112); documented in the script
  header instead of carrying fallback code.

## Open questions / deferrals

- The mobile-emulation heuristic (`mobile: true` for widths ≤ 600) is a
  documented magic number; an explicit per-viewport syntax
  (`390x844@mobile`) was considered and deferred until someone actually
  needs a wide mobile or narrow desktop emulation.
- The load+grace fallback (networkIdle never fires on long-polling pages)
  is exercised only indirectly; a hanging-fetch fixture in the smoke was
  considered and deferred to keep the smoke fast.
- Re-deferred from 2026-07-01-2212 (out of this PR's scope, which runs no
  eval): the needs-human skill-creator bug report, and the
  card-text/theme-consistency assertions to add before the next
  visual-evidence eval run.
