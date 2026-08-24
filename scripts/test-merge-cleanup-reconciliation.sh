#!/usr/bin/env bash
# Validation matrix for skills/merge-cleanup/reconciliation-ledger.sh.
#
# The cases enumerate every deterministic project-reconciliation exit class:
# successful single and multiple writes, zero work, no-op and report-only work,
# every freshness failure position, source/tool/input-reread stops, mutation
# and verification failures, rejected attempts, partial fields, and malformed
# traces that try to bypass the ordering or complete-disposition invariants.
#
# Usage: test-merge-cleanup-reconciliation.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="$ROOT/skills/merge-cleanup/reconciliation-ledger.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
NAME=""
OUT=""
RC=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $NAME: $1"; }

run_case() { # run_case <name> <exit>: trace arrives on stdin
  NAME="$1"
  expected_rc="$2"
  trace="$TMP/trace"
  cat > "$trace"
  OUT=$("$SUT" "$trace" 2>&1)
  RC=$?
  if [ "$RC" -eq "$expected_rc" ]; then ok
  else bad "exit $RC, wanted $expected_rc (got: $OUT)"
  fi
}
want() {
  case "$OUT" in *"$1"*) ok ;; *) bad "output lacks '$1' (got: $OUT)" ;; esac
}
reject() {
  case "$OUT" in *"$1"*) bad "output contains '$1' (got: $OUT)" ;; *) ok ;; esac
}

run_case "one verified write completes" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	full-input-set
post	A
final	A
EOF
want 'RESULT complete'
want 'COMPLETED T1:transition (changed)'
want 'OWNER ACTION none'

run_case "a GitHub-shaped optimistic write follows fresh input rereads" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	closing-issue	dependency-tracker	T1
pre	A
guard	complete	closing-issue	dependency-tracker	T1
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	closing-issue	dependency-tracker	T1
post	A
final	A
EOF
want 'RESULT complete'
reject 'acquire a complete guard'

run_case "a post-write selector change makes verified state unknown" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	closing-issue	T1
pre	A
guard	complete	closing-issue	T1
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	changed	closing-issue	T1
post	A
final	A
EOF
want 'RESULT partial'
want 'UNKNOWN T1:transition: post-write inputs were changed'
want 'inspect every unknown write'

run_case "an unverifiable post-write input makes verified state unknown" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	dependency-tracker	T1
pre	A
guard	complete	dependency-tracker	T1
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	unverifiable	dependency-tracker	T1
post	A
final	A
EOF
want 'RESULT partial'
want 'UNKNOWN T1:transition: post-write inputs were unverifiable'

run_case "a fresh selector reread can stop before the write" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	closing-issue	T1
pre	A
guard	complete	closing-issue	T1
skip	T1:transition	closing issue no longer selects T1	remaining
final	A
EOF
want 'RESULT incomplete'
want 'SKIPPED T1:transition: closing issue no longer selects T1'
reject 'COMPLETED T1:transition'

run_case "a post-reread skip cannot omit a selecting input" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	closing-issue	T1
pre	A
guard	complete	T1
skip	T1:transition	closing issue no longer selects T1	remaining
EOF
want 'guard complete omits freshly reread input closing-issue for T1:transition'

run_case "a post-write input recheck cannot omit a guarded input" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	closing-issue	T1
pre	A
guard	complete	closing-issue	T1
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	T1
EOF
want 'recheck input set differs from guard complete'

run_case "a post-write input recheck cannot repeat an input" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	closing-issue	T1
pre	A
guard	complete	closing-issue	T1
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	T1	T1
EOF
want 'recheck repeats an input: T1'

run_case "multiple writes and an atomic multi-field write complete" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
plan	T2:transition	write	full-input-set
plan	T2:readiness	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	full-input-set
post	A
pre	A
guard	complete	full-input-set
attempt	accepted	T2:transition	T2:readiness
verify	T2:transition	changed
verify	T2:readiness	changed
recheck	fresh	full-input-set
post	A
final	A
EOF
want 'RESULT complete'
want 'COMPLETED T2:readiness (changed)'

run_case "zero known work still needs and passes final freshness" 0 <<'EOF'
policy	A	complete	initial
final	A
EOF
want 'RESULT complete'

run_case "readable policy absence stays silent only after final freshness" 0 <<'EOF'
policy	A	absent	initial
final	A
EOF
want 'RESULT complete'
want 'OWNER ACTION none'

run_case "a policy advance invalidates readable absence" 0 <<'EOF'
policy	A	absent	initial
final	B
EOF
want 'RESULT restart'
want 'rediscover policy'

run_case "a second policy advance stops as unstable" 0 <<'EOF'
policy	B	absent	replacement
final	C
EOF
want 'RESULT unstable'
want 'wait for the base tip to stabilize'
reject 'RESULT restart'

