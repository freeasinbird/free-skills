# Proof Record

Use this reference from SKILL.md's Write the Proof Record section.
`prepare-hill-climb` writes the record, and `hill-climb`'s Prove the Check
section reads it. Its fields are the interface between the two skills.

## §proof-record

Write the record only for a proven check: one whose known-good versus
known-bad gap exceeds its noise band. Save it as `proof-record.md` in the
climb directory, beside the draft goal file. Write "none" in a field the
tier doesn't use.

```markdown
# Proof: <slug>

- Goal file: <path of the draft goal file>
- Artifact: <every path the score reads that a candidate could change>
- Baseline revision: <full commit SHA the baseline scores were taken at>
- Check command: <the command that scores a candidate from the frozen copy>
- Check source: <repository paths of every file the check reads>
- Frozen copy: <path of the frozen check in the climb directory>
- Frozen hash: <the hash of the frozen copy>
- Hash command: <the command that recomputes the hash from the frozen copy
  and from the check source>
- Baseline scores: <climb cases, and held-out cases when taken>
- Noise band: <spread of the baseline rescores, and the number of rescores>
- Known-good: <the case and its score>
- Known-bad: <the case, what it removes, and its score>
- Gap: <known-good minus known-bad, beside the noise band>
- Cost per score: <money and time for one score, with the settings>
- Proving cost: <total money and time the proving runs spent>
- Target basis: <a pilot's ratio, a benchmark, a service level, or the
  owner's own number>
- Guards: <each guard, its baseline result, and cheap or expensive>
- Environment: <for a program check, each pinned version or condition>
- Council panel: <for a council check, the rung, and each member's
  provider, model, and effort>
- Coverage map: <for a scored eval, each rule and the case that fails
  without it>
- Blind spots: <each thing the check can't see, its evidence, and the
  Constraint proposed for it, if any>
```

Field notes:

- **Artifact and baseline revision.** List more than the file under climb
  when the score reads more. A scored eval reads the whole skill copy
  without `evals/`, so its bundle belongs here too. `hill-climb` compares
  these paths at the climb's starting revision with the same paths at this
  revision. Any difference means the baseline no longer describes the
  artifact. Use a revision the project's remote holds.
- **Check command.** Include every setting that changes the score, such as
  the model, the repeats, and the split. `hill-climb` accepts the record
  only when its goal file runs this command with these settings.
- **Frozen hash and hash command.** The command must cover every file under
  Check source, and give the same value for the frozen copy and for the
  check source at any revision that holds it unchanged. Hash by relative
  path, so the copy's location doesn't matter.
- **Scores.** Take every score here from the frozen copy, after the last
  edit to any file the hash covers.
- **Cost per score.** Name the settings that set the cost, such as the
  model, repeats, and parallel jobs. `hill-climb` uses this to state a
  climb's budget.
- **Council panel.** This is the recorded panel that `hill-climb` names on
  its first council call.
- **Blind spots.** Name the evidence for each, such as a variant that
  dropped a rule and still scored the baseline. A blind spot proposed as a
  Constraint names this record as its source in the goal file.
