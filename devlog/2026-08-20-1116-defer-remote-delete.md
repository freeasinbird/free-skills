# Deferring remote deletion until after base resync

Issue #105 resolves a destructive-path ordering defect found during PR #104:
merge-cleanup deleted the remote feature branch before landing on and
resyncing the base. A branch-conditioned include could therefore change the
base remote after checkout, leaving cleanup half-complete or fetching from a
different repository after the recovery ref was gone.

## Decisions

- **Resync before remote deletion.** Landing and the explicit fast-forward are
  reversible preparation. The remote feature branch remains intact until both
  complete. The lease, OID, consumer, and stacked-PR guards move with the
  delete and still run immediately before it; their protection does not depend
  on deletion occurring before the checkout.
- **Re-resolve remote roles after checkout.** A remote name is not a stable
  repository identity because `includeIf "onbranch:…"` can change any remote
  key. Hosted remotes are checked against the forge's authoritative clone
  endpoints under the base branch's effective configuration. A hostless path
  cannot be matched to the forge, so any post-checkout hostless mapping is
  pinned to the canonical filesystem destination explicitly trusted before
  checkout, resolving relative paths and symlinks on both sides of the
  boundary. A hosted replacement can instead be proved against the
  authoritative endpoints.
- **Bind cleanup-created tracking after remote validation.** Creating a local
  base from a remote-tracking ref can automatically bind it to the remote
  selected before checkout. Suppress that tracking, then configure the new
  branch against the validated post-landing remote so later pulls cannot use
  a stale repository mapping.
- **Keep the prompt and executable sequences aligned.** `merge-cleanup`, the
  self-merge executable and specification, and the agent-setup canonical merge
  wording all use the same order. A partial update would leave one shipped
  cleanup path with the known destructive sequence.
- **Keep the landing planner read-only.** It still reports the state of the
  branch checked out when it runs. The caller runs it again after checkout and
  owns remote-role identity; teaching the planner forge identity would couple
  a Git-local decision script to PR-host metadata.

## Rejected alternatives

- **Detect every branch-conditioned include and stop.** Rejected because an
  include that changes only `user.email` is harmless. A blanket stop declines
  cleanup Git can express, while recursively classifying every nested include
  by the keys it may affect adds machinery without fixing the sequence.
- **Capture a pre-landing URL and use it after checkout.** Rejected because it
  deliberately ignores the configuration effective under the base branch and
  can preserve a feature-only mapping the user did not intend there. Re-read
  and validate at the operation boundary instead.
- **Leave the limitation documented.** Rejected because the old order could
  remove the remote recovery ref before a predictable later stop. The failure
  is structural and has a smaller, safer ordering.

## Verification findings

Baseline before implementation: `test-merge-cleanup-landing.sh` passed 254
assertions and `test-self-merge.sh` passed 358 assertions.

The regression matrix includes four branch-conditioned remote cases. They
remove the base URL after checkout, replace a hosted base URL with a hostless
path, reveal a different valid local repository whose base is a fast-forward
descendant, and replace the head remote after a successful resync. Each must
preserve the remote feature branch, and the different-repository case must stop
before the wrong base commit is fetched or merged.

The refute-first run executed the finished 383-assertion self-merge matrix
against the old executable from `main`. It failed 19 assertions: the old order
deleted the remote head before two refused resyncs, accepted replacement local
base and head repositories, failed to repair a cleanup-created upstream, and
followed a checkout-switched symlink into another repository. The same matrix
passed all 383 assertions against the new executable. The landing-planner
matrix passed all 258 assertions.

An identity-boundary lens found an asymmetric first draft that rejected a
hostless-to-hosted replacement but accepted the reverse. The final check uses
the validated post-checkout identity rather than the pre-checkout identity's
kind, and the hosted-to-hostless regression now covers that correction.

Automated review found that the missing-local-base path still let Git create
tracking configuration from the pre-landing remote. A discriminating
branch-conditioned regression now requires the created base to track the
post-landing remote selected for resync.

A second automated review found that raw hostless URL equality missed a
tracked symlink whose destination changes across checkout. Hostless identity
now resolves the effective filesystem destination from the worktree root
before and after landing; the destructive-path matrix runs cleanup from a
subdirectory and requires both the trusted and replacement remote branches to
survive that redirect.

The required fresh-context refute pass found one stale comment that still
named the invocation directory; it is corrected to the worktree root. The pass
found no behavioral, security, portability, or test-discrimination defect.
Filesystem namespace mutation between identity validation and Git opening the
destination remains a residual race; Git exposes no operation that couples
those steps, so cleanup keeps the validation at the operation boundary and
stops on every observable mismatch.

A later automated review found another member of the hostless-path class:
Git expands leading `~/` and `~user/` syntax before opening a remote, while the
identity guard had treated those values as ordinary worktree-relative paths.
The guard now delegates that syntax to Git's own path interpolator before
physical resolution. The destructive matrix changes a tracked symlink reached
through `~/` across checkout and requires both possible remote branches to
survive. A re-armed fresh-context refute pass matched `~`, `~/`, and `~user/`
behavior to Git, confirmed that invalid users fail closed, and found no new
behavioral, security, portability, or test-discrimination defect. Linux and
Bash 3.2 portability were reviewed statically rather than executed.

## Revisit when

Revisit the hostless-path rule if a forge or Git API can prove that a local
remote destination identifies the PR repository without relying on the user's
explicit trust. Until then, canonical destination equality across checkout is
the only available identity guard when the post-checkout mapping is hostless.
