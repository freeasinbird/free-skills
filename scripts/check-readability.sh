#!/usr/bin/env bash
# Report readability density or gate touched prose in markdown files.
#
# Counting rules:
# - A sentence ends at `.`, `!`, or `?` followed by whitespace or the end
#   of its unit.
# - Each list item, heading, table row, and blank-line-separated block is
#   its own unit, so a bullet never merges into its neighbour.
# - Fenced code, leading YAML frontmatter, HTML comments, and the devlog/
#   and .claude/ trees are excluded. The tree exclusions apply to the
#   default file set; explicitly named files are measured.
# - Words are whitespace-separated tokens after structural markdown
#   markers for headings, list items, and table rows are removed.
# - Gate mode checks only sentences and units whose line ranges intersect
#   added or modified lines relative to the merge base. Sentences may have
#   at most 40 words; units may have at most 120 words.
# - `<!-- readability: allow -->` starts an exempt region. The region ends
#   at `<!-- readability: end -->` or the end of the file.
#
# Usage: check-readability.sh [--gate --base <ref>] [file ...]
#   With no arguments, reports tracked and untracked-unignored *.md files,
#   excluding devlog/ and .claude/. Explicit paths are resolved relative
#   to the caller's directory.
#   Gate mode resolves the merge base of <ref> and HEAD, checks changed
#   markdown outside devlog/ and .claude/ by default, and prints word deltas.
#   Run `git add -N <path>` before a local gate check to include a new file.
#
# Exit codes: 0 after a report or clean gate, 1 for gate violations, and 2
# on a usage or environment error. Report mode never enforces thresholds.
set -euo pipefail

usage() {
  echo "usage: check-readability.sh [--gate --base <ref>] [file ...]" >&2
}

gate=0
base=
arguments=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --gate)
      gate=1
      shift
      ;;
    --base)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        usage
        exit 2
      fi
      base=$2
      shift 2
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      arguments+=("$1")
      shift
      ;;
  esac
done

if { [ "$gate" -eq 1 ] && [ -z "$base" ]; } || \
  { [ "$gate" -eq 0 ] && [ -n "$base" ]; }; then
  usage
  exit 2
fi

