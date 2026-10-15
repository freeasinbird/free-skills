#!/usr/bin/env bash
# tracker-refresh.sh: compute the merge-time refresh of one tracker on the
# shared tracker format (agent-setup's references/tracker-format.md §refresh)
# and print the refreshed Markdown. Read-only by construction: it reads the
# tracker and its units with gh and writes nothing to the forge, because the
# whole-body write belongs to the reconciliation protocol, which rereads every
# input right before it writes and reruns this command to verify the write.
#
# Usage:
#   tracker-refresh.sh --repo host/owner/name --issue N [--comment ID]
#   tracker-refresh.sh --help
#
# Without --comment it refreshes the issue body; with it, that one comment on
# the issue, for a tracker kept in a comment. Every unit is a `- [ ] <ref>`
# line under `## Units`; a chart node maps to a unit by the first reference in
# its label, and a node that maps to no unit is left alone.
#
# The refresh, from each unit issue's state and Dependencies field:
#   - A unit is merged when its issue is closed as completed. Closed as not
#     planned, or open, is not merged.
#   - Tick every merged unit's line and double-border its node. Never remove a
#     tick or a double border; one that issue state does not support is left
#     and reported.
#   - A unit is startable when its issue is open, its node is not in the
#     `fenced` class, and every `starts-after` prerequisite is merged.
#     `merges-after`, `stacked-on`, and `exclusive-with` do not gate a start.
#   - Rewrite the `class ... startable` line and the **Startable now** bullet
#     with that set in Units order. Edges, labels, other classes, and every
#     other line stay as they are.
#
# Stdout is the refreshed text exactly, ready for `gh issue edit --body-file`
# or a comment PATCH. One status line goes to stderr; it begins
# `OK unchanged` when the tracker already matches its refresh and
# `OK changed` otherwise, then lists what was ticked and double-bordered, the
# startable set, and anything left that issue state does not support. Exit
# codes:
#   0   refreshed text printed, whether or not anything changed
#   2   STOP: the tracker is closed, the comment is not on it, or the text is
#       not on the shared tracker format (including a unit line, class line,
#       or unit node it cannot read exactly)
#   4   LOOKUP_FAILED: a read failed, a node maps to units ambiguously (a
#       unit's node ID declared more than once, on its own line or inline on
#       an edge), or an open unit's Dependencies field is missing or does
#       not parse. Parsing fails closed: a shape it does not know stops the
#       run rather than dropping a prerequisite.
#   64  usage on stderr
#   69  gh or awk missing
set -u

ISSUE="" REPO_SPEC="" COMMENT=""

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:-}" in
  --help|-h) [ $# -eq 1 ] || usage; sed -n '2,/^set -u$/p' "$0" | sed '$d'; exit 0 ;;
esac

while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --repo|--issue|--comment) ;;
    *) echo "tracker-refresh.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "tracker-refresh.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  case "$opt" in
    --repo) REPO_SPEC="$val" ;;
    --issue) ISSUE="$val" ;;
    --comment) COMMENT="$val" ;;
  esac
done

[ -n "$REPO_SPEC" ] && [ -n "$ISSUE" ] || usage
case "$ISSUE" in ''|*[!0-9]*|0*)
  echo "tracker-refresh.sh: --issue must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$COMMENT" in
  '') ;;
  *[!0-9]*|0*)
    echo "tracker-refresh.sh: --comment must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$REPO_SPEC" in
  */*/*/*|*[!A-Za-z0-9._/-]*)
    echo "tracker-refresh.sh: --repo must be host/owner/name" >&2; usage ;;
  ?*/?*/?*) ;;
  *) echo "tracker-refresh.sh: --repo must be host/owner/name" >&2; usage ;;
esac
FORGE_HOST="${REPO_SPEC%%/*}"
REPO="${REPO_SPEC#*/}"
case "$FORGE_HOST" in
  ''|*[!A-Za-z0-9.-]*|.*|-*|*..*|*.-*|*-.|*.)
    echo "tracker-refresh.sh: --repo has an invalid host" >&2; usage ;;
esac

for tool in gh awk; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "tracker-refresh.sh: $tool not found on PATH" >&2
    exit 69
  }
done

TMPD=$(mktemp -d) || { echo "tracker-refresh.sh: mktemp failed" >&2; exit 69; }
trap 'rm -rf "$TMPD"' EXIT
REPO_LC=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')

