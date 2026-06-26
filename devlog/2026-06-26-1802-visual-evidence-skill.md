# Add the visual-evidence skill

New skill owning before/after screenshot _capture craft + workflow timing_
for PRs/issues, layered on top of the external `@freeasinbird/gh-imgup`
skill which owns safe upload + the mandatory pre-upload secret review.
From `visual-evidence-skill-spec.md`.

## Decisions

- **Name `visual-evidence`** (over `before-after-shots`, `screenshot-pr`).
  Centers the trigger on the _outcome_ (review evidence for visual work),
  not the artifact — the clean separation from gh-imgup's "I have an image
  to attach." `screenshot-pr` was rejected as colliding almost exactly with
  gh-imgup's "attach an image to a PR"; `before-after-shots` undersells the
  single-after and proactive-capture cases. Description leads with concrete
  visual-change triggers to neutralize "evidence" reading as forensics.
- **Text-only examples.** Matches the markdown-only repo (other 3 skills are
  text-only); no binary assets to maintain.
- **Tool-agnostic with concrete one-liners** (Playwright, Chrome DevTools/CDP,
  OS tools), framed as host examples not requirements (invariant #2).
- **Lean proactive** — the _before_ state is perishable, so capturing late
  loses it; the skill says capture before first, reconstruct from a worktree
  if the fix already landed.

## Boundary / invariant (carried, non-negotiable)

gh-imgup's pre-upload secret review is a load-bearing security control. This
skill _reminds and defers_ to it and never restates a weaker paraphrase
(spec §8). Capture-quality (framing/crop) and secret-safety are different
axes — this skill adds the former, points at gh-imgup for the latter.

## Cross-repo pairing

Paired with a gh-imgup PR (`docs/delineate-visual-evidence-trigger`) that
narrows gh-imgup's SKILL.md trigger to the upload/attach moment, so the two
descriptions don't overlap. Two independent PRs, either can merge first.

Coupling is one-directional, by design: visual-evidence names the concrete
`@freeasinbird/gh-imgup` **CLI** as a fallback (you must run a tool to upload),
but gh-imgup refers to capture only generically — it doesn't name this skill,
since it ships independently to users who usually won't have it. Name a tool
you depend on; refer to an upstream skill generically.

## Review-round refinements

- **gh-imgup CLI breadcrumb** in _Compose & attach_: if the gh-imgup skill
  isn't loaded, the underlying tool is the `@freeasinbird/gh-imgup` CLI (`npx`,
  Node 22+); its `--help` (which ships in npm) restates the secret-review
  requirement. Names the CLI, not the skill — the SKILL.md prose isn't in the
  npm bundle, the CLI is.
- **Capture-quality validation** (new step 6, "Check the shots before handing
  off"): non-blank/non-truncated, shows the intended component+state, before/
  after comparable. A different axis from the secret review; one look at upload
  time covers both. Closes the "publish evidence you didn't eyeball" gap.

## Review fix: YAML frontmatter parse (P1, Codex)

The `description` was an unquoted (plain) folded scalar containing
`proactively: the` — a colon-then-space makes a YAML parser read it as a
mapping key, so the frontmatter fails to load (Ruby Psych: "mapping values are
not allowed in this context"). Fixed by switching to a `>-` block scalar
(matches gh-imgup), which makes the whole description literal text immune to
YAML structural characters like `:` and `#`. Verified with Psych: the plain
version fails, `>-` parses; all four skill frontmatters now parse.

**Promoted to AGENTS.md** in `2026-06-26-1845-frontmatter-convention.md` (its
own PR): `description` should be a `>-` block scalar; frontmatter must parse as
YAML. The other three skills use plain scalars but are parse-safe (no
colon-then-space) and were grandfathered; converting them is optional hardening.

## Review fix: secret-review fallback too narrow (P2, Codex)

The gh-imgup CLI breadcrumb leaned on `--help`, but that string only says
"review for secrets" — narrower than the gh-imgup skill's load-bearing review
(internal hostnames/IPs/infra, customer/PII), the categories screenshots leak
most. Relying on it made the no-skill fallback a softer paraphrase (violates
spec §8). Fixed: the secret-review bullet now enumerates the full surface
inline (credentials/tokens/keys; internal hostnames/IPs/infra; customer
data/PII; anything not meant to be shared), and the breadcrumb stops treating
`--help` as the complete checklist — it points to that full review (or reading
the gh-imgup skill) before upload. gh-imgup stays the canonical owner;
reinforced, not weakened. (Credential-leak-surface change, accepted-by-decision.)

## Deferred (separate gh-imgup issue)

A per-run **stderr** secret-review warning in the gh-imgup CLI, for agents/CI
that skip `--help`. The tool can't verify an image is clean, so the honest role
is visibility, not an attestation gate (which trains rubber-stamping). Code
change to the published tool → its own PR with tests; out of scope here.

## Verification

Markdownlint + prettier --check run before PR.
