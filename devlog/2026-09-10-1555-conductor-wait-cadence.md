# Cap Watcher Runs Under the Cache, Keep the Conductor on the Session Model

Chose a 4-minute default watcher cap over the 9-minute one because a Claude
Code subagent's prompt cache lasts about 5 minutes. Under the old cap, each
re-run after a quiet wait started cold and rewrote the conductor's whole
context. On 51 Fable conductor runs in one month, a third of the cache-write
tokens came from those rewrites; the worst run rewrote a 290k-token context
ten times in 109 minutes. The 10-minute host command limit stays as the outer
bound. Flags, output lines, and exit codes are unchanged.

Rejected a host-gated cap (4 minutes on Claude Code, longer elsewhere), which
the Codex review proposed. The cap bounds the conductor's own foreground
command. On Codex the cache decays gradually, 99 percent cached at the median
under 10 minutes idle, so a 4-minute re-run lands warm there too, and the
extra turns cost cached reads only. The Codex wait-once rule governs the main
agent's `wait_agent` on the conductor, which the cap does not touch.

Chose to state the keepalive break-even per tier instead of one ten-wake
figure. The ten-wake number assumed a 0.1x cached-read multiplier. A Fable
subagent prices cached reads at 0.025x and its 5-minute cache write at 1.25x,
so the break-even is about 50 wakes; the main thread's 1-hour write moves it
to about 80. The cost model names the multipliers and list prices so a reader
can re-derive them.

Chose the session model for the conductor over a cheaper tier because the
conductor's cost is context, not reasoning. It triages findings and decides
fix or decline, which needs main-thread judgment. On 51 Fable runs against 65
Opus runs, the median run cost was $2.58 against $2.51, so the cheaper tier
saved nothing. The session model is a preference, not a grant: where a host
fixes the subagent model, the conductor runs on it if it can edit and judge a
review.

Evidence: local conductor transcripts from Aug 11 to Sep 10, 2026, and
Anthropic list prices as of 2026-09.

Revisit when the subagent cache TTL or the cached-read and cache-write
multipliers change, when a cheaper tier shows a materially lower measured run
cost, or when Codex's command timeout or cache behavior changes.
