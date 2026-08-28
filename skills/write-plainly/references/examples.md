# Write Plainly: Examples

Worked examples for the rules in `SKILL.md`. Read this file before drafting
anything longer than a short reply, and whenever you rewrite or review
someone else's text.

## Common Rewrites

| Avoid                                                                                                                     | Prefer                                                                                       | Why                                                 |
| ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| "Understood, and thank you for the correction. The implementation plan has already been produced, so I will now proceed." | "The plan already exists, so I'll implement it."                                             | Accept the correction and state what changes.       |
| "At a high level, the system facilitates the persistence of handoff context across session boundaries."                   | "Put the decision in the issue so the next agent can find it."                               | Name the actor, action, and reason.                 |
| "The implementation is currently in a review-convergent state."                                                           | "The code is pushed. CI passed. I'm still waiting for review."                               | Report observable facts instead of workflow jargon. |
| "Integration evidence is valid only for the selected base commit."                                                        | "The checks only count for the base commit you tested. If the base changes, run them again." | Turn an abstract rule into actions and conditions.  |
| "There are several considerations that should be taken into account before a determination can be made."                  | "I need two facts before I can decide."                                                      | Remove throat-clearing and say what is missing.     |
| "It may potentially be advisable to consider separating these concerns."                                                  | "These concerns change independently. Split them."                                           | State the recommendation and its reason.            |
| "No issues were identified during the verification process."                                                              | "The tests passed, and I found no issues in the final diff."                                 | Name what was actually checked.                     |
| "I would be happy to provide additional detail if that would be helpful."                                                 | Omit it.                                                                                     | A generic offer adds no information.                |

## Examples by Situation

### Answering a Simple Question

> Yes. The plan already exists, so I'll implement it.

Answer first. Add explanation only if it changes what happens next.

### Giving a Status Update

> The wording changes are pushed and CI passed. The bot review is still
> running. You don't need to do anything yet.

This tells the reader what changed, what remains, and whether they have an
action.

### Explaining a Technical Problem

> The cache key ignores the locale. Two users can request the same page in
> different languages and receive the first cached version. Include the locale
> in the key and add a test that requests the page in two locales.

The explanation follows cause, consequence, fix, and proof. It doesn't start
with framework vocabulary.

### Disagreeing

> I don't think that guard helps here. Every caller already validates the
> value, so the failing state can't reach this function. Adding another check
> would duplicate the invariant without changing behavior.

The disagreement is visible in the first sentence. The rest gives evidence,
not deference or attitude.

### Reporting Uncertainty

> I couldn't verify the production setting from this checkout. The code path
> is correct under the documented default, but the deployment value could
> change the result.

Say what was not checked and exactly how it affects confidence.

### Asking a Question

> Which file should be the source of truth? I recommend `AGENTS.md` because
> the other files already point to it.

Ask only when the answer changes the work. Include a default when there is a
sensible one.

### Making a Request

> Audit the text for rules that lost meaning in the rewrite. List each one
> with the old and new wording.

Start with the task. Add the constraint or output shape, not background
ceremony.

### Correcting a Misreading

> The plan already exists. It's in the issue's second comment, so the next
> step is implementing it, not planning again.

State what's wrong, the corrected understanding, and what changes. No apology,
no praise.

### Writing an Implementation Plan

> Replace the parser without changing its public output.
>
> 1. Capture the current accepted and rejected inputs in tests.
> 2. Replace the parsing logic behind the existing interface.
> 3. Run the focused tests, then the full suite.
>
> The command names and output format stay unchanged.

The plan says what success means, what will happen, and what will not change.
It doesn't restate the issue in project-management language.

### Rewriting a Dense Rule

Before:

> Integration evidence (CI, final diff review, readiness assessment) is
> validity-scoped to the base commit against which it was obtained and must be
> re-established upon base movement.

After:

> CI, the final diff review, and the readiness check count only for the base
> commit you tested. If the base moves, repeat all three.

Every requirement survives: the three checks, the base-commit scope, and the
repeat condition. Only the abstraction is gone.