run_case "no-op and report-only results complete under final freshness" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	noop	T1-revision
plan	startable-now	report	readiness-inputs
observe	T1:transition	fresh	T1-revision
observe	startable-now	fresh	readiness-inputs
final	A
EOF
want 'COMPLETED T1:transition (noop)'
want 'COMPLETED startable-now (report)'

run_case "a no-op must revalidate every planned input" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	noop	closing-issue	T1-revision
observe	T1:transition	stale	closing-issue	T1-revision
final	A
EOF
want 'RESULT incomplete'
want 'SKIPPED T1:transition: inputs were stale at re-observation'
want 'freshly reread every affected input'

run_case "a no-op recheck cannot omit a selecting input" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	noop	closing-issue	T1-revision
observe	T1:transition	fresh	T1-revision
EOF
want 'observe input set differs from its plan'

run_case "duplicate no-op inputs cannot substitute for an omitted input" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	noop	closing-issue	T1-revision
observe	T1:transition	fresh	T1-revision	T1-revision
EOF
want 'observe repeats an input: T1-revision'

run_case "a derived report cannot finish before a planned write" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	T1-revision
plan	startable-now	report	T1-revision	dependency
observe	startable-now	fresh	T1-revision	dependency
EOF
want 'observe must follow every planned write disposition: T1:transition'

run_case "a derived report cannot finish before a planned no-op" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	noop	T1-revision
plan	startable-now	report	T1-revision	dependency
observe	startable-now	fresh	T1-revision	dependency
EOF
want 'report observation must follow every no-op disposition: T1:transition'

run_case "a report recomputed after its write can complete" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	T1-revision
plan	startable-now	report	T1-revision	dependency
pre	A
guard	complete	T1-revision
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	T1-revision
post	A
observe	startable-now	fresh	T1-revision	dependency
final	A
EOF
want 'RESULT complete'
want 'COMPLETED startable-now (report)'

run_case "duplicate report inputs cannot substitute for an omitted input" 2 <<'EOF'
policy	A	complete	initial
plan	startable-now	report	T1-revision	dependency
observe	startable-now	fresh	dependency	dependency
EOF
want 'observe repeats an input: dependency'

run_case "a moved final tip restarts a zero-write run" 0 <<'EOF'
policy	A	complete	initial
final	B
EOF
want 'RESULT restart'
want 'do not use a precomputed edit'

run_case "an unverifiable final tip invalidates report-only work" 0 <<'EOF'
policy	A	complete	initial
plan	mergeable-next	report	readiness-inputs
observe	mergeable-next	fresh	readiness-inputs
final	unverifiable
EOF
want 'RESULT restart'
reject 'RESULT complete'

run_case "an unreadable policy source reports all known work skipped" 0 <<'EOF'
policy	A	unreadable	initial
plan	project-reconciliation	report
skip	project-reconciliation	detailed mechanics is unreadable	source
final	A
EOF
want 'RESULT incomplete'
want 'SKIPPED project-reconciliation: detailed mechanics is unreadable'

run_case "freshness supersedes repair of a stale unreadable source" 0 <<'EOF'
policy	A	unreadable	initial
plan	project-reconciliation	report
skip	project-reconciliation	detailed mechanics at A is unreadable	source
final	B
EOF
want 'RESULT restart'
want 'rediscover policy, freshly reread every input at the current base tip'
reject 'restore or correct the named authoritative current-base source'

run_case "ambiguity is incomplete with no guessed work" 0 <<'EOF'
policy	A	complete	initial
plan	T1:readiness	write	full-input-set
skip	T1:readiness	dependency relation is ambiguous	ambiguity
final	A
EOF
want 'RESULT incomplete'
want 'SKIPPED T1:readiness: dependency relation is ambiguous'

run_case "a failed input reread permits no attempt" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	unavailable
skip	T1:transition	an input could not be freshly reread	guard
final	A
EOF
want 'RESULT incomplete'
want 'freshly reread every selector and computation input'

run_case "a final policy move supersedes a failed input reread" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	unavailable
skip	T1:transition	an input could not be freshly reread	guard
final	B
EOF
want 'RESULT restart'
want 'rediscover policy, freshly reread every input at the current base tip'
reject 'acquire a complete guard'

run_case "a pre-write move before any change restarts" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	B
skip	T1:transition	policy moved before the write	policy
final	B
EOF
want 'RESULT restart'

run_case "a pre-write move after a completed write is partial" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
plan	T2:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	full-input-set
post	A
pre	B
skip	T2:transition	policy moved before the next write	policy
final	B
EOF
want 'RESULT partial'
want 'COMPLETED T1:transition (changed)'
want 'SKIPPED T2:transition: policy moved before the next write'
want 're-establish current base identity'

run_case "a verified mutation failure is incomplete" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	failed	T1:transition
verify	T1:transition	failed
recheck	fresh	full-input-set
post	A
final	A
EOF
want 'RESULT incomplete'
want 'SKIPPED T1:transition: write failed or its condition was rejected'

