# shellcheck shell=bash
# landing-record.sh: shared, fail-closed reader for a repository's landing
# record in AGENTS.md. Sourced by list-ready.sh and landed-since.sh; expects
# the caller to define stop <guard> <detail> and lookup_failed <what> <detail>.
#
# Exports:
#   read_landing_record <commit-ref> <default-branch>
#     Verifies AGENTS.md at <commit-ref> is a regular file free of NUL bytes,
#     bare carriage returns, and a leading UTF-8 BOM, then parses the visible
#     landing record while skipping line-1 front matter, fenced code blocks,
#     and HTML comments. Sets RECORD to "key<TAB>value" lines on success.
#     Stops no-landing-record when AGENTS.md is absent or clean with zero
#     visible records, stops bad-record on malformed/duplicate records or any
#     Markdown layout this narrow reader cannot classify with certainty, and
#     calls lookup_failed record on a failed git tree/blob read.
#   record_value <key>
#     Prints the value for <key> from RECORD without truncating on tabs.

read_landing_record() { # read_landing_record <commit-ref> <default-branch>
  local ref="$1" default_branch="$2"
  local entry blob_oid tmp nul_tmp rc bom last_byte parsed

  entry=$(git ls-tree --full-tree "$ref" -- AGENTS.md 2>/dev/null) \
    || lookup_failed record "could not list AGENTS.md at $default_branch's tip"
  [ -n "$entry" ] \
    || stop no-landing-record "AGENTS.md is missing at $default_branch's tip, so there is no landing record"
  case "$entry" in
    *$'\n'*)
      stop bad-record "AGENTS.md at $default_branch's tip is not a regular file" ;;
    "100644 blob "*$'\tAGENTS.md'|"100755 blob "*$'\tAGENTS.md') ;;
    *)
      stop bad-record "AGENTS.md at $default_branch's tip is not a regular file" ;;
  esac

  blob_oid="${entry#* blob }"
  blob_oid="${blob_oid%%$'\t'*}"
  case "$blob_oid" in
    ''|*[!0-9a-f]*)
      lookup_failed record "could not parse AGENTS.md blob OID at $default_branch's tip" ;;
  esac

  tmp=$(mktemp) || lookup_failed tmp "mktemp failed"
  git cat-file blob "$blob_oid" > "$tmp" 2>/dev/null \
    || { rm -f -- "$tmp"; lookup_failed record "could not read AGENTS.md at $default_branch's tip"; }

  # Command substitution drops or truncates NUL bytes, so inspect the temp
  # file directly with two files rather than a pipe (cmp exits at the first
  # difference and could kill tr).
  nul_tmp=$(mktemp) || { rm -f -- "$tmp"; lookup_failed tmp "mktemp failed"; }
  rc=2
  LC_ALL=C tr -d '\000' < "$tmp" > "$nul_tmp" && { cmp -s -- "$tmp" "$nul_tmp"; rc=$?; }
  case "$rc" in
    0) ;;
    1) rm -f -- "$tmp" "$nul_tmp"; stop bad-record "AGENTS.md at $default_branch's tip holds a NUL byte" ;;
    *) rm -f -- "$tmp" "$nul_tmp"; lookup_failed record "could not inspect AGENTS.md at $default_branch's tip" ;;
  esac

  bom=$(LC_ALL=C od -An -tx1 -N 3 "$tmp" 2>/dev/null) \
    || { rm -f -- "$tmp" "$nul_tmp"; lookup_failed record "could not inspect AGENTS.md at $default_branch's tip"; }
  bom="${bom//[[:space:]]/}"
  if [ "$bom" = "efbbbf" ]; then
    rm -f -- "$tmp" "$nul_tmp"
    stop bad-record "AGENTS.md at $default_branch's tip starts with a UTF-8 BOM"
  fi

  # A trailing lone CR at EOF with no LF would otherwise look like CRLF to
  # awk's per-line CR strip. Reuse nul_tmp to avoid masking errors in a pipe.
  tail -c 1 "$tmp" > "$nul_tmp" 2>/dev/null \
    && last_byte=$(LC_ALL=C od -An -tx1 "$nul_tmp" 2>/dev/null) \
    || { rm -f -- "$tmp" "$nul_tmp"; lookup_failed record "could not inspect AGENTS.md at $default_branch's tip"; }
  rm -f -- "$nul_tmp"
  last_byte="${last_byte//[[:space:]]/}"
  if [ "$last_byte" = "0d" ]; then
    rm -f -- "$tmp"
    stop bad-record "AGENTS.md at $default_branch's tip holds a bare carriage return"
  fi

  parsed=$(LC_ALL=C awk '
    BEGIN {
      tags = "address article aside base basefont blockquote body caption center col colgroup dd details dialog dir div dl dt fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hr html iframe legend li link main menu menuitem nav noframes ol optgroup option p param search section source summary table tbody td tfoot th thead title tr track ul"
      n_tags = split(tags, tag_arr, " ")
      for (t = 1; t <= n_tags; t++) html_block_tags[tag_arr[t]] = 1
      err = ""
      in_fm = ""
      fence_char = ""
      fence_len = 0
      fence_indent = 0
      in_comment = 0
      comment_indent = 0
      in_record = 0
      after_record_blank = 0
      in_linklabel = 0
      in_linkref = 0
      record_count = 0
      cur_key = ""
      cur_val = ""
      out_count = 0
    }

    function fail(msg) {
      if (err == "") err = msg
    }

    function flush_kv() {
      if (cur_key != "") {
        out_count++
        out_lines[out_count] = cur_key "\t" cur_val
        cur_key = ""
        cur_val = ""
      }
    }

    function leading_ws(s,    i, n, ch) {
      WS_SPACES = 0
      WS_TAB = 0
      n = length(s)
      for (i = 1; i <= n; i++) {
        ch = substr(s, i, 1)
        if (ch == " ") {
          if (!WS_TAB) WS_SPACES++
        } else if (ch == "\t") {
          WS_TAB = 1
        } else {
          break
        }
      }
      WS_REST = substr(s, i)
    }

    function count_char(s, target,    i, n) {
      n = length(s)
      for (i = 1; i <= n; i++) {
        if (substr(s, i, 1) != target) break
      }
      return i - 1
    }

    # Peel leading CommonMark container markers (blockquotes and list items) so
    # blocks opened on the same line as a marker (e.g. "- ```" or "- <script>")
    # cannot bypass top-level fence, HTML, or link-reference checks.
    function peel_containers(rest,    s, progressed) {
      PC_PEELED = 0
      PC_HAD_LIST = 0
      PC_HAD_QUOTE = 0
      s = rest
      while (1) {
        progressed = 0
        if (s ~ /^>[ \t]*/) {
          sub(/^>[ \t]*/, "", s)
          PC_PEELED = 1
          PC_HAD_QUOTE = 1
          progressed = 1
        } else if (s ~ /^[-*+][ \t]+/) {
          sub(/^[-*+][ \t]+/, "", s)
          PC_PEELED = 1
          PC_HAD_LIST = 1
          progressed = 1
        } else if (s ~ /^[0-9]+[.)][ \t]+/) {
          sub(/^[0-9]+[.)][ \t]+/, "", s)
          PC_PEELED = 1
          PC_HAD_LIST = 1
          progressed = 1
        }
        if (!progressed) break
      }
      PC_REST = s
    }

    # CommonMark HTML block start conditions (Types 1, 3, 4, 5, 6, 7).
    # Type 2 (<!--) is handled separately.
    function is_raw_html_block(rest,    lr, start, i, n, ch, tag, after) {
      if (substr(rest, 1, 1) != "<") return 0
      if (substr(rest, 1, 4) == "<!--") return 0
      if (substr(rest, 1, 2) == "<?") return 1
      if (substr(rest, 1, 9) == "<![CDATA[") return 1
      if (rest ~ /^<![A-Za-z]/) return 1
      lr = tolower(rest)
      if (lr ~ /^<(pre|script|style|textarea)([ \t>]|$)/) return 1
      # Type 6: block-level open or close tag
      start = (substr(lr, 1, 2) == "</") ? 3 : 2
      n = length(lr)
      i = start
      while (i <= n) {
        ch = substr(lr, i, 1)
        if (ch ~ /[a-z0-9]/) i++
        else break
      }
      if (i > start) {
        tag = substr(lr, start, i - start)
        after = substr(lr, i)
        if ((tag in html_block_tags) && (after == "" || after ~ /^[ \t>]/ || substr(after, 1, 2) == "/>")) {
          return 1
        }
      }
      # Type 7: complete open or closing tag alone on the line
      if (rest ~ /^<\/[A-Za-z][A-Za-z0-9-]*[ \t]*>[ \t]*$/) return 1
      if (rest ~ /^<[A-Za-z][A-Za-z0-9-]*([ \t]+[A-Za-z_:][A-Za-z0-9_.:-]*([ \t]*=[ \t]*([^ \t"\047=<>`]+|\047[^\047]*\047|"[^"]*"))?)*[ \t]*\/?>[ \t]*$/) return 1
      return 0
    }

    # Scan a single line for inline HTML comments while respecting backtick
    # code spans and backslash escapes outside code spans.
    function scan_inline_comments(s,    i, n, ch, run, in_code, in_cmt) {
      SCAN_ERR = ""
      SCAN_SAW_CMT = 0
      SCAN_OUT = ""
      in_code = 0
      in_cmt = 0
      i = 1
      n = length(s)
      while (i <= n) {
        if (in_cmt) {
          if (substr(s, i, 4) == "<!--") {
            SCAN_ERR = "nested <!-- inside an HTML comment"
            return
          }
          if (substr(s, i, 4) == "\\-->") {
            SCAN_ERR = "escaped HTML comment closer"
            return
          }
          if (substr(s, i, 3) == "-->") {
            in_cmt = 0
            i += 3
            continue
          }
          i++
          continue
        }
        ch = substr(s, i, 1)
        if (in_code > 0) {
          if (ch == "`") {
            run = count_char(substr(s, i), "`")
            SCAN_OUT = SCAN_OUT substr(s, i, run)
            i += run
            if (run == in_code) in_code = 0
          } else {
            SCAN_OUT = SCAN_OUT ch
            i++
          }
          continue
        }
        if (ch == "\\" && i < n) {
          if (substr(s, i, 5) == "\\<!--" || substr(s, i, 4) == "\\-->") {
            SCAN_ERR = "escaped HTML comment marker"
            return
          }
          SCAN_OUT = SCAN_OUT substr(s, i, 2)
          i += 2
          continue
        }
        if (ch == "`") {
          run = count_char(substr(s, i), "`")
          in_code = run
          SCAN_OUT = SCAN_OUT substr(s, i, run)
          i += run
          continue
        }
        if (substr(s, i, 4) == "<!--") {
          if (substr(s, i + 4, 1) == ">" || substr(s, i + 4, 2) == "->") {
            SCAN_ERR = "ambiguous short HTML comment"
            return
          }
          SCAN_SAW_CMT = 1
          in_cmt = 1
          i += 4
          continue
        }
        if (substr(s, i, 3) == "-->") {
          SCAN_SAW_CMT = 1
          SCAN_ERR = "orphan HTML comment closer"
          return
        }
        SCAN_OUT = SCAN_OUT ch
        i++
      }
      if (in_cmt) {
        SCAN_ERR = "unclosed mid-line HTML comment"
        return
      }
      if (in_code > 0) {
        SCAN_ERR = "unbalanced backtick span on line with HTML comment marker"
        return
      }
    }

    {
      if (err != "") next

      # Normalize CRLF (at most one trailing CR) and reject any bare CR.
      sub(/\r$/, "")
      if (index($0, "\r") > 0) {
        fail("line " NR " holds a bare carriage return")
        next
      }

      # 1. Line-1 front matter (--- or +++)
      if (NR == 1 && ($0 ~ /^---[ \t]*$/ || $0 ~ /^\+\+\+[ \t]*$/)) {
        in_fm = substr($0, 1, 3)
        next
      }
      if (in_fm != "") {
        if (in_fm == "---" && $0 ~ /^---[ \t]*$/) in_fm = ""
        else if (in_fm == "+++" && $0 ~ /^\+\+\+[ \t]*$/) in_fm = ""
        next
      }

      leading_ws($0)

      # 2. Active fenced code block
      if (fence_char != "") {
        if (WS_REST == "") next
        if (fence_indent >= 2 && !WS_TAB && WS_SPACES < fence_indent) {
          fail("line " NR " dedents inside an indented fenced code block")
          next
        }
        if (substr(WS_REST, 1, 1) == fence_char) {
          run = count_char(WS_REST, fence_char)
          after = substr(WS_REST, run + 1)
          if (run >= fence_len && after ~ /^[ \t]*$/) {
            if (!WS_TAB && WS_SPACES <= 3) {
              fence_char = ""
              fence_len = 0
              fence_indent = 0
              next
            }
            if (fence_indent >= 2 && (WS_TAB || (WS_SPACES >= 4 && WS_SPACES <= fence_indent + 3))) {
              fail("line " NR " has an ambiguous indented closing fence")
              next
            }
          }
        }
        next
      }

      # 3. Active multi-line HTML comment
      if (in_comment) {
        if (WS_REST != "" && comment_indent >= 2 && !WS_TAB && WS_SPACES < comment_indent) {
          fail("line " NR " dedents inside an indented HTML comment")
          next
        }
        if (index($0, "<!--") > 0) {
          fail("line " NR " nests <!-- inside an HTML comment")
          next
        }
        cpos = index($0, "-->")
        if (cpos > 0) {
          if (cpos > 1 && substr($0, cpos - 1, 1) == "\\") {
            fail("line " NR " has an escaped HTML comment closer")
            next
          }
          after = substr($0, cpos + 3)
          if (after !~ /^[ \t]*$/) {
            fail("line " NR " has trailing content after -->")
            next
          }
          in_comment = 0
          comment_indent = 0
        }
        next
      }

      # 4. Active landing record
      if (in_record) {
        if (WS_REST == "") {
          if (index($0, "\t") > 0) {
            fail("line " NR " has a tab inside the landing record")
            next
          }
          flush_kv()
          in_record = 0
          after_record_blank = 1
          in_linkref = 0
          next
        }
        if (index($0, "\t") > 0) {
          fail("line " NR " has a tab inside the landing record")
          next
        }
        if (index($0, "<!--") > 0 || index($0, "-->") > 0) {
          if (substr(WS_REST, 1, 4) == "<!--") {
            fail("line " NR " has an HTML comment inside the landing record")
            next
          }
          scan_inline_comments($0)
          if (SCAN_ERR != "") {
            fail("line " NR ": " SCAN_ERR)
            next
          }
          if (SCAN_SAW_CMT) {
            fail("line " NR " has an HTML comment inside the landing record")
            next
          }
        }
        if ($0 ~ /^  - \*\*[^*:]+:\*\* /) {
          line = substr($0, 7)
          pos = index(line, ":** ")
          k = substr(line, 1, pos - 1)
          v = substr(line, pos + 4)
          if (k == "" || index(k, "*") > 0 || index(k, ":") > 0 || k ~ /^ / || k ~ / $/) {
            fail("line " NR " has a malformed landing-record key")
            next
          }
          lk = tolower(k)
          if (lk in seen_key) {
            fail("line " NR " repeats landing-record key \"" k "\"")
            next
          }
          seen_key[lk] = 1
          flush_kv()
          cur_key = k
          cur_val = v
          next
        }
        if ($0 ~ /^    [^ ]/) {
          cont = substr($0, 5)
          if (cont ~ /^[-*+]([ ]|$)/ || cont ~ /^[0-9]+[.)]([ ]|$)/ || cont ~ /^>/ || cont ~ /^#(#?)(#?)(#?)(#?)(#?)([ ]|$)/ || cont ~ /^(```|~~~)/ || cont ~ /^(---+|___+|\*\*\*+)[ ]*$/ || cont ~ /^=+[ ]*$/ || is_raw_html_block(cont)) {
            fail("line " NR " is not a clean continuation line inside the landing record")
            next
          }
          if (cur_val == "") cur_val = cont
          else cur_val = cur_val " " cont
          next
        }
        fail("line " NR " is unexpected inside or directly after the landing record")
        next
      }

      # 5. Outside front matter, fence, comment, and landing record
      if (WS_REST == "") {
        in_linklabel = 0
        in_linkref = 0
        next
      }

      # Reject a second paragraph (4+ spaces or tab) or loose-list sibling
      # bullet (1-3 spaces) directly after the blank line(s) that ended the
      # landing record, rather than silently dropping trailing record content.
      if (after_record_blank) {
        if (WS_TAB || WS_SPACES >= 4) {
          fail("line " NR " continues the landing record after a blank line")
          next
        }
        if (WS_SPACES >= 1 && WS_SPACES <= 3 && (WS_REST ~ /^[-*+][ \t]/ || WS_REST ~ /^[0-9]+[.)][ \t]/)) {
          fail("line " NR " splits the landing record across a blank line")
          next
        }
        after_record_blank = 0
      }

      # 5a. Line-start HTML comment at 0-3 spaces (no leading tab)
      if (!WS_TAB && WS_SPACES <= 3 && substr(WS_REST, 1, 4) == "<!--") {
        if (in_linkref) {
          fail("line " NR " places an HTML comment in the same paragraph as a link reference definition")
          next
        }
        rest = substr(WS_REST, 5)
        if (substr(rest, 1, 1) == ">" || substr(rest, 1, 2) == "->") {
          fail("line " NR " has an ambiguous short HTML comment")
          next
        }
        cpos = index(rest, "-->")
        if (cpos > 0) {
          inside = substr(rest, 1, cpos - 1)
          if (index(inside, "<!--") > 0) {
            fail("line " NR " nests <!-- inside an HTML comment")
            next
          }
          if (length(inside) > 0 && substr(inside, length(inside), 1) == "\\") {
            fail("line " NR " has an escaped HTML comment closer")
            next
          }
          after = substr(rest, cpos + 3)
          if (after !~ /^[ \t]*$/) {
            fail("line " NR " has trailing content after -->")
            next
          }
          next
        }
        if (index(rest, "<!--") > 0) {
          fail("line " NR " nests <!-- inside an HTML comment")
          next
        }
        in_comment = 1
        comment_indent = WS_SPACES
        next
      }

      # 5b. Fenced code block opener (or ambiguous 4+-space / tab-indented fence)
      if (substr(WS_REST, 1, 3) == "```" || substr(WS_REST, 1, 3) == "~~~") {
        if (in_linkref) {
          fail("line " NR " places a code fence in the same paragraph as a link reference definition")
          next
        }
        fc = substr(WS_REST, 1, 1)
        run = count_char(WS_REST, fc)
        info = substr(WS_REST, run + 1)
        if (WS_TAB || WS_SPACES >= 4) {
          fail("line " NR " has a fence marker indented 4+ spaces or with a tab")
          next
        }
        if (fc == "~" || index(info, "`") == 0) {
          fence_char = fc
          fence_len = run
          fence_indent = WS_SPACES
          next
        }
      }

      # 5c. Inline HTML comment / backtick check on any line carrying <!-- or -->
      clean_line = $0
      saw_cmt = 0
      if (index($0, "<!--") > 0 || index($0, "-->") > 0) {
        scan_inline_comments($0)
        if (SCAN_ERR != "") {
          fail("line " NR ": " SCAN_ERR)
          next
        }
        saw_cmt = SCAN_SAW_CMT
        if (saw_cmt && in_linkref) {
          fail("line " NR " places an HTML comment in the same paragraph as a link reference definition")
          next
        }
        if (saw_cmt && (WS_TAB || WS_SPACES >= 4)) {
          fail("line " NR " has an HTML comment marker indented 4+ spaces or with a tab")
          next
        }
        clean_line = SCAN_OUT
      }

      # 5d. Non-comment raw HTML blocks (Types 1, 3, 4, 5, 6, 7), at top level
      # or directly after a container marker (list item or blockquote).
      if (is_raw_html_block(WS_REST)) {
        fail("line " NR " opens a raw HTML block")
        next
      }

      clean_rest = clean_line
      sub(/^[ \t]+/, "", clean_rest)
      peel_containers(clean_rest)
      if (PC_PEELED) {
        if (substr(PC_REST, 1, 3) == "```" || substr(PC_REST, 1, 3) == "~~~") {
          fc = substr(PC_REST, 1, 1)
          run = count_char(PC_REST, fc)
          info = substr(PC_REST, run + 1)
          if (fc == "~" || index(info, "`") == 0) {
            fail("line " NR " opens a code fence inside a container marker")
            next
          }
        }
        if (is_raw_html_block(PC_REST)) {
          fail("line " NR " opens a raw HTML block inside a container marker")
          next
        }
        if (PC_REST ~ /^\[[^]]+\]:/) {
          in_linkref = 1
          in_linklabel = 0
          next
        }
        if (PC_REST ~ /^\[[^]]*$/) {
          in_linklabel = 1
          next
        }
      }

      # 5e. Link reference definition paragraph tracking (single- or multi-line label)
      if (WS_REST ~ /^\[[^]]+\]:/) {
        in_linkref = 1
        in_linklabel = 0
        next
      }
      if (in_linklabel && WS_REST ~ /^[^[]*\]:/) {
        in_linkref = 1
        in_linklabel = 0
        next
      }
      if (WS_REST ~ /^\[[^]]*$/) {
        in_linklabel = 1
        next
      }

      # 5f. Landing record candidate detection
      lc = tolower(clean_line)
      lc_inner = tolower(PC_REST)
      if (lc ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\*\*|__)[ \t]*mechanism[ \t]*(\\?:(\*\*|__)|(\*\*|__)[ \t]*\\?:)/ || (PC_HAD_LIST && lc_inner ~ /^(\*\*|__)[ \t]*mechanism[ \t]*(\\?:(\*\*|__)|(\*\*|__)[ \t]*\\?:)/)) {
        if (in_linkref) {
          fail("line " NR " places a Mechanism bullet in the same paragraph as a link reference definition")
          next
        }
        if (saw_cmt) {
          fail("line " NR " has an HTML comment on a Mechanism bullet")
          next
        }
        if (index($0, "\t") > 0) {
          fail("line " NR " has a tab on a Mechanism bullet")
          next
        }
        if ($0 !~ /^  - \*\*Mechanism:\*\* /) {
          fail("line " NR " has a non-canonical Mechanism bullet")
          next
        }
        record_count++
        if (record_count > 1) {
          fail("line " NR " starts a second landing record")
          next
        }
        in_record = 1
        seen_key["mechanism"] = 1
        cur_key = "Mechanism"
        cur_val = $0
        sub(/^  - \*\*Mechanism:\*\* /, "", cur_val)
        next
      }
    }

    END {
      if (err != "") {
        print "ERR " err
        exit 1
      }
      if (in_fm != "") {
        print "ERR unclosed front matter"
        exit 1
      }
      if (fence_char != "") {
        print "ERR unclosed fenced code block"
        exit 1
      }
      if (in_comment) {
        print "ERR unclosed HTML comment"
        exit 1
      }
      if (in_record) flush_kv()
      for (i = 1; i <= out_count; i++) print out_lines[i]
    }
  ' "$tmp")
  rc=$?
  rm -f -- "$tmp"
  if [ "$rc" -ne 0 ]; then
    case "$parsed" in
      "ERR "*) stop bad-record "AGENTS.md at $default_branch's tip: ${parsed#ERR }" ;;
      *) lookup_failed record "could not parse AGENTS.md at $default_branch's tip" ;;
    esac
  fi

  RECORD="$parsed"
  [ -n "$RECORD" ] \
    || stop no-landing-record "AGENTS.md at $default_branch's tip has no landing record (no Mechanism bullet)"
}

record_value() { # record_value <key>
  printf '%s\n' "$RECORD" | LC_ALL=C awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }'
}
