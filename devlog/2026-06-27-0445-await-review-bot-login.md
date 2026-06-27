# await-pr-review: note the GraphQL-vs-REST bot login form

Held back during #27's convergence test (so it wouldn't muddy it), now its own
follow-up since #27 merged. While dogfooding the watcher I hit a real gotcha:
GitHub returns a bot's login as `chatgpt-codex-connector` in GraphQL but
`chatgpt-codex-connector[bot]` in REST. My summary-review check used the GraphQL
form against the REST `pulls/N/reviews` endpoint, so it silently matched nothing
— a real review would have looked like "no activity."

## Change

One clause in the step-3 author-filter guidance: mind the login form, GitHub
returns `name` in GraphQL but `name[bot]` in REST, so match the right form per
API or the filter silently matches nothing.

## Verification

Markdownlint + prettier --check clean; frontmatter still parses (`>-`).