# Resolve caller-relative arguments before moving: the paths belong to the
# directory the report was invoked from.
files=()
for arg in "${arguments[@]}"; do
  case "$arg" in
    /*) files+=("$arg") ;;
    *) files+=("$PWD/$arg") ;;
  esac
done
cd "$(dirname "$0")/.."
repo_root=$(pwd -P)

if ! command -v python3 >/dev/null 2>&1; then
  echo "readability: python3 is required" >&2
  exit 2
fi

merge_base=
if [ "$gate" -eq 1 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "readability: gate mode requires a git worktree" >&2
    exit 2
  fi
  if ! merge_base=$(git merge-base "$base" HEAD); then
    echo "readability: cannot resolve merge base for $base" >&2
    exit 2
  fi
elif [ "${#files[@]}" -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "readability: default scan requires a git worktree" >&2
    exit 2
  fi
  while IFS= read -r -d '' file; do
    [ -f "$file" ] && files+=("$file")
  done < <(git ls-files -z --cached --others --exclude-standard -- \
    '*.md' ':!devlog' ':!.claude')
fi

if [ "$gate" -eq 0 ] && [ "${#files[@]}" -eq 0 ]; then
  echo "readability: no markdown files to report"
  exit 0
fi

python3 - "$gate" "$merge_base" "$repo_root" "${#files[@]}" \
  "${files[@]}" <<'PY'
import os
import re
import statistics
import subprocess
import sys


CONTAINER_PREFIX = re.compile(r"^(?P<quotes>(?: {0,3}>[ \t]?)*)(?P<rest>.*)$")
FENCE_OPEN = re.compile(
    r"^(?P<indent> {0,3})"
    r"(?:(?P<list>[-+*]|\d+[.)])(?P<spacing>[ \t]{1,4}))?"
    r"(?P<fence>`{3,}|~{3,})(?P<info>.*)$"
)
FENCE_CLOSE = re.compile(r"^(?P<indent>[ \t]*)(?P<fence>`{3,}|~{3,})[ \t]*$")
HEADING = re.compile(r"^[ \t]{0,3}#{1,6}(?:[ \t]+(?P<text>.*)|[ \t]*)$")
SETEXT_HEADING = re.compile(r"^[ \t]{0,3}(?:=+|-+)[ \t]*$")
LIST_ITEM = re.compile(r"^[ \t]*(?:[-+*]|\d+[.)])[ \t]+(?P<text>.*)$")
LIST_PREFIX = re.compile(
    r"^(?P<indent> {0,3})(?P<marker>[-+*]|\d+[.)])"
    r"(?P<spacing>[ \t]{1,4})(?P<text>.*)$"
)
SENTENCE_END = re.compile(
    r"(?<=[.!?])"
    r"(?:[*_~]+|[\"'”’»)]|\](?:\([^)]*\))?)*"
    r"(?:\s+|$)"
)
TABLE_DELIMITER = re.compile(r"^:?-{3,}:?$")
HUNK_HEADER = re.compile(
    r"^@@ -\d+(?:,\d+)? \+(?P<start>\d+)(?:,(?P<count>\d+))? @@"
)
ALLOW_START = re.compile(r"^ {0,3}<!-- readability: allow -->[ \t]*$")
ALLOW_END = re.compile(r"^ {0,3}<!-- readability: end -->[ \t]*$")

gate_mode = sys.argv[1] == "1"
merge_base = sys.argv[2]
repo_root = sys.argv[3]
file_count = int(sys.argv[4])
paths = sys.argv[5 : 5 + file_count]
explicit_mode = bool(paths)


def strip_frontmatter(text):
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return text
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            blanked = []
            for line in lines[: index + 1]:
                content = line.rstrip("\r\n")
                blanked.append(line[len(content) :])
            return "".join(blanked + lines[index + 1 :])
    return text


def container_parts(line):
    match = CONTAINER_PREFIX.match(line)
    return match.group("quotes").count(">"), match.group("rest")


def indentation_width(text):
    column = 0
    for character in text:
        if character == "\t":
            column += 4 - column % 4
        else:
            column += 1
    return column


def leading_indentation_width(text):
    prefix = text[: len(text) - len(text.lstrip(" \t"))]
    return indentation_width(prefix)


def list_item_indent(line):
    quote_depth, rest = container_parts(line)
    match = LIST_PREFIX.match(rest)
    if not match:
        return None
    prefix = match.group("indent") + match.group("marker") + match.group("spacing")
    return quote_depth, indentation_width(prefix)


def consume_indentation(text, width):
    column = 0
    index = 0
    while index < len(text) and text[index] in " \t" and column < width:
        if text[index] == "\t":
            column += 4 - column % 4
        else:
            column += 1
        index += 1
    if column < width:
        return None
    return " " * (column - width) + text[index:]


def fence_match(rest):
    match = FENCE_OPEN.match(rest)
    if not match:
        return None
    fence = match.group("fence")
    if fence[0] == "`" and "`" in match.group("info"):
        return None
    return match, fence


def fence_opener(line, active_quote_depth=None, active_list_indent=None):
    quote_depth, rest = container_parts(line)
    matched = fence_match(rest)
    if matched:
        match, fence = matched
        list_indent = None
        if match.group("list"):
            list_indent = indentation_width(
                match.group("indent")
                + match.group("list")
                + match.group("spacing")
            )
        return fence, quote_depth, list_indent

    if (
        active_list_indent is None
        or quote_depth != active_quote_depth
        or leading_indentation_width(rest) < active_list_indent
    ):
        return None
    continuation = consume_indentation(rest, active_list_indent)
    matched = fence_match(continuation)
    if not matched:
        return None
    _, fence = matched
    return fence, quote_depth, active_list_indent


def fence_closer(line, quote_depth, list_indent):
    candidate_depth, rest = container_parts(line)
    if candidate_depth != quote_depth:
        return None
    match = FENCE_CLOSE.match(rest)
    if not match:
        return None
    indent = indentation_width(match.group("indent"))
    if list_indent is None and indent > 3:
        return None
    if list_indent is not None and not list_indent <= indent <= list_indent + 3:
        return None
    return match.group("fence")


def is_escaped(line, position):
    before = position - 1
    backslashes = 0
    while before >= 0 and line[before] == "\\":
        backslashes += 1
        before -= 1
    return backslashes % 2 == 1


def code_delimiter(line, start):
    if is_escaped(line, start):
        return None
    run_end = start + 1
    while run_end < len(line) and line[run_end] == "`":
        run_end += 1
    return line[start:run_end]


def find_code_span_close(line, delimiter, start):
    close = start
    while True:
        close = line.find(delimiter, close)
        if close == -1:
            return None
        before_is_tick = close > 0 and line[close - 1] == "`"
        after = close + len(delimiter)
        after_is_tick = after < len(line) and line[after] == "`"
        if not before_is_tick and not after_is_tick:
            return after
        close = after


def code_span_end(line, start):
    delimiter = code_delimiter(line, start)
    if delimiter is None:
        return None
    return find_code_span_close(line, delimiter, start + len(delimiter))


def starts_inline_block_boundary(line, quote_depth):
    candidate_depth, rest = container_parts(line)
    if candidate_depth != quote_depth:
        return True
    if fence_opener(line) or HEADING.match(rest) or LIST_PREFIX.match(rest):
        return True
    return rest.lstrip(" ").startswith("<!--")


def has_future_code_span_close(lines, line_index, delimiter, quote_depth):
    for raw_line in lines[line_index + 1 :]:
        line = raw_line.rstrip("\r\n")
        if not line.strip():
            return False
        if starts_inline_block_boundary(line, quote_depth):
            return False
        if find_code_span_close(line, delimiter, 0) is not None:
            return True
    return False


def fence_container_ended(line, quote_depth, list_indent):
    candidate_depth, rest = container_parts(line)
    if candidate_depth < quote_depth:
        return True
    if candidate_depth != quote_depth or list_indent is None or not rest.strip():
        return False
    indent = leading_indentation_width(rest)
    return indent < list_indent


def strip_nonprose(text, preserve_allow_markers=False):
    lines = text.splitlines(keepends=True)
    kept = []
    fence_char = None
    fence_length = 0
    fence_quote_depth = 0
    fence_list_indent = None
    in_comment = False
    inline_delimiter = None
    active_list_quote_depth = None
    active_list_indent = None
    for line_index, raw_line in enumerate(lines):
        line = raw_line.rstrip("\r\n")
        line_ending = raw_line[len(line) :]

        if fence_char is not None:
            if fence_container_ended(line, fence_quote_depth, fence_list_indent):
                fence_char = None
                fence_length = 0
                fence_quote_depth = 0
                fence_list_indent = None
            else:
                fence = fence_closer(line, fence_quote_depth, fence_list_indent)
                if (
                    fence
                    and fence[0] == fence_char
                    and len(fence) >= fence_length
                ):
                    fence_char = None
                    fence_length = 0
                    fence_quote_depth = 0
                    fence_list_indent = None
                kept.append(line_ending)
                continue

        visible = []
        cursor = 0
        if inline_delimiter is not None:
            end = find_code_span_close(line, inline_delimiter, 0)
            if end is None:
                kept.append(line_ending if preserve_allow_markers else raw_line)
                continue
            visible.append(line[:end])
            cursor = end
            inline_delimiter = None

        if (
            preserve_allow_markers
            and not in_comment
            and cursor == 0
            and (ALLOW_START.match(line) or ALLOW_END.match(line))
        ):
            kept.append(raw_line)
            continue

        if cursor == 0 and not in_comment:
            item = list_item_indent(line)
            quote_depth, rest = container_parts(line)
            if item:
                active_list_quote_depth, active_list_indent = item
            elif (
                active_list_indent is not None
                and rest.strip()
                and (
                    quote_depth != active_list_quote_depth
                    or leading_indentation_width(rest) < active_list_indent
                )
            ):
                active_list_quote_depth = None
                active_list_indent = None

            opener = fence_opener(
                line, active_list_quote_depth, active_list_indent
            )
            if opener:
                fence, fence_quote_depth, fence_list_indent = opener
                if (
                    fence_list_indent is None
                    and active_list_indent is not None
                    and fence_quote_depth == active_list_quote_depth
                    and leading_indentation_width(rest) >= active_list_indent
                ):
                    fence_list_indent = active_list_indent
                fence_char = fence[0]
                fence_length = len(fence)
                kept.append(raw_line if preserve_allow_markers else line_ending)
                continue

        while cursor < len(line):
            if in_comment:
                end = line.find("-->", cursor)
                if end == -1:
                    cursor = len(line)
                    continue
                in_comment = False
                cursor = end + 3
                continue

            if line.startswith("<!--", cursor) and not is_escaped(line, cursor):
                visible.append(" excluded " if preserve_allow_markers else " ")
                in_comment = True
                cursor += 4
                continue

            if line[cursor] == "`":
                delimiter = code_delimiter(line, cursor)
                if delimiter is not None:
                    end = find_code_span_close(
                        line, delimiter, cursor + len(delimiter)
                    )
                    if end is not None:
                        visible.append(line[cursor:end])
                        cursor = end
                        continue
                    quote_depth, _ = container_parts(line)
                    if has_future_code_span_close(
                        lines, line_index, delimiter, quote_depth
                    ):
                        visible.append(line[cursor:])
                        inline_delimiter = delimiter
                        cursor = len(line)
                        continue

            visible.append(line[cursor])
            cursor += 1

        kept.append("".join(visible) + line_ending)
    return "".join(kept)


def table_parts(line):
    cells = [[]]
    separators = 0
    cursor = 0
    while cursor < len(line):
        if line[cursor] == "`":
            end = code_span_end(line, cursor)
            if end is not None:
                cells[-1].append(line[cursor:end])
                cursor = end
                continue
        if line[cursor] == "|" and not is_escaped(line, cursor):
            cells.append([])
            separators += 1
            cursor += 1
            continue
        cells[-1].append(line[cursor])
        cursor += 1

    parts = ["".join(cell).strip() for cell in cells]
    if parts and not parts[0]:
        parts.pop(0)
    if parts and not parts[-1]:
        parts.pop()
    return parts, separators


def table_text(line):
    cells, _ = table_parts(line.strip())
    return " ".join(cell for cell in cells if not TABLE_DELIMITER.match(cell))


def table_line_indexes(lines):
    indexes = set()
    for index, line in enumerate(lines):
        cells, separators = table_parts(line.strip())
        if not separators or index == 0:
            continue
        if not cells or not all(TABLE_DELIMITER.match(cell) for cell in cells):
            continue
        _, header_separators = table_parts(lines[index - 1].strip())
        if not header_separators:
            continue
        indexes.update((index - 1, index))
        following = index + 1
        while following < len(lines):
            _, row_separators = table_parts(lines[following].strip())
            if not row_separators:
                break
            indexes.add(following)
            following += 1
    return indexes


def make_unit(pieces):
    text_parts = []
    segments = []
    cursor = 0
    for line_number, piece in pieces:
        piece = piece.strip()
        if not piece:
            continue
        if text_parts:
            cursor += 1
        start = cursor
        text_parts.append(piece)
        cursor += len(piece)
        segments.append((start, cursor, line_number))
    if not text_parts:
        return None
    return {
        "text": " ".join(text_parts),
        "start": segments[0][2],
        "end": segments[-1][2],
        "segments": segments,
    }


def split_units(text):
    units = []
    current = []
    current_kind = None
    lines = [container_parts(line)[1] for line in text.splitlines()]
    table_lines = table_line_indexes(lines)

    def flush():
        nonlocal current, current_kind
        unit = make_unit(current)
        if unit:
            units.append(unit)
        current = []
        current_kind = None

    for index, line in enumerate(lines):
        line_number = index + 1
        stripped = line.strip()
        if not stripped:
            flush()
            continue

        match = HEADING.match(line)
        if match:
            flush()
            heading = re.sub(
                r"[ \t]+#+[ \t]*$", "", (match.group("text") or "").strip()
            )
            if heading:
                units.append(make_unit([(line_number, heading)]))
            continue

        if SETEXT_HEADING.match(line):
            flush()
            continue

        match = LIST_ITEM.match(line)
        if match:
            flush()
            current = [(line_number, match.group("text").strip())]
            current_kind = "list"
            continue

        if index in table_lines:
            flush()
            row = table_text(stripped)
            if row:
                units.append(make_unit([(line_number, row)]))
            continue

        if current_kind != "list" and current_kind != "paragraph":
            current_kind = "paragraph"
        current.append((line_number, stripped))

    flush()
    return units


def read_path(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeError) as err:
        print("readability: %s" % err, file=sys.stderr)
        sys.exit(2)


def units_for_text(text):
    text = strip_frontmatter(text)
    text = strip_nonprose(text)
    return split_units(text)


def sentence_ranges(unit):
    text = unit["text"]
    spans = []
    start = 0
    for match in SENTENCE_END.finditer(text):
        spans.append((start, match.start()))
        start = match.end()
    spans.append((start, len(text)))

    sentences = []
    for start, end in spans:
        while start < end and text[start].isspace():
            start += 1
        while end > start and text[end - 1].isspace():
            end -= 1
        if start == end:
            continue
        start_line = None
        end_line = None
        for segment_start, segment_end, line_number in unit["segments"]:
            if segment_start <= start < segment_end:
                start_line = line_number
            if segment_start <= end - 1 < segment_end:
                end_line = line_number
        if start_line is None or end_line is None:
            print("readability: cannot map sentence to source lines", file=sys.stderr)
            sys.exit(2)
        sentences.append(
            {
                "text": text[start:end],
                "start": start_line,
                "end": end_line,
            }
        )
    return sentences


def lengths_for_text(text):
    units = units_for_text(text)
    unit_lengths = [len(unit["text"].split()) for unit in units]
    sentence_lengths = []
    for unit in units:
        sentence_lengths.extend(
            len(sentence["text"].split()) for sentence in sentence_ranges(unit)
        )
    return unit_lengths, sentence_lengths


def lengths_for(path):
    return lengths_for_text(read_path(path))


def repo_relative(path):
    return os.path.relpath(os.path.abspath(path), repo_root)


def in_default_gate_scope(path):
    normalized = os.path.normpath(path).replace(os.sep, "/")
    return normalized.endswith(".md") and not (
        normalized.startswith("devlog/")
        or normalized.startswith(".claude/")
    )


def parse_diff():
    result = subprocess.run(
        [
            "git",
            "-c",
            "core.quotePath=false",
            "diff",
            "--no-ext-diff",
            "--no-color",
            "-M",
            "-U0",
            merge_base,
            "--",
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print("readability: %s" % result.stderr.strip(), file=sys.stderr)
        sys.exit(2)
    entries = []
    current = None
    for line in result.stdout.splitlines():
        if line.startswith("diff --git "):
            if current is not None:
                entries.append(current)
            current = {"before": None, "after": None, "ranges": []}
            continue
        if current is None:
            continue
        if line.startswith("rename from "):
            current["before"] = line[len("rename from ") :]
            continue
        if line.startswith("rename to "):
            current["after"] = line[len("rename to ") :]
            continue
        if line.startswith("--- "):
            source = line[4:]
            current["before"] = None if source == "/dev/null" else source[2:]
            continue
        if line.startswith("+++ "):
            destination = line[4:]
            current["after"] = (
                None if destination == "/dev/null" else destination[2:]
            )
            continue
        match = HUNK_HEADER.match(line)
        if not match:
            continue
        count = int(match.group("count") or "1")
        if count:
            start = int(match.group("start"))
            current["ranges"].append((start, start + count - 1))
    if current is not None:
        entries.append(current)
    if explicit_mode:
        selected = {os.path.normpath(repo_relative(path)) for path in paths}
        return [
            entry
            for entry in entries
            if os.path.normpath(entry["after"] or entry["before"] or "")
            in selected
        ]
    return [
        entry
        for entry in entries
        if in_default_gate_scope(entry["after"] or entry["before"] or "")
    ]


def intersects(start, end, ranges):
    return any(start <= range_end and range_start <= end for range_start, range_end in ranges)


def allowed_ranges(text):
    lines = text.splitlines()
    ranges = []
    start = None
    for index, line in enumerate(lines):
        line_number = index + 1
        if ALLOW_START.match(line):
            if start is None:
                start = line_number
            continue
        if not ALLOW_END.match(line) or start is None:
            continue
        ranges.append((start, line_number))
        start = None
    if start is not None:
        ranges.append((start, len(lines)))
    return ranges


def text_at_base(path):
    if path is None:
        return None
    blob = subprocess.run(
        ["git", "show", "%s:%s" % (merge_base, path)],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if blob.returncode != 0:
        return None
    return blob.stdout


def words_at_base(path):
    text = text_at_base(path)
    if text is None:
        return 0
    unit_lengths, _ = lengths_for_text(text)
    return sum(unit_lengths)


def words_now(path):
    if path is None:
        return 0
    absolute = os.path.join(repo_root, path)
    if not os.path.exists(absolute):
        return 0
    unit_lengths, _ = lengths_for(absolute)
    return sum(unit_lengths)


def format_median(lengths):
    if not lengths:
        return "0"
    value = statistics.median(lengths)
    return str(int(value)) if value == int(value) else "%.1f" % value


if gate_mode:
    entries = parse_diff()
    print("| File | Words before | Words after | Delta |")
    print("| --- | ---: | ---: | ---: |")
    for entry in sorted(entries, key=lambda item: item["after"] or item["before"]):
        display_path = entry["after"] or entry["before"]
        before = words_at_base(entry["before"])
        after = words_now(entry["after"])
        print(
            "| %s | %d | %d | %+d |"
            % (display_path, before, after, after - before)
        )

    violations = []
    for entry in sorted(entries, key=lambda item: item["after"] or ""):
        relative = entry["after"]
        ranges = entry["ranges"]
        if relative is None or not ranges:
            continue
        path = os.path.join(repo_root, relative)
        if not os.path.isfile(path):
            continue
        raw_text = read_path(path)
        marker_text = strip_nonprose(
            strip_frontmatter(raw_text), preserve_allow_markers=True
        )
        exempt = allowed_ranges(marker_text)
        for unit in units_for_text(raw_text):
            if not intersects(unit["start"], unit["end"], ranges):
                continue
            if intersects(unit["start"], unit["end"], exempt):
                continue
            unit_words = len(unit["text"].split())
            if unit_words > 120:
                violations.append(
                    (
                        relative,
                        unit["start"],
                        "paragraph of %d words (limit 120)" % unit_words,
                    )
                )
            for sentence in sentence_ranges(unit):
                if not intersects(sentence["start"], sentence["end"], ranges):
                    continue
                sentence_words = len(sentence["text"].split())
                if sentence_words > 40:
                    violations.append(
                        (
                            relative,
                            sentence["start"],
                            "sentence of %d words (limit 40)" % sentence_words,
                        )
                    )

    for path, line_number, message in sorted(violations):
        print("%s:%d: %s" % (path, line_number, message))
    sys.exit(1 if violations else 0)

rows = []
all_units = []
all_sentences = []
for path in sorted(paths):
    units, sentences = lengths_for(path)
    all_units.extend(units)
    all_sentences.extend(sentences)
    rows.append(
        (
            path,
            sum(units),
            format_median(sentences),
            max(sentences, default=0),
            sum(length > 40 for length in sentences),
            max(units, default=0),
        )
    )

print(
    "| File | Words | Median sentence | Max sentence | "
    "Sentences >40 | Max paragraph |"
)
print("| --- | ---: | ---: | ---: | ---: | ---: |")
for row in rows:
    print("| %s | %d | %s | %d | %d | %d |" % row)
print(
    "| TOTAL | %d | %s | %d | %d | %d |"
    % (
        sum(all_units),
        format_median(all_sentences),
        max(all_sentences, default=0),
        sum(length > 40 for length in all_sentences),
        max(all_units, default=0),
    )
)
PY
