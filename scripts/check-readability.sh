#!/usr/bin/env bash
# Report readability density for markdown files.
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
#
# Usage: check-readability.sh [file ...]
#   With no arguments, reports tracked and untracked-unignored *.md files,
#   excluding devlog/ and .claude/. Explicit paths are resolved relative
#   to the caller's directory.
#
# Exit codes: 0 after any report, 2 on a usage or environment error. This
# script is report-only; readability thresholds are not enforced.
set -euo pipefail

# Resolve caller-relative arguments before moving: the paths belong to the
# directory the report was invoked from.
files=()
for arg in "$@"; do
  case "$arg" in
    /*) files+=("$arg") ;;
    *) files+=("$PWD/$arg") ;;
  esac
done
cd "$(dirname "$0")/.."

if ! command -v python3 >/dev/null 2>&1; then
  echo "readability: python3 is required" >&2
  exit 2
fi

if [ "${#files[@]}" -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "readability: default scan requires a git worktree" >&2
    exit 2
  fi
  while IFS= read -r -d '' file; do
    if [ -f "$file" ]; then
      files+=("$file")
    fi
  done < <(git ls-files -z --cached --others --exclude-standard -- \
    '*.md' ':!devlog' ':!.claude')
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "readability: no markdown files to report"
  exit 0
fi

python3 - "${files[@]}" <<'PY'
import re
import statistics
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
SENTENCE_END = re.compile(r"(?<=[.!?])(?:\s+|$)")
TABLE_DELIMITER = re.compile(r"^:?-{3,}:?$")


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


def strip_nonprose(text):
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
                kept.append(raw_line)
                continue
            visible.append(line[:end])
            cursor = end
            inline_delimiter = None

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
                kept.append(line_ending)
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
                visible.append(" ")
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


def split_units(text):
    units = []
    current = []
    current_kind = None
    lines = [container_parts(line)[1] for line in text.splitlines()]
    table_lines = table_line_indexes(lines)

    def flush():
        nonlocal current, current_kind
        unit = " ".join(part for part in current if part).strip()
        if unit:
            units.append(unit)
        current = []
        current_kind = None

    for index, line in enumerate(lines):
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
                units.append(heading)
            continue

        if SETEXT_HEADING.match(line):
            flush()
            continue

        match = LIST_ITEM.match(line)
        if match:
            flush()
            current = [match.group("text").strip()]
            current_kind = "list"
            continue

        if index in table_lines:
            flush()
            row = table_text(stripped)
            if row:
                units.append(row)
            continue

        if current_kind != "list" and current_kind != "paragraph":
            current_kind = "paragraph"
        current.append(stripped)

    flush()
    return units


def lengths_for(path):
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, UnicodeError) as err:
        print("readability: %s" % err, file=sys.stderr)
        sys.exit(2)

    text = strip_frontmatter(text)
    text = strip_nonprose(text)
    units = split_units(text)
    unit_lengths = [len(unit.split()) for unit in units]
    sentence_lengths = []
    for unit in units:
        sentences = [part.strip() for part in SENTENCE_END.split(unit)]
        sentence_lengths.extend(len(part.split()) for part in sentences if part)
    return unit_lengths, sentence_lengths


def format_median(lengths):
    if not lengths:
        return "0"
    value = statistics.median(lengths)
    return str(int(value)) if value == int(value) else "%.1f" % value


rows = []
all_units = []
all_sentences = []
for path in sorted(sys.argv[1:]):
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
