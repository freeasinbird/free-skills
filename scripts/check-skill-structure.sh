#!/usr/bin/env bash
# Assert the structural conventions of skills/<name>/, the ones AGENTS.md
# states in prose and only a human reading the file has enforced so far.
#
#   frontmatter  SKILL.md opens and closes with ---, its `name` matches the
#                directory, and its `description` is written as a `>-` block
#                scalar (a plain scalar silently fails to load once its text
#                holds a colon-then-space).
#   paragraph    No prose paragraph exceeds 15 lines, the ceiling being one
#                line above the tallest paragraph in the tree once the packed
#                ones were re-presented, so it forbids regrowth rather than
#                re-flagging accepted prose.
#   flags        Every flag a script under the skill parses is mentioned in
#                that skill's markdown, and every flag a fenced example passes
#                to that script is one the script parses. A flag documented
#                only in the script's own header is not documented: the skill
#                prose never points there. Shell (.sh) and JavaScript
#                (.mjs/.js) scripts are read; a skill shipping a script in
#                another language is not covered, since extracting its flags
#                means knowing a third option-parsing idiom.
#   pointers     Every `references/<file>.md` §<slug> pointer resolves to a
#                `## §<slug>` heading in that file, and every such heading is
#                pointed at from somewhere in the skill.
#
# Deliberately conservative: stdlib only, no markdown or YAML parser, and
# every rule biased toward missing a defect rather than inventing one. A
# false finding blocks valid work and costs whoever hits it a debugging pass,
# while a missed one costs a review comment. So the paragraph rule measures
# only unambiguous column-zero prose and abandons any run it is unsure of,
# and the frontmatter rule checks what the convention actually says rather
# than trying to decide whether arbitrary YAML loads.
#
# Usage: check-skill-structure.sh [skills-dir]
#   Defaults to `skills` in the repository root. Pass a directory to check a
#   tree elsewhere (a worktree of an older commit, say); a relative path is
#   resolved against the caller's directory, not this repository.
#
# Output: one `path:line: <rule>: <detail>` finding per line, then a summary.
# Exit codes: 0 clean, 1 findings, 2 usage/environment error.
set -euo pipefail

usage() {
  echo "usage: check-skill-structure.sh [skills-dir]" >&2
  exit 2
}

root=""
for arg in "$@"; do
  case "$arg" in
    # A mistyped flag must not be read as a directory: the comparator's
    # --require_all typo taught that lesson once already.
    -*)
      echo "check-skill-structure.sh: unknown option: $arg" >&2
      usage
      ;;
    *)
      if [ -n "$root" ]; then
        echo "check-skill-structure.sh: unexpected extra argument: $arg" >&2
        usage
      fi
      root="$arg"
      ;;
  esac
done

# Resolve an explicit root before moving: `check-skill-structure.sh skills`
# run from another worktree means that worktree's skills/, and a cd to this
# repository first would silently check this repository's tree instead.
if [ -n "$root" ]; then
  if [ ! -d "$root" ]; then
    echo "check-skill-structure.sh: not a directory: $root" >&2
    exit 2
  fi
  root=$(cd "$root" && pwd)
else
  cd "$(dirname "$0")/.."
  root="skills"
  if [ ! -d "$root" ]; then
    echo "check-skill-structure.sh: not a directory: $root" >&2
    exit 2
  fi
fi

python3 - "$root" <<'PY'
import os
import re
import shlex
import sys

CEILING = 15

root = sys.argv[1]
findings = []
scanned = 0


def add(path, line, rule, detail):
    findings.append((path, line, "%s: %s" % (rule, detail)))


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})(.*)$")


