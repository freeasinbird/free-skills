# Standard Files and Repo Settings Audit

Use this reference at the SKILL.md audit steps in init and update mode.

## §standard-files

Audit for these during init and update. Report presence/absence; don't
create them (content is project-specific), just flag what's missing and
note why it matters.

### Root Signal Files (GitHub-Recognized)

| File                 | Purpose                                         | When needed       |
| -------------------- | ----------------------------------------------- | ----------------- |
| `README.md`          | Landing page: what, who, how to start           | Always            |
| `LICENSE`            | Legal terms (GitHub auto-detects)               | Always            |
| `CHANGELOG.md`       | Release history (Keep a Changelog format)       | Shipping releases |
| `CODE_OF_CONDUCT.md` | Community standards (GitHub links from sidebar) | Open-source       |
| `SECURITY.md`        | Vulnerability reporting policy (GitHub sidebar) | Has users         |

### CI Configuration

The workflow conventions assume CI exists: the finish line polls
required checks, the commits section requires every commit green, and
the definition of done expects a successful build, passing tests, and clean
lint and formatting. Check for any of:
`.github/workflows/`, `.circleci/`, `Jenkinsfile`, `.gitlab-ci.yml`,
`Makefile` with a `ci` target, or equivalent. If none is found, flag it:
"Your workflow conventions depend on CI but no CI configuration was
detected." Don't create a CI config (too project-specific), just warn.

### Scaffolded by This Skill (Created, Not Just Audited)

| File                               | Purpose                                                   |
| ---------------------------------- | --------------------------------------------------------- |
| `CLAUDE.md`                        | Agent entry point; `@`-imports AGENTS.md                  |
| `AGENTS.md`                        | Development conventions (single source)                   |
| `CONTRIBUTING.md`                  | Human contribution guide                                  |
| `devlog/README.md`                 | Decision-note protocol (Decision-log/High-assurance only) |
| `.github/pull_request_template.md` | PR body scaffold                                          |
| `docs/agent-workflow.md`           | Step-local procedure the managed blocks point at          |

### docs/ (Project-Specific; Only `docs/agent-workflow.md` Above Is Canonical)

| File                   | Purpose                                       | When needed      |
| ---------------------- | --------------------------------------------- | ---------------- |
| `docs/architecture.md` | System design, data model, module boundaries  | Non-trivial code |
| `docs/concepts.md`     | Domain glossary, mental model for the project | Domain language  |

Note: projects may have additional `docs/` files for format specs,
API references, or other concerns. These two are the baseline worth
flagging; everything else is project-specific.

## §repo-settings

Several canonical conventions name or benefit from repository settings:
merged branches auto-delete, a real merge commit is the only merge method,
the merge commit message is the PR title alone, and stale PR branches are
surfaced for an explicit update. Restricted Actions workflow permissions also
keep the repository token at least privilege unless a workflow declares a
specific need. The audit keeps that setup true so the canonical text's manual
fallbacks stay rare.

Treat this as
**detect → report → offer to align**, never a silent mutation. Changing repo
settings needs admin rights the agent may not have, so confirm before applying;
otherwise tell the user the desired state and where to set it.

Settings the conventions use or the audit recommends:

| Setting                                        | Why it matters                                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Auto-delete head branches on merge             | `branches`/`pull-requests` state merged branches auto-delete                                |
| Merge-commit-only (squash and rebase off)      | `commits` needs real merge commits for the `--first-parent` history                         |
| Merge commit message = PR title only           | keeps the body's review material out of history; the title carries the `--first-parent` log |
| Always suggest updating pull request branches  | surfaces a stale branch and offers an explicit refresh action                               |
| Default workflow token permissions = read      | makes workflows declare the specific write permissions they need                            |
| Actions cannot create or approve pull requests | prevents the repository workflow token from creating or approving changes by default        |

These toggles are forge-specific. On GitHub, check and (after confirming)
set them with `gh`; skip or adapt this on other forges, which expose
equivalent settings:

```sh
# Check current state
gh api repos/{owner}/{repo} \
  --jq '{delete_branch_on_merge, allow_merge_commit, allow_squash_merge,
         allow_rebase_merge, merge_commit_title, merge_commit_message,
         allow_update_branch}'

gh api repos/{owner}/{repo}/actions/permissions/workflow \
  --jq '{default_workflow_permissions, can_approve_pull_request_reviews}'

# Align (only after confirming with the user)
gh api -X PATCH repos/{owner}/{repo} \
  -F delete_branch_on_merge=true \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false \
  -F allow_update_branch=true \
  -f merge_commit_title=PR_TITLE \
  -f merge_commit_message=BLANK

gh api --method PUT repos/{owner}/{repo}/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

On GitHub, `allow_update_branch` is the **Always suggest updating pull request
branches** setting under Settings → General → Pull Requests. On other forges,
look for the equivalent stale-branch/update suggestion. If the setting or its
read is unavailable because of the forge, plan, or permissions, report that
limitation clearly and point to the canonical "Handing Off the PR" manual
freshness procedure; never infer that an unread setting is disabled.

Before offering to restrict Actions workflow permissions, inspect
`.github/workflows/` for jobs that rely on implicit write access or use the
repository workflow token to create pull requests. Report each affected
workflow. Prefer explicit workflow or job-level `permissions` for required
write scopes while retaining the read-only default. If creating pull requests
from Actions is intentional, surface the conflict and ask whether to keep that
repository-level exception; a workflow cannot override the repository setting
that prevents Actions from creating or approving pull requests. An owning
organization or enterprise may also lock either value. Report that policy
constraint instead of treating the setting as unsupported or disabled.

## §required-checks

When branch protection is configured, required status checks are matched
by context name, and a skipped required check counts as satisfied. Both
failure modes bite when a single CI job becomes a matrix. Renaming the
job leaves the required context never reporting, so nothing can merge.
Keeping the name via a bare fan-in job (`needs:` alone) fails open,
because a failed matrix leg skips the fan-in and the skipped check
passes. Keep the required context reporting through a fan-in job with
`if: always()` and an explicit result test:

```yaml
check:
  needs: test # the matrix job
  if: always() # run even when a leg failed
  runs-on: ubuntu-latest
  steps:
    - run: test "${{ needs.test.result }}" = "success"
