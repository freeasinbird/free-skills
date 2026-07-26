# Re-presenting merge-cleanup's packed paragraphs as bullets

merge-cleanup's identify section was a single 72-line prose paragraph
carrying fifteen independent rules on the one path the skill says it must
never risk, with two more packed paragraphs at the verify section and the
worktree preflight. This repo ships prompt-crafter, whose defect taxonomy
ranks that shape as top-severity (buried rules in a dense paragraph are the
first an agent drops), so the skill most needing its rules followed was
violating the repo's own rule about how to get rules followed (#78).

## Decisions

- **Chose one rule per bullet with the wording preserved, over rewriting the
  rules for concision.** Concision was never the defect; retrievability was.
  Preserving wording is also what makes equivalence measurable against the
  base blob rather than asserted.
- **Chose to split evidence into `references/hazards.md` on a
  mechanism-versus-consequence line, not a rule-versus-prose line.** Every
  "so X breaks" clause stays in `SKILL.md`; only "here is why git behaves
  that way, and here is the repro" moves. The reference is evidence only, so
  an agent that never opens it makes the same choices, per the contract
  set for `await-pr-review`'s references (2026-07-02 note).
- **Chose the `§slug` pointer convention** already used by agent-setup's
  scaffolding reference, over markdown `file.md#anchor` links, which appear
  nowhere in this repo for intra-skill pointers.
- **Chose to move the proofs the issue named even where they sit inside the
  numbered steps 2-4** (ignored-file overwrite, `-d`-checks-upstream), while
  leaving those steps' structure untouched: they are already one rule per
  step, so only their evidence needed relocating. Owner's call, taken at
  planning time.
- **Chose three `###` subheadings inside the identify section**, since
  fifteen flat bullets is the same dense block in another shape.
- **Rejected importing the extra scratch-repo repros that live only in the
  2026-07-02 note** (the `pull origin release` FETCH_HEAD result, the lease
  CAS verification, exit codes). Importing them would add content under a
  re-presentation-only claim and put rows in the equivalence table with no
  source in the base blob.
- **Rejected keeping the prose "Two hard rules on the resolved name" count.**
  The count was a prose scaffold for rules a reader had to track by hand; the
  section heading now spans four bullets (the two hard rules, the checkout
  exception, the untrusted-input rule). Nothing was weakened: the exception
  still sits directly after the rule it qualifies and opens with
  "Exception:".

## Refute-first pass (destructive path)

Two independent fresh-context lenses, both read-only, per the finish line's
refute-first requirement for destructive paths. Lens A re-derived the rule
inventory from `git show origin/main:skills/merge-cleanup/SKILL.md` and hunted
for changed meaning; lens B walked ten scenarios through the new text as a
literal executing agent (squash merge with no CLI, rebase merge with a CLI,
fork clone with no head remote, tag shadowing the base branch, unquotable
branch name, base branch held by another worktree, ignored file tracked on
the base, cross-repo stacked PR, ambiguous `--merged` output, post-merge
force-push).

Confirmed and fixed:

- **The worktree remedy's conjunction was lost.** The base paragraph joined
  two obligatory remedies with "and" and made the stop conditional on that
  pair; three sibling bullets read as options, so an agent could resync in
  the primary worktree, skip `git worktree remove`, and stall at step 4 with
  the remote branch already deleted. The two remedies are now one bullet with
  an explicit "and", and the fallback's "that" again refers to the whole
  arrangement, with the step-1 prohibition inside the bold lead.
- **The `ls-remote` tail-match hole was generalized away.** The base text
  named two distinct resolution holes; the first draft's inline summary named
  only the tag one, leaving step 1's exactly-one-line acceptance criterion
  with no rationale anywhere in `SKILL.md` (a tag cannot appear in
  `ls-remote --heads` output). The tail-match clause is inline again, with
  only the `bar/<branch>` example and the lookup order in the reference.
- **Step 4's surviving claim read as false without its mechanism.** With the
  upstream mechanic moved out, "it would delete with a mere warning" asserts
  something an agent knows is wrong for the default case, inviting it to skip
  the explicit ancestry check. The upstream clause is inline again.
- **The head-field collection was the file's only second-level bullet**,
  making the input to three later guards the most skippable line in the
  section. Promoted to a top-level bullet.
- **The new subheadings created a phase illusion**: the branch-resolution
  subsection uses `<base-remote>` while the subsection defining the remote
  roles comes two subheadings later. Bullet now says the roles are resolved
  below.
- **Back-references in the reference file were one-way.** §tag-shadow did not
  name step 1 as a consumer, and §merged-not-ancestor named step 4 while step
  4 carried no pointer. Both closed.

Rejected by verification, do not re-raise:

- The "verified head OID" definition losing its inline bold marker. It stayed
  in the verify section, its text is unchanged, both consumers (step 1's OID
  match and lease, step 4's `-D` confirmation) still reference it by name,
  and it now leads a bullet, which is more prominent than a mid-paragraph
  bold, not less.
- Any decision having moved into the reference. All six sections were read
  against a normative-language test: every relocated passage describes git
  behavior or how it was verified, and the only imperative in the file is
  about when to read it.
- Narrowing of the universal scopes ("every PR-record lookup", "every ref a
  guard resolves or compares, the base side included", "every name the PR
  supplies", "never a bare `origin`"). All four are verbatim, and the
  issue-close section's back-reference to the identify pin still resolves.
- Folding the two ask-the-user rules together. They survive as separate
  bullets with their distinct triggers.

Accepted by decision:

- The added navigational text: the identify section's framing sentence, the
  reference preamble, and the "Relied on by" back-reference lines. These are
  additions under a re-presentation claim, but none is a rule, and the
  back-references are what makes the split auditable in the other direction.
- The dropped "Two hard rules" count (see Decisions).

Out of scope, filed instead of fixed:

- merge-cleanup's untrusted-name rule stops at quoting; #83 verified that
  quoting cannot carry a value containing a single quote and does nothing
  about git's own argument parsing (a leading-hyphen ref name needs `--`).
  That is a missing guard, not a presentation defect.
- `git worktree remove` run from inside the worktree being removed succeeds
  and deletes the caller's working directory (lens B verified on git 2.50.1);
  the preflight's remedy does not say to run it from the other worktree. Same
  wording as the base file, so not a regression here.

## Verification instrument

Equivalence is measured, not asserted: the mapping table in the PR is
re-derived from the base blob, and a code-span conservation diff between the
base blob and the new pair of files shows every backticked token accounted
for (two deliberate replacements by more precise forms). The pointer check
runs both directions, and must normalize line wrapping: a `§slug` pointer can
wrap across lines, so a naive line-oriented grep reports a false unreferenced
section.

Revisit when: a third packed paragraph appears in any skill, or when the
structural checker in #79 lands and can enforce the paragraph-length and
pointer-payoff checks this note ran by hand.
