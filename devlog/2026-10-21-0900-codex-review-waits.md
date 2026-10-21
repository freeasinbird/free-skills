# Reduce Empty Codex Waits

Chose longer Codex watcher runs over four-minute restarts to reduce calls
after empty waits. The existing `--cap-minutes` flag suffices; no host detection or
new flag is needed. Claude and other hosts keep the four-minute default.

This revises the September 10 decision to accept cached Codex turns. The
owner wants fewer such calls; caching doesn't make them free. Savings still
need measurement across parent and conductor, including cache usage and
detection latency.

Longer processes can still cause model calls when tool waits return empty.
Host limits still apply. Rejected ending a turn on the strength of a
background process alone: the host must reliably resume the same agent.
Keep the wait policy in one reference so its copies can't drift.

Work contract: [free-prompts #60](https://github.com/freeasinbird/free-prompts/issues/60).
Follow-up: [free-prompts #61](https://github.com/freeasinbird/free-prompts/issues/61).

Revisit when the host changes its wait or resumption contract, or measured
cost and latency show that a different Codex cadence performs better.
