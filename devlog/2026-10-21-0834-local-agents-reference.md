# Keep Project Check Details Behind Read Instructions

Chose a project-local reference over shortening rules into vague summaries.
The owner requested less noncanonical AGENTS.md text without changed project
behavior. Full check details remain available at the steps that need them.

Chose `docs/project-checks.md` over `docs/agent-workflow.md` because the latter
mirrors a canonical scaffold. Local verification details should not enter the
downstream workflow payload. This follows the imperative-read-trigger boundary
in `2026-08-21-1049-core-reference-split.md`.

## Rule Map

| Original AGENTS.md Material                                                     | Preserved Home                                                                      |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Readability commands, report fields, gate semantics, exemptions, and exit codes | `docs/project-checks.md` Readability; read before running the check                 |
| CI jobs, required contexts, base freshness, and fan-in safeguard                | `docs/project-checks.md` CI; read before editing workflows or protection            |
| Full commit grammar and checked range                                           | `docs/project-checks.md` Commit Messages; read before writing or revising a message |
| Conditional test commands and their triggers                                    | `docs/project-checks.md` Conditional Tests; read before verification                |
| Comparator, sync-check, and review-layer test triggers                          | AGENTS.md local done-checks, unchanged                                              |
| Skill directory, supporting files, entry point, and required frontmatter        | AGENTS.md Architecture Invariants, combined into one rule                           |

The shorter introduction points to README.md. The removed TODO named possible
future topics, not an operative rule. Reviewer evidence and all operational
records remain in place. No canonical text or checker changes.

The existing safe-plain-description allowance conflicts with the structure
check's block-scalar requirement. Both remain unchanged: resolving that mismatch
would choose policy beyond this unit's behavior-preserving scope.

Revisit when an agent skips a needed reference section or a local check changes
without its instructions being updated.
