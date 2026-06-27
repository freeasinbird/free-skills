# Re-scope self-review; add risk-gated fresh-context review

Follow-up to the methodology question: is same-context self-review useful, or
should substantive review come from a fresh-context subagent? Researched both
vendors (Claude + Codex) to back the call. Stacked on `feat/review-fix-the-class`
(#24) since it edits the same `pull-requests` review block.

## What the research said

- **Anthropic** directly backs fresh-context review: the Claude Code subagents
  docs recommend a subagent for unbiased review because it "doesn't inherit the
  assumptions, context, or blind spots from the primary conversation"; the
  evaluator-optimizer and multi-agent patterns separate generation from
  evaluation (multi-agent beat single by ~90% on high-value tasks, but ~15×
  tokens — value-gated).
- **OpenAI/Codex** ships review as a separate pass (P0/P1 focus, whole-repo
  context, runs before human review, reads `AGENTS.md` review guidelines) — but
  its prompting guides favor _in-context_ self-verification and its LLM-as-judge
  cookbook uses the same model as judge. So "fresh context beats self" is
  Anthropic-backed + Codex-product-design-implied, not an OpenAI prescription.

## Change (canonical-sections.md + AGENTS.md, byte-identical)

- **Re-scoped the self-review bullet** to mechanical hygiene (stray hunks, scope
  creep) — works via representation shift, explicitly _not_ a substantive-QA
  substitute.
- **Added "substantive critique needs fresh, ideally non-self eyes"** with the
  independence ladder (self < same-model subagent < different-vendor bot /
  human); names the external bot / human as the load-bearing pass.
- **Added optional, risk-gated pre-push fresh-context review** — refute-first,
  diff+intent only, same-model = partial independence, token-costed, skip
  trivial. Main payoff: converge before the external bot (ties to #24).
  Review-round fix (Codex P2): since this canonical text is copied into
  downstream AGENTS.md files, **gated the subagent mechanism on the platform
  supporting delegation** and documented the fallback (skip / external / human;
  never emit steps the agent can't perform) — honors the platform-agnostic
  invariant. Fittingly, fresh-context Codex caught a portability flaw same-
  context self-review missed — the PR's own thesis in action.

## Decision

Did **not** mandate subagent review: we already receive Codex (different-vendor,
top of the ladder), so a same-model self-spawned reviewer is weaker than what we
get — positioned as optional/pre-filter, strongest where no external reviewer
exists. Avoided overselling per the OpenAI gap.

## Verification

Markdownlint + prettier --check clean; the 3-bullet block diffs identical across
both files.
