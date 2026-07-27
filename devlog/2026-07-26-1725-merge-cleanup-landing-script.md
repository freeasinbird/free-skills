# Escalating merge-cleanup's base landing from prose to a script

Issue #100 asked whether merge-cleanup's hyphen-leading base path should be
made executable, dropped, or left as prose and watched. The path and its five
review rounds are recorded in
`devlog/2026-07-26-1306-merge-cleanup-hyphen-args.md`, which filed the question
rather than answering it.

## Decisions

- **Chose escalation over dropping the path or leaving it as prose.** Owner
  decision. Four of the five rounds reported a clause the instructions omitted
  (the `git switch` probe, the missing upstream, the direct config writes, the
  second tracking key) rather than an oversight in an otherwise settled rule.
  That is the diagnostic for prose re-deriving a program, where no enumeration
  converges and the last clause exists only because a reviewer happened to
  find it. Dropping the path back to a stop was rejected because round 1's
  argument still holds: a stop refuses a cleanup git can express, and nothing
  changed that. Leaving it as prose was rejected on the evidence rather than
  its absence: the clean reviewer pass recorded on #100 after round 5 is
  exactly the condition that option named, but one clean pass is a single data
  point against four rounds of the opposite.

- **Chose a script that decides over one that lands.** Owner decision,
  deliberately narrower than #100's own description of the option ("probe,
  switch, create, tracking repair"). `base-landing-plan.sh` prints a plan; the
  caller runs it. Landing is a mutation on a destructive path, and leaving the
  mutation with the agent and the user preserves the property that made
  `worktree-inventory.sh` cheap to trust. Read-only also buys the placement
  round 2 asked for: the script can run before step 1 deletes the remote
  branch, so a missing `git switch` is a stop that costs nothing, where
  discovering it afterwards leaves the branch gone and the workspace still on
  the merged branch.

- **Chose to own the whole landing decision, not the hyphen variant.** A
  hyphen-only script would leave two implementations of one landing, one code
  and one prose, with nothing holding them in step; the prose twin is where
  the next omitted clause would appear. Owning the decision makes the name
  shape one input value, and pays for itself on the ordinary path, where the
  tag shadow, `status.showUntrackedFiles=no`, and an untracked base branch
  bite in real clones. The option-shaped name contributes one branch of the
  verb choice and one extra fetch refspec.

- **Step 2 re-runs the script rather than trusting the pre-step-1 reading.**
  The two runs answer different questions: the first stops the sequence before
  it deletes anything it cannot undo, the second produces the plan step 2
  executes. A single reading would have to serve both, and the earlier one
  describes the tree before a push rather than the tree about to be switched;
  a clean-tree guard means nothing except immediately before the switch. Same
  reasoning that rejected a post-push clock reading as a review-watch
  baseline: a reading taken at one moment is not evidence about another.

## What the script deliberately does not do

- **It does not predict an ignored-file overwrite.** That hazard is already
  mechanical: the landing commands pass `--no-overwrite-ignore` and git aborts
  by itself. Predicting it would mean intersecting the base tree's paths with
  the worktree's ignored files, to raise a stop where git already has one.
  The status read therefore omits `--ignored`, which is where it diverges from
  `worktree-inventory.sh`, whose subject is a directory about to be deleted.

- **It does not carry a fallback for git older than 2.23.** An option-shaped
  base branch on such a git is a stop, as the frozen note already accepted.

- **It does not remove the layer-2 stop** (a name holding a single quote).
  The frozen note's first "Revisit when" condition reads as though it would:
  it says that merge-cleanup shipping an executable of its own makes the stop
  cheap to replace, "a script binds values as a matter of course". That
  condition does not fire here, and the property it actually needs is narrower
  than the wording suggests: an executable that _performs_ the sequence binds
  the names, while one that only decides leaves the landing commands as shell
  templates the caller interpolates, exactly as before. Note that
  `worktree-inventory.sh` already existed when that bullet was written, so the
  condition was never "any executable" in substance. Read it as: when
  merge-cleanup ships an executable that runs the destructive commands, the
  layer-2 stop costs nothing to replace.

## Verification findings

