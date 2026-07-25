# await-pr-review: the reviewer login rule splits by API, not by item

Issue #77's audit findings, worked as one unit. Two of them turned on the
same misconception, and one of the issue's own prescribed fixes did not
survive contact with the API.

## The axis

Chose "the field name and the login form each follow the API you query"
over the skill's previous "`author.login` for reviews, `user.login` for
reactions". The old rule is true inside GraphQL and false everywhere else:
REST review, review-comment and reaction payloads all carry `user.login`
and no `author` field at all. Since `references/detection.md` prescribes
the REST feeds for paging, an agent hand-rolling the watch (no `gh`, no
shell, or a second bot doing the filtering) followed the prose onto a
field that does not exist, matched zero, and reported "no review arrived":
the silent-no-match failure the same file warns about two steps later. The
2026-06-27 bot-login note already had the form rule right ("match the right
form per API"); the field rule was written on the wrong axis beside it.

## Rejected: splitting review matching onto a second login

Issue #77 finding 5 asked for review/comment matching to use a login
derived independently of `--reaction-login`, because all three REST filters
keyed off the reaction flag while the normalized `$LOGIN` was dead. The
diagnosis is right; the prescription was rejected (user decision, after the
alternatives were laid out).

The watcher reads REST only, and REST hands back one login form for all
three sources: `name[bot]` for an App bot, the plain login for a machine
user. There is no REST case where a reviewer's reaction identity differs
from its review identity, so two independently settable logins would only
add a way to set one and forget the other, which fails by matching zero
reviews in silence: the exact class the issue exists to close, reintroduced
by its own fix. The flag was never reaction-scoped; it was misnamed.
Renamed it `--rest-login`, documented as the form matched against all three
sources, with `--reaction-login` kept as an alias.

Revisit when a reviewer is observed whose reaction author differs from its
review author on REST, or when the watcher grows a GraphQL read (where the
field genuinely splits and a single login no longer suffices).

## polls_ok counts polls that observed all three sources

A count query failing on every poll skipped every scan silently and exited
`CAP_EXPIRED` with a payload identical to a quiet PR. Chose to count the
polls that scanned all three signal sources, rather than the polls whose
count query returned: a poll that fetched the totals but could not scan
them establishes no absence either, so counting it would report watching
that never happened. `polls_ok:0` therefore means "could not watch", which
is what the caller must say instead of "no review arrived".

The first cut of this counted a poll once its review and comment scans
completed, before the reactions scan ran, which review (#86, P2) caught: a
persistently failing reactions endpoint would then report `polls_ok` above
zero, and a reviewer whose clean pass leaves only a 👍 reaction would read
as a quiet PR. Accepted, because it is the same defect one source over.
The counter's meaning is "this poll saw the whole PR", so a source that
never scanned is not a source that was quiet, and the conservative
direction (undercount, report "could not watch") is the safe one: the cap
already backstops a watcher that gives up too readily, while nothing
backstops a false "no review arrived".

## A count cannot express coverage; the last poll can

The next review round (#86, P2 again) found the same class a third time: an
early successful poll followed by persistent failures still reported
`polls_ok` above zero, so the caller called a run quiet whose last usable
observation was 25 minutes stale. Per this repo's escalation rule, a second
member of a class means the boundary was drawn too narrow, so the fix
widened instead of patching the arithmetic once more.

The property that settles it: both scanners restart at page one (or at the
totalCount-derived last page) and terminate on the fixed baseline, so every
poll rescans the entire window from the baseline to now. Coverage is
therefore a property of the **last** successful poll alone. A count of
successes cannot express it, which is why patching the count kept
producing findings; and a count of failures would be actively wrong, since
a mid-run blip followed by a success costs nothing.

Added `last_poll_ok`, and kept `polls_ok` only for the distinction it
genuinely carries: never-observed (`polls_ok:0`) versus observed-then-blind.
The caller contract is now one rule, "trust a quiet report only when
`last_poll_ok` is true".

Revisit when the watcher stops rescanning from the baseline each poll (an
incremental or cursor-resumed scan), since coverage would then depend on
the whole poll history again and one boolean could no longer express it.

## Invoke the watcher by path, from the PR's checkout

The first cut of the worked invocation said to run the script from the
skill's own directory, which review (#86, P2) caught: `--repo` defaults to
the repository the working directory belongs to, so from a globally
installed skill that default finds no repository, or silently resolves the
installing repository and watches its PR N. Evidence that this is not
hypothetical: dogfooding this very PR, the agent followed the instruction
and ran `cd .../skills/await-pr-review && ./watch-review.sh`, which
resolved correctly only because that directory happened to sit inside the
target repository. `agent-setup` already documented the correct shape (an
absolute path, plus an explicit warning that relative arguments resolve
from the caller's directory); this skill now matches it.

Follow-up: #87 tracks the same shape in visual-evidence's `capture.mjs`
invocation, left out of this PR as out of scope.

## The test matrix was structurally blind

The 41-assertion matrix returned the _post-jq_ line from its page shims, so
`JQ_COMMENTS`, `JQ_REVIEWS` and `JQ_REACTIONS` never executed and no
filter-semantics defect could fail a test. Verified rather than assumed:
against a mutant watcher whose filters read `.author.login` (matching
nothing on REST), the old matrix passes 41/41 while the reworked one
reports 15 failures. It serves raw JSON fixtures and runs the caller's `--jq`,
which costs a `jq` dependency for the detection half; it degrades to a
loud skip where `jq` is absent, since this repo runs the matrix locally and
has no CI.

Revisit when the watcher grows a code path that `gh`'s embedded gojq and
`jq` disagree on; today's filters use only constructs the two share.
