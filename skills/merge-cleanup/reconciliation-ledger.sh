#!/usr/bin/env bash
# reconciliation-ledger.sh: validate one project-obligation reconciliation
# trace and print its complete disposition ledger.
#
# The trace is tab-separated, one event per line:
#
#   policy  <base-tip|unverifiable>  <absent|complete|unreadable|invalid>  <initial|replacement>
#   plan    <item>  <write|noop|report>  <input> [<input> ...]
#   plan    <item>  unsupported
#   pre     <base-tip|unverifiable>
#   guard   <complete|unavailable>
#   attempt <accepted|failed|rejected> <write item> [<write item> ...]
#   verify  <attempted item> <changed|failed|unknown>
#   recheck <fresh|changed|unverifiable> <input> [<input> ...]
#   post    <base-tip|unverifiable>
#   observe <noop|report item> <fresh|stale|unverifiable> <input> [<input> ...]
#   skip    <item>  <reason>  <owner-action-class>
#   final   <base-tip|unverifiable>
#
# `policy` comes first and identifies the immutable tip used for both governing
# instructions and detailed mechanics. All `plan` rows follow it and precede
# execution. `guard complete` records every named input freshly reread
# immediately before the attempt; `guard unavailable` means an input could not
# be freshly reread. A write is exactly pre, guard, attempt, one verify per
# attempted field, recheck, post. `recheck fresh` records that the same external
# inputs were readable and still support the post-write computation, including
# intended target changes; `changed` or `unverifiable` cannot yield completion.
# The attempt status records the interface result separately from what the
# target reread proves. `observe` revalidates a no-op or report
# item after all writes, while `skip` dispositions work that could not safely
# run.
# Owner-action classes are
# source, ambiguity, tooling, guard, policy, closing, unauthorized, or
# remaining. `final` is mandatory even when the plan is empty, report-only, or
# already stopped.
# Tabs and newlines are separators and therefore cannot occur inside a field.
#
# Usage:
#   reconciliation-ledger.sh <trace-file>
#   reconciliation-ledger.sh -
#   reconciliation-ledger.sh --skeleton <plan-file>
#   reconciliation-ledger.sh --skeleton -
#   reconciliation-ledger.sh --help
#
# `--skeleton` reads a plan file holding only the `policy` row and its `plan`
# rows, then prints a complete trace in the checked order: one pre, guard,
# attempt, verify, recheck, post block per write item, one observe per no-op
# and then per report item, and the closing final. Every observation carries
# its expected value (the policy tip, accepted, changed, fresh); replace each
# with what was actually observed as the work runs. An unsupported item, or a
# failed policy source, becomes a skip whose reason is an angle-bracket
# placeholder to replace. The printed skeleton passes the checker as is.
#
# Output is a canonical plain-text ledger, or the skeleton trace. Exit codes:
#   0   valid trace; RESULT says complete, restart, unstable, incomplete, or partial
#   2   INVALID trace or plan; do not use it to claim a reconciliation result
#   64  usage on stderr
#   69  awk missing or trace unreadable
set -u