- **The plan is executable end to end, and the tracking repair is the part
  that matters.** In a `--single-branch --branch main` clone with the base
  branch `-x` absent locally, the emitted plan (two refspecs, `switch`,
  `tracking: write`) ran verbatim, attached `HEAD` to `-x`, and a subsequent
  `git pull --ff-only` fetched `-x` and fast-forwarded onto its real tip. The
  same clone without the two config writes reported "Already up to date" while
  the branch sat a commit behind the remote: the pull had followed the clone's
  configured refspec, not the branch. That is §leading-hyphen-args' hazard
  reproduced against the shipped script rather than against a scratch recipe.

- **The discriminating cases discriminate.** Ten degraded copies were built
  and run against the full matrix: no switch verb, one fetch refspec, one
  tracking key, a plain `--porcelain` status, an `--ignored` status, an
  unconditional switch probe, a blanket remote check, a config check reading
  only an exit code, a help check that ignores the argument count, and a help
  flag scanned across every argument. Each failed, and each failed exactly the
  case whose comment claims it.

- **Two coverage claims were wrong as first written and were corrected.** The
  `-h`-in-the-branch-position case does not kill a help check keyed on the
  first argument's spelling, because that variant never inspects the second
  argument; what kills it is the empty-remote form of the argument-count case,
  where `${1:---help}` substitutes its default for an empty value as well as
  an unset one and the script prints help at exit 0 on a call that named no
  remote. The `-h` case kills a different degradation, a help flag scanned
  across every argument. Both comments now name the variant actually verified.

- **`git config --get` is not the right existence test**, which the matrix
  pins. It exits 0 on a key set to the empty string, and older git refuses a
  multi-valued key outright; `--get-all` plus a non-empty test answers the
  question that was being asked.

## Refute-first review

Required for this path (a destructive-path change under AGENTS.md's
high-assurance profile). Three independent lenses, each prompted to disprove
rather than confirm: git semantics and the read-only claim; the matrix's
coverage and discrimination claims; and contract drift between the new prose
and the script, including a mechanical survival check of every guard the old
step 2 carried.

**Confirmed and fixed.** Two of these would have stranded a cleanup after
step 1 deleted the remote branch, which is the failure mode the whole
placement exists to prevent.

- **The remote was validated only where the landing itself would touch it.**
  Step 3 fetches from it in every shape, so a typo'd base remote passed the
  pre-step-1 gate and failed two steps later. Now validated unconditionally:
  one read, and it is the reason the script runs early at all.
- **`git show-ref --verify` is not an exact existence test.** It case-folds a
  loose ref on a case-folding filesystem (and not a packed one, so the answer
  also depended on whether the repository had been packed), so a base named
  `Main` in a repository holding `main` planned `create: false` and the
  landing attached `HEAD` to a name in no ref listing, which steps 3 and 4
  then fast-forwarded and deleted against. Now an exact match over
  `for-each-ref`.
- **The JSON tail mangled any non-ASCII name.** Byte-wise `\u` escaping under
  `LC_ALL=C` turned `café` into two escapes decoding to `cafÃ©`, and that name
  reached the caller inside a fetch refspec. Fixed in both copies of the
  helper, the sibling `worktree-inventory.sh` included, since a fix in one
  would be a divergence rather than a repair.
- **The `git switch` probe trusted exit 129 alone.** Where switch is not yet a
  builtin, an `alias.switch` is expanded instead and answers `-h` with 129
  too, so the plan would have named `git switch -- <name>`, running the alias
  with `--` read as a pathspec. The probe now also requires switch's own usage
  text.
- **`git status` is not read-only**: it rewrites the index to refresh stale
  stat information and takes `index.lock`. Now `--no-optional-locks`, since
  the script is run early on the strength of touching nothing.
- **A lone empty argument printed help and exited 0**, because `${1:---help}`
  substitutes its default for an empty value as well as an unset one.
- **The "cannot run" fallback did not say not to delete the remote branch**,
  where its sibling gate for the worktree inventory does. With the landing no
  longer in prose, that omission was worse than before the change.
