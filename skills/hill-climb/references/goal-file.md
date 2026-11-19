# Goal File

Use this reference from SKILL.md's Intake section. The goal file is the
owner's statement of the climb. Other skills that run a climb use these fields
as their interface.

## §goal-file

Draft the file in the climb directory, fill every field, and show it to the
owner. A field left blank needs the owner's answer before sign-off.

```markdown
# Climb: <slug>

- Goal: <what should get better, in one sentence>
- Metric: <what the check measures>
- Better direction: <higher or lower>
- Target: <the score that ends the climb>
- Guards: <checks that must not regress, each with its current result>
- Check: <the command, reference, or rubric, and every file it reads>
- Check tier: <program, reference, or council at rung 1 or 2>
- Score rule: <for council, how member scores become one number>
- Screen: <for council, the program or single judge that screens attempts>
- Reference examples: <for council, anchors for the rubric's scale>
- Known-good case: <path or description>
- Known-bad case: <path or description>
- Held-out cases: <cases scored only at the end>
- Budget: <attempts, time, or runs; for council, runs per attempt>
- Stop rule: <target plus a minimum of N attempts>
- Plateau: <reverted attempts in a row; default 5>
- Ratchet stages: <declared next stages, or none>
- Climb directory: <durable path outside the repository>
```

Field notes:

- **Guards.** List each guard with its baseline result, so a regression is
  plain. A scored guard holds while it stays within its noise band of that
  result.
- **Check.** List the files the check reads that a candidate could change,
  such as tests, fixtures, and build targets. Freezing copies all of them.
- **Score rule.** Default to the lowest member's mean score, which matches a
  target such as "every judge 9 or higher". The noise band is the spread of
  this one number across baseline rescores.
- **Reference examples.** Keep them apart from the known-good and known-bad
  cases. A judge that has seen a case as an anchor recognizes it, so a case
  used as both proves nothing.
- **Held-out cases.** Keep them out of every attempt's scoring. Score them
  once, at the end.
- **Budget.** For a council-scored climb, state the panel's runs for each
  attempt that reaches it.
- **Stop rule.** The minimum number of attempts stops a lucky early score
  from ending the climb.
- **Ratchet stages.** Each stage names its own metric, target, and check. The
  earlier stage's metric becomes a guard at its final score.
- **Sign-off.** Record it in the attempt log, not in this file: who signed
  off, when, and the file's hash. The climber checks the hash before each
  attempt and never edits the file.
