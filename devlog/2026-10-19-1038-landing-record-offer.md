# Offer Landing Records During Agent Setup

Issue #322 makes agent-setup offer the record that `land-approved-prs` needs.
The owner set the scope: offer and validate unmanaged project content, report
missing labels, and leave label creation to the owner.

- **Ask for the Approver instead of deriving it.** Authentication, commit
  authorship, and repository ownership don't establish who may approve a PR
  for landing. The owner supplies that login before accepting the exact text.
- **Report missing labels without creating them.** Agents never apply the
  approval label. Setup leaves creation of both approval and hand-back labels
  to the owner, keeping its audit separate from granting approval.
- **Use the forge template's consumer list.** Validation now checks Consumers
  as well as host and slug. This extends the host-and-slug-only validation
  recorded in `2026-10-02-1018-forge-record-clone-independent.md`: retiring
  `self-merge` showed that consumer guidance can drift too. Per-clone remote
  differences still aren't disagreements.
- **Copy the landing template into agent-setup.** A pointer to
  `land-approved-prs` would require downstream projects to install that skill
  before setup could offer the record. Keeping a local template avoids that
  dependency and leaves the landing skill and its parser unchanged.
- **Read every label page.** The planned `gh label list` command defaults to
  30 labels. A paginated API read avoids reporting a label on a later page as
  missing; a failed read remains an unverified check.
- **Check the copied marker before offering it.** Reviewer records can name
  observed markers such as an HTML comment, but the landing parser accepts
  only letters, digits, dots, underscores, and hyphens. Report incompatible
  markers instead of offering an unusable record or silently changing the
  project's signal.

Revisit when `land-approved-prs` changes the record shape.
