# Default Actions workflow permissions to least privilege

Chose read-only default permissions for the Actions repository token and
disabled Actions-created or -approved pull requests as agent-setup's desired
state. This limits ambient workflow authority while keeping necessary write
access visible through explicit workflow or job-level `permissions`.

Kept the existing detect, report, and offer policy instead of applying the
settings silently. Before offering the change, the skill inspects workflows
for implicit writes and pull-request creation. Explicit permissions preserve
ordinary write use cases; intentional Actions-created pull requests remain a
repository-level exception that needs an owner choice.

Kept this policy in agent-setup's repo-settings audit rather than the managed
AGENTS.md sections. It governs setup behavior and does not need to consume
every downstream agent's context.

Revisit when GitHub separates pull-request creation from approval in the
repository setting, or when its workflow-permission inheritance rules change.
