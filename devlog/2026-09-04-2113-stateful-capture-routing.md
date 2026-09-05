# Route Captures by the Required UI State

Issue #242 requires choosing the capture method before the before shot.
A URL helper cannot open a menu or restore authentication merely by waiting
for an element. Keep state setup in an available browser or application test
setup, and keep `capture.mjs` a narrow URL-capture helper.

## Decisions

- **Choose before capturing.** Use the helper only when a fresh URL load
  reaches the state. Otherwise establish it with a capable stateful method,
  or name the missing capability and uncaptured state.
- **Keep replay instructions local.** Store source, fixture, display, framing,
  and ordered setup in `capture-recipe.md`. Keep credentials and session data
  out, and keep the recipe out of publication text.
- **Test interaction rather than a forced screenshot.** The synthetic menu
  starts closed on each load. Only the supplied spacing patch may change
  source; the eval requires a UI interaction before every capture.
- **Require evidence of order.** Grade routing and setup from a harness export
  of ordered messages, tool calls, and results. An agent-written account
  cannot prove those assertions.
- **Keep constrained grading honest.** An unavailable-method run counts only
  under a verified enforcing harness. Voluntary restrictions don't prove a
  capability was unavailable, and this unit won't build an enforcement system.

These choices preserve the narrow helper decision from 2026-07-02 and the
2026-08-28 decision to keep the option table and complete image review in the
entry point. The current upload order and local-only override remain intact.

## Refute-First Findings

- **Confirmed and fixed by fresh review:** Captures can live in a project
  directory, where a broad Git add could include the recipe. Explicitly forbid
  committing or posting it as well as attaching it to published evidence.
- **Disproved by exact comparison:** The complete Compose and Attach section,
  helper option table, and exit-69 fallback match the base revision.
- **Disproved by recipe review:** Reproduction requires fixture identifiers
  and ordered actions, not credentials, cookies, or storage dumps. Private
  routes use templates, and login setup is named by reference.
- **Disproved by path review:** The stateful route still flows through the
  subject/state check and mandatory sensitive-image review. The recipe adds
  no upload command or authorization.

Revisit when the helper gains session or interaction support, or an existing
harness can enforce the constrained profile and export its ordered actions.
