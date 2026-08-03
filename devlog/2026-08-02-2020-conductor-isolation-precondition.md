# Checkout isolation is a precondition to establish, not a gate to check

Observed live in a Codex (app) session on an unrelated repo's PR 478: the
agent declined conductor ownership with "the review skill's
isolated-conductor gate is not available in this shared checkout" and ran
the bounded foreground watcher instead, blocking its own thread for the
wait. Subagents, write access, and a shell were all available to it; the
only missing piece was an isolated checkout, which it could have created
with `git worktree add` at any point. When the user pointed this out, the
agent agreed immediately and switched, having already paid for one
watcher.

The misread was invited by the skill text, not invented by the agent.
Three properties of the pre-change wording produced it:

- **False parallelism at the routing decision.** The step-0 gate listed
  "checkout isolation or exclusivity for the PR branch" alongside three
  genuine platform capabilities (write-capable delegation, resumability,
  completion re-entry). Four grammatically parallel items read as four
  things the platform either extends or withholds.
- **A passive framing instruction.** "Map the gate against what the
  platform actually offers" told the agent to inventory features, which
  is the correct move for three of the four items and the wrong move for
  the fourth.
- **The Claude Code example generalized wrongly.** "Worktree isolation at
  spawn satisfies the checkout grant" reads as a native spawn-time
  feature. A platform without that spawn parameter reads itself as
  lacking the grant, though plain `git worktree add` was always the
  platform-agnostic path (AGENTS.md's own Branches section already names
  it).