```

During the audit, compare the protected branch's required contexts against the
workflow job names and flag any context no job reports, and any bare fan-in
guarding a matrix. Also inspect whether required checks enforce current-base
freshness. On GitHub, `.required_status_checks.strict: true` is **Require
branches to be up to date before merging**:

```sh
gh api repos/{owner}/{repo}/branches/{branch}/protection \
  --jq '{strict: .required_status_checks.strict,
         contexts: .required_status_checks.contexts,
         checks: .required_status_checks.checks}'
```

When required checks exist and strict freshness is off, report it and offer to
enable it, preserving the existing check names and app bindings if the user
accepts. Never change protection silently. If branch protection, strict checks,
or their read is unavailable because of forge support, plan, or permissions,
report the limitation and point to the canonical manual freshness procedure.
A forge merge queue may be reported as an optional capability for a busy
repository, but it is not a canonical requirement.

## §forge-record

Forge CLI calls such as `gh --repo` need the forge host and the `owner/name`
slug. Both are plain when the remote URL names the forge's canonical host,
such as `github.com`. A remote whose host is an SSH alias hides them, for
example `git@bnw.github.com:owner/name.git` or `git@github-work:owner/name.git`.
An agent that reads that URL sees an unfamiliar host. One that guesses the
owner from a sibling project sends every call to a repository that doesn't
exist, and the forge answers each one with a resolution error.

During init and update, list the remotes with a userinfo-redacted `git remote
-v`. Validate any forge record AGENTS.md already carries against the base
repository's remote, whatever that remote's host. Both consumers prefer the
record over the remote, so a transfer or a switch to a canonical URL can leave
a stale record routing them. Offer a new record only when the base remote's
host isn't the forge's canonical host: an entry in an unmanaged,
project-specific section that states the forge host and the `owner/name` slug.
Treat the audit as **detect → report → offer to write**, never a silent
mutation:

- Redact userinfo from every remote URL as it is read. `git remote -v` and
  `git remote get-url` print an HTTP(S) URL's password or token verbatim,
  so pipe either through `sed -E 's#://[^/@]*@#://***@#'`. Host and path
  survive it, so every derivation below still works, and an SSH URL's
  `git@` is untouched. Never print or record a credential; report only that
  one was present.
- Derive the slug from the base remote's fetch URL, read with that redacted
  `git remote get-url <remote>`, as `owner/name` without `.git`. One remote
  can carry a separate push URL naming a fork, which `git remote -v` lists
  beside the fetch URL, so treat `git remote get-url --push` output as role
  evidence only.
- Treat `ssh -G <alias>` as a hint and never as the answer. It reports the
  SSH transport endpoint, so it echoes an unconfigured alias back with exit
  0, and it names a transport-only host such as `ssh.github.com` under a
  port-443 config.
- Confirm the host with `gh repo view --json nameWithOwner,url` in the
  audited checkout, whose `url` names it. Accept that answer only when its
  `nameWithOwner` matches the derived slug, because a second remote or a
  configured `gh repo set-default` points the argument-less form at another
  repository. `gh` maps any `*.github.com` alias to `github.com` and no
  other, so a failed resolution is expected for other aliases, not evidence
  against the record. Ask the user when `gh` cannot resolve the alias or
  answers for another repository.
- Offer to add the record, to correct one that disagrees with the base
  repository's remote, or to remove one whose repository that remote no
  longer names. Identify that remote first, and record any other remote by
  its role only, so a fork's head remote never rewrites the base slug. Show
  the exact text first; this is unmanaged project content.

Write the record following the reviewer-record pattern, as a bullet in the
same project-specific conventions section:

```markdown
- **Use `owner/name` on GitHub for forge calls.** This project has the
  following forge record:

  - **Host:** `github.com`.
  - **Slug:** `owner/name`.
  - **Remote:** `origin` is `git@bnw.github.com:owner/name.git`;
    `bnw.github.com` is an SSH host alias for `github.com`. Pass
    `--repo owner/name` to `gh`; never derive the owner from a sibling
    project.
  - **Consumers:** `await-pr-review` and `merge-cleanup` read this record
    before inferring a repository from a remote.
```

The host records what the alias resolves to, so the `owner/name` slug is
correct only for a CLI whose default host is that host. A canonical-host
remote needs no new record, so report nothing beyond validating one that
already exists. A fork layout records the base repository's slug and names
the head remote's role beside it. Never move the record inside a managed
block, and never delete or rewrite one during a sync.