run_case "a failed command with a verified change stops partial" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	failed	T1:transition
verify	T1:transition	changed
recheck	fresh	full-input-set
post	A
final	A
EOF
want 'RESULT partial'
want 'COMPLETED T1:transition (changed)'
want 'failed or rejected interface result'

run_case "an unknown write outcome is partial" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	unknown
recheck	fresh	full-input-set
post	A
final	A
EOF
want 'RESULT partial'
want 'UNKNOWN T1:transition'
want 'inspect every unknown write'

run_case "a moved post-write tip preserves verified work and stops" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
plan	T2:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	full-input-set
post	B
skip	T2:transition	policy moved after T1	policy
final	B
EOF
want 'RESULT partial'
want 'preserve every verified write'
want 're-establish current base identity'

run_case "an unverifiable post-write tip is partial after a verified write" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	changed
recheck	fresh	full-input-set
post	unverifiable
final	unverifiable
EOF
want 'RESULT partial'

run_case "a partial-field verification records completed and unknown fields" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
plan	T1:readiness	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition	T1:readiness
verify	T1:transition	changed
verify	T1:readiness	unknown
recheck	fresh	full-input-set
post	A
final	A
EOF
want 'COMPLETED T1:transition (changed)'
want 'UNKNOWN T1:readiness'

run_case "a failed tracker call still requires verify then post" 0 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	failed	T1:transition
verify	T1:transition	failed
recheck	fresh	full-input-set
post	A
final	A
EOF
want 'RESULT incomplete'

run_case "a missing final observation is invalid" 2 <<'EOF'
policy	A	complete	initial
EOF
want 'trace has no final freshness observation'

run_case "an attempt without fresh input rereads is invalid" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
attempt	accepted	T1:transition
EOF
want 'attempt must immediately follow guard complete'

run_case "fresh input rereads cannot omit a selecting input" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	closing-issue	T1
pre	A
guard	complete	T1
attempt	accepted	T1:transition
EOF
want 'guard complete omits freshly reread input closing-issue for T1:transition'

run_case "post cannot precede complete per-field verification" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
plan	T1:readiness	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition	T1:readiness
verify	T1:transition	changed
post	A
EOF
want 'attempted item has no verification: T1:readiness'

run_case "post cannot omit the full-input recheck" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	changed
post	A
EOF
want 'post must follow the post-write input recheck'

run_case "every planned field needs exactly one disposition" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
final	A
EOF
want 'planned item has no disposition: T1:transition'

run_case "a source failure cannot omit its umbrella disposition" 2 <<'EOF'
policy	A	invalid	initial
final	A
EOF
want 'failed policy needs one skipped project-reconciliation umbrella item'

run_case "a failed source cannot substitute an unauthorized item" 2 <<'EOF'
policy	A	unreadable	initial
plan	not-the-umbrella	unsupported
skip	not-the-umbrella	mechanics missing	unauthorized
final	A
EOF
want 'failed policy needs one skipped project-reconciliation umbrella item'

run_case "a failed source umbrella cannot use an unsupported kind" 2 <<'EOF'
policy	A	unreadable	initial
plan	project-reconciliation	unsupported
skip	project-reconciliation	mechanics missing	unauthorized
final	A
EOF
want 'failed policy needs one skipped project-reconciliation umbrella item'

run_case "a failed source cannot split its umbrella into multiple items" 2 <<'EOF'
policy	A	invalid	initial
plan	project-reconciliation	report
plan	project-source	report	source-input
skip	project-reconciliation	record is invalid	source
skip	project-source	mechanics pointer is invalid	source
final	A
EOF
want 'failed policy needs one skipped project-reconciliation umbrella item'

run_case "a failed source umbrella requires the source action" 2 <<'EOF'
policy	A	invalid	initial
plan	project-reconciliation	report
skip	project-reconciliation	record is invalid	guard
final	A
EOF
want 'failed policy needs one skipped project-reconciliation umbrella item'

run_case "a skip cannot omit its exact owner-action class" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
skip	T1:transition	tooling missing
EOF
want 'expected 4 tab-separated fields'

run_case "no later write can begin after an unknown outcome" 2 <<'EOF'
policy	A	complete	initial
plan	T1:transition	write	full-input-set
plan	T2:transition	write	full-input-set
pre	A
guard	complete	full-input-set
attempt	accepted	T1:transition
verify	T1:transition	unknown
recheck	fresh	full-input-set
post	A
pre	A
EOF
want 'no write may begin after a stop condition'

NAME="help documents the trace contract"
OUT=$("$SUT" --help 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then ok; else bad "exit $RC, wanted 0"; fi
want 'reconciliation-ledger.sh <trace-file>'
want 'final   <base-tip|unverifiable>'

echo "merge-cleanup reconciliation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