The escape hatch existed ("otherwise grant it exclusivity over the shared
checkout") but sat ~670 lines below the routing decision, at the end of a
step-4 paragraph. A scanner routes at step 0 and never reaches it.

## Decision

Split the conductor gate by kind wherever it appears: three platform
capabilities you check, and one precondition you establish. Checkout
isolation is stated as establish-first with three ordered routes (native
mechanism, plain `git worktree add` or a clone, declared exclusivity over
the shared checkout), and the observed bad inference is named and refuted
in the text: a shared default checkout is never itself a reason to fall
back, because it is the starting state isolation is established from.
Naming isolation as the unmet gate now requires having found all three
routes unavailable.

Applied in four places so the skim layer stops carrying the old
parallelism: the frontmatter description, the step-0 ownership decision,
the step-4 gate paragraph, and the platform-support ladder bullet (where
isolation is removed from the ladder entirely, since a ladder rung is by
definition a grant the platform extends or withholds).

The establish-isolation paragraph names the route in prose, a detached
worktree at the PR head or a separate clone, and prescribes no command
at all. Naming the route is what refutes the misread (isolation is
establishable wherever there is a shell); every mechanic behind it is a
separate work unit, below.

**A runnable command was tried here and withdrawn.** An intermediate
revision prescribed the sequence, reasoning that a named route which
cannot resolve its own head is wrong rather than merely incomplete.
Three real failures back that reasoning, verified on git 2.50.1:
`git worktree add` resolves its commit-ish locally, so it fails on a
host-resolved head the checkout has never fetched; a bare force-push
with a pinned lease from the detached checkout supplies no refspec and
fails for want of a branch; and a fork head fetched from the base
repository fails or retrieves a same-named base branch.

**The reasoning is sound and the conclusion still went the other way.**
Prescribing the sequence drew six further review rounds, and the round
that followed the last of them raised a leading-hyphen branch name
parsed as a fetch option: the hardening surface of a runnable command
is unbounded in prose, and each clause added invites the next finding.
That is this skill's own signal that prose is re-deriving a program, so
the three failures above are recorded here as evidence for why the
mechanics are the follow-up's tested script, not as clauses to patch
into this unit. Owner's call, 2026-08-03, over the intermediate
revision's boundary.

## Split into two work units

The original PR carried this reclassification and, appended to it, a
lifecycle script that grew out of prescribing the route. In eight review
rounds the reclassification drew zero findings and the script drew all
of them, so the owner's call (2026-08-03) was to split, and let each be
judged as what it is. The reclassification is this note's decisions
above and below; the isolation script, the prescribed lifecycle, and
this note's lifecycle sections are the stacked follow-up.

## Verification finding: the naive worktree command fails here

The obvious command to prescribe, `git worktree add <path> <branch>`,
fails in precisely the situation the rule addresses. The shared checkout
is normally sitting on the PR branch, and git refuses to check that
branch out in a second worktree ("is already used by worktree at ...",
exit 128, git 2.50.1). Prescribing it would have handed the agent a
failing command at the moment it was deciding whether isolation was
available, re-triggering the same fallback by a new route.

The skill therefore prescribes `git worktree add --detach <path>
<pr-head-sha>`, with the conductor committing on the detached HEAD and
pushing `HEAD:<branch>` under the pinned lease. Both the detached add
and the pinned force-push were exercised against a local bare remote on
git 2.50.1 before the wording was committed. Detaching at the step-1
expected head also satisfies the existing pre-write alignment check by
construction.

Prescribing a concrete isolation route turned out to pull a whole
lifecycle behind it, which three Codex rounds (six P2 findings) mapped
out. The findings were one class: **a lifecycle command is only correct
for the route and checkout state it runs against**. Round 3 is what
settled the medium: it caught that `--ff-only` refuses after any fold,
which is the _normal_ end of a review exchange, so the prose rule would
have failed on the common path while reading correct. That is the
skill's own "the instructions omit a clause rather than the program has
a bug" signal, and the owner's call (Ben, mid-exchange) was to stop
clause-patching and move the lifecycle into a tested script.

`skills/await-pr-review/conductor-isolation.sh` now owns it, with
`scripts/test-conductor-isolation.sh` as its matrix (one adversarial
case per finding, each against real local repositories, no network; a
count here would only go stale a round later). The skill prose keeps the
_decision_ (establish isolation, three routes, shared checkout refuted)
and points at the script for the _mechanism_. The obligations it
encodes, all verified on git 2.50.1:

- **Setup.** Fetch the expected head before creating the checkout, or
  `git worktree add` dies on `fatal: invalid reference`. Fetch it from
  the **base** remote: a fork PR's head lives in the fork while
  `refs/pull/<n>/head` is served by the base repository, so the pull-ref
  form is the only one covering both cases.
- **Teardown.** Match the route: `git worktree remove` for a worktree;
  for a separate clone, which worktree removal rejects outright
  (`fatal: '.' is a main working tree`), realign the branch but report
  `removed=manual` rather than deleting a directory the script does not
  own; nothing to remove under the exclusivity route.
- **Which remote.** The pull ref comes from the base repository, but the
  branch the conductor pushes lives wherever the PR head lives. Fetching
  that branch from the base fails for a fork PR, or silently realigns to
  an unrelated same-named base branch, so setup records the head repo's
  URL and teardown fetches from it. A teardown with no setup record (the
  clone the operator made by hand) has nothing to fetch from but
  `--remote`, so on a fork PR that flag carries the fork: verified, the
  omission realigns the primary branch onto the base's decoy and reports
  it as a clean fast-forward.
- **Realignment.** A detached worktree or clone pushing `HEAD:<branch>`
  leaves the primary checkout's local branch on the pre-review SHA, so
  the next edit there silently drops every review fix. Three cases, not
  one: fast-forward where the conductor only added commits, a direct ref
  move where it folded and the branch still sits exactly where setup
  found it (proving it gained nothing unseen), and a refusal otherwise.
  `--ff-only` guards neither cleanliness nor rewrites: with unrelated
  uncommitted edits present it advances HEAD underneath them rather than
  refusing.

Three further findings came from executing rather than reviewing, which
is the argument for the medium. Path comparison had to normalize
(`pwd -P` plus the parent), since `"$(pwd)/$arg"` yields
`/repo/primary/../w` where git prints `/repo/w`, and macOS `/var` vs
`/private/var` fails the same way. The cleanliness guard belongs only
on the checked-out case, since moving a ref no working tree holds
cannot disturb one, while a _third_ worktree holding the branch must
block. And host resolution built a malformed API path, because
`${REPO:-{owner}/{repo}}` is not the expansion it looks like: the brace
in `{owner}` closes it early.

That third one is the instructive failure. It survived the first matrix
because host resolution was the one path every case skipped via
`--head`/`--branch`, so the suite was thorough about git and blind
about `gh`. What caught it was running the script against this PR at
the owner's suggestion, on the first invocation. **A matrix that stubs a
dependency proves nothing about the code that calls it**, so the
end-to-end run is not a nicety after a green suite; it is the only thing
that exercises the seams the fixtures replaced.

The whole lifecycle then ran against PR 114 itself: setup while the
primary checkout held the branch, a fold and force-push from the
detached worktree, and `teardown --realign` taking the rewritten branch
back to the pushed head, which is precisely the case `--ff-only` cannot
serve.

## The sibling gate: permission, resolved by attempting

The review exchange surfaced that the conductor gate's _first_ clause has
the same defect this note's main decision fixed in its fourth. "Write-capable
delegation **permitted without asking**" asks the agent to predict a
permission, exactly as the old isolation wording asked it to check for a
checkout, and a prediction of "not permitted" is unfalsifiable: nothing
later contradicts it, so the exchange silently runs in the expensive
context forever.

The evidence was this session. Delegation was simultaneously forbidden by
injected session guidance, permitted by the owner's own global
conventions ("one subagent for exploration or review is normal"), and
routinely exercised by other skills in the same session. The agent
followed the strictest reading and never tested it, paying five review
rounds of full-context replay for a permission it never checked. The
owner's observation that authorization "is inconsistent, and some of the
time it _is_ authorized" is the general case, not this session's quirk:
authorization is per-pathway, not per-capability.

**Decision: attempt once and route on the outcome.** A refusal is cheap,
observable, and recorded as "refused when attempted"; a prediction is
none of those. Ambiguity resolves toward attempting. The carve-out stays
narrow: a policy that plainly forbids the spawn, where attempting is the
violation rather than the test.

**A policy that merely conditions the spawn is not that carve-out; it is
the paradigm case for attempting.** Rejected: widening the carve-out to
cover approval-conditioned policies, tried and reversed. The falsifiable
evidence is this
work unit: session guidance carried "do not call the delegation tool
unless the user requested it", which reads as forbidding, and on both
occasions it was actually attempted, in two separate sessions, the spawn
went straight through with no permission prompt and no refusal. The first
misread cost six review rounds of main-context replay, the second one
round. Widening the carve-out would route exactly that class to the
fallback, reinstating the prediction this decision exists to remove.

**That directive was a shipped default of one platform configuration,
not one operator's setup.** On the configuration this work ran under,
the agent platform's own system prompt told the agent not to delegate
unless the user asked, while the same session's project conventions and
bundled skills exercised delegation routinely. No local configuration
reconciled them: the text was absent from the user's settings, the
user's global instructions, this repo's AGENTS.md, and the installed
plugins, and whether it appeared was decided by the platform rather than
by the operator. An agent that predicts the permission therefore
mispredicts by construction there, for every user of that
configuration. Not claimed: that this holds for other models, other
sessions, or other versions; the specific configuration was checked
once, at one point in time, and a platform can change it at any moment
without notice.

That is also the direct refutation of the review finding. The policy it
would have honored as a no-spawn case is the default in that
configuration, so honoring it disables conductor ownership there
entirely. The skill prose stays platform-agnostic per the architecture
invariant; this note carries the platform specifics.

Stated at both altitudes, for the reason the main decision was: the
ownership call happens at step 0, so a rule reachable only from step 4,
some 700 lines below, is unread by exactly the agents that route without
it. Step 0 carries the instruction, step 4 the argument and the
carve-out.

**Not the ask-once alternative**, which an earlier draft of this note
carried and the owner rejected: converting the unmet carve-out into a
prose question spends the turn this decision exists to save and returns
policy rather than the approval itself. The turn is better spent on the
next permitted path, which the user can override at any point.

Rejected: leaving this to the operator's configuration. The owner can
grant a standing permission, and probably should, but a skill whose
routing collapses when two authorization signals disagree is defective
independent of any one operator's setup, and disagreement is the normal
condition.

## A clean bot pass is not convergence

Round 7's Codex review posted no inline findings on first read, and the
exchange looked quiet. It was not: four findings (three P1) had landed on
the same review, and independently, the first refute pass this exchange
was ever able to run defeated **all three** of round 6's guards. Two of
the three were the same defects Codex raised, found by different routes,
which is the cross-validation the refute pattern exists to produce.

The guards failed on the cases their authors did not picture: `-e` on
`data/file.txt` returns false when `data` is a local file (ENOTDIR), so
the collision scan skipped exactly the file `reset --hard` would delete;
the credential check anchored on `://` and so missed the scp-style
`token@host:path`; and a state key on the literal path spelling gives
`wt/Foo` and `wt/foo` separate records on a case-insensitive filesystem.
Codex added a fourth: an unqualified fetch refspec lets a same-named tag
win into `FETCH_HEAD`, realigning the primary branch to an unrelated
commit.

**Revisit when** a guard here is changed: each was written confidently and
each was defeated on first adversarial contact, so the pattern is that
this file's guards need an attacker, not a reader.

## Enumerate the collision scan's inputs, not its symptoms

Round 8 defeated the collision scan a third time, and the fix is the
last one that gets to be per-symptom. The scan answers one question per
changed path: would `reset --hard` destroy something the index does not
hold? That question has a small, enumerable input space (the local
shape: absent, file, real directory, symlink; the pushed shape: blob,
tree, absent; the spelling git hands the path back in; and the directory
the whole scan is resolved against), and every previous round fixed the
one cell a reviewer happened to land on. Walking the product instead
found three live defects where the review named one:

- **A directory judged tracked by its descendants.** `git ls-files
--error-unmatch -- foo` succeeds for any directory holding an indexed
  file, so a pushed blob at `foo` passed the scan and `reset --hard`
  removed the directory with its ignored contents. Reported by Codex,
  reproduced before the fix.
- **C-quoted paths.** `git diff --name-only` renders any non-ASCII path
  as `"caf\303\251.txt"`, a name no filesystem carries, so every such
  path tested as absent and safe. Found by enumeration, not review.
- **Paths resolved against the cwd.** The changed paths are
  root-relative while the `ls-files` pathspecs were evaluated wherever
  the process stood, so a run from a subdirectory asked about the wrong
  file; the same assumption made the worktree-identity check report the
  primary checkout as "another worktree". Also found by enumeration.

The scan also **stopped refusing** two cases it never needed to: a
directory whose contents are entirely indexed, and one the pushed tree
merely writes into or empties. git removes a directory only once it is
empty, so nothing unrecoverable is at stake there, and an over-refusal
strands the branch at its pre-review SHA just as surely as a missed one
loses a file. Both directions are pinned, because a guard that only
ever gets tightened converges on refusing everything.

**Revisit when** this scan changes again: the unit of work is the input
product above, run as cases, not the cited path shape. Three of the four
instances closed here were never reported by anyone.

## A remote's shape, not a list of secret names

Round 9 defeated the credential guard the same way round 8 defeated the
collision scan: by using a spelling the guard's author had not pictured.
The check inspected userinfo, so `https://host/r.git?access_token=...`
passed it, was written to the state file, and was printed back verbatim
in the `BLOCKED` report when the fetch failed. Reproduced before fixing,
in all three sinks; the fragment form (`#token`) leaked identically.

The tempting fix is to also look for `access_token`, `sig`, `sas`,
`key`, and whatever the next host invents, which is a blacklist against
an input space the attacker (or the hosting provider) extends at will.
The rule is now a **shape a URL may have** instead: a remote URL names a
location and carries no userinfo, query, or fragment. Two exemptions
stay, both narrow and stated: the conventional `git@` ssh identity,
which is not a secret, and a filesystem path, which has no query or
fragment to hold one. A URL that legitimately needs a query has an
escape hatch that costs one command: configure it as a named remote and
pass the name, which is the documented primary route anyway.

The sweep also reached the sink the finding did not name. The head
repository URL is a field of a value `gh` handed back, and it lands in
the same state file and the same reports, so it is now held to the same
shape. That the host normally returns a bare clone URL is a habit of the
host, not a property of the script, which is the returned-object trust
boundary AGENTS.md names as its own risk class.

**Revisit when** a new remote-valued input is added: it goes through
`remote_defect` at the point it enters, not at each place it is printed.
One boundary check is what keeps every sink covered by construction.

## A path is bytes, and two of them are not newline

Round 10 found the same assumption in two places, and the sweep found a
third: a path may legally contain a newline or a tab, and this script
both parsed and printed as though it could not. Reproduced together in
one run. The line-oriented read of `git worktree list --porcelain` never
saw a whole `worktree <target>` record, so teardown called its own
linked worktree a foreign directory, reported `removed=manual`, and left
it registered and on disk; the same values went into a report that then
spanned two lines of invalid JSON, against a one-report-line contract
the file's own header advertises. The third instance was in neither
finding: the state file is `key=value` lines, so a control character in
a remote silently truncates what teardown later fetches from.

Fixed at the three sinks that make up the class, not at the two cited
lines: `--porcelain -z` for both worktree loops (with a fallback that
preserves today's behavior on a git without `-z`, rather than dropping
the records and the "checked out elsewhere" guard with them), full C0
escaping in `esc`, and control characters refused in `remote_defect`,
where no legitimate remote spelling has one.

**Revisit when** a new git plumbing call is parsed here: the porcelain
formats have NUL variants because paths are bytes, and every
line-oriented read of one is this bug again.

## The realign proved the wrong half

Every realign guard asked what the _local_ branch holds: clean tree, no
collisions, nothing the conductor never saw. None asked whether the
fetched tip is what the conductor pushed. A contributor landing a commit
in the window between the conductor's last push and teardown therefore
passed all of them, and reproducing it took one force-push: the primary
branch was reset to an unrelated unreviewed head and the move was
reported as a clean `fast-forward`. An appended commit does the same
thing more quietly, since it fast-forwards legitimately.

The proof is the conductor's own checkout, read while it still exists.
Route decides where: a linked worktree shares the primary's refs, so
only its detached HEAD records what was pushed, while a separate clone
has its own `refs/heads/<branch>`, which is exactly that and survives
the clone being parked on another branch. Two consequences fell out of
_when_ rather than _what_. Removal happens before every guard, so a
realign that blocks (a dirty primary) had already consumed the checkout
holding the proof; it is therefore persisted into the state record the
moment it is read, which is what makes the documented "clear the blocker
and re-run" retry work. And where neither a live checkout nor a record
exists, `--expect <sha>` supplies it by hand, checked rather than
trusted, exactly as `--at-setup` does for the other half of the proof.
With none of the three, the realign refuses: this is the destructive
path, and there is nothing to check against.

**Revisit when** a new realign guard is added: ask which side it proves.
Ten rounds of guards all proved the local side, and the remote side was
unguarded the entire time.

Round 11 then narrowed the clone half of that proof, which had been
written too coarsely: preferring the clone's `refs/heads/<branch>` is
right only when the clone is parked on some _other_ branch, and wrong
for the route the skill actually documents, where the conductor detaches
and pushes `HEAD:<branch>`, leaving that ref at the pre-fold SHA. The
selector is now the placement of the clone's HEAD, with all three
positions enumerated (detached, on the branch, on another branch) and a
fourth outcome for the clone that never held the branch at all: no
proof, ask for `--expect`, rather than offering an unrelated commit as
what the conductor pushed. This is the only fix in the exchange that
repaired the previous round's fix, and it is why the proof selector is
now stated as a three-way rule rather than a preference.

## A guard configuration can switch off is not a guard

Round 11's other finding: `git status --porcelain` honors
`status.showUntrackedFiles=no`, so both cleanliness guards reported a
clean tree with untracked files sitting in it, which a later broad
`git add` would sweep into the conductor's push. Both now pass
`--untracked-files=all`.

This is the same shape as `diff.relative` and `core.quotePath` in the
earlier rounds: a plumbing call whose answer the reader's configuration
gets to change. The three known instances are now pinned, and the
question to ask of any new one is not what it returns here but what it
returns for someone whose config differs.

## An empty field is not a default

Round 12's P1: `gh` returns `.head.repo: null` for a deleted or
inaccessible fork, the query's `// ""` turned that into an empty string,
and teardown read the empty string as "use the base remote". Those are
not the same statement. The host saying it does not know where the
branch lives is not the host saying the branch lives in the base, and
resolving it against a repository that never held it realigns the
primary checkout onto whatever same-named branch happens to sit there,
which is the fork hazard from round 4 arriving through a different door.
Setup now refuses when host resolution produced no head repository, and
names `--head-remote` as the way through; the `--head`/`--branch`
override path keeps its documented base fallback, since there the
operator chose it.

The same round's P2 finished the report-encoding class. Valid UTF-8 now
passes through `esc` intact while any byte that is not part of a valid
sequence becomes `\u00xx`, so a non-ASCII path stays readable and no
path can leave the payload undecodable. Two things surfaced only by
running it: on BSD sed an invalid byte is not copied through but
_fatal_ ("RE error: illegal byte sequence"), which emptied the entire
payload rather than corrupting one field, so both stages of `esc` now
run under `LC_ALL=C`; and APFS refuses to create a filename with such a
byte at all, so the fixture feeds it through `--remote`, which a
`BLOCKED` report echoes, rather than through a path.

## Refusing to move the branch is only half the protection

Round 13's P1, and the sharpest finding of the exchange: round 10's
guard refuses to realign onto a hijacked head, but removal happens
first, and removal is what makes the conductor's commits unreachable.
A detached worktree's HEAD and its reflog are the only references to
them; `git worktree remove` deletes both, and a push aimed at a URL
rather than a configured remote leaves no tracking ref either. So the
refusal was printed over work the next `git gc --prune=now` would
collect. Reproduced exactly that way.

Recording the SHA in the state file did not help, which is the lesson:
**a SHA is a name, not a reference.** Teardown now anchors the head in
`refs/conductor-isolation/<key>` before unlinking the worktree, drops
that anchor when the branch takes the commits over, and names the ref in
the refusal so the human is told where the work is rather than left to
find it in a reflog that no longer exists.

**Revisit when** anything else in this file records a SHA and then
destroys its holder: the question is not whether the value survives but
whether the object does.

## Command substitution is lossy, and paths are bytes

Round 13's second P1 closed the loop on the newline class from round 10.
`-z` fixed how the changed paths arrive; the walk over their ancestors
still went through `parent=$(dirname "$probe")`, and command
substitution strips every trailing newline. A component ending in one
therefore stepped the walk to a _different_ ancestor, and the ignored
file at the name it skipped was deleted by the reset, reported as a
clean `TEARDOWN_DONE`. Reproduced, and the first attempt at the fixture
built the directory with `$(printf 'foo\n')` and lost the byte before
the test began, which is the same defect demonstrating itself.

Both sites now split paths with parameter expansion instead
(`${p%/*}`, `${p##*/}`), including `abspath`, which the finding did not
name but which had the identical `dirname`/`basename` pair. `pwd` is a
command too, so its own trailing newlines are protected with a sentinel
(`pwd -P && printf x`, then strip the `x`). Trailing-slash normalization
was `dirname`'s doing and is now explicit, since `--path w/` is what tab
completion produces; there is a case pinning it.

There is a third site, and finding it is the argument for the rule
rather than the patch: `TARGET=$(abspath "$PATH_ARG")` is itself a
command substitution, so fixing the splitting _inside_ `abspath` bought
nothing until the call site got the same sentinel. The test written for
the reviewer's `--path` case is what caught it, against a script already
believed fixed.

**Revisit when** a path is passed through any command substitution here:
the value that comes back is not the value that went in, and that
applies to the calls that wrap a function already corrected.

## "Unchanged since setup" is not "nothing the conductor missed"

The last P1 of the exchange, and the one that most deserved to be found
earlier, since it defeats the oldest guard in the file on its own terms.
Setup records the local branch tip as the head to compare against at
teardown, and the rewritten realign reads a match as proof the branch
gained nothing unseen. That inference only holds if there was nothing
unseen at setup. A branch sitting on clean unpushed commits is unchanged
at teardown while holding work the conductor never had, so
`reset --hard` discarded it. Reproduced with one local commit.

The record is now written only when the branch already equals the head
the conductor starts from. Otherwise it stays empty, which costs the
automatic rewritten realign and leaves `--at-setup` as the explicit way
to say "discard them, I mean it". Setup also says so in its report
rather than saving it for the teardown refusal, since setup is the
moment the operator can still push those commits.

**Revisit when** a guard here compares two states: check what it assumes
about the state it started from, not just about the change between them.

## Round 11, and the escalation at round 12

Round 11's two P2s were both fixed and verified: the clone proof selector above (a
defect in round 10's own fix, and the only one of those in eleven
rounds) and the configuration-defeatable cleanliness guards. Neither is
blocking, so under the rising bar they were a triage push rather than a
round, and the re-review that push triggers is left for the merging
human rather than waited out.