def scan(lines):
    """One pass over a file: which lines are code, and what a reader sees.

    Fenced blocks and HTML comments each hide the other's markers, so they are
    tracked together and whichever opened first wins. Tracking them separately
    let a fence marker inside a comment leave that comment open, hiding live
    content after it, and a comment marker inside a fenced sample pair with
    another sample, hiding the content between them.

    An opener takes at most three spaces of indentation, since four makes it
    an indented code line. Over-counting fenced lines is not the harmless
    direction it looks like: it hides headings from the pointer rule, which
    then reports a live section as missing.

    Returns (code_lines, visible_lines, blocks): the 1-based line numbers
    inside a fenced block, the lines with comment spans blanked, and one
    (first-content-line, info-string, content-lines) triple per fenced block. Blanking rather
    than deleting keeps every line number intact. A comment with no `-->`
    hides everything after it, so a flag or pointer left in an unfinished note
    documents nothing.
    """

    def blank(chunk):
        return "".join("\n" if ch == "\n" else " " for ch in chunk)

    code = set()
    out = []
    blocks = []
    open_block = None
    in_comment = False
    marker = None
    for lineno, line in enumerate(lines, 1):
        if marker is not None:
            # Inside a fence, comment markers are sample text.
            code.add(lineno)
            out.append(line)
            m = FENCE.match(line.rstrip("\n"))
            if (
                m
                and len(m.group(1)) < 4
                and m.group(2)[0] == marker[0]
                and len(m.group(2)) >= len(marker)
                and not m.group(3).strip()
            ):
                marker = None
                blocks.append(open_block)
                open_block = None
            elif open_block is not None:
                open_block[2].append(line.rstrip("\n"))
            continue
        pieces = []
        pos = 0
        indented_line = line[:4] == "    "
        while pos < len(line):
            if in_comment:
                found = line.find("-->", pos)
                stop = len(line) if found < 0 else found + 3
                pieces.append(blank(line[pos:stop]))
                in_comment = found < 0
                pos = stop
            else:
                begin = line.find("<!--", pos)
                # An opener on a line indented four or more spaces is sample
                # text in an indented code block, not a comment: treating it
                # as one blanked the rest of the file and hid live content.
                # The cost is that a genuinely indented comment stays
                # visible, which can only under-report. Indentation is the
                # line's, not the opener's column: an inline comment after
                # prose sits far to the right and is still a comment.
                if begin < 0 or indented_line:
                    pieces.append(line[pos:])
                    pos = len(line)
                else:
                    pieces.append(line[pos:begin])
                    pos = begin
                    in_comment = True
        shown = "".join(pieces)
        out.append(shown)
        # A fence opens on visible text only, and a backtick fence's info
        # string may not contain a backtick.
        m = FENCE.match(shown.rstrip("\n"))
        if (
            m
            and len(m.group(1)) < 4
            and not (m.group(2)[0] == "`" and "`" in m.group(3))
        ):
            marker = m.group(2)
            code.add(lineno)
            open_block = [lineno + 1, m.group(3).strip(), []]
    if open_block is not None:
        blocks.append(open_block)
    return code, out, blocks


def visible(text):
    """The text a reader sees, comment spans blanked."""
    return "".join(scan(text.splitlines(True))[1])


def fenced(lines):
    """1-based line numbers inside a fenced block."""
    return scan(lines)[0]


# Fence languages whose content is a command line. An unlabelled fence counts;
# a labelled one that is not a shell means the text is a sample of something
# else, and reading it as an invocation rejects valid documentation.
# A session transcript prefixes its commands with a prompt.
PROMPT = re.compile(r"^\s*[$%>]\s+")
SHELL_FENCES = {"", "sh", "shell", "bash", "zsh", "console", "shell-session", "sh-session", "terminal"}


# --- frontmatter ------------------------------------------------------------

# YAML allows whitespace before the colon and quotes around the key, so
# `name : x`, `'name': x`, and `name: x` are one key; matching only the tight
# form would miss a duplicate whose later value is the one that loads.
SEQUENCE_ITEM = re.compile(r"^-(\s|$)")
KEY = re.compile(r"""^(?:(['"])([A-Za-z0-9_-]+)\1|([A-Za-z0-9_-]+))[ \t]*:(.*)$""")