stop() { echo "tracker-refresh.sh: STOP $1" >&2; exit 2; }
lookup_failed() { echo "tracker-refresh.sh: LOOKUP_FAILED $1" >&2; exit 4; }

# One awk program serves three modes, so the reference grammar is defined
# once. scan: list the Units lines. deps: list one unit body's dependency
# entries. rewrite: apply the refresh from a facts file.
AWK_PROG=$(cat <<'AWK'
function die(code, msg) {
  print "tracker-refresh.sh: " (code == 2 ? "STOP " : "LOOKUP_FAILED ") msg > "/dev/stderr"
  failed = code
  exit code
}
# full_key: canonical lowercase owner/repo#N for `#N` (relative to base) or
# `owner/repo#N`. A chart's short `repo#N` form returns "" with RP_PRE and
# RP_NUM set, for the caller to resolve against the Units list.
function full_key(ref, base,   h) {
  h = index(ref, "#")
  RP_PRE = tolower(substr(ref, 1, h - 1))
  RP_NUM = substr(ref, h + 1) + 0
  if (RP_PRE == "") return tolower(base) "#" RP_NUM
  if (index(RP_PRE, "/")) return RP_PRE "#" RP_NUM
  return ""
}
function last_index(s, t,   p, q) {
  p = 0
  while ((q = index(substr(s, p + 1), t)) > 0) p += q
  return p
}
function join(list, item) { return list == "" ? item : list ", " item }

# count_node_declarations: set NIDC[id] to how many times chart lines a..b
# declare node id, on its own line or inline on an edge. A declaration is an
# ID followed at once by a shape opener. The scan reads the chart as one
# stream and tells apart only what can make a mention look like one: front
# matter; strings, which may span lines; `%%` comments; statements that open
# with a keyword such as `subgraph` or `accTitle`; edge text; shape bodies;
# and longer IDs. Anything else is passed over, so unknown syntax can at
# worst hide a redeclaration, never stop a valid chart.
function count_node_declarations(a, b,   s, i, len, p, c, d, e, q, w, stmt, stmt_was) {
  # Mermaid strips front matter before it parses the chart.
  if (L[a] ~ /^[ \t]*---[ \t]*$/)
    for (i = a + 1; i <= b; i++) if (L[i] ~ /^[ \t]*---[ \t]*$/) { a = i + 1; break }
  s = ""
  for (i = a; i <= b; i++) s = s L[i] "\n"
  len = length(s); p = 1; stmt = 1
  while (p <= len) {
    c = substr(s, p, 1); d = substr(s, p, 2)
    if (c == "\n" || c == ";") { stmt = 1; p++; continue }
    if (c == " " || c == "\t") { p++; continue }
    if (d == "%%") { p = line_end(s, p); continue }
    stmt_was = stmt; stmt = 0
    if (stmt_was && match(substr(s, p, 12), /^[A-Za-z]+/)) {
      w = substr(s, p, RLENGTH); e = substr(s, p + RLENGTH, 1)
      if (w ~ /^acc(Title|Descr)$/ && e ~ /[ \t:{]/) {
        for (p += RLENGTH; substr(s, p, 1) ~ /[ \t]/; p++) ;
        if (substr(s, p, 1) != "{") { p = line_end(s, p); continue }
        q = index(substr(s, p), "}")
        p = q ? p + q : len + 1
        continue
      }
      if (w ~ /^(subgraph|end|direction|class|classDef|style|linkStyle|click|flowchart|graph)$/ && (e == "" || e ~ /[ \t\n;]/)) {
        p = statement_end(s, p + RLENGTH); continue
      }
    }
    if (c == "\"") { p = string_end(s, p); continue }
    if (d == "--" || d == "-." || d == "==") { p = edge_end(s, p); continue }
    # As in Mermaid, an ID runs to whitespace, a quote, `;`, one of
    # ()<=>@[]^{|}~, or an arrow, so `a-->b` is two IDs while `lane-i10`,
    # `lane.i10`, and `a&i10` are each one.
    for (q = p; q <= len && substr(s, q, 1) !~ /[] \t\n";()<=>@[^{|}~]/ && substr(s, q, 2) !~ /^-[-.>]/; q++) ;
    if (q == p) { p++; continue }
    w = substr(s, p, q - p); p = q
    c = substr(s, p, 1)
    if (c == "[" || c == "(" || c == "{" || c == ">" || substr(s, p, 2) == "@{") {
      NIDC[w]++
      p = shape_end(s, p + (c == "@" ? 2 : 1))
    }
  }
}
# string_end: p is at an opening quote; return the index past its closing
# quote, or past the end of s when it never closes.
function string_end(s, p,   q) {
  q = index(substr(s, p + 1), "\"")
  return q ? p + q + 1 : length(s) + 1
}
# line_end: the index of the newline that ends p's line.
function line_end(s, p,   q) {
  q = index(substr(s, p), "\n")
  return q ? p + q - 1 : length(s) + 1
}
# statement_end: the index of the newline or `;` that ends p's statement,
# passing over strings and stopping at a `%%` comment.
function statement_end(s, p,   c, len) {
  len = length(s)
  while (p <= len) {
    c = substr(s, p, 1)
    if (c == "\n" || c == ";" || substr(s, p, 2) == "%%") return p
    p = (c == "\"") ? string_end(s, p) : p + 1
  }
  return p
}
# shape_end: p is past a shape opener; return the index past the closing
# run, such as `]`, `]]`, `)]`, or `}}`, passing over strings.
function shape_end(s, p,   c, len) {
  len = length(s)
  while (p <= len) {
    c = substr(s, p, 1)
    if (c == "\"") { p = string_end(s, p); continue }
    p++
    if (c ~ /[])}]/) {
      while (substr(s, p, 1) ~ /[])}]/) p++
      return p
    }
  }
  return p
}
# edge_end: p is at an edge's `--`, `-.`, or `==`. An arrow continues at once
# (`-->`, `-.->`, `==>`, `--o`); otherwise the edge has text, as in
# `-- text -->`, that runs to the closing arrow on the same line. Return the
# index past the arrow and any `|text|` after it. Text with no closing
# arrow is not edge text, and the scan resumes after the opening pair.
function edge_end(s, p,   q, c, len, closer) {
  len = length(s); q = p + 2
  if (substr(s, q, 1) ~ /[-.=xo>]/) return arrow_end(s, q)
  closer = (substr(s, p, 2) == "-.") ? ".-" : substr(s, p, 2)
  while (q <= len) {
    c = substr(s, q, 1)
    if (c == "\n") break
    if (substr(s, q, 2) == closer) return arrow_end(s, q + 2)
    q = (c == "\"") ? string_end(s, q) : q + 1
  }
  return p + 2
}
# arrow_end: q is past an arrow's opening pair; return the index past the
# rest of the arrow (more `-`, `.`, or `=`, then one `x`, `o`, or `>`) and
# any `|text|` label after it.
function arrow_end(s, q,   r, c, len) {
  len = length(s)
  while (substr(s, q, 1) ~ /[-.=]/) q++
  if (substr(s, q, 1) ~ /[xo>]/) q++
  for (r = q; substr(s, r, 1) ~ /[ \t]/; r++) ;
  if (substr(s, r, 1) != "|") return q
  for (r++; r <= len; ) {
    c = substr(s, r, 1)
    if (c == "|") return r + 1
    if (c == "\n") return q
    r = (c == "\"") ? string_end(s, r) : r + 1
  }
  return r
}