Round 12 then arrived with another P1 (an empty `.head.repo` read as
"use the base remote") plus a P2, and round 13 with two more (the
unreachable commits and the ancestor walk above). That is where the exchange stops and goes
back to the owner: not because the findings stopped being worth fixing,
but because they show no sign of stopping at all.

The round-5 call made "continue until the reviewer is quiet" the
stopping condition. It never went quiet. Thirteen rounds produced valid
findings every time, and rounds 8 through 13 alone produced six
data-loss or wrong-branch defects, a credential leak, and two broken
report contracts, none of them recurrences. This is not thrash by the
definition: fixes are not spawning problems without net progress, and
two findings in six rounds (round 11's clone proof selector and round
13's unreachable commits) were follow-ons from fixes of this exchange's
own making, and both were narrowing gaps in new guards rather than
recurrences. Every other one
was a defect the code had carried all along, in a surface an earlier
round had not touched.

That is the finding worth escalating, and it is about the code rather
than the loop: **on this surface every hand-written guard has been
defeated on first adversarial contact, thirteen times running.** The
reviewer is not running out of material because the material is not
running out. That bears directly on the scope question below: if most of
this script is replaceable by a platform-native worktree, the right
response to an unbounded supply of guard defects is to delete the
guards, not to keep winning the argument one round at a time.

## Round 10's convergence call

One P1 from round 8 was still undispositioned when this round closed,
having been missed rather than judged: the realign trusting a fetched
tip, above. It was blocking, so it was fixed and verified rather than
triaged, and the exchange does not get to end on a blocker nobody
answered. The three round-10 findings were then judged on their own
merits.

Three P2 findings, none blocking by the categories that sustain the loop
(no data loss, no security hole, no broken invariant on the ordinary
path; all three need a hostile path or an exotic filesystem, and each
fails toward refusing rather than toward damage). Per the rising-bar
rule, the exchange ends here with a triage push rather than another
round: two fixed above, and the case-folding probe deferred to #116,
which quotes the finding. It was deferred rather than fixed because it
is the one of the three the offline matrix cannot verify (it needs two
filesystems with different case semantics), and shipping an unverified
change to this file is the habit the whole note argues against.

## Checkpoint, round 5

Recorded per the skill's blocker-sustained checkpoint rule. Five fix
rounds, fifteen findings, every one valid and none a recurrence of an
already-fixed defect: rounds 1 to 3 hit the prose, 4 and 5 the script's
fork and state-lifecycle paths. Rounds 4 and 5 each surfaced follow-ons
from the previous round's fix, which is the mild thrash the checkpoint
exists to catch, so the call went to the owner (Ben) with the ledger and
three options. **Call: continue until the reviewer is quiet**, over the
recommendation to fix and hand off. Renew the checkpoint if the pattern
of each fix seeding the next finding persists past round 7.

**Renewed at round 9: continue, under the round-5 call.** The renewal
condition was "each fix seeding the next finding", and rounds 8 and 9
are not that. Both raised a defect the previous rounds' code had carried
all along, in a surface the previous rounds never touched, and both were
reproduced before being fixed rather than accepted on the reviewer's
description. No finding in either round is a recurrence of an earlier
fix, and none arrived from a fix of this exchange's own making, which is
the thrash signal that would end it. What has changed is the reason to
keep going: the loop is no longer converging on a finished script, it is
demonstrating that a hand-written guard on this surface fails on first
adversarial contact every time, which is evidence for the scope question
(below) rather than against the code.

**Revisit when** a conductor exchange runs on a fork PR for real. The
fork paths (pull-ref fetch from the base, branch fetch from the head
repo's URL) are covered by fixtures with two local bare repositories,
which is stronger than the prose ever was but still not a live fork.

## Rejected alternatives

- **Fix only the step-4 paragraph** (where the observed sentence lives).
  The routing call happens at step 0; leaving the parallel four-item list
  there would have preserved the misread for exactly the agents that
  route without reading step 4 in full.
- **Add a Codex-specific carve-out.** The defect is platform-agnostic
  phrasing that happened to fail on Codex first. Any platform without a
  native isolation spawn parameter, which is most of them, reads the old
  text the same way.

Revisit when: a platform appears where an agent genuinely cannot create a
second checkout and cannot hold exclusivity over the one it has (a
sandbox with no `git worktree` and concurrent writers). That would make
isolation a real gate again on that platform, though still not a ladder
rung elsewhere.