def scalar(value):
    """A source value with quotes stripped and a trailing comment removed."""
    value = re.split(r"(?:^|\s)#", value, maxsplit=1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        inner = value[1:-1]
        return inner.replace("''", "'") if value[0] == "'" else inner
    return value


def frontmatter_span(lines):
    """(first, last) line numbers of the frontmatter body, or None."""
    if not lines or lines[0].rstrip("\n") != "---":
        return None
    for i, line in enumerate(lines[1:], 2):
        if line.rstrip("\n") == "---":
            return (2, i - 1)
    return None


def check_frontmatter(path, skill, lines):
    if not lines or lines[0].rstrip("\n") != "---":
        add(path, 1, "frontmatter", "file does not open with ---")
        return
    span = frontmatter_span(lines)
    if span is None:
        add(path, 1, "frontmatter", "no closing --- for the frontmatter")
        return
    first, last = span
    # A mapping may sit at any consistent indentation and still load, so the
    # keys are read at the block's own base rather than at column zero.
    base = ""
    for lineno in range(first, last + 1):
        line = lines[lineno - 1].rstrip("\n")
        # A comment may sit at any indentation and says nothing about the
        # mapping's, so the base comes from the first key line. Only spaces
        # count: YAML forbids tabs for indentation, so a tab-indented mapping
        # does not load and must not be blessed by accepting its base.
        if line.strip() and not line.lstrip().startswith("#"):
            indent = line[: len(line) - len(line.lstrip())]
            base = indent if set(indent) <= {" "} else ""
            break
    keys = {}
    for lineno in range(first, last + 1):
        line = lines[lineno - 1].rstrip("\n")
        if base:
            if not line.startswith(base):
                continue
            line = line[len(base) :]
        m = KEY.match(line)
        if not m:
            continue
        key = m.group(2) or m.group(3)
        if key in keys:
            add(path, lineno, "frontmatter", "duplicate key %s" % key)
        keys[key] = (lineno, m.group(4).strip())

    # Every line of the mapping is a key, a comment, blank, or content
    # indented past the mapping. A dedent to the mapping's own indentation
    # that is not a key ends a block scalar with something no loader accepts,
    # and YAML forbids tabs for indentation outright. This completes the
    # frontmatter rules rather than validating YAML at large.
    for lineno in range(first, last + 1):
        line = lines[lineno - 1].rstrip("\n")
        if not line.strip():
            continue
        indent = line[: len(line) - len(line.lstrip())]
        if len(indent) > len(base):
            if set(indent) - {" "}:
                add(path, lineno, "frontmatter", "indented with a tab, which YAML forbids")
            continue
        # A comment may sit at any indentation, including less than the
        # mapping's, so it is recognized before the line is realigned.
        if line.lstrip().startswith("#"):
            continue
        body = line[len(base) :] if line.startswith(base) else line.lstrip()
        # A sequence may sit at the mapping's own indentation: `tags:` followed
        # by `- one` at column zero loads fine, so those items are content.
        if SEQUENCE_ITEM.match(body):
            continue
        if not KEY.match(body):
            add(
                path,
                lineno,
                "frontmatter",
                "line is neither a key, a comment, nor content indented past the mapping",
            )

    if "name" not in keys:
        add(path, first, "frontmatter", "no name key")
    elif scalar(keys["name"][1]) != skill:
        add(
            path,
            keys["name"][0],
            "frontmatter",
            'name "%s" does not match the directory name "%s"'
            % (scalar(keys["name"][1]), skill),
        )
    if "description" not in keys:
        add(path, first, "frontmatter", "no description key")
    else:
        # The rule is about how the value is written, so it reads the source:
        # a `>-` header, with an inline comment after it allowed.
        written = re.split(r"(?:^|\s)#", keys["description"][1], maxsplit=1)[0]
        if written.strip() == ">-":
            # A folded block promises an indented body, so the line after the
            # header has to be one.
            follow = keys["description"][0] + 1
            body = lines[follow - 1].rstrip("\n") if follow <= last else ""
            if len(body) - len(body.lstrip()) <= len(base) and body.strip():
                add(
                    path,
                    follow,
                    "frontmatter",
                    "the description block body is not indented past its key",
                )
        if written.strip() != ">-":
            add(
                path,
                keys["description"][0],
                "frontmatter",
                'description must be a ">-" block scalar, not "%s"'
                % (written.strip() or "<empty>"),
            )


# --- paragraph length -------------------------------------------------------

# A line this rule refuses to measure: indented, or opening a list, heading,
# quote, table, HTML block, fence, directive, setext underline, or thematic
# break. Anything matching abandons the run, so a container is never measured
# and never mismeasured. The markers are written as markdown requires them
# (`- ` not `-`, three backticks not one), since `**bold**` and `` `code` ``
# open plenty of real paragraphs and skipping those would cost real coverage.
NOT_PLAIN = re.compile(
    r"^(?:\s"
    r"|#{1,6}(?:\s|$)"
    r"|[>|<]"
    r"|`{3,}|~{3,}|:{3,}"
    r"|=+\s*$|-{3,}\s*$|\*{3,}\s*$|_{3,}\s*$"
    r"|[-*+]\s"
    r"|[0-9]+[.)]\s"
    r")"
)


def check_paragraphs(path, lines):
    # A comment may hold blank lines, and its hidden text is not prose, so it
    # is blanked with the same helper the flag and pointer rules use.
    lines = visible("".join(lines)).splitlines(True)
    span = frontmatter_span(lines)
    skip_to = span[1] + 1 if span else 0
    inside = fenced(lines)
    run = 0
    start = 0
    # A raw HTML block runs to the next blank line. Its interior is ordinary
    # text that markdown does not render as a paragraph, so measuring it
    # would reject valid documentation markup; skipping to the blank line
    # over-skips at worst.
    in_html = False

    def flush():
        if run > CEILING:
            add(
                path,
                start,
                "paragraph",
                "%d lines exceeds the %d-line ceiling" % (run, CEILING),
            )

    for i, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        if i not in inside:
            if not line.strip():
                in_html = False
            elif line.startswith("<"):
                in_html = True
        if (
            i > skip_to
            and i not in inside
            and not in_html
            and line.strip()
            and not NOT_PLAIN.match(line)
        ):
            if run == 0:
                start = i
            run += 1
            continue
        flush()
        run = 0
    flush()


# --- flag parity ------------------------------------------------------------

CASE_WORD = re.compile(r"\bcase\b")
CASE_IN = re.compile(r"\bin\b")
CASE_CLOSE = re.compile(r"\besac\b")
# A case label, whatever it holds: alternatives may be quoted, may be short
# aliases, and may attach a value (`-h|--help)`, `--output=*)`). The long
# options are extracted from the alternatives rather than the whole label
# having to be long options, since rejecting a mixed label would both miss
# the flags it parses and report a documented example as inventing them.
# A case label opens its line, optionally after the opener's `case ... in`,
# and its text is pattern characters only: no whitespace, `$`, backtick, or
# parenthesis. That rejects body lines, including ones holding a command
# substitution, without needing to know where quotes begin and end.
SH_LABEL = re.compile(
    r"^(?:\s*case\s+\S+\s+in(?=\s)|\s*in(?=\s))?\s*\(?\s*"
    r"([^;$`()\s|]+(?:\s*\|\s*[^;$`()\s|]+)*)\s*$"
)
SH_ALTERNATIVE = re.compile(r"^(--[A-Za-z0-9][A-Za-z0-9_-]*)(?:=.*)?$")
# Only an option-map key or an explicit comparison counts as parsing a flag,
# so a passthrough default sitting in an array literal is not mistaken for
# one the script accepts. Both quote styles are valid JavaScript.
JS_KEY = re.compile(r"""(?:^|[{,(])\s*['"](--[A-Za-z0-9][A-Za-z0-9_-]*)['"]\s*:""")
JS_SWITCH = re.compile(r"""\bcase\s+['"](--[A-Za-z0-9][A-Za-z0-9_-]*)['"]\s*:""")
JS_CMP = re.compile(
    r"""==\s*['"](--[A-Za-z0-9][A-Za-z0-9_-]*)['"]"""
    r"""|['"](--[A-Za-z0-9][A-Za-z0-9_-]*)['"]\s*=="""
)
# JavaScript comments hold plenty of flags that no longer exist.
JS_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
FLAG = re.compile(r"--[A-Za-z0-9][A-Za-z0-9_-]*")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
OPERATORS = {"|", "||", "&", "&&", ";", ";;", "(", ")", "\n"}
# A redirection does not end the command: `./x.sh > log --flag` still passes
# --flag. The operator and its one operand are dropped, the rest stays.
REDIRECTIONS = {"<", ">", ">>", "<<", "<<<"}
# A redirection carrying its operand, with or without a file descriptor
# (`>log`, `2>log`), is not a word of the command.
ATTACHED_REDIRECTION = re.compile(r"^[0-9]*>")
# Command words that stand in front of the real one.
LAUNCHERS = {
    "bash", "env", "exec", "node", "npx", "python", "python3", "sh", "sudo",
    "time", "zsh",
}


JS_STRING = re.compile(r"'[^']*'|\"[^\"]*\"")


def js_uncommented(line):
    """A JavaScript line with its `//` comment removed.

    A `//` inside a string literal is a URL, not a comment, so the quoted
    spans are masked and the comment is located in what is left. Relying on
    whitespace after the slashes was wrong twice: `fallback:// if (...)` and
    `fallback://if (...)` are both comments after an object key, while
    `"http://host"` is neither.

    Escapes and template literals are not modelled; an unbalanced quote just
    leaves the line unmasked, which keeps a comment visible rather than
    hiding code.
    """
    masked = JS_STRING.sub(lambda m: " " * len(m.group(0)), line)
    found = masked.find("//")
    return line if found < 0 else line[:found]


def parsed_flags(path):
    """Map flag -> the first line that parses it.

    Arity is deliberately not tracked. Six review rounds went into deciding
    whether a flag consumes the token after it, from shell arms, JavaScript
    branches, comments, and quoted literals, and every answer needed more of
    the language's semantics than a text scan can hold. The rule instead
    treats every recognized flag as consuming the next token, which is what a
    passthrough option like `--chrome-flag --no-sandbox` needs. The cost is
    one blind spot, pinned in the matrix: an invented flag written directly
    after a boolean flag goes unreported.
    """
    flags = {}
    ext = os.path.splitext(path)[1]
    source = read(path).splitlines()
    in_block_comment = False
    case_depth = 0
    case_pending = False
    for lineno, raw in enumerate(source, 1):
        if ext != ".sh":
            # A flag named only in a comment is not a flag the script parses,
            # and demanding documentation for it would fail valid work.
            if in_block_comment:
                if "*/" not in raw:
                    continue
                raw = raw.split("*/", 1)[1]
                in_block_comment = False
            raw = JS_BLOCK_COMMENT.sub(" ", raw)
            if "/*" in raw:
                raw = raw.split("/*", 1)[0]
                in_block_comment = True
            raw = js_uncommented(raw)
        hits = []
        if ext == ".sh":
            # `case` and its `in` may sit on separate lines, and a comment
            # mentioning either is not an opener.
            code = uncommented(raw)
            if case_pending:
                if CASE_IN.search(code):
                    case_depth += 1
                    case_pending = False
            elif CASE_WORD.search(code):
                if CASE_IN.search(code.split("case", 1)[1]):
                    case_depth += 1
                else:
                    case_pending = True
            # Labels are read before `esac` closes the block, so a whole
            # case statement written on one line still yields its arms.
            in_case = case_depth > 0
            if CASE_CLOSE.search(code):
                case_depth = max(0, case_depth - 1)
            if in_case:
                # Every label on the line, since an arm may share the
                # opener's line (`case "$1" in --secret)`) or follow another
                # arm on one. Each alternative's last word is the pattern, so
                # the `case ... in` prefix falls away on its own.
                # Only the first `)` on the line, so a quoted `;;` or a
                # command substitution later in the arm cannot invent a
                # label. The cost is a second arm written on the same line,
                # which is not read: a missed check, not a false one.
                head, sep, _ = code.partition(")")
                label = SH_LABEL.match(head) if sep else None
                if label:
                    for alternative in label.group(1).split("|"):
                        alt = SH_ALTERNATIVE.match(alternative.strip().strip("'\""))
                        if alt:
                            hits.append(alt.group(1))
        else:
            hits += JS_KEY.findall(raw) + JS_SWITCH.findall(raw)
            hits += [
                flag for pair in JS_CMP.findall(raw) for flag in pair if flag
            ]
        for flag in hits:
            flags.setdefault(flag, lineno)
    return flags


def mentions(text, flag):
    # The boundary has to know every character a flag name may continue with,
    # or `--api` reads as documented by a mention of `--api_key`.
    return re.search(re.escape(flag) + r"(?![A-Za-z0-9_-])", text) is not None


def uncommented(line):
    """A command line with its unquoted `#` comment removed.

    Needed before joining continuations: a backslash inside a comment is
    commented out too, so `cmd # note \\` continues nothing, and joining on
    the raw suffix would swallow the next command whole.
    """
    out = []
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            out.append(ch)
            if ch == "\\" and quote == '"' and i + 1 < len(line):
                out.append(line[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "\\" and i + 1 < len(line):
            out.extend(line[i : i + 2])
            i += 2
            continue
        if ch == "#" and (not out or out[-1].isspace()):
            break
        out.append(ch)
        i += 1
    return "".join(out)


def shell_segments(command):
    """Token lists, one per shell segment, split on control operators.

    Lexing comes first and splitting second: a pattern applied to the raw
    text splits inside `"a|b"`, leaving the script in one fragment and its
    flags in another, and the parity check then sees neither.
    """
    # `<` and `>` are left out of the punctuation set: documentation spells
    # its paths with placeholders (`<skill-dir>/x.sh`, `--repo <owner/name>`),
    # and treating those angle brackets as redirections split every such
    # invocation into fragments where the script was never the command word,
    # which silently disabled this rule for the skills that write it that way.
    # Redirections still separate, since a real one is whitespace-delimited.
    lexer = shlex.shlex(command, posix=True, punctuation_chars="();|&")
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        # An unbalanced quote in a snippet: fall back to whitespace splitting
        # rather than losing the command entirely.
        tokens = command.split()
    segments = [[]]
    skip_operand = False
    for token in tokens:
        if skip_operand:
            skip_operand = False
            continue
        if token in REDIRECTIONS:
            skip_operand = True
            continue
        # A redirection may carry its operand (`>/tmp/log`), before the
        # command as easily as after it, and is not a word of the command.
        # A documented placeholder path opens with `<` too, so it is kept.
        if ATTACHED_REDIRECTION.match(token) or (
            token.startswith("<") and ">" not in token
        ):
            continue
        if token in OPERATORS:
            segments.append([])
        else:
            segments[-1].append(token)
    return segments


def names_script(token, spellings):
    """Whether a command-word token refers to this script.

    Three spellings count as the skill's own: a bare basename, a
    placeholder-prefixed path (`<skill-dir>/demo.sh`), and the skill-relative
    path itself with or without a leading `./`. Any other qualified path is
    somebody else's command that happens to share a basename, whether absolute
    (`/opt/tools/demo.sh`) or relative (`../tools/demo.sh`), and attributing
    its flags to the skill would reject a valid example. A qualified path that
    really does point at the skill's own copy is indistinguishable from those,
    so it is skipped: a missed check, not a false one.
    """
    if "/" not in token:
        return token in spellings
    if token.startswith("<"):
        # A documented placeholder prefix (`<skill-dir>/x.sh`) is how every
        # real invocation in this repo spells its path.
        return any(token.endswith("/" + spelling) for spelling in spellings)
    normalized = token[2:] if token.startswith("./") else token
    return normalized in spellings


def script_arguments(tokens, spellings):
    """The tokens a segment passes to the script, or None.

    `cp demo.sh /tmp --preserve` names the script as an argument and owns its
    own flags, so the script has to be the command word. Past a launcher its
    own options are skipped and the script must be the next plain token:
    `env cp demo.sh /tmp` runs `cp`, not the script, and reading cp's flags
    as the script's would fail a valid example. The cost is that a launcher
    option taking a separate value (`env -u NAME ./demo.sh`) hides the
    invocation, which is a missed check rather than a false one.
    """
    i = 0
    while True:
        while i < len(tokens) and ASSIGN.match(tokens[i]):
            i += 1
        if i >= len(tokens):
            return None
        if names_script(tokens[i], spellings):
            return tokens[i + 1 :]
        if os.path.basename(tokens[i]) not in LAUNCHERS:
            # Some other command's word, whether it names the script as an
            # operand (`cp demo.sh /tmp`) or not.
            return None
        # Peel this launcher and its own options, then look again: wrappers
        # nest (`sudo env MODE=test ./demo.sh`).
        i += 1
        while i < len(tokens) and tokens[i].startswith("-"):
            i += 1


def detached(token):
    """A token with any attached redirection suffix removed.

    `--bogus>/tmp/log` passes `--bogus` to the command, but the lexer keeps
    angle brackets inside tokens so documented placeholder paths survive
    (`<skill-dir>/x.sh`), so the split happens here. A token opening with a
    placeholder keeps it; otherwise the first bracket ends the token.
    """
    if token.startswith("<") and ">" in token:
        return token
    for index, char in enumerate(token):
        if char in "<>":
            return token[:index]
    return token


def invented(tokens, flags):
    """Flag-looking tokens a command passes that the script does not parse.

    The token after a recognized flag is treated as that flag's value and is
    never a finding, even when it looks like a flag: `--chrome-flag
    --no-sandbox` passes a Chrome flag through, and reading the value as an
    invented option would forbid documenting a supported invocation. A bare
    `--` ends option parsing by convention, so everything after it is data.
    """
    found = []
    skip = False
    for token in tokens:
        if token == "--":
            break
        if skip:
            skip = False
            continue
        name = detached(token).split("=", 1)[0]
        if not FLAG.fullmatch(name):
            continue
        if name in flags:
            skip = "=" not in token
            continue
        found.append(name)
    return found


def invocations(lines, spellings):
    """(line, arguments) per shell-fence segment that runs the script."""
    found = []
    for first, info, body in scan(lines)[2]:
        language = info.split()[0].lower() if info.split() else ""
        if language not in SHELL_FENCES:
            continue
        # A transcript's unprompted lines are program output, not commands;
        # only a continuation of a prompted command carries on.
        prompted = any(PROMPT.match(line) for line in body)
        pending = None
        for offset, line in enumerate(body):
            lineno = first + offset
            if prompted and pending is None and not PROMPT.match(line):
                continue
            code = uncommented(PROMPT.sub("", line, count=1)).rstrip()
            # Only an odd-length run of trailing backslashes continues the
            # line: an even run is escaped literals, and `./x.sh --ok \\`
            # ends the command rather than swallowing what follows it.
            run = len(code) - len(code.rstrip("\\"))
            continues = run % 2 == 1
            if pending is None:
                pending = [lineno, ""]
            pending[1] += " " + (code[:-1] if continues else code)
            if continues:
                continue
            for segment in shell_segments(pending[1]):
                args = script_arguments(segment, spellings)
                if args is not None:
                    found.append((pending[0], args))
            pending = None
    return found


def check_flags(skill_dir, scripts, md_paths):
    docs = {p: visible(read(p)) for p in md_paths}
    joined = "\n".join(docs.values())
    shared = {}
    for script in scripts:
        shared.setdefault(os.path.basename(script), []).append(script)
    for script in scripts:
        basename = os.path.basename(script)
        # Two scripts in one skill may share a basename, and checking each
        # one's invocations against the other's flags would report both as
        # inventing the other's options. Where that happens, only the
        # skill-relative path identifies the script.
        relative = os.path.relpath(script, skill_dir)
        spellings = [relative] if len(shared[basename]) > 1 else [basename, relative]
        flags = parsed_flags(script)
        for flag, lineno in sorted(flags.items()):
            if not mentions(joined, flag):
                add(
                    script,
                    lineno,
                    "flags",
                    "%s is parsed here but mentioned in no markdown of this "
                    "skill" % flag,
                )
        for path, text in docs.items():
            for lineno, args in invocations(text.splitlines(True), spellings):
                for flag in invented(args, flags):
                    add(
                        path,
                        lineno,
                        "flags",
                        "%s is passed to %s, which does not parse it"
                        % (flag, basename),
                    )


# --- reference pointers -----------------------------------------------------

POINTER = re.compile(r"`references/([A-Za-z0-9._-]+\.md)` §([a-z0-9][a-z0-9-]*)")
SECTION = re.compile(r"^ {0,3}## §([a-z0-9][a-z0-9-]*)\s*$")
LIST_MARKER = re.compile(r"^ {0,3}(?:[-*+]|[0-9]+[.)])\s")
HEADING_LINE = re.compile(r"^ {0,3}#{1,6}\s")


def flattened(lines):
    """Whitespace-collapsed text plus a per-character line number.

    A pointer routinely wraps between the file name and the slug, and a
    line-oriented match would then report its target section as unreferenced.
    Deleting a live section is the cost of that false reading, so matching
    happens on the flattened text. Block boundaries stay as newlines, on both
    of their sides: joining across one would let a file name ending a heading
    or a paragraph pair with an unrelated slug in the next block, and that
    false pointer would mark a genuinely orphaned section as used.
    """
    edges = {
        i
        for i, line in enumerate(lines, 1)
        if not line.strip() or HEADING_LINE.match(line)
    }
    out = []
    where = []
    prev_space = False
    for lineno, line in enumerate(lines, 1):
        if lineno in edges or lineno - 1 in edges:
            if out and out[-1] == " ":
                out[-1] = "\n"
            else:
                out.append("\n")
                where.append(lineno)
            prev_space = True
            if not line.strip():
                continue
        for ch in line + "\n":
            if ch.isspace():
                if prev_space:
                    continue
                out.append(" ")
                where.append(lineno)
                prev_space = True
            else:
                out.append(ch)
                where.append(lineno)
                prev_space = False
    return "".join(out), where


def sections_of(path):
    """{slug: line} for the `## §slug` sections of a file, fences excluded."""
    lines = read(path).splitlines(True)
    inside = fenced(lines)
    found = {}
    for lineno, raw in enumerate(visible("".join(lines)).splitlines(), 1):
        if lineno in inside:
            continue
        m = SECTION.match(raw)
        if m:
            found.setdefault(m.group(1), lineno)
    return found


def check_pointers(skill_dir, md_paths):
    pointed = set()
    for path in md_paths:
        lines = read(path).splitlines(True)
        inside = fenced(lines)
        # An indented code sample holds pointer-shaped text as text. A line
        # indented four spaces counts as code only when a blank line precedes
        # it, since a wrapped pointer inside a list item is indented too and
        # follows prose.
        shown = visible("".join(lines)).splitlines(True)
        readable = []
        previous_blank = True
        in_indented = False
        list_open = False
        for i, line in enumerate(shown):
            body = line.rstrip("\n")
            if body.strip():
                if LIST_MARKER.match(body):
                    list_open = True
                elif not body[:1].isspace():
                    list_open = False
                if body[:4] == "    ":
                    # An indented block opens after a blank line and continues
                    # through every further indented line. Inside an open list
                    # the same indentation is the item's own continuation,
                    # which markdown keeps as prose, pointers included.
                    in_indented = in_indented or (previous_blank and not list_open)
                else:
                    in_indented = False
            readable.append("" if (i + 1 in inside or in_indented) else body)
            previous_blank = not body.strip()
        text, where = flattened(readable)
        for m in POINTER.finditer(text):
            target, slug = m.group(1), m.group(2)
            lineno = where[m.start()]
            pointed.add((target, slug))
            resolved = os.path.join(skill_dir, "references", target)
            if not os.path.isfile(resolved):
                add(path, lineno, "pointers", "references/%s does not exist" % target)
            elif slug not in sections_of(resolved):
                add(
                    path,
                    lineno,
                    "pointers",
                    "references/%s has no `## §%s` heading" % (target, slug),
                )
    refdir = os.path.join(skill_dir, "references")
    for path in sorted(md_paths):
        if os.path.dirname(path) != refdir:
            continue
        target = os.path.basename(path)
        for slug, lineno in sorted(sections_of(path).items(), key=lambda s: s[1]):
            if (target, slug) not in pointed:
                add(
                    path,
                    lineno,
                    "pointers",
                    "§%s is referenced by no pointer in this skill" % slug,
                )


# --- drive ------------------------------------------------------------------

try:
    skills = sorted(
        name for name in os.listdir(root) if os.path.isdir(os.path.join(root, name))
    )
except OSError as err:
    print("check-skill-structure.sh: %s" % err, file=sys.stderr)
    sys.exit(2)

for skill in skills:
    skill_dir = os.path.join(root, skill)
    md_paths = []
    scripts = []
    for dirpath, dirnames, filenames in os.walk(skill_dir):
        dirnames.sort()
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            if name.endswith(".md"):
                md_paths.append(path)
            elif name.endswith((".sh", ".mjs", ".js")):
                scripts.append(path)
    scanned += len(md_paths)

    entry = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(entry):
        add(skill_dir, 1, "frontmatter", "no SKILL.md entry point")
    else:
        check_frontmatter(entry, skill, read(entry).splitlines(True))

    for path in md_paths:
        check_paragraphs(path, read(path).splitlines(True))

    check_flags(skill_dir, scripts, md_paths)
    check_pointers(skill_dir, md_paths)

for path, line, message in sorted(findings, key=lambda f: (f[0], f[1], f[2])):
    print("%s:%d: %s" % (path, line, message))

if findings:
    print("skill structure: %d finding(s), %d file(s) scanned" % (len(findings), scanned))
    sys.exit(1)
print("skill structure: clean (%d file(s) scanned)" % scanned)
PY
