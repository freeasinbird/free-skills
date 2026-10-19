# Approve Landings by Repository Permission

The landing record named one approver login, and agent-setup asked the owner
for that login before offering the record. Both rules came from this
repository's single-maintainer case. The owner replaced the login with a
permission floor and let setup create the landing labels.

- **Count a label by its actor's repository role, not a recorded login.**
  `list-ready.sh` reads each label actor's role from the collaborator
  permission endpoint and accepts the label when that role is at or above
  the record's Approver permission: `write`, `maintain`, or `admin`. This
  supersedes the one-login rule in `2026-10-18-1027-land-approved-prs.md`
  and the ask-for-the-login rule in
  `2026-10-19-1038-landing-record-offer.md`. A single login fits one
  maintainer, and asking for it gated an otherwise mechanical setup. The
  forge's own merge rights are the trust boundary the label stands in for,
  so they decide who may approve. Rejected: a list of logins, which needs
  maintenance as maintainers change and still asks the owner for names.
- **Default the floor to `write`.** A user-owned repository has only the
  admin and write roles, so a `maintain` floor would exclude every
  collaborator there, which is the one-login limit again. An organization
  that wants a narrower set raises the floor in its record.
- **Read `role_name`, then the `user.permissions` flags, then `permission`.**
  The legacy field maps maintain to write and triage to read, so it can't
  enforce a `maintain` floor. `role_name` can, but an organization's custom
  role is outside the order. Its base role comes from the `user.permissions`
  flags in the same response, which a maintain-based custom role sets
  through `maintain`. The legacy field is the last resort.
- **Stop on an old record rather than default.** A record with an `Approver`
  login bullet stops `bad-record` with a message naming the change. Setup
  reports it as drift and offers the replacement bullet.
- **Let setup create missing labels.** Creating a label grants nobody
  approval; applying the approval label to a PR is the act agents never
  perform. Reporting a missing label and leaving its creation to the owner,
  as the 2026-10-19 note recorded, added a manual step without adding
  safety.

A fresh-context refute-first review of the parser change recorded these
outcomes:

- **Confirmed and fixed:** the matrix's debug-header scrub check had been
  left inspecting a run that never set `GH_DEBUG`; the permission-failure
  case now runs under it with its own scrub check. The bracket encoding,
  the login-alphabet reject, and the per-actor role cache were untested and
  now have cases.
- **Found by the automated reviewer and fixed:** the login alphabet omitted
  the underscore that every Enterprise Managed User login carries, so such
  an organization could never land a PR. It accepts `_` now, with a case.
- **Found by the automated reviewer and fixed:** the legacy `permission`
  fallback reported a maintain-based custom role as `write`, so a `maintain`
  floor rejected it. The base role now comes from `user.permissions`.
- **Allowed by decision:** the role is read when the batch lists, not when
  the label was added. A collaborator demoted after approving is excluded,
  which fails safe; one promoted after approving is landed on the old
  label, a window the skill's prose now names.
- **Disproved:** a nonexistent actor login would abort the batch with
  `LOOKUP_FAILED` rather than exclude the PR, but deleted users appear as
  `ghost` and renamed users resolve to their current login, so the path
  isn't reachable from a real timeline. A public repository reports a
  non-collaborator as `read`, not `none`; both rank below `write`.

Revisit when the collaborator permission endpoint changes its fields, or
when a project needs an approver set that a role floor can't express.
