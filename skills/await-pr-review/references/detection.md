# Detection: the prose specification

`watch-review.sh`, bundled alongside `SKILL.md`, is the **canonical
executable form** of review-activity detection; prefer it over re-deriving
anything here. This file is the prose specification the script implements.
Read it in two situations: the script cannot run (no `gh`, no shell) and you
must hand-roll the watch, or the project has no recorded reviewer and you
must detect one (see "Detecting an unrecorded reviewer" below).

## The snapshot query

Record the baseline snapshot with one GraphQL call. Capture **three** things,
because they are separate connections: top-level **reviews** (a bot can
complete a review with a summary/approval and _no_ inline findings: that
round shows up only here, not under threads), the inline **review threads**,
and the PR-description **reactions**, where some reviewers signal review
status out of band (see the status signals in SKILL.md step 3). Snapshot the
latest reviewer review time, the current thread IDs, and the reviewer's
reactions:

```sh
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  reviews(last:20){nodes{author{login} submittedAt state}}
  reviewThreads(first:50){nodes{id isResolved comments(last:1){nodes{author{login} createdAt}}}}
  reactions(last:20){nodes{content createdAt user{login}}}}}}' \
  -F o=OWNER -F r=REPO -F n=PR
```

Note `comments(last:1)`: the **newest** comment per thread, not the first; a
reviewer reply on an _existing_ thread is the latest comment, and using the
oldest would miss it.

## Time, not enumeration; pages, not windows

This enumerate-and-diff snippet is illustrative but edge-prone (paging,
first-vs-last comment, author filtering), so **prefer time, not
enumeration**: treat a round as arrived when the configured reviewer has a
`submittedAt` (from `reviews` above), any review-comment `createdAt`, or a
status-signal reaction `createdAt` (SKILL.md step 3) _after_ the baseline.
That single timestamp comparison sidesteps every snippet edge except one,
and it applies to **every windowed connection in the snapshot**
(`reviews(last:20)`, `reviewThreads(first:50)`, `reactions(last:20)`): a
single page is a window, not the collection, so enough newer activity by
other authors can push the item you are looking for out of it. When
detecting, read each source through a **paged** feed until you are past the
baseline: on REST,
`gh api "repos/OWNER/REPO/pulls/PR/comments?per_page=100&page=N"` and the
matching `pulls/PR/reviews` and `issues/PR/reactions` endpoints (authors
there carry the `name[bot]` form; the login-form rule is in SKILL.md
step 3); on GraphQL, cursor-page with `pageInfo{hasNextPage endCursor}` /
`after:`. Reach for the full thread set only when you actually need it
(e.g. to resolve threads).

## Detecting an unrecorded reviewer

The scan procedure behind SKILL.md step 2's detection fallback:

- Scan recent PRs for a bot-authored review (`gh pr list --state all
--limit 20 --json number`, then each PR's reviews); a `Bot`/`App` author
  that submitted a _review_ is the reviewer (CI bots post checks/statuses,
  not reviews).
- Once reviews identify the bot, scan recent PRs' description reactions by
  that same bot too, and record any status signals you observe; match the
  reactions on the **reaction form** of its login (the plain review login
  plus the `[bot]` suffix for an App bot; login-form rule in SKILL.md
  step 3), since the review-author form matches no reactions. A reviewer
  that posts reviews only on findings rounds marks clean passes out of
  band, and a record missing the clean-pass signal still burns the full
  wait cap on every clean PR.
- If no PR carries a bot review at all, check PR-description reactions too:
  a bot reacting on PRs shortly after they open, recurring across PRs, is a
  clean-pass-only reviewer signalling out of band, and its reaction
  `user.login` yields the login: for an App-based bot, in the `name[bot]`
  form (strip the suffix for the review-author form and record both); a
  reviewer running as a regular machine-user account reacts under its plain
  login. Either way this yields both the gate (a reviewer exists) and the
  login to match.

The decision rules that govern this scan (multi-bot ambiguity, the
trigger-is-not-revealed caveat, when to fall through or hand back) stay in
SKILL.md step 2; this file only carries the mechanics.
