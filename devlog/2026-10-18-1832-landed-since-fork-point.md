# Read What Landed From the PR's Fork Point

Chose to start `landed-since.sh`'s range at the common ancestor of the
default-branch parents of every commit the PR has had over proving which head
was pushed first. The planner made this call on issue #312, and the owner
didn't veto it before implementation started. It replaces a decision frozen in
`2026-10-18-1027-land-approved-prs.md`.

## Decisions

- **The fork point, not the first head.** The range needs the base the PR
  forked from, and every head the PR has had carries it. A commit's parent
  that isn't itself in the PR's lineage is on the default branch, and the
  common ancestor of all such parents across all heads is the original fork
  point. A merge-in only adds a candidate and never removes the root
  commit's, so a merge of a newer default branch can't move the range
  forward.
- **Rejected: prove the first head.** Nothing on the forge records the head at
  PR open. Fast-forward pushes leave no timeline event, workflow runs don't
  say whether `opened` or `synchronize` triggered them, and the repository
  Events API keeps only 90 days or 300 events. A script that stopped unless it
  proved the first head would stop on almost every PR.
- **The common ancestor, not the farthest candidate.** The plan picked the
  candidate with the most commits behind the tip. That means "oldest" only
  while the candidates lie on one line. A branch cut from a side branch that
  merged later has a candidate with fewer commits behind the tip than an older
  first-parent one, and the farthest candidate's range skipped landings. `git
merge-base --octopus` over the candidates is an ancestor of each, so its
  range covers every candidate's; on one line it is the oldest.
- **Every head the PR has had.** The current head's lineage comes from
  `pulls/N/commits`; each force push's replaced head comes from
  `compare/<tip>...<before>`. The compare runs against the fetched tip's OID,
  not the branch name, so every candidate is reachable from the tip the run
  reads up to.
- **Candidates off the first-parent line are read as of their landing.** A
  candidate can be on the default branch but off its first-parent line, as
  when another PR landed a replaced head, or a prefix of the current or a
  replaced head. Its own merge-in may have absorbed landings, so a range
  from it skips them. The script replaces such a candidate with the parents
  of the commits it brought onto the line, read from the checkout: those not
  reachable from the first parent of the oldest first-parent commit that
  contains it. It repeats until every candidate is on the line. Each
  replacement is an ancestor, so the range only widens.
- **Before-commits from GraphQL.** The REST timeline's force-push `commit_id`
  is the after-commit (on PR 311 it equals GraphQL `afterCommit` for all five
  force pushes), so only GraphQL's `beforeCommit` names the replaced head.
  Pagination follows `pageInfo`: on PR 311, `totalCount` with the type filter
  reported 32 while 5 nodes matched.
- **Fail rather than start later.** A null `beforeCommit` stops
  `original-base-unknown`. A list shorter than the forge's own count, a list
  without its own head, a PR over the 250-commit list cap, an unparseable OID,
  or a candidate that isn't an ancestor of the fetched tip is `LOOKUP_FAILED`.
  Each of these could otherwise drop the oldest candidate.
- **No CI dependence.** The script no longer reads workflow runs, so a
  repository without `pull_request` workflows is readable and a rebase before
  the first run resolves to the pre-rebase fork point.

## Changed Assumption

The frozen decision "The first head is unknown when a force-push precedes the
earliest CI run" assumed the range needed the first head. It doesn't once the
commit graph supplies the fork point, so that stop and the
`first-head-unknown` name are gone.

## Forge Evidence

- **PR 311's replaced head 5685854:** its compare lists six commits whose root
  parent 53c06f2 equals the compare's merge base. The live run reports `from`
  53c06f2 across 6 heads.
- **PR 266:** the root commit's parent effcb6d sits 68 commits behind the tip
  at bdc7885, older than the merge-in parent at 66. The live run reports
  `from` effcb6d across 2 heads.
- **Compare pagination:** `gh api --paginate` follows compare's `Link`
  headers; at `per_page=2` it returned three pages carrying all six commits.

## Refute-First Findings

A fresh-context reviewer tried to break the fork-point choice with fixture
mutations, under bash 5 and macOS bash 3.2 with BSD awk.

- **Confirmed, fixed: side-branch candidates.** A PR cut from a side branch's
  tip with a merge-in of c1, or a force-pushed head cut from it, started the
  range at c1 or c2 and skipped landings. The common-ancestor choice above
  fixes both, and the matrix pins them.
- **Confirmed, fixed: a list for another head.** A force push between the PR
  read and the commit-list read let a list without the PR's head pass, and a
  compare without its own head, or an empty one whose merge base wasn't its
  head, passed too. Each lineage must now contain its head.
- **Allowed by decision: malformed forge OIDs.** A parent "sha" with an
  embedded space or newline could inject a candidate, and a commit reported
  with an empty parent list adds none. Both need GitHub to return a value that
  isn't a git object's real hex OID or parent list, which no PR author
  controls.
- **Allowed by decision: duplicate force-push events.** A head pushed away
  twice gets one compare, but `heads` counts both events. `heads` counts the
  heads the PR has had, not distinct OIDs.
- **Confirmed in review, fixed: candidates off the first-parent line.**
  The pass checked a before-commit on the default branch and found no
  failure. Review then showed that a replaced head, or a prefix of a head,
  that had merged the default branch in and then landed through a merge
  started the range at itself and skipped what the merge-in absorbed. The
  decision above fixes the class, and the matrix pins the full-head and
  prefix cases.
- **Allowed by decision: a head that landed by fast-forward.** A replaced
  head pushed straight onto the first-parent line looks like one of the
  default branch's own commits, so it stays a candidate and the range
  excludes it. No GitHub merge method fast-forwards, and the graph can't
  tell such a head from a direct commit.
- **Allowed by decision: a fork point in unrelated history.** A PR cut from
  history merged with `--allow-unrelated-histories` has no ancestor on the
  first-parent line, so it is `LOOKUP_FAILED` and handed back.
- **Confirmed, fixed: quadratic lookup.** BSD `grep -F -f` costs patterns
  times lines; finding where a candidate landed now uses an awk hash.
- **Disproved by checks:** two roots with different parents, uppercase or
  null OIDs and counts, a padded list with duplicate commits, a commit shared across
  lineages, a compare commit without a parents key, a PR reporting no commits
  while its head is off the default branch, repeated T and M lines across
  compare pages, and bash 3.2.
- **Acceptable, fails loud:** a PR from a fork. Compare takes bare OIDs, so
  any forge read error is `LOOKUP_FAILED`; this wasn't checked against a real
  fork PR.

## Revisit When

- GitHub exposes the head at PR open, or the 250-commit cap on
  `pulls/N/commits` changes.
- The forge stops keeping force-pushed-away commits long enough for an
  approved PR's read, which would turn the null-before stop into the common
  case.
