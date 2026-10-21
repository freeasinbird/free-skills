# Remove Duplicated Managed Guidance

For [#327](https://github.com/freeasinbird/free-skills/issues/327), chose to
remove repeated rules from the managed blocks where an existing pointer
already requires reading their other home. No rule moves behind a new read
trigger. The readiness definition and approval freeze remain in AGENTS.md.

This follows the [canonical readability decision](2026-08-24-1130-canonical-readability.md):
keep rules used throughout a work unit in the core and step-local detail in
the workflow reference. The [context-discipline decision](2026-07-07-1213-context-discipline-section.md)
also treats payload trimming as a small token saving whose main benefit is
attention and context headroom.

## Rule Map

Line numbers below refer to the unchanged destination files at
`165a9e928b569d826ad949824d05465c36131807`. Each row maps a removed sentence
or clause to its remaining home.

| Removed From the Managed Blocks                                                                              | Remaining Home                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Record final reasoning, rejected options, changed assumptions, and important verification findings.          | `devlog/README.md:22–24`, "Record lasting reasons and evidence."                                                                                  |
| Include a useful "Revisit when ..." condition.                                                               | `devlog/README.md:25–27`, "Add a 'Revisit when ...' condition when useful."                                                                       |
| Exclude diffs, test logs, chronology, and PR status.                                                         | `devlog/README.md:24`, the exclusions in "Record lasting reasons and evidence."                                                                   |
| Update an active note while the work unit or PR is open.                                                     | `devlog/README.md:15–17`, "In the ordinary case, keep at most one permanent note per work unit or PR."                                            |
| Freeze the note when the PR merges.                                                                          | `devlog/README.md:17–18`, the same bullet.                                                                                                        |
| Track deferred work in issues and link the note from an issue that starts there.                             | `devlog/README.md:28–29`, "Put actionable follow-ups in issues."                                                                                  |
| Keep historical follow-up links without a second status record.                                              | `devlog/README.md:29–30`, the issue owns current status.                                                                                          |
| Put non-actionable observations in "Revisit when ...".                                                       | `devlog/README.md:25–30`, reconsideration conditions need no status tracking; actionable follow-ups belong in issues.                             |
| An up-to-date required check, merge queue, or land command reruns CI on the refreshed branch.                | `docs/agent-workflow.md:51–57`, §handing-off step 3.                                                                                              |
| A refresh needs its diff read by the automated reviewer or by self-review.                                   | `docs/agent-workflow.md:59–63`, §handing-off step 3. The shortened bullet also retains the CI/review distinction and watch restart.               |
| Without a landing check, repeat CI, final diff review, and readiness by hand.                                | `docs/agent-workflow.md:51–57`, the manual integration pass in step 3, followed by checks, self-review, and watch closure in steps 4–6 (`68–82`). |
| Read `git range-diff` after a conflicted rebase.                                                             | `docs/agent-workflow.md:47–49`, §handing-off step 3.                                                                                              |
| Diff size does not define risk; a mechanical change outside the risk list relies on CI and the bot reviewer. | `docs/agent-workflow.md:286–292`, §pre-push-review's first paragraph.                                                                             |
| Check for an installed review-watch skill and use it when present.                                           | `docs/agent-workflow.md:12–31`, §handing-off step 1.                                                                                              |
| Start the watch from PR open or push, count only later activity, and restart from each new push.             | `docs/agent-workflow.md:33–40`, §handing-off step 2.                                                                                              |
| Refresh from the current base and record its commit.                                                         | `docs/agent-workflow.md:42–51`, §handing-off step 3.                                                                                              |
| Wait for required checks and never hand off known-red work.                                                  | `docs/agent-workflow.md:68–70`, §handing-off step 4.                                                                                              |
| Self-review the final diff.                                                                                  | `docs/agent-workflow.md:72–73`, §handing-off step 5.                                                                                              |
| Close the watch by handling findings or recording its bounded timeout.                                       | `docs/agent-workflow.md:75–82`, §handing-off step 6.                                                                                              |
| Stop and summarize for the human reviewer.                                                                   | `docs/agent-workflow.md:84–87`, §handing-off step 7.                                                                                              |

The existing pointers still require the devlog protocol, §handing-off, and
§pre-push-review at their original steps. The heading "Handing Off the PR"
and all managed marker names remain intact.

## Boundaries and Rejected Options

Kept the fresh-eyes risk list. It includes contract changes and untested
behavior, which the finish-line refute-first list does not. Only the
mechanical-change clause duplicates the pointed procedure.

Rejected moving "Find notes from the work first" and "Treat old notes as
evidence, not rules" into the README. That file does not contain those rules.
Downstream syncs refresh `docs/agent-workflow.md`, but a README refresh is only
an offer under [the scaffold drift rules](../skills/agent-setup/references/managed-blocks.md#scaffold-files),
lines 142–158. Moving them could leave downstream projects without either rule.

Revisit when [#328](https://github.com/freeasinbird/free-skills/issues/328)
moves more one-step procedures behind read triggers. That change must assess
when each rule gets loaded; this change only removes existing duplication.
