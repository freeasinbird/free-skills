# Replan

## §blocked-replan

When a blocker prevents a truthful replacement plan, follow these steps. An
occupied issue is the exception: write nothing and leave its plan as it is
(see Check Occupancy).

1. Edit the old plan to mark it blocked and name the invalidating fact. If
   editing is unavailable, post one linked invalidation comment.
2. Reread the exact plan. Confirm it is visibly blocked or deprecated and no
   competing plan remains current.
3. Report failed verification as an unsafe state that needs manual action.
4. Do not invent a replacement only to retire a stale plan.

## §replan

Search the issue for an existing implementation-plan comment before posting.
Use retirement-first when evidence shows that the current plan is invalid:

1. Retire the exact current plan before publishing its replacement. Mark it
   blocked or deprecated, then confirm the retirement by reread. Update the
   contract if needed only after the old plan is non-current.
2. Edit the retired comment into the replacement when the forge supports it.
   Otherwise, post one superseding comment that links the retired plan and
   identifies itself as the only current plan. Never leave competing current
   comments.
3. If a later write or verification fails, stop with the old plan non-current.
   Report the partial unsafe state and include the prepared replacement text.
   State that planning is blocked, not complete.

Never rely on a later replacement write to retire stale instructions. Use any
available forge API, CLI, or interface without assuming a platform-specific
tool.
