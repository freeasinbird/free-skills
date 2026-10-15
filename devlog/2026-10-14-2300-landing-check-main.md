# Add a Landing Check to free-skills Main

Issue #296 gives free-skills the landing check its own agent-setup now treats
as the baseline (#292, `devlog/2026-10-14-1438-landing-rule-baseline.md`).
Before it, `main` had no branch protection and no rulesets, so authors
repeated CI, diff review, and readiness by hand whenever the base moved.

## Decisions

- **Chose a fan-in job over listing contexts.** `markdown.yml` gains
  `markdown-required`, which needs `markdown-checks` and every matrix leg.
  Requiring only `check` and `markdown-checks` would leave the script test
  matrices non-gating. Listing every matrix context would drift each time a
  script is added; #299 had just added one. `needs:` can't cross workflows,
  so `commit-messages.yml`'s `check` stays required on its own.
- **Kept `if: always()` with an explicit result test.** Without it, a failed
  leg skips the fan-in, and GitHub counts a skipped required check as
  passing. This follows `skills/agent-setup/references/audit.md`
  §required-checks.
- **Chose classic branch protection over a ruleset.** Agent-setup's audit
  command reads `branches/{branch}/protection`. A ruleset doesn't appear
  there, so the audit would still report the gap.
- **Chose required checks plus the up-to-date rule over a merge queue or land
  command.** `strict: true` makes GitHub rerun CI on the branch combined with
  the tip before merge, which is the landing check the baseline asks for.
  A land command is #293's separate work.
- **Bound both contexts to the GitHub Actions app (ID 15368).** The binding
  keeps another app from satisfying a context with the same name.
- **Recommended `enforce_admins` on.** Agents run with the owner's admin
  token, so an unenforced rule wouldn't bind them. The owner can turn it off
  for an emergency merge. The owner confirms this before protection is
  applied.

## Revisit When

Revisit when protection must cover more than these two workflows, when either
workflow gains a `paths:` filter (a required context that never reports
blocks every merge), or when the repository adopts a merge queue.
