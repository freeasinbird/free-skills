# Agent-setup instructions an agent cannot follow

Issue #76 collected seven defects in `agent-setup` that degrade operation
without changing behavior. Two of them needed a decision rather than an
edit; a third overturned part of the issue's own acceptance criteria.

## Decisions

- **Init's post-write check documents a per-profile split rather than
  growing a comparator flag.** Init pastes the managed blocks by hand and
  every later comparison depends on their byte-exactness, so `--require-all`
  is the natural gate. Under Standard the deliberately absent `devlog`
  block fails strict mode, so the alternative was an `--allow-missing KEY`
  flag that would let one exit code carry the whole gate. Rejected: it adds
  parsing surface and a second way to express a profile, when the run
  already prints one line per key and Standard's check is "exit 0 with
  `missing: devlog` as the only missing line". Decided by the owner.
- **The CLAUDE.md scaffolding gate in #76 was dropped; only the drift rule
  changed.** The issue read unconditional CLAUDE.md scaffolding as an
  architecture-invariant-2 violation. Invariant 2 governs what the
  _running agent_ is assumed to be able to do, not whether a
  product-named file lands in the target repo, and the skill already
  scaffolds `.github/pull_request_template.md` with no forge gate, so a
  detection heuristic (`.claude/`, an existing CLAUDE.md) would buy
  nothing and misfire on a fresh repo. The load-bearing half of the item
  was the drift rule: the template is a five-line pointer, so a
  downstream CLAUDE.md holding real instructions diffs as a total
  rewrite and "offer to refresh" is an offer to delete it. That case now
  routes to migrate-then-reduce. Decided by the owner against the
  issue's checklist; the acceptance criterion is recorded as dropped on
  the issue rather than silently unchecked.
- **Marker validation precedes profile discovery in update mode.**
  Ordering, not new content: the profile step could run a whole
  legacy-migration negotiation and then defer to a validation step that
  might abort the run. Nothing reads the file for meaning before its
  boundaries are trusted. Steps 5-11 keep their numbers so
  `references/scaffolding.md`'s "update step 9" pointer still lands, and
  the same constraint kept init's new verification inside step 5 instead
  of becoming a step 6.

## Verification findings

- The pre-fix comparator's argument handling failed two ways, not one:
  a flag typo alone reported "AGENTS.md not found: --require_all", but a
  typo _ahead of a path_ was silently dropped, so a `--require_all` run
  exited 0 as a tolerant one. The silent false pass is the worse half and
  is what the new rejection arm and its test case target.
- Running the pre-fix instruction verbatim (from the skill directory,
  relative project path) exits 1 with "AGENTS.md not found: AGENTS.md",
  confirming the issue's first item as reproduced rather than inferred.

## Review-driven scope addition

Review surfaced a class the issue never named: boundary invariants
checked conditionally, per known key, or per observed spelling, so a
file could reach the comparison with untrusted boundaries. Every
instance was reproduced before fixing, and all were fixed here rather
than deferred, because the PR was already rewriting that validation and
a deferred half-check would contradict the mode-detection rule this PR
widened.

- The nested `project:done-checks` pairing and order checks ran only
  when a managed `done` opener existed, so with `done` opted out a lone
  or reversed nested marker exited 0 and re-adopting `done` later would
  inherit it. Pairing and order are now unconditional; only containment
  in the `done` block still depends on that block.
- Per-key pairing cannot see two overlapping blocks: open `branches`,
  open `commits`, close `branches`, close `commits` leaves every key
  paired once and in order, so the run reported ordinary drift and
  accepting the refresh would have deleted the inner opener. Block
  ranges are now checked for global disjointness.
- The marker-text scans each matched on a **spelling**, and every
  spelling let the next mangling through: comment-leading lines missed
  prefixed markers, a per-key literal missed unknown keys, `[a-z0-9-]+`
  missed uppercase and underscores, and a contiguous-key pattern missed
  internal spaces plus `:*bogus`. Three review rounds went to widening
  that pattern one variant at a time, which is precisely the cost the
  fix-the-class rule predicts. What closed it was dropping the key from
  the detection altogether: a line carrying the `agents-md` namespace
  token and a closing arrow is claiming to be a marker, so it must be an
  exact marker line, with the documented `*` wildcard dropped before the
  test (and only when no key character follows). One scan replaced
  three, and the input space (case, punctuation, internal and leading
  spacing, prefix, suffix, comment opener, broken and missing closing
  arrow, wildcard lookalike, both
  namespaces) is enumerated once as tests, including acceptance cases
  pinning the prose forms so a later widening cannot start rejecting
  downstream files that document their own setup. The enumeration was
  derived from every mention actually present in the canonical file and
  this repo's AGENTS.md, not guessed.

  Two corrections worth recording, both from over-correcting. First,
  consolidating to a single scan initially traded one spelling for
  another, requiring a well-formed `-->`, which silently regressed a
  case the three-scan version caught
  (`<!-- agents-md:managed:unknown -- >`); running the old script against
  the new fixture is what surfaced it. Second, dropping the delimiter
  requirement widened the trigger to the bare `agents-md` token, so an
  ordinary downstream comment (`<!-- see docs/agents-md.md -->`) aborted
  the whole run: a false positive is not the safe direction here, since
  validation failure blocks the update entirely.

  Those two corrections are the same oscillation, and it took a third
  round to see the shape of it: successive adversarial cases pull the
  detector wider (missed mangling) and then narrower (false positive),
  and `origin/main`'s version fails in **both** directions too, so
  neither end is a safe resting place. What settled it was requiring two
  independent signals rather than tuning one: a marker namespace claim
  is the `agents-md` root, a short mangled separator, a section word,
  **and** the colon that introduces a key. The separator half absorbs
  dropped or doubled colons; the key-colon half is what distinguishes a
  marker claim from prose that merely says agents-md and managed in one
  comment. A form with no key colon at all is explicitly out of scope,
  documented in the script, because reaching it re-introduces the false
  positive. The matrix now pins both directions, which is what every
  earlier round lacked: it only ever added rejections.

## Open trade-off: marker-claim detection cannot satisfy both findings

Review round 14 asked for `<!-- agents-md, managed: do not edit
manually -->` to be accepted as prose. Round 8 asked for
`<!-- agents-md:managed:unknown key -->` to be rejected as a mangled
marker. On a single-line detector these are the same shape: namespace,
colon, then a multi-word tail. Implementing the round-14 request (a
key must be one token ending the comment) turns the round-8 case green
again; keeping round 8 keeps the round-14 false positive. Any tie-break
by token count or key character class is the spelling trap this surface
already paid nine review rounds for.

Left unresolved deliberately, with the current behaviour favouring
rejection (round 8's direction), because a false negative degrades to
"drift the user reviews" while the false positive blocks updates until
someone edits prose, and both directions are pinned by the matrix so
either choice is a one-line change plus a test flip.

Three ways out, for whoever picks this up: accept the false positive as
documented behaviour (downstream files avoid `managed:` in prose
comments); accept the false negative and rely on the diff review; or
redesign so the scan only polices lines inside managed block ranges,
where prose is not expected, and requires exact-marker shape outside
them. The third looks best and is a bigger change than this PR should
carry.

Revisit when a downstream maintainer objects to an unrequested
CLAUDE.md, which would reopen the gating question the second decision
closed; when a project legitimately carries a stray exact nested
marker, which the unconditional pairing rule now rejects; or when
someone takes the marker-claim trade-off above.
