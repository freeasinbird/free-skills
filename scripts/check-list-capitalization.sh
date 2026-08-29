#!/usr/bin/env bash
# Flag Markdown list items whose first word starts with a lowercase letter.
#
# Usage: check-list-capitalization.sh [file ...]
#   With no arguments, scans tracked and untracked-unignored *.md files,
#   excluding devlog/ (merged entries are frozen by protocol) and .claude/
#   (session-local worktree copies, not project prose).
#
# Fenced code blocks are skipped. Items whose first character is not a
# lowercase letter, including code-span-, link-, and digit-led items, are
# outside this check. Exact locked strings may be listed in
# scripts/list-capitalization-allow.txt.
# This lexical, fence-aware check uses that exact-item-text allowlist as the
# escape hatch for occasional false positives.
#
# Exit codes: 0 clean, 1 findings, 2 usage/environment error.
set -euo pipefail

# Resolve caller-relative arguments before moving: the paths belong to the
# directory the check was invoked from, and reading them after the cd would
# silently scan this repository's like-named files instead.
files=()
for arg in "$@"; do
  case "$arg" in
    /*) files+=("$arg") ;;
    *) files+=("$PWD/$arg") ;;
  esac
done
cd "$(dirname "$0")/.."

if [ "${#files[@]}" -eq 0 ]; then
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(git ls-files -z --cached --others --exclude-standard -- \
    '*.md' ':!devlog' ':!.claude')
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "list capitalization: no markdown files to scan"
  exit 0
fi

python3 - "${files[@]}" <<'PY'
import re
import sys


ALLOWLIST_PATH = "scripts/list-capitalization-allow.txt"
CONTAINER_PREFIX = re.compile(r"^(?P<quotes>(?: {0,3}>[ \t]?)*)(?P<rest>.*)$")
FENCE_OPEN = re.compile(
    r"^(?P<indent> {0,3})"
    r"(?:(?P<list>[-+*]|\d+[.)])(?P<spacing>[ \t]{1,4}))?"
    r"(?P<fence>`{3,}|~{3,})(?P<info>.*)$"
)
FENCE_CLOSE = re.compile(r"^(?P<indent>[ \t]*)(?P<fence>`{3,}|~{3,})[ \t]*$")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(\S)(.*)$")
LIST_PREFIX = re.compile(
    r"^(?P<indent> {0,3})(?P<marker>[-+*]|\d+[.)])"
    r"(?P<spacing>[ \t]{1,4})(?P<text>.*)$"
)


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


def fence_opener(
    line,
    active_quote_depth=None,
    active_list_indent=None,
):
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
    match, fence = matched
    list_indent = active_list_indent
    if match.group("list"):
        list_indent += indentation_width(
            match.group("indent")
            + match.group("list")
            + match.group("spacing")
        )
    return fence, quote_depth, list_indent


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


def fence_container_ended(line, quote_depth, list_indent):
    candidate_depth, rest = container_parts(line)
    if candidate_depth < quote_depth:
        return True
    if candidate_depth != quote_depth or list_indent is None or not rest.strip():
        return False
    return leading_indentation_width(rest) < list_indent


try:
    with open(ALLOWLIST_PATH, encoding="utf-8") as allowlist_file:
        allowed = {
            line.rstrip()
            for line in allowlist_file
            if line.strip() and not line.lstrip().startswith("#")
        }
except OSError as err:
    print("list capitalization: %s" % err, file=sys.stderr)
    sys.exit(2)


findings = 0
for path in sys.argv[1:]:
    try:
        markdown_file = open(path, encoding="utf-8")
    except OSError as err:
        print("list capitalization: %s" % err, file=sys.stderr)
        sys.exit(2)

    fence_character = None
    fence_length = 0
    fence_quote_depth = 0
    fence_list_indent = None
    active_list_quote_depth = None
    active_list_indent = None
    with markdown_file:
        for lineno, raw_line in enumerate(markdown_file, 1):
            line = raw_line.rstrip("\r\n").expandtabs(4)
            if fence_character is not None:
                if fence_container_ended(
                    line, fence_quote_depth, fence_list_indent
                ):
                    fence_character = None
                    fence_length = 0
                    fence_quote_depth = 0
                    fence_list_indent = None
                else:
                    fence = fence_closer(
                        line, fence_quote_depth, fence_list_indent
                    )
                    if (
                        fence
                        and fence[0] == fence_character
                        and len(fence) >= fence_length
                    ):
                        fence_character = None
                        fence_length = 0
                        fence_quote_depth = 0
                        fence_list_indent = None
                    continue

            quote_depth, content = container_parts(line)
            item = list_item_indent(line)
            if item:
                active_list_quote_depth, active_list_indent = item
            elif (
                active_list_indent is not None
                and content.strip()
                and (
                    quote_depth != active_list_quote_depth
                    or leading_indentation_width(content) < active_list_indent
                )
            ):
                active_list_quote_depth = None
                active_list_indent = None

            opener = fence_opener(
                line,
                active_list_quote_depth,
                active_list_indent,
            )
            if opener:
                fence, fence_quote_depth, fence_list_indent = opener
                if (
                    fence_list_indent is None
                    and active_list_indent is not None
                    and fence_quote_depth == active_list_quote_depth
                    and leading_indentation_width(content) >= active_list_indent
                ):
                    fence_list_indent = active_list_indent
                fence_character = fence[0]
                fence_length = len(fence)
                continue

            item_match = LIST_ITEM.match(content)
            if item_match:
                first_character = item_match.group(1)
                item_text = (first_character + item_match.group(2)).rstrip()
                if (
                    first_character.isalpha()
                    and first_character.islower()
                    and item_text not in allowed
                ):
                    print(
                        '%s:%d: lowercase list item ("%s")'
                        % (path, lineno, item_text)
                    )
                    findings += 1

scanned = len(sys.argv) - 1
if findings:
    print(
        "list capitalization: %d finding(s), %d file(s) scanned"
        % (findings, scanned)
    )
    sys.exit(1)
print("list capitalization: clean (%d file(s) scanned)" % scanned)
PY