- **Five smaller prose-to-script contract errors**: the exit codes that report
  on stderr were unlisted, an empty `fetch` list had no skip instruction (a
  bare `git fetch` follows the clone's refspec), the switch command's stated
  justification was false for `create: false`, `tag_shadow` was written as
  though it changed what the caller runs, and the pre-step-1 run did not say
  which worktree to run in under the relocate rule.
- **The matrix overstated its own coverage.** "The plan mutates nothing" was
  marked discriminating but exercised only the `create: false` path, so no
  mutating copy failed it; the snapshot also could not see a fetch (FETCH_HEAD
  and the index were outside it). Three cases passed against a state their
  setup never created, the `--` on the remote read had no case at all, and two
  labels misdescribed what they killed. Matrix 79 -> 107 assertions, verified
  against eighteen degraded copies rather than ten.

**Confirmed by the automated reviewer**, on PR #104, both fixed.

- **A ref name may hold raw bytes that are not UTF-8**, which `check-ref-format`
  accepts, and no JSON string can carry one: passing them through verbatim, as
  the mojibake fix above did, made the plan line unparseable while the script
  still exited 0. Escaping such a byte back to `\u00XX` would not save the
  landing either, since that code point re-encodes as two different bytes, so
  the arguments are now validated as UTF-8 and refused (exit 64) before any
  plan is emitted. The escaper still escapes an invalid byte rather than
  emitting it, for the sibling inventory's sake: a worktree path is under no
  UTF-8 obligation at all, and there a lossy name in a stop beats a line the
  caller cannot read.
- **`chmod 000` does not block root**, so the unreadable-index case would have
  failed only in a root CI container or devcontainer. It now forces the failure
  through a git shim, which asserts the same contract wherever it runs.
- **Round 2 named one class twice: a read whose failure is indistinguishable
  from a negative answer.** The sibling inventory already holds the rule ("a
  failed read is not an established absence"), and this script had three leaks
  of it, so all three were closed together rather than the two cited.
  `git for-each-ref` piped into `grep` reported grep's status, so a ref-backend
  failure arrived as "no match" and planned `create: true` for a branch that
  exists; `git config --get-all` treated every non-zero as "not set", where
  only exit 1 means that; and the remote was checked for existence alone. That
  last one's mechanism is not the one reported: `git remote get-url` on a
  remote whose URL is empty exits 0 and echoes the remote's _name_, because git
  falls back to treating the name as a URL, so an empty-output test would not
  have caught it either. The configured value is what gets read now.

- **Round 3 found the read-only claim's last hole, in the probe itself.**
  Asking `git switch -h` whether switch exists invokes it, and where switch is
  not a builtin an `alias.switch` is expanded in its place; git runs a
  `!`-prefixed alias as a shell command with the `-h` appended. Reproduced: the
  alias created a file. So the probe could mutate the repository from inside
  the preflight whose entire argument for running early is that it touches
  nothing, and the output check added in the refute-first pass came too late by
  construction, since the alias had already run. It now reads
  `git --list-cmds=builtins`, which expands no alias and cannot be shadowed.

- **Round 4 overturned "no name shape is a stop", which #99's note recorded and
  this work inherited.** The reviewer cited a base named `-`; the enumeration
  it prompted found three. Git resolves `-`, `@`, and `HEAD` as revision
  shorthand before it reaches `refs/heads`, so the collision is in revision
  parsing, where no terminator reaches, and two of the three land on the wrong
  branch at exit 0. No spelling attaches HEAD to them (`switch refs/heads/-`
  and its terminated form exit 128, `checkout refs/heads/-` detaches), so the
  plan now stops on those three literals. That is still not a skill declining
  what git can express: it is the one shape git cannot. The rest of the space
  was enumerated rather than assumed, and `--`, `-x`, `-h`, `--all`, `a/b`, and
  all eight `*_HEAD` pseudo-ref names land correctly, which is why the refusal
  is a list and not a pattern. §leading-hyphen-args and the identify section
  both carried the old claim and now carry this one.

- **Round 6 closed the last of the read-only claim's exposure, and narrowed the
  claim itself.** Three findings, all confirmed. A byte count taken on a
  `local LC_ALL=C` declaration line is a character count under a UTF-8 locale,
  so a name of valid multibyte text followed by an invalid byte was measured
  short and its tail never validated; the same locale also made `grep` refuse
  the ref match with "illegal byte sequence", which the pipeline read as
  "branch absent". Both are fixed by setting the C locale once, globally, which
  is what the per-function declarations were reaching for. `core.fsmonitor` is
  run as a hook during `status` even under `--no-optional-locks`, so repository
  configuration could execute code inside the preflight; overridden now. And a
  single-valued config key's effective value is the last one set, so a tracking
  key set to `origin` and then to empty read as present through `--get-all`
  while `git pull` saw nothing.
- **The read-only claim is now stated as "writes nothing itself".** One vector
  cannot be closed: asking git whether the tree is clean runs the repository's
  configured `filter.<driver>.clean` over changed paths (verified). Rather than
  keep asserting a guarantee with an exception, the header says what is true
  and names the exception. Worth keeping in proportion, though: any git command
  the user runs in that repository already executes the same configuration, so
  this script adds no exposure a checkout did not already carry.

- **Rounds 7 and 8 found one bug in the tests and one in the prose, not in the
  script.** The locale case named `en_US.UTF-8` outright, so where that locale
  is not installed (a minimal container often has only `C`, `C.utf8`, and
  `POSIX`) `setlocale` fails, the previous locale stands, and under a `C`
  default the case passes with the bug it exists to catch restored; it now
  resolves an installed UTF-8 locale and skips loudly when there is none. And
  step 2 took the tracking decision from a plan read before the landing, which
  an `includeIf "onbranch:…"` section invalidates: keys supplied that way are
  visible while their branch is checked out and gone afterwards, so the plan
  said `ok` over a base branch left with no upstream. The plan now runs once
  more after the switch, which is the same rule step 2 already applied to the
  pre-step-1 reading, one step later.
- **Correcting the claim on that locale case rather than only the case.** It
  discriminates only against a copy that drops the global `LC_ALL=C` _and_
  takes the byte count on a `local` declaration line; with the global locale in
  place the declaration-line count is harmless. The redundancy is deliberate,
  so each function stays correct alone, but the comment now says which revert
  the case actually catches, after a first attempt asserted more than it could.

**Accepted by decision, and escalated rather than patched** (round 9).

- **A branch-conditional include can change the remote URL across the landing
  too**, the same class as round 8 one key over, and reproduced: with
  `remote.origin.url` supplied by an `includeIf "onbranch:feature"` section,
  the pre-step-1 plan validated it and the post-landing plan reported
  `LOOKUP_FAILED remote`, after step 1 had deleted the branch. Round 8's fix
  does not generalise here: the tracking write could move after the landing,
  and the remote check cannot, because step 1 needs it and step 1 runs first.
  No read taken before the landing can predict a value git evaluates against
  whichever branch is checked out at the time, so this is a property of the
  sequence, not of the check. Documented in §leading-hyphen-args and in the
  preflight prose, and the ordering question filed as issue #105 rather than
  redesigned inside this work unit. A detector was considered and rejected:
  `git config --get-regexp '^includeif\.'` does surface the directive, but
  refusing every repository with a branch-conditional include would block
  cleanups that are perfectly safe, which is the rule against declining what
  git can express.

- **Round 10 closed the residue of round 4's own fix.** Replacing
  `git show-ref --verify` with an exact match stopped the plan silently landing
  on a case-folded name, but left it planning `create:true` for a base that a
  case-folding filesystem cannot create: the prescribed `checkout -b` fails with
  "a branch named 'Main' already exists", after step 1. Silent became loud-but-
  late, which is still a strand, so the plan now stops on a case collision
  before the deletion, gated on `core.ignoreCase` so a case-sensitive
  filesystem still plans the create. Taken rather than deferred, unlike #105,
  because the guard is precise, refuses nothing git can perform, and the
  platform in question is the ordinary macOS default rather than a hostile
  configuration.
- **The matrix case for it now executes the create instead of reading the
  plan's JSON.** The reviewer's second point, and correct: asserting the field
  was asserting the thing that had been wrong. It reads `core.ignoreCase` and
  asserts whichever answer that filesystem makes right, then runs the create to
  show the answer was right, which is the third time in this work unit a case
  claimed more than it checked.

- **Round 11 caught the round-10 guard reading a boolean as a string**, so it
  fired on `core.ignoreCase = true` and silently did not on `yes`, `on`, `1`, or
  `TRUE`, four of the five spellings git accepts. One flag (`--bool --get`), and
  worth recording for the reason rather than the size: the rule was already
  written down in this same skill directory, in `worktree-inventory.sh`'s sparse
  read, whose comment says exactly why raw `--get` is wrong for a boolean. The
  miss was not new knowledge, it was failing to apply the sibling's. The matrix
  now sets the flag explicitly and pins all eight spellings plus unset, which
  also makes the case portable, where the case above it branches on whatever the
  ambient filesystem does.

- **Round 12 inverted rounds 10 and 11: the guard was refusing landings git can
  perform.** Gating the case-collision stop on `core.ignoreCase` treated a
  working-tree hint as proof about the ref store, so a case-sensitive volume
  whose flag was stale or set by hand got a stop while `checkout -b Main`
  succeeded and made both refs. Confirmed on a case-sensitive APFS disk image
  created for the purpose, rather than on the reviewer's ext4 report alone. The
  guard now probes what git resolves (`show-ref --verify`), which matched the
  create's real outcome in all four cells of volume type by ref storage, and
  the `core.ignoreCase` read disappears entirely, retiring round 11's boolean
  handling with it.
- **That fix was itself wrong, and a re-armed refute pass caught it before the
  reviewer did.** `checkout -b` exiting 0 is not the same as the landing being
  safe: on a folding filesystem against a _packed_ ref it exits 0 and leaves the
  new loose file case-folding over the packed entry, so `git rev-parse release`
  reports the new tip while `for-each-ref` still reports the old one, and the
  user's branch is silently aliased under a sequence that then fast-forwards and
  deletes against it. Reproduced: `release` at `89c074b` read back as `477f7ac`.
  So the guard needs both conditions, whether the filesystem folds (probed
  read-only by asking for `$GIT_DIR/head`, which resolves only where it does)
  and whether a variant exists (a fold over the enumerated refs, since
  `show-ref --verify` folds for loose refs and not packed ones and so misses
  exactly this case). Correct now in all four cells of volume type by ref
  storage.
- **The matrix oracle had to change with it**, the fourth and last form of one
  mistake: it now asserts what the create _leaves behind_, that the pre-existing
  branch still resolves to its own commit, rather than the create's exit status,
  which was what blessed the hijack. Both storage shapes run, because the
  flag-gated copy fails only on packed and the no-stop copy only on loose.

## Re-armed refute pass

Spent a second adversarial pass, which the convergence rule permits when a class
recurs after the first: rounds 10 and 11 each found a defect in code written in
response to the round before, so the guards added mid-review were the
least-tested code in the change. Two read-only lenses, one attacking those
guards and one auditing every "discriminating" claim in the matrix by building
each named degraded copy.

- It paid for itself on the packed-ref hijack above, a P1-shaped defect in a fix
  that was minutes old and would otherwise have reached the reviewer or the
  user.
- **Two matrix claims were overstated**, found by building all 31 degraded
  copies rather than sampling. The help case named the wrong degradation: what
  it kills is the colon form of the default, not an ungated argument count,
  which changes nothing. And the pipelined-enumeration case does not
  discriminate on a case-folding filesystem, because the collision guard's own
  separate enumeration reports the failure by another path; it discriminates on
  a case-sensitive one, and now says so.
- **Two assertions could not fail.** `want_no_out '\\u00'` was single-quoted, so
  the needle was two literal backslashes and never matched the mojibake it was
  meant to catch. And an assertion that grep never reports an illegal byte
  sequence was unreachable, since the UTF-8 refusal upstream means the ref match
  never sees an invalid name; it is gone, with the reason recorded in its place.
- **Two comments understated their coverage**, claiming not to discriminate
  while their option-shaped base names kill two listed copies. Corrected, since
  the header promises the labels are accurate in both directions.
- The UTF-8 table survived: 30 hand-built RFC 3629 cases plus a 387-case random
  fuzz differential against python's decoder, zero mismatches, and the bounds
  check is not off by one. The `-`, `@`, `HEAD` refusal was confirmed complete
  against all eight `$GIT_DIR` pseudo-refs, each of which does land correctly.

**Accepted by decision from that pass, then reversed by round 13**: the lens
proposed treating a whitespace-only config value as missing, and I took it
without testing whether git could use such a value, which is the verification I
demand of every reviewer finding. It cannot be waived for my own lens. Whitespace
is legal in a Unix path, and `git fetch` through a remote URL of exactly three
spaces naming a directory that holds a repository succeeds (verified), so the
strip refused a cleanup git performs, the same error round 12 caught in the
collision guard. Only a genuinely empty value counts as missing now. Declined
from the same pass: a syntactically broken loose ref, which the ref-path stat
added in round 13 now stops anyway, and a corrupt `.git/config` surfacing as
"not inside a git work tree", which stops correctly and reports the wrong reason.

- **Round 13 closed the collision guard's last real gap and reverted that
  whitespace change.** APFS aliases by Unicode rules as well as by case, so an
  existing `refs/heads/CAFÉ` is what `refs/heads/café` resolves to, which a fold
  written under `LC_ALL=C` cannot see: the plan said create and `checkout -b`
  then failed at 128. The guard now stats the ref path first, which is exact for
  every aliasing the filesystem performs, case folding and Unicode
  normalization alike, and costs one stat instead of any folding rules of our
  own. It also subsumes the broken-loose-ref case above. The name fold stays for
  packed refs, which have no file to stat, and is ASCII, so a non-ASCII variant
  of a _packed_ ref is the one shape still undetected; recorded here and in the
  matrix rather than left implicit.

**Rejected by verification** (recorded so they are not re-raised).

- **Dropping `@` from the unspellable stop** (round 5), reported as landing
  correctly on git 2.43.0. Not reproduced on 2.50.1, and re-checked with the
  branches at deliberately different commits, which is what makes the outcome
  legible: `git checkout --no-overwrite-ignore @` left `HEAD` on the previously
  checked-out branch at that branch's commit, and
  `git switch --no-overwrite-ignore -- '@'` refused with "a branch is expected,
  got 'refs/heads/other'", git naming the expansion it had performed. Kept as a
  stop for two reasons: the behaviour cannot be reproduced on the git available
  here, and the two errors are not symmetric. Wrongly stopping refuses a
  cleanup the user can still do by hand; wrongly landing puts `HEAD` on another
  branch, which step 3 fast-forwards and step 4 deletes against. A version
  split, if real, argues the same way, since a skill that runs on whatever git
  it finds cannot depend on the favourable version.

- **A remote whose `url` is multi-valued with an empty first entry** (round 4),
  reported as fetching through the empty entry and failing. Not reproduced on
  git 2.50.1: git skips the empty value, `git remote get-url` returns the valid
  one, and the fetch succeeds, so the plan's `OK landing` is correct. All four
  configurations were checked (empty alone, empty then valid, valid then empty,
  two empties), and the aggregate non-empty test answers each correctly; round
  2's single-empty-URL case still fails the fetch and is still caught. Worth
  revisiting only with a git version where the empty entry is actually used.

- **Defer the dirty-tree stop to step 2**, on the grounds that the pre-step-1
  reading is of a tree that has not been switched yet. Rejected: stopping
  before step 1 deletes anything is strictly better than stopping after it,
  and the re-run at step 2 already covers the window. The prose said this
  badly rather than doing the wrong thing, and now says it plainly.

**Accepted by decision** (left as they are, with the reason).

- **The script does not fold in the "base branch held by another worktree"
  case**, which makes the landing command fail. It is already a documented
  precondition with a relocate rule, owned by the worktree preflight and its
  own script; this one owns the landing decision, not the worktree topology.
- **A symref base branch plans against the ref it points at**, so the caller's
  `HEAD` confirmation fires as a false alarm. Exotic, and it fails safe.
- **An untracked file still stops the whole cleanup**, where a checkout would
  have carried it along harmlessly. That is the pre-existing behaviour of the
  guard this replaced, and conservative is the right direction on this path.

## Revisit when

- The reviewer's findings on this path stop being ordinary program bugs and
  start reporting decisions the plan gets wrong. Escalation converts a prose
  omission into a testable defect; if the findings still read as "the rule
  omits a case", the medium was not the problem after all.
- merge-cleanup ships an executable that _runs_ the destructive commands.
  Then the layer-2 stop costs nothing to replace (see above), and the plan
  script's fields become that executable's arguments rather than a caller's
  template inputs.
- `git switch` loses its experimental notice. Then the verb choice collapses:
  the script would emit `switch` for every name, and the two-refspec fetch
  would be the only thing the option-shaped case still needs.
