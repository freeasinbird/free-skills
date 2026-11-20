# Scored Eval

Use this reference from SKILL.md's Program Tier section. A scored eval runs
an agent skill on fixed cases in fresh sessions and grades each run by
program. It turns "does the skill still behave?" into one number that a
size or edit climb can hold.

## §scored-eval

These steps come from the evals built for the `merge-cleanup` and
`land-approved-prs` size climbs in free-skills, and from what those climbs
showed the evals missed. They describe a method. Any runner that meets it
fits.

### The Runner

A runner must:

- **Start each run fresh.** Use a new agent session with no user
  instructions, no installed skills, and no memory shared between runs.
- **Repeat each case.** Run each case at least three times, so the spread
  gives a noise band.
- **Grade by program.** Each case has a setup program that builds a
  fixture and a grade program that passes or fails the run.
- **Split the cases.** Run the climb cases by default, and the held-out
  cases only on request.
- **Hash the check.** Print a hash over the runner and every file of the
  eval, by relative path, so a frozen copy hashes the same as its source.

free-skills ships one that fits: `scripts/run-scored-eval.sh`. It drives
Claude Code only, and no skill installs it. Its case contract, from its
header:

```text
Case contract: `setup <fixture-dir>` builds the fixture; when it leaves a
<fixture-dir>/bin, that directory leads the agent's PATH. The agent starts
in <fixture-dir> with the case's evals.json prompt, `<fixture-repo>`
replaced by <fixture-dir>/repo, behind "Read <skill-copy>/SKILL.md and follow
it." Then `grade <fixture-dir> <final-message-file>` exits 0 for a pass and
prints one line per failed assertion.
```

Its last output line is
`score=<mean> band=<max-min> runs=<n> cost_usd=<sum> check=<sha256>`.

In a project without such a runner, say so before building cases. Offer
the owner three paths: copy or port a runner that meets the list above,
choose another program check, or report that this tier is unavailable.
Never grade runs by reading transcripts yourself; a judge-graded eval
belongs to the rubric tier.

### Build the Cases

1. **List the rules.** Name each instruction in the skill that directs
   behavior, by section. Note which rules also live in the skill's bundle,
   such as a script's `--help`, a script header, or a reference file. An
   agent rebuilds those from the bundle when the instruction is gone.
2. **Write one case per behavior.** Give each case a setup, a prompt, and
   a grade program. Prefer cases drawn from the skill's recorded failures.
3. **Grade behavior, not wording.** A grader reads state the run leaves:
   a stub's call log, the fixture's files and refs, or a fact in the final
   message, such as an issue number or a path. It never matches phrasing,
   so a shorter skill that keeps the behavior keeps the score.
4. **Keep graders out of reach.** Score each candidate from a copy of the
   skill without its `evals/` directory, so no run can read a grader, a
   case list, or an expected answer.
5. **Hold out cases.** Put a few cases on the held-out list, such as cases
   from recorded failures. The climb never scores them; they run once, at
   the end. In the `merge-cleanup` climb, only held-out cases caught two
   cuts the climb cases missed.

### Map the Coverage

Tie each rule to a case that fails when the rule is removed. Make a
variant of the skill without the rule, score the variant on that case, and
compare with the baseline.

- **Covered.** The variant's score on the case drops past the noise band.
- **Weakly covered.** It drops, but not past the noise band. In the
  `land-approved-prs` eval, removing `## Revoking Approval` failed its case
  in only 2 of 9 runs. List the rule in the blind-spot map.
- **Uncovered.** No case fails without the rule. Write a case that does,
  or list the rule in the blind-spot map.

Count the variant runs in the proving cost before running them. When the
budget can't cover a variant for every rule, start with rules that live
only in `SKILL.md`, and list the untested rest as blind spots.

### Choose the Known-Bad Case

Use a variant that drops one behavior-directing section and scores below
the baseline past the noise band. A copy with only the frontmatter isn't
enough. Its score shows how much the bundle rebuilds, not whether one rule
counts. `merge-cleanup`'s frontmatter-only copy scored 0.952 against a
baseline of 1.000. In the `land-approved-prs` eval, dropping
`### Hand-Back` scored 0.556 in every repeat.

Try sections whose rules live only in `SKILL.md` first. Record each section
whose removal didn't move the score as a blind spot.

### Freeze Last

Finish every edit to every hashed file before freezing: cases, graders,
the held-out list, and any README in the eval directory. Then copy the
runner and the eval directory into the climb directory, record the hash,
and take every recorded score from that copy.

Keep proving results out of hashed files. Put them in the proof record.
When the project wants results in a hashed README, write them first, then
freeze and take the recorded scores again from the frozen copy. Count those
runs in the cost. A README edit after the freeze changes the source's hash,
and `hill-climb` then can't accept the proof record.

For `scripts/run-scored-eval.sh`, this function recomputes its `check=`
value. Pass the runner and the eval directory, from the source or from the
frozen copy:

```sh
check_hash() {
  {
    printf '%s  run-scored-eval.sh\n' "$(shasum -a 256 <"$1" | cut -d' ' -f1)"
    (cd "$2" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(shasum -a 256 <"$f" | cut -d' ' -f1)" "${f#./}"
    done)
  } | shasum -a 256 | cut -d' ' -f1
}
```

Compare its value with the `check=` the proving runs printed. On a host
with `sha256sum` and no `shasum`, use `sha256sum` in its place.

### Mark the Guards

List the skill's other checks as guards, each with its baseline result.
Mark the structure, lint, and format checks cheap, since each costs less
than one score. Mark another scored eval expensive. A guard failure found
before scoring saves a full score.