usage() { # usage [reason]
  [ $# -eq 0 ] || echo "reconciliation-ledger.sh: $1" >&2
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

SKELETON=0
case "${1-}" in
  --help | -h)
    [ $# -eq 1 ] || usage
    sed -n '2,/^set -u$/p' "$0" | sed '$d'
    exit 0
    ;;
  --skeleton)
    [ $# -eq 2 ] || usage "--skeleton takes exactly one plan file"
    SKELETON=1
    shift
    ;;
esac
[ $# -eq 1 ] || usage
TRACE="$1"
command -v awk >/dev/null 2>&1 \
  || { echo "reconciliation-ledger.sh: awk is not on PATH" >&2; exit 69; }
if [ "$TRACE" != - ]; then
  [ -r "$TRACE" ] \
    || { echo "reconciliation-ledger.sh: trace is not readable: $TRACE" >&2; exit 69; }
fi

awk -F '\t' -v skeleton="$SKELETON" '
function invalid(message) {
  if (!bad) print "INVALID line " NR ": " message
  bad = 1
  exit 2
}
function item_index(item, i) {
  for (i = 1; i <= plan_count; i++) if (plan_item[i] == item) return i
  return 0
}
function require_fields(want) {
  if (NF != want) invalid("expected " want " tab-separated fields, got " NF)
  for (field = 1; field <= NF; field++)
    if ($field == "") invalid("empty field " field)
}
function require_at_least(want) {
  if (NF < want) invalid("expected at least " want " tab-separated fields, got " NF)
  for (field = 1; field <= NF; field++)
    if ($field == "") invalid("empty field " field)
}
function inputs_of(idx, dep_no, list) {
  for (dep_no = 1; dep_no <= dep_count[idx]; dep_no++)
    list = list "\t" plan_dep[idx, dep_no]
  return list
}
function print_skeleton(idx) {
  # The expected value fills every observation slot, so the printed trace is
  # the happy path the agent overwrites as real observations arrive. Only a
  # skip reason has no expected value; it gets a placeholder to replace.
  # Every rejection precedes the first print, so a redirected skeleton file
  # is either complete or empty apart from the INVALID line.
  if (source_failed) {
    if (plan_count == 0) {
      plan_count = 1
      plan_item[1] = "project-reconciliation"
      plan_kind[1] = "report"
      plan_row[1] = "plan\tproject-reconciliation\treport"
    }
    if (plan_count != 1 || plan_item[1] != "project-reconciliation" ||
        plan_kind[1] != "report") {
      print "INVALID: failed policy needs one project-reconciliation report umbrella item"
      exit 2
    }
    print policy_row
    print plan_row[1]
    print "skip\tproject-reconciliation\t<name the " policy_status \
      " source, field, or pointer>\tsource"
    print "final\t" policy
    return
  }
  print policy_row
  for (idx = 1; idx <= plan_count; idx++) print plan_row[idx]
  for (idx = 1; idx <= plan_count; idx++)
    if (plan_kind[idx] == "unsupported")
      print "skip\t" plan_item[idx] \
        "\t<name the requested action outside merge-cleanup authority>\tunauthorized"
  if (policy == "unverifiable") {
    for (idx = 1; idx <= plan_count; idx++)
      if (plan_kind[idx] != "unsupported")
        print "skip\t" plan_item[idx] "\tbase tip was unverifiable at discovery\tpolicy"
    print "final\tunverifiable"
    return
  }
  for (idx = 1; idx <= plan_count; idx++)
    if (plan_kind[idx] == "write") {
      print "pre\t" policy
      print "guard\tcomplete" inputs_of(idx)
      print "attempt\taccepted\t" plan_item[idx]
      print "verify\t" plan_item[idx] "\tchanged"
      print "recheck\tfresh" inputs_of(idx)
      print "post\t" policy
    }
  for (idx = 1; idx <= plan_count; idx++)
    if (plan_kind[idx] == "noop")
      print "observe\t" plan_item[idx] "\tfresh" inputs_of(idx)
  for (idx = 1; idx <= plan_count; idx++)
    if (plan_kind[idx] == "report")
      print "observe\t" plan_item[idx] "\tfresh" inputs_of(idx)
  print "final\t" policy
}
function stop_writes_for_freshness(tip) {
  if (tip == "unverifiable" || policy == "unverifiable" || tip != policy) {
    freshness_failed = 1
    writes_stopped = 1
  }
}
BEGIN {
  phase = "start"
}
/^[[:space:]]*$/ { next }
{
  event = $1
  if (event == "policy") {
    require_fields(4)
    if (phase != "start") invalid("policy must be the first event")
    if ($3 != "absent" && $3 != "complete" && $3 != "unreadable" && $3 != "invalid")
      invalid("policy status must be absent, complete, unreadable, or invalid")
    if ($4 != "initial" && $4 != "replacement")
      invalid("policy trace must be initial or replacement")
    policy = $2
    policy_status = $3
    trace_origin = $4
    policy_row = $0
    policy_seen = 1
    phase = "planning"
    if (policy == "unverifiable") {
      freshness_failed = 1
      writes_stopped = 1
    }
    if (policy_status == "unreadable" || policy_status == "invalid") {
      source_failed = 1
      writes_stopped = 1
    }
    next
  }
  if (!policy_seen) invalid("policy must be the first event")
  if (event == "plan") {
    require_at_least(3)
    if (phase != "planning") invalid("plan rows must precede execution")
    if (policy_status == "absent") invalid("absent policy cannot plan reconciliation work")
    if ($3 != "write" && $3 != "noop" && $3 != "report" && $3 != "unsupported")
      invalid("plan kind must be write, noop, report, or unsupported")
    if (item_index($2)) invalid("duplicate plan item: " $2)
    plan_count++
    plan_item[plan_count] = $2
    plan_kind[plan_count] = $3
    plan_row[plan_count] = $0
    if ($3 != "unsupported") {
      if (NF < 4 && !(source_failed && $2 == "project-reconciliation" && $3 == "report"))
        invalid("write, noop, and report plans must enumerate every input")
      for (field = 4; field <= NF; field++) {
        for (dep_no = 1; dep_no <= dep_count[plan_count]; dep_no++)
          if (plan_dep[plan_count, dep_no] == $field)
            invalid("plan repeats an input: " $field)
        dep_count[plan_count]++
        plan_dep[plan_count, dep_count[plan_count]] = $field
      }
    } else if (NF != 3) invalid("unsupported plans cannot name inputs")
    next
  }

  if (skeleton) invalid("a skeleton plan holds only policy and plan rows")
  if (phase == "planning") phase = "idle"
  if (phase == "final") invalid("no event may follow final")

  if (event == "pre") {
    require_fields(2)
    if (phase != "idle") invalid("pre requires an idle write state")
    if (writes_stopped) invalid("no write may begin after a stop condition")
    stop_writes_for_freshness($2)
    phase = freshness_failed ? "blocked" : "pre"
    next
  }
  if (event == "guard") {
    require_at_least(2)
    if (phase != "pre") invalid("guard must immediately follow a fresh pre")
    guard_count = 0
    if ($2 == "complete") {
      if (NF < 3) invalid("guard complete must enumerate freshly reread inputs")
      for (field = 3; field <= NF; field++) {
        for (guard_no = 1; guard_no <= guard_count; guard_no++)
          if (guard_input[guard_no] == $field)
            invalid("guard repeats an input: " $field)
        guard_count++
        guard_input[guard_count] = $field
      }
      phase = "guarded"
    }
    else if ($2 == "unavailable") {
      if (NF != 2) invalid("an unavailable guard takes no input list")
      writes_stopped = 1
      phase = "blocked"
    } else invalid("guard status must be complete or unavailable")
    next
  }
  if (event == "attempt") {
    require_at_least(3)
    if (phase != "guarded") invalid("attempt must immediately follow guard complete")
    if ($2 != "accepted" && $2 != "failed" && $2 != "rejected")
      invalid("attempt status must be accepted, failed, or rejected")
    attempt_status = $2
    attempt_count = 0
    for (field = 3; field <= NF; field++) {
      idx = item_index($field)
      if (!idx) invalid("attempt names an unplanned item: " $field)
      if (plan_kind[idx] != "write") invalid("attempt requires write items")
      if (disposition[idx] != "") invalid("item already dispositioned: " $field)
      if (attempted[idx]) invalid("attempt repeats an item: " $field)
      for (dep_no = 1; dep_no <= dep_count[idx]; dep_no++) {
        dep = plan_dep[idx, dep_no]
        covered = 0
        for (guard_no = 1; guard_no <= guard_count; guard_no++)
          if (guard_input[guard_no] == dep) covered = 1
        if (!covered) invalid("guard complete omits freshly reread input " dep " for " $field)
      }
      attempt_count++
      attempt_index[attempt_count] = idx
      attempted[idx] = 1
    }
    phase = "attempt"
    next
  }
  if (event == "verify") {
    require_fields(3)
    if (phase != "attempt" && phase != "verified")
      invalid("verify must follow attempt or another verify")
    idx = item_index($2)
    if (!idx || !attempted[idx]) invalid("verify names an unattempted item: " $2)
    if (verified[idx]) invalid("item already verified: " $2)
    if ($3 != "changed" && $3 != "failed" && $3 != "unknown")
      invalid("verify result must be changed, failed, or unknown")
    verification[idx] = $3
    verified[idx] = 1
    phase = "verified"
    next
  }
  if (event == "recheck") {
    require_at_least(3)
    if (phase != "verified") invalid("recheck must follow every field verification")
    for (attempt_no = 1; attempt_no <= attempt_count; attempt_no++) {
      idx = attempt_index[attempt_no]
      if (!verified[idx]) invalid("attempted item has no verification: " plan_item[idx])
    }
    if ($2 != "fresh" && $2 != "changed" && $2 != "unverifiable")
      invalid("recheck status must be fresh, changed, or unverifiable")
    if (NF - 2 != guard_count) invalid("recheck input set differs from guard complete")
    for (field = 3; field <= NF; field++) {
      if (rechecked_input[$field]) invalid("recheck repeats an input: " $field)
      rechecked_input[$field] = 1
      covered = 0
      for (guard_no = 1; guard_no <= guard_count; guard_no++)
        if (guard_input[guard_no] == $field) covered++
      if (covered != 1) invalid("recheck names an input absent from guard complete: " $field)
    }
    for (guard_no = 1; guard_no <= guard_count; guard_no++) {
      dep = guard_input[guard_no]
      if (!rechecked_input[dep]) invalid("recheck omits guarded input: " dep)
      delete rechecked_input[dep]
    }
    input_recheck = $2
    phase = "rechecked"
    next
  }
  if (event == "post") {
    require_fields(2)
    if (phase != "rechecked") {
      if (phase == "verified")
        for (attempt_no = 1; attempt_no <= attempt_count; attempt_no++) {
          idx = attempt_index[attempt_no]
          if (!verified[idx]) invalid("attempted item has no verification: " plan_item[idx])
        }
      invalid("post must follow the post-write input recheck")
    }
    for (attempt_no = 1; attempt_no <= attempt_count; attempt_no++) {
      idx = attempt_index[attempt_no]
      if (!verified[idx]) invalid("attempted item has no verification: " plan_item[idx])
      if (verification[idx] == "changed" && input_recheck == "fresh") {
        disposition[idx] = "completed"
        detail[idx] = "changed"
        changed_count++
      } else if (verification[idx] == "changed") {
        disposition[idx] = "unknown"
        detail[idx] = "post-write inputs were " input_recheck
        unknown_count++
        writes_stopped = 1
      } else if (verification[idx] == "failed") {
        disposition[idx] = "skipped"
        detail[idx] = "write failed or its condition was rejected"
        action_class[idx] = "remaining"
        skipped_count++
        writes_stopped = 1
      } else {
        disposition[idx] = "unknown"
        detail[idx] = "write outcome could not be verified"
        unknown_count++
        writes_stopped = 1
      }
      delete attempted[idx]
      delete verified[idx]
      delete verification[idx]
      delete attempt_index[attempt_no]
    }
    if (attempt_status != "accepted") {
      attempt_problem = 1
      writes_stopped = 1
    }
    if (input_recheck != "fresh") writes_stopped = 1
    stop_writes_for_freshness($2)
    attempt_count = 0
    attempt_status = ""
    for (guard_no = 1; guard_no <= guard_count; guard_no++)
      delete guard_input[guard_no]
    guard_count = 0
    input_recheck = ""
    phase = "idle"
    next
  }
  if (event == "observe") {
    require_at_least(4)
    if (phase != "idle") invalid("observe requires an idle state")
    if (writes_stopped) invalid("no work may complete after a stop condition")
    idx = item_index($2)
    if (!idx) invalid("observe names an unplanned item: " $2)
    if (plan_kind[idx] != "noop" && plan_kind[idx] != "report")
      invalid("observe requires a noop or report item")
    if (disposition[idx] != "") invalid("item already dispositioned: " $2)
    if ($3 != "fresh" && $3 != "stale" && $3 != "unverifiable")
      invalid("observe status must be fresh, stale, or unverifiable")
    for (plan_no = 1; plan_no <= plan_count; plan_no++)
      if (plan_kind[plan_no] == "write" && disposition[plan_no] == "")
        invalid("observe must follow every planned write disposition: " plan_item[plan_no])
    if (plan_kind[idx] == "report")
      for (plan_no = 1; plan_no <= plan_count; plan_no++)
        if (plan_kind[plan_no] == "noop" && disposition[plan_no] == "")
          invalid("report observation must follow every no-op disposition: " plan_item[plan_no])
    if (NF - 3 != dep_count[idx]) invalid("observe input set differs from its plan")
    for (field = 4; field <= NF; field++) {
      if (observed_input[$field]) invalid("observe repeats an input: " $field)
      observed_input[$field] = 1
      covered = 0
      for (dep_no = 1; dep_no <= dep_count[idx]; dep_no++)
        if (plan_dep[idx, dep_no] == $field) covered++
      if (covered != 1) invalid("observe names an unplanned or duplicate input: " $field)
    }
    for (dep_no = 1; dep_no <= dep_count[idx]; dep_no++) {
      dep = plan_dep[idx, dep_no]
      if (!observed_input[dep]) invalid("observe omits planned input: " dep)
      delete observed_input[dep]
    }
    if ($3 == "fresh") {
      disposition[idx] = "completed"
      detail[idx] = plan_kind[idx]
    } else {
      disposition[idx] = "skipped"
      detail[idx] = "inputs were " $3 " at re-observation"
      action_class[idx] = "remaining"
      skipped_count++
      writes_stopped = 1
    }
    next
  }
  if (event == "skip") {
    require_fields(4)
    if (phase != "idle" && phase != "blocked" && phase != "guarded")
      invalid("skip requires an idle, blocked, or freshly reread state")
    idx = item_index($2)
    if (!idx) invalid("skip names an unplanned item: " $2)
    if (disposition[idx] != "") invalid("item already dispositioned: " $2)
    if (phase == "guarded" && plan_kind[idx] != "write")
      invalid("a post-reread skip requires a write item")
    if (phase == "guarded") {
      for (dep_no = 1; dep_no <= dep_count[idx]; dep_no++) {
        dep = plan_dep[idx, dep_no]
        covered = 0
        for (guard_no = 1; guard_no <= guard_count; guard_no++)
          if (guard_input[guard_no] == dep) covered = 1
        if (!covered) invalid("guard complete omits freshly reread input " dep " for " $2)
      }
    }
    if ($4 != "source" && $4 != "ambiguity" && $4 != "tooling" &&
        $4 != "guard" && $4 != "policy" && $4 != "closing" &&
        $4 != "unauthorized" && $4 != "remaining")
      invalid("unknown owner-action class: " $4)
    if (plan_kind[idx] == "unsupported" && $4 != "unauthorized")
      invalid("unsupported work requires the unauthorized owner action")
    disposition[idx] = "skipped"
    detail[idx] = $3
    action_class[idx] = $4
    skipped_count++
    if (phase == "guarded") {
      for (guard_no = 1; guard_no <= guard_count; guard_no++)
        delete guard_input[guard_no]
      guard_count = 0
    }
    if (phase == "blocked" || phase == "guarded") phase = "idle"
    next
  }
  if (event == "final") {
    require_fields(2)
    if (phase != "idle" && phase != "blocked")
      invalid("final requires an idle or blocked state")
    for (idx = 1; idx <= plan_count; idx++)
      if (disposition[idx] == "")
        invalid("planned item has no disposition: " plan_item[idx])
    stop_writes_for_freshness($2)
    final_seen = 1
    phase = "final"
    next
  }
  invalid("unknown event: " event)
}
END {
  if (bad) exit 2
  if (!policy_seen) {
    print "INVALID: trace has no policy event"
    exit 2
  }
  if (skeleton) {
    print_skeleton()
    exit 0
  }
  if (!final_seen) {
    print "INVALID: trace has no final freshness observation"
    exit 2
  }
  if (source_failed &&
      (plan_count != 1 || plan_item[1] != "project-reconciliation" ||
       plan_kind[1] != "report" || disposition[1] != "skipped" ||
       action_class[1] != "source")) {
    print "INVALID: failed policy needs one skipped project-reconciliation umbrella item with the source owner action"
    exit 2
  }

  if (freshness_failed) {
    if (changed_count || unknown_count) result = "partial"
    else if (trace_origin == "replacement") result = "unstable"
    else result = "restart"
  } else if (source_failed) {
    if (changed_count || unknown_count) result = "partial"
    else result = "incomplete"
  } else if (unknown_count || skipped_count || attempt_problem) {
    if (changed_count || unknown_count) result = "partial"
    else result = "incomplete"
  } else result = "complete"

  print "RESULT " result
  for (idx = 1; idx <= plan_count; idx++) {
    if (disposition[idx] == "completed")
      print "COMPLETED " plan_item[idx] " (" detail[idx] ")"
    else if (disposition[idx] == "unknown")
      print "UNKNOWN " plan_item[idx] ": " detail[idx]
    else
      print "SKIPPED " plan_item[idx] ": " detail[idx]
  }
  if (result == "complete") {
    print "OWNER ACTION none"
  } else if (result == "restart") {
    print "OWNER ACTION rediscover policy, freshly reread every input at the current base tip, and recompute; do not use a precomputed edit"
  } else if (result == "unstable") {
    print "OWNER ACTION wait for the base tip to stabilize, then rediscover policy and reacquire every input before recomputing; do not reuse either prior trace"
  }
  if (result == "partial") {
    print "OWNER ACTION preserve every verified write before any reconciliation continues"
    if (unknown_count)
      print "OWNER ACTION inspect every unknown write before rediscovery or recomputation"
  }
  if (freshness_failed && result == "partial")
    print "OWNER ACTION re-establish current base identity, rediscover policy, and reacquire every affected input before recomputing; do not replay or roll back a prior write"
  if (attempt_problem)
    print "OWNER ACTION reconcile the verified tracker state with the failed or rejected interface result, then reacquire current inputs before recomputing; do not retry blindly"
  for (idx = 1; idx <= plan_count; idx++) {
    if (disposition[idx] == "unknown")
      print "OWNER ACTION " plan_item[idx] ": establish the actual tracker state, then rediscover current policy and recompute remaining work; do not retry or roll back blindly"
    else if (disposition[idx] == "skipped" && !freshness_failed) {
      if (action_class[idx] == "source")
        action = "restore or correct the named authoritative current-base source, then restart discovery; do not substitute another source"
      else if (action_class[idx] == "ambiguity")
        action = "resolve the named ambiguity, then rediscover policy and reacquire every affected input before recomputing; do not guess"
      else if (action_class[idx] == "tooling")
        action = "use the documented tracker interface, then freshly reread every input and recompute; do not improvise a mutation mechanism"
      else if (action_class[idx] == "guard")
        action = "restore access, then freshly reread every selector and computation input and recompute before applying; do not use a precomputed edit"
      else if (action_class[idx] == "policy")
        action = "re-establish current base identity, then rediscover policy and reacquire every input before recomputing; do not use a precomputed edit"
      else if (action_class[idx] == "closing")
        action = "reverify the closing issues, then rediscover trackers and recompute from freshly reread inputs"
      else if (action_class[idx] == "unauthorized")
        action = "authorize and perform this as a separate work unit; merge-cleanup cannot inherit it"
      else
        action = "rediscover current policy, freshly reread every affected input, and recompute remaining work; do not use a precomputed edit"
      print "OWNER ACTION " plan_item[idx] ": " action
    }
  }
}
' "$TRACE"