function parse_tracker(   i, s0, s1, u0, u1, lane, ref, k, ln, rest, p, dbl, lbl, q, nm, cnt, j, t, ids, m, cls, x, key_name) {
  s0 = s1 = u0 = u1 = 0
  for (i = 1; i <= n; i++) {
    if (L[i] !~ /^## /) continue
    if (s0 && !s1) s1 = i
    if (u0 && !u1) u1 = i
    if (!s0 && L[i] ~ /^## Status[ \t]*$/) s0 = i
    else if (!u0 && L[i] ~ /^## Units[ \t]*$/) u0 = i
  }
  if (!s0 || !u0) die(2, "not on the shared tracker format: no ## Status or ## Units section")
  if (!s1) s1 = n + 1
  if (!u1) u1 = n + 1

  lane = ""
  for (i = u0 + 1; i < u1; i++) {
    if (L[i] ~ /^### /) {
      lane = ""
      if (L[i] ~ /^### lane:[^ \t]/) { lane = substr(L[i], 10); sub(/[ \t]+$/, "", lane) }
      continue
    }
    if (L[i] !~ /^[ \t]*[-*+][ \t]+\[[ xX]\]/) continue
    if (L[i] !~ /^- \[[ xX]\] (#[0-9]+|[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+#[0-9]+)[ \t]*$/)
      die(2, "not on the shared tracker format: unit line is not `- [ ] #N`: " L[i])
    ref = substr(L[i], 7); sub(/[ \t]+$/, "", ref)
    k = full_key(ref, repo)
    if (k in UIDX) die(4, "unit " ref " is listed twice under Units")
    nu++; UK[nu] = k; UD[nu] = ref; UL[nu] = i; UIDX[k] = nu
    ULANE[k] = lane
    UT[k] = (substr(L[i], 4, 1) != " ")
  }
  if (!nu) die(2, "not on the shared tracker format: no unit lines under ## Units")
  if (mode == "scan") return

  f0 = f1 = 0
  for (i = s0 + 1; i < s1; i++) {
    if (!f0) { if (L[i] ~ /^[ \t]*```[ \t]*mermaid[ \t]*$/) f0 = i; continue }
    if (L[i] ~ /^[ \t]*```[ \t]*$/) { f1 = i; break }
  }
  if (!f1) die(2, "not on the shared tracker format: no mermaid chart under ## Status")
  b0 = 0
  for (i = f1 + 1; i < s1; i++) if (L[i] ~ /^- \*\*Startable now:\*\*/) { b0 = i; break }
  if (!b0) die(2, "not on the shared tracker format: no **Startable now** bullet")
  bend = b0
  while (bend + 1 < s1 && L[bend + 1] ~ /^[ \t]+[^ \t]/) bend++

  count_node_declarations(f0 + 1, f1 - 1)
  IND = ""
  for (i = f0 + 1; i < f1; i++) {
    ln = L[i]
    if (ln ~ /[^ \t]/) { match(ln, /^[ \t]*/); IND = substr(ln, 1, RLENGTH) }
    if (ln ~ /^[ \t]*class[ \t]+[^ \t]+[ \t]+[A-Za-z0-9_-]+[ \t]*;?[ \t]*$/) {
      t = ln; sub(/^[ \t]*class[ \t]+/, "", t); sub(/[ \t]*;?[ \t]*$/, "", t)
      match(t, /[ \t]+/)
      cls = substr(t, RSTART + RLENGTH)
      m = split(substr(t, 1, RSTART - 1), ids, ",")
      for (j = 1; j <= m; j++) CLS[ids[j], cls] = 1
      if (cls == "startable") {
        nsl++; SL[nsl] = i
        if (nsl == 1) { match(ln, /^[ \t]*/); SLIND = substr(ln, 1, RLENGTH) }
        for (j = 1; j <= m; j++) if (!(ids[j] in SEEN)) { SEEN[ids[j]] = 1; nso++; SO[nso] = ids[j] }
      }
      continue
    }
    if (ln ~ /^[ \t]*class[ \t]/) die(2, "not on the shared tracker format: class line does not parse: " ln)
    # A node standing on its own line: id["label"] or id[["label"]]. A
    # quoted Mermaid label holds no bare quote, so an edge line that defines
    # two nodes never matches.
    if (ln !~ /^[ \t]*[A-Za-z0-9_-]+(\["[^"]*"\]|\[\["[^"]*"\]\])[ \t]*;?[ \t]*$/) continue
    match(ln, /^[ \t]*/); rest = substr(ln, RLENGTH + 1)
    p = index(rest, "[")
    id = substr(rest, 1, p - 1)
    dbl = (substr(rest, p, 3) == "[[\"")
    lbl = substr(rest, p + (dbl ? 3 : 2))
    lbl = substr(lbl, 1, last_index(lbl, "\"") - 1)
    if (!match(lbl, /([A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]*#[0-9]+/)) continue
    ref = substr(lbl, RSTART, RLENGTH)
    k = full_key(ref, repo)
    if (k == "") {
      nm = RP_PRE; cnt = 0
      for (j = 1; j <= nu; j++) {
        key_name = UK[j]; sub(/#.*/, "", key_name); sub(/.*\//, "", key_name)
        x = UK[j]; sub(/.*#/, "", x)
        if (key_name == nm && x + 0 == RP_NUM) { cnt++; k = UK[j] }
      }
      if (cnt > 1) die(4, "node " id " (" ref ") matches more than one unit")
      if (!cnt) continue
    }
    if (!(k in UIDX)) continue
    if (k in NODE) die(4, "unit " UD[UIDX[k]] " has two nodes, " NODE[k] " and " id)
    NODE[k] = id; NL[k] = i; ND[k] = dbl; NODE_UNIT[id] = k
  }
  # Mermaid draws a repeated ID as one node with the last label, so a
  # border or class on that ID could land on another issue's box.
  for (k in NODE) if (NIDC[NODE[k]] > 1) die(4, "node " NODE[k] " of unit " UD[UIDX[k]] " is declared more than once")
}

function rewrite(   changed, j, k, i, p, q, fen, ids, s, item, quals, out, anyopen, anyfenced, allmerged, waits, nw, w, wl, ticked, bordered, left, text) {
  ticked = bordered = left = ids = out = waits = ""
  anyopen = anyfenced = 0; allmerged = 1
  for (j = 1; j <= nu; j++) {
    k = UK[j]
    if (!(k in M)) die(4, "no issue facts for unit " UD[j])
    # A unit drawn some other way, such as inline on an edge or with a
    # `:::` class, could carry a fence this command cannot see.
    if (!(k in NODE)) die(2, "not on the shared tracker format: unit " UD[j] " has no node line of the form id[\"#N ...\"]")
    i = UL[j]
    if (M[k] && !UT[k]) { L[i] = "- [x]" substr(L[i], 6); ticked = join(ticked, UD[j]) }
    else if (UT[k] && !M[k]) left = join(left, UD[j] " ticked but not merged")
    if (k in NODE) {
      i = NL[k]
      if (M[k] && !ND[k]) {
        p = index(L[i], "[\""); q = last_index(L[i], "\"]")
        L[i] = substr(L[i], 1, p - 1) "[[\"" substr(L[i], p + 2, q - p - 2) "\"]]" substr(L[i], q + 2)
        bordered = join(bordered, NODE[k])
      } else if (ND[k] && !M[k]) left = join(left, NODE[k] " double-bordered but not merged")
    }
    fen = (k in NODE) && ((NODE[k], "fenced") in CLS)
    if (!M[k]) allmerged = 0
    if (O[k]) anyopen = 1
    if (O[k] && fen) anyfenced = 1
    if (O[k] && !fen && !R[k]) {
      nw = split(W[k], wl, ",")
      for (w = 1; w <= nw; w++) if (!(wl[w] in WSEEN)) { WSEEN[wl[w]] = 1; waits = join(waits, wl[w]) }
    }
    if (!(O[k] && R[k] && !fen)) continue
    quals = ULANE[k]
    if ((k in NODE) && ((NODE[k], "contract") in CLS)) quals = (quals == "" ? "contract" : quals ", contract")
    out = join(out, UD[j] (quals == "" ? "" : " (" quals ")"))
    if (k in NODE) ids = ids (ids == "" ? "" : ",") NODE[k]
  }
  # Keep a non-unit node's own startable membership: it is not this
  # tracker's to refresh.
  for (s = 1; s <= nso; s++) if (!(SO[s] in NODE_UNIT)) ids = ids (ids == "" ? "" : ",") SO[s]

  if (nsl) {
    if (ids != "") L[SL[1]] = SLIND "class " ids " startable"
    else DEL[SL[1]] = 1
    for (s = 2; s <= nsl; s++) DEL[SL[s]] = 1
  } else if (ids != "") INS = IND "class " ids " startable"

  text = out
  if (text == "") {
    if (!anyopen) text = allmerged ? "all units merged" : "no unit is open"
    else if (waits == "") text = "every open unit is fenced"
    else if (anyfenced) text = "every open unit is fenced or waits on " waits
    else text = "every open unit waits on " waits
  }
  L[b0] = "- **Startable now:** " text "."
  for (i = b0 + 1; i <= bend; i++) DEL[i] = 1

  # The text was read with the one newline gh's --jq adds after the body,
  # so the last line is printed without one: stdout is the body exactly, and
  # a write of it reads back the same.
  changed = (INS != "")
  for (i = 1; i <= n; i++) {
    if (i == f1 && INS != "") printf "%s\n", INS (CR[i] ? "\r" : "")
    if (i in DEL) { changed = 1; continue }
    if (L[i] != ORIG[i]) changed = 1
    printf "%s%s", L[i] (CR[i] ? "\r" : ""), (i < n ? "\n" : "")
  }
  print (changed ? "changed" : "unchanged") \
    "; ticked " (ticked == "" ? "none" : ticked) \
    "; double-bordered " (bordered == "" ? "none" : bordered) \
    "; startable now " text \
    (left == "" ? "" : "; left " left) > report
}

# parse_entry: emit `relation<TAB>key` for each relation in t and return 1
# only when the whole entry parses. An entry is a relation followed by
# `none` or by references joined with `,` or `and`, each optionally followed
# by a parenthetical. Relations may follow one another after `,` or `;`. A
# colon or a period ends the entry and starts a note, which may name
# `starts-after` only as reverse_only allows. Anything else after a
# reference, such as `or`, `&`, or a bare second reference, returns 0, so an
# unforeseen shape stops the run rather than dropping a prerequisite.
function parse_entry(t,   rel, got, s) {
  t = tolower(t)
  while (1) {
    if (!match(t, /^(starts-after|merges-after|stacked-on|exclusive-with)/)) return 0
    rel = substr(t, 1, RLENGTH)
    t = substr(t, RLENGTH + 1)
    if (!sub(/^:?[ \t]+/, "", t)) return 0
    if (t ~ /^none([^a-z0-9]|$)/) t = substr(t, 5)
    else {
      got = 0
      while (match(t, /^([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+/)) {
        print rel "\t" full_key(substr(t, 1, RLENGTH), base)
        got++
        t = substr(t, RLENGTH + 1)
        sub(/^[ \t]*\([^)]*\)/, "", t)
        if (t !~ /^(,[ \t]*(and[ \t]+)?|[ \t]+and[ \t]+)([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+/) break
        match(t, /^(,[ \t]*(and[ \t]+)?|[ \t]+and[ \t]+)/)
        t = substr(t, RLENGTH + 1)
      }
      if (!got) return 0
    }
    if (t ~ /^[ \t]*$/) return 1
    if (t ~ /^[ \t]*(:|\.([ \t]|$))/) return reverse_only(t)
    if (!match(t, /^[ \t]*[;,][ \t]*(and[ \t]+)?/) && !match(t, /^[ \t]+and[ \t]+/)) return 0
    s = substr(t, RLENGTH + 1)
    if (s !~ /^(starts-after|merges-after|stacked-on|exclusive-with)/) return 0
    t = s
  }
}

# reverse_only: prose may name `starts-after` only to say which issues wait
# on this unit, as Freeside's `Reverse:` lines do; every other mention is a
# prerequisite this command cannot place.
function reverse_only(t) {
  t = tolower(t)
  while (match(t, /starts-after/)) {
    t = substr(t, RSTART + RLENGTH)
    sub(/^:?[ \t]+/, "", t)
    if (!match(t, /^([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+/)) return 0
    if (full_key(substr(t, 1, RLENGTH), base) != self) return 0
  }
  return 1
}

# dep_text: one entry or note from the field. An entry for a relation that
# gates no start may be prose, such as `exclusive-with other open contract
# units`, unless it also names `starts-after`.
function dep_text(t, item,   lt) {
  lt = tolower(t)
  if (lt ~ /^(starts-after|merges-after|stacked-on|exclusive-with)/) {
    if (parse_entry(t)) return
    if (lt ~ /starts-after/) die(4, "cannot parse a Dependencies entry of " unit ": " t)
    return
  }
  if (item || lt ~ /^([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+/ || !reverse_only(t))
    die(4, "cannot parse a Dependencies entry of " unit ": " t)
}

# parse_deps reads a `Dependencies` heading's section, or failing that a
# `**Dependencies.**` lead and its paragraph. In a section, every list item
# and every line that begins with a relation or a reference is an entry; a
# list item's indented continuation lines join it. `Fence:` lines and
# other prose, such as Freeside's `Refs` lines, are notes. A
# section that opens with a bare `none` or `_No response_` line declares no
# dependency, and what follows explains it, as Freeside's #2019 does; a line
# there shaped like an entry contradicts it and fails. A field that is
# absent, or a section with neither an entry nor `none`, fails, since this
# runs only for an open unit and its prerequisites cannot be known.
function parse_deps(   i, lvl, t, lt, item, para, seen, nonef, stated) {
  for (i = 1; i <= n; i++) if (L[i] ~ /^#+[ \t]+Dependencies([^A-Za-z]|$)/) break
  if (i <= n) {
    match(L[i], /^#+/); lvl = RLENGTH
    for (i++; i <= n; i++) {
      t = L[i]
      if (t ~ /^#+[ \t]/) { match(t, /^#+/); if (RLENGTH <= lvl) break; continue }
      item = (t ~ /^[ \t]*([-*+]|[0-9]+[.)]|>)[ \t]+/)
      if (item)
        while (i < n && L[i + 1] ~ /^[ \t]+[^ \t]/ && L[i + 1] !~ /^[ \t]*([-*+]|[0-9]+[.)]|>)[ \t]+/)
          t = t " " L[++i]
      sub(/^[ \t]*(([-*+]|[0-9]+[.)]|>)[ \t]+)?/, "", t); gsub(/\*\*|`/, "", t)
      gsub(/[ \t]+/, " ", t); sub(/[ \t]+$/, "", t)
      if (t == "") continue
      lt = tolower(t)
      if (lt ~ /^(none|_no response_)\.?$/) { if (!seen) nonef = 1; seen = stated = 1; continue }
      seen = 1
      if (lt ~ /^fence[.:]/) {
        if (!reverse_only(t)) die(4, "cannot parse a Dependencies entry of " unit ": " t)
        continue
      }
      if (!nonef) {
        dep_text(t, item)
        if (lt ~ /^(starts-after|merges-after|stacked-on|exclusive-with)/) stated = 1
        continue
      }
      if (lt ~ /^(starts-after|merges-after|stacked-on|exclusive-with)/ || lt ~ /^(([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+[ \t,.]*(and[ \t]+)?)+$/)
        die(4, "Dependencies of " unit " say none, then: " t)
    }
    if (!stated) die(4, "the Dependencies section of " unit " has no entry and no none")
    return
  }
  for (i = 1; i <= n; i++) if (L[i] ~ /^([-*][ \t]+)?(\*\*)?Dependencies(\*\*)?[:.](\*\*)?/) break
  if (i > n) die(4, "open unit " unit " has no Dependencies field")
  para = L[i]
  sub(/^([-*][ \t]+)?(\*\*)?Dependencies(\*\*)?[:.](\*\*)?[ \t]*/, "", para)
  for (i++; i <= n && L[i] ~ /[^ \t]/; i++) para = para " " L[i]
  gsub(/\*\*|`/, "", para); gsub(/[ \t]+/, " ", para)
  lt = tolower(para)
  if (lt ~ /^(none|_no response_)([^a-z0-9_]|$)/) {
    if (!reverse_only(para)) die(4, "cannot parse the Dependencies field of " unit ": " para)
    return
  }
  # The lead's paragraph is the field's value, never a note.
  if (lt ~ /^(starts-after|merges-after|stacked-on|exclusive-with)/ && (parse_entry(para) || lt !~ /starts-after/)) return
  die(4, "cannot parse the Dependencies field of " unit ": " para)
}

mode == "rewrite" && FILENAME == facts {
  split($0, f, "\t")
  M[f[1]] = f[2] + 0; O[f[1]] = f[3] + 0; R[f[1]] = f[4] + 0; W[f[1]] = f[5]
  next
}
{ line = $0; cr = sub(/\r$/, "", line); n++; L[n] = ORIG[n] = line; CR[n] = cr }
END {
  if (failed) exit failed
  if (mode == "deps") { parse_deps(); exit }
  parse_tracker()
  if (mode == "scan") { for (j = 1; j <= nu; j++) print UK[j] "\t" UD[j]; exit }
  rewrite()
}
AWK
)

# issue_state <key>: set STATE to MERGED, OPEN, or CLOSED and, when a body
# path is given, save the issue body there. Cached per key, so a
# prerequisite shared by several units is read once.
issue_state() {
  local key="$1" body="${2:-}" or num cache raw
  or="${key%#*}"; num="${key##*#}"
  cache="$TMPD/state.$(printf '%s' "$key" | tr '/#' '~@')"
  if [ -z "$body" ] && [ -f "$cache" ]; then STATE=$(cat "$cache"); return; fi
  raw="$TMPD/raw"
  if [ -n "$body" ]; then
    gh issue view "$num" --repo "$FORGE_HOST/$or" --json state,stateReason,body \
      --jq '.state, (.stateReason // ""), .body' </dev/null >"$raw" 2>/dev/null \
      || lookup_failed "issue $key"
    tail -n +3 "$raw" >"$body"
  else
    gh issue view "$num" --repo "$FORGE_HOST/$or" --json state,stateReason \
      --jq '.state, (.stateReason // "")' </dev/null >"$raw" 2>/dev/null \
      || lookup_failed "issue $key"
  fi
  case "$(sed -n 1p "$raw") $(sed -n 2p "$raw")" in
    "CLOSED COMPLETED") STATE=MERGED ;;
    "OPEN "*) STATE=OPEN ;;
    "CLOSED "*) STATE=CLOSED ;;
    *) lookup_failed "issue $key: unrecognized state" ;;
  esac
  printf '%s' "$STATE" >"$cache"
}

display() { # display <key>: the form a tracker in this repository writes
  case "${1%#*}" in
    "$REPO_LC") printf '#%s' "${1##*#}" ;;
    *) printf '%s' "$1" ;;
  esac
}

TEXT="$TMPD/text"
gh issue view "$ISSUE" --repo "$REPO_SPEC" --json state,body --jq '.state, .body' \
  >"$TMPD/tracker" 2>/dev/null || lookup_failed "tracker issue #$ISSUE"
case "$(sed -n 1p "$TMPD/tracker")" in
  OPEN) ;;
  CLOSED) stop "tracker #$ISSUE is closed; a closed tracker is never edited" ;;
  *) lookup_failed "tracker issue #$ISSUE: unrecognized state" ;;
esac
if [ -z "$COMMENT" ]; then
  tail -n +2 "$TMPD/tracker" >"$TEXT"
else
  gh api --hostname "$FORGE_HOST" "repos/$REPO/issues/comments/$COMMENT" \
    --jq '.issue_url, .body' >"$TMPD/comment" 2>/dev/null \
    || lookup_failed "comment $COMMENT"
  owner_url=$(sed -n 1p "$TMPD/comment" | tr 'A-Z' 'a-z')
  case "$owner_url" in
    */repos/"$REPO_LC"/issues/"$ISSUE") ;;
    *) stop "comment $COMMENT is not on tracker #$ISSUE" ;;
  esac
  tail -n +2 "$TMPD/comment" >"$TEXT"
fi

awk -v mode=scan -v repo="$REPO_LC" "$AWK_PROG" "$TEXT" >"$TMPD/units" || exit $?

FACTS="$TMPD/facts"
: >"$FACTS"
while IFS="$(printf '\t')" read -r key shown; do
  issue_state "$key" "$TMPD/unit-body"
  unit_state="$STATE"
  ready=1 waits=""
  # Only an open unit can be startable, so a closed unit's Dependencies
  # field, often stale history by then, is never read.
  if [ "$unit_state" = OPEN ]; then
    awk -v mode=deps -v base="${key%#*}" -v self="$key" -v unit="$shown" "$AWK_PROG" \
      "$TMPD/unit-body" >"$TMPD/deps" || exit $?
    while IFS="$(printf '\t')" read -r rel prereq; do
      [ "$rel" = starts-after ] || continue
      issue_state "$prereq"
      [ "$STATE" = MERGED ] && continue
      ready=0
      waits="${waits:+$waits,}$(display "$prereq")"
    done <"$TMPD/deps"
  fi
  merged=0 open=0
  [ "$unit_state" = MERGED ] && merged=1
  [ "$unit_state" = OPEN ] && open=1
  printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$merged" "$open" "$ready" "$waits" >>"$FACTS"
done <"$TMPD/units"

awk -v mode=rewrite -v repo="$REPO_LC" -v facts="$FACTS" -v report="$TMPD/report" \
  "$AWK_PROG" "$FACTS" "$TEXT" >"$TMPD/out" || exit $?
cat "$TMPD/out"
echo "tracker-refresh.sh: OK $(cat "$TMPD/report")" >&2
exit 0
