#!/usr/bin/env bash
# Assert the structural invariants of skills/<name>/, the ones AGENTS.md
# states in prose and only a human reading the file has enforced so far.
# Four rule groups, each encoding an existing convention:
#
#   frontmatter  Every skill has a SKILL.md whose YAML frontmatter parses,
#                carries a `name` matching the directory, and writes
#                `description` as a `>-` block scalar (AGENTS.md
#                Conventions: a plain scalar silently fails to load once its
#                text contains a colon-then-space). Validity is PyYAML's
#                answer: an earlier version judged it against a subset it
#                modelled itself, and six review rounds each found another
#                construct that subset certified as clean.
#   paragraph    No prose paragraph exceeds 15 lines. Lists, tables, fenced
#                code, and frontmatter are exempt; the ceiling is one line
#                above the tallest paragraph left after PR #92 re-presented
#                the packed ones, so it forbids regrowth, not today's prose.
#   flags        Every flag a script under the skill parses is mentioned in
#                that skill's markdown, and every flag a fenced example
#                passes to that script is one the script parses. A flag
#                documented only in the script's own header is not
#                documented: the skill prose never points there.
#   pointers     Every `references/<file>.md` §<slug> pointer resolves to a
#                `## §<slug>` heading in that file, and every such heading is
#                pointed at from somewhere in the skill. Pointers are matched
#                across line wraps, since prose routinely splits one between
#                the file name and the slug.
#
# Requires PyYAML (pip install pyyaml); exits 2 without it rather than
# reporting frontmatter clean that it cannot validate.
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


COMMENT_SPAN = re.compile(r"<!--.*?-->", re.DOTALL)


def visible(text):
    """The text a reader sees: HTML comment spans blanked, lines preserved.

    A flag documented only inside `<!-- ... -->`, or a pointer hidden there,
    satisfies nothing: the reader never sees it. Blanking rather than
    deleting keeps every line number intact for the findings.
    """
    return COMMENT_SPAN.sub(
        lambda m: "".join("\n" if ch == "\n" else " " for ch in m.group(0)),
        text,
    )


# --- frontmatter ------------------------------------------------------------

# YAML allows whitespace between a plain key and its colon, so `name : x`
# and `name: x` are the same key: matching only the tight form would let a
# duplicate through, and the loader keeps just one of the two values.
KEY = re.compile(r"""^['"]?([A-Za-z0-9_-]+)['"]?[ \t]*:(.*)$""")


def uncommented(value):
    """A source value with a trailing YAML comment stripped."""
    return re.split(r"(?:^|\s)#", value, maxsplit=1)[0].strip()


def frontmatter_block(lines):
    """Return (start, end) line numbers of the frontmatter body, or None."""
    if not lines or lines[0].rstrip("\n") != "---":
        return None
    for i, line in enumerate(lines[1:], 2):
        if line.rstrip("\n") == "---":
            return (2, i - 1)
    return None


def check_frontmatter(path, skill, lines, yaml_mod):
    """Validity comes from the parser; the conventions come from the source.

    An earlier version judged validity itself, against the syntax subset it
    could model. Six review rounds each found another construct outside that
    subset which it certified as clean (an unindented block body, a flow
    collection, an invalid escape, an out-of-range indentation indicator, a
    dedenting body, a body contradicting an explicit indicator), so the
    subset is gone: a real parser decides whether the block loads, and this
    function only adds what a parser cannot know, namely that `name` matches
    the directory and that `description` is written as a `>-` block scalar.
    """
    if not lines or lines[0].rstrip("\n") != "---":
        add(path, 1, "frontmatter", "file does not open with ---")
        return
    span = frontmatter_block(lines)
    if span is None:
        add(path, 1, "frontmatter", "no closing --- for the frontmatter")
        return
    start, end = span
    try:
        loaded = yaml_mod.safe_load("".join(lines[start - 1 : end]))
    except Exception as err:  # noqa: BLE001 - any parse failure is a finding
        add(
            path,
            start,
            "frontmatter",
            "does not parse as YAML: %s" % " ".join(str(err).split()),
        )
        return
    if not isinstance(loaded, dict):
        add(path, start, "frontmatter", "is not a mapping of keys to values")
        return

    # Source-level keys, for the two rules the loaded value cannot answer:
    # which line to report, whether `description` used a `>-` block scalar,
    # and whether a key was written twice (a loader keeps only the last).
    written = {}
    for lineno in range(start, end + 1):
        m = KEY.match(lines[lineno - 1].rstrip("\n"))
        if not m:
            continue
        if m.group(1) in written:
            add(path, lineno, "frontmatter", "duplicate key %s" % m.group(1))
        written[m.group(1)] = (lineno, m.group(2).strip())

    if "name" not in loaded:
        add(path, start, "frontmatter", "no name key")
    elif str(loaded["name"]) != skill:
        add(
            path,
            written.get("name", (start,))[0],
            "frontmatter",
            'name "%s" does not match the directory name "%s"'
            % (loaded["name"], skill),
        )
    if "description" not in loaded:
        add(path, start, "frontmatter", "no description key")
    else:
        # `description: >- # a comment` is the same block scalar to a loader,
        # so the comparison reads the value with any inline comment removed.
        source = uncommented(written.get("description", (0, ""))[1])
        if source != ">-":
            add(
                path,
                written.get("description", (start,))[0],
                "frontmatter",
                'description must be a ">-" block scalar, not "%s"'
                % (source or "<empty>"),
            )


# --- markdown structure ----------------------------------------------------


def blocks(lines):
    """Line spans from a real markdown parse.

    Returns (fenced, measured, boundaries):

      fenced      1-based line numbers inside a fenced or indented code block
                  or a raw HTML block, the regions whose contents are not
                  markdown and must not be read as headings, pointers, or
                  prose.
      measured    (start, length) per paragraph the ceiling applies to, which
                  is every paragraph not inside a list item (the issue exempts
                  list bodies) but including quoted ones, since a container
                  does not stop its contents being a paragraph.
      boundaries  1-based line numbers where a block ends, so flattening for
                  pointer matching joins wrapped lines without joining across
                  a heading or a paragraph break.

    Eleven review rounds went into approximating this with patterns, and each
    one found another construct the patterns mismodelled (indented fences,
    lazy continuations, setext headings, block quotes, HTML block interiors,
    tables without outer pipes). A parser answers all of them at once, the
    same move the frontmatter rules made after six rounds.
    """
    text = "".join(lines)
    tokens = MarkdownIt("commonmark").enable("table").parse(text)
    fenced = set()
    measured = []
    boundaries = set()
    depth = 0
    for token in tokens:
        if token.type == "list_item_open":
            depth += 1
        elif token.type == "list_item_close":
            depth -= 1
        if not token.map:
            continue
        first, stop = token.map[0] + 1, token.map[1]
        if token.type in ("fence", "code_block", "html_block"):
            fenced.update(range(first, stop + 1))
            boundaries.add(stop)
        elif token.type == "paragraph_open":
            if depth == 0:
                measured.append((first, stop - first + 1))
            boundaries.add(stop)
        elif token.type in ("heading_open", "table_open", "hr", "blockquote_open"):
            boundaries.add(stop)
    return fenced, measured, boundaries


def check_paragraphs(path, lines):
    span = frontmatter_block(lines)
    skip_to = span[1] + 1 if span else 0
    _, measured, _ = blocks(lines)
    for first, length in measured:
        if first > skip_to and length > CEILING:
            add(
                path,
                first,
                "paragraph",
                "%d lines exceeds the %d-line ceiling" % (length, CEILING),
            )


# --- flag parity ------------------------------------------------------------

SH_CASE = re.compile(r"^\s*(--[a-z0-9][a-z0-9-]*(?:\|--[a-z0-9][a-z0-9-]*)*)\)")
# Only an option-map key or an explicit comparison counts as parsing a flag,
# so a Chrome passthrough default sitting in an array literal is not mistaken
# for one the script accepts.
JS_KEY = re.compile(r"^\s*'(--[a-z0-9][a-z0-9-]*)'\s*:")
JS_CMP = re.compile(r"===\s*'(--[a-z0-9][a-z0-9-]*)'")
FLAG = re.compile(r"--[a-z0-9][a-z0-9-]*")


def parsed_flags(path):
    """Map flag -> first line that parses it, for one script."""
    flags = {}
    ext = os.path.splitext(path)[1]
    for lineno, raw in enumerate(read(path).splitlines(), 1):
        hits = []
        if ext == ".sh":
            m = SH_CASE.match(raw)
            if m:
                hits = m.group(1).split("|")
        else:
            m = JS_KEY.match(raw)
            if m:
                hits = [m.group(1)]
            hits += JS_CMP.findall(raw)
        for flag in hits:
            flags.setdefault(flag, lineno)
    return flags


def mentions(text, flag):
    return re.search(re.escape(flag) + r"(?![A-Za-z0-9-])", text) is not None


# Control operators, as the lexer emits them.
OPERATORS = {"|", "||", "&", "&&", ";", ";;", "(", ")", "<", ">", ">>", "\n"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Command words that stand in front of the real one.
LAUNCHERS = {
    "bash",
    "env",
    "exec",
    "node",
    "npx",
    "python",
    "python3",
    "sh",
    "sudo",
    "time",
    "zsh",
}


def uncommented_command(line):
    """A command line with its unquoted `#` comment removed.

    Needed before joining continuations: a backslash inside a comment is
    commented out too, so `cmd # note \\` does not continue anywhere, and
    joining on the raw suffix would swallow the next command whole.
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
            out.append(ch)
            out.append(line[i + 1])
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
    text splits inside `"a|b"`, which leaves the script in one fragment and
    its flags in another, and the parity check then sees neither. The lexer
    also drops a `#` comment and respects quoting.
    """
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        # An unbalanced quote in a documentation snippet: fall back to
        # whitespace splitting rather than losing the command entirely.
        tokens = command.split()
    segments = [[]]
    for token in tokens:
        if token in OPERATORS:
            segments.append([])
        else:
            segments[-1].append(token)
    return segments


def script_arguments(tokens, basename):
    """The tokens a shell segment passes to the script, or None.

    `cp demo.sh /tmp --preserve` mentions the script as an argument, and
    reading its flags as the script's would fail documentation of a perfectly
    good command, so the script has to be the segment's command word (after
    any environment assignments and launchers such as `node` or `bash`).
    A launcher's own options belong to the launcher: only what follows the
    script token is the script's.
    """

    i = 0
    while i < len(tokens) and ASSIGN.match(tokens[i]):
        i += 1
    if i >= len(tokens):
        return None
    if os.path.basename(tokens[i]) == basename:
        return tokens[i + 1 :]
    if os.path.basename(tokens[i]) not in LAUNCHERS:
        # Some other command's word: `cp demo.sh /tmp --preserve` names the
        # script as an argument and owns its own flags.
        return None
    # Past a launcher, options and their values are the launcher's, and their
    # arity is unknowable from here (`env -u NAME`, `node -r mod`), so the
    # script is simply the next token that bears its name.
    for j in range(i + 1, len(tokens)):
        if os.path.basename(tokens[j]) == basename:
            return tokens[j + 1 :]
    return None


def code_blocks(lines):
    """(first-line, [content lines]) per fenced code block.

    Fenced only: the reverse-parity contract is about commands the docs show
    as invocations, and an indented block is prose formatting. Both kinds
    still count as code for the paragraph and pointer rules.
    """
    text = "".join(lines)
    out = []
    for token in MarkdownIt("commonmark").parse(text):
        if token.type == "fence" and token.map:
            out.append((token.map[0] + 1, token.content.splitlines()))
    return out


def invocations(lines, basename):
    """(line, arguments) per code-block shell segment that runs the script.

    Line continuations join into one logical command, which is then split on
    shell operators; each segment is tokenized with shell rules, so a `#`
    comment inside a documented invocation is not read as arguments.
    """
    found = []
    for first, body in code_blocks(lines):
        pending = None
        for offset, line in enumerate(body):
            lineno = first + offset + 1
            code = uncommented_command(line).rstrip()
            if pending is None:
                pending = [lineno, ""]
            pending[1] += " " + code.rstrip("\\")
            if code.endswith("\\"):
                continue
            for segment in shell_segments(pending[1]):
                args = script_arguments(segment, basename)
                if args is not None:
                    found.append((pending[0], args))
            pending = None
    return found


def invented(tokens, flags):
    """Flag-looking tokens in a command that the script does not parse.

    A token right after a recognized flag is that flag's value and is never
    a finding, even when it looks like a flag itself: `--chrome-flag
    --no-sandbox` passes a Chrome flag through, and reading the value as an
    invented option would forbid documenting a supported invocation. The
    cost is one blind spot, a genuinely invented flag written directly after
    another flag, which is the cheaper error of the two.
    """
    found = []
    skip = False
    for token in tokens:
        if skip:
            skip = False
            continue
        name = token.split("=", 1)[0]
        if not FLAG.fullmatch(name):
            continue
        if name in flags:
            # `--flag=value` carries its own value; `--flag value` eats the
            # next token.
            skip = "=" not in token
            continue
        found.append(name)
    return found


def check_flags(skill_dir, scripts, md_paths):
    docs = {p: visible(read(p)) for p in md_paths}
    joined = "\n".join(docs.values())
    for script in scripts:
        basename = os.path.basename(script)
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
            for lineno, args in invocations(text.splitlines(True), basename):
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
HEADING_TEXT = re.compile(r"^§([a-z0-9][a-z0-9-]*)$")


def unfenced(lines):
    """Code blocks and comment spans blanked, line numbering preserved.

    Raw HTML blocks come from the parse; an inline comment after visible
    prose does not, since markdown parses that line as a paragraph, so the
    comment spans are blanked separately.
    """
    fenced, _, _ = blocks(lines)
    kept = [
        "" if i + 1 in fenced else line.rstrip("\n")
        for i, line in enumerate(lines)
    ]
    return visible("\n".join(kept)).split("\n")


def flattened(lines, boundaries=()):
    """Whitespace-collapsed text plus a per-character line number.

    A pointer routinely wraps between the file name and the slug, and a
    line-oriented match would then report its target section as unreferenced.
    Deleting a live section is the cost of that false reading, so matching
    happens on the flattened text.

    Block ends stay as newlines rather than collapsing: joining across one
    would let a file name ending a heading or a paragraph pair with an
    unrelated slug in the next block, and that false pointer would mark a
    genuinely orphaned section as used. The boundaries come from the parse,
    so a heading with no blank line after it separates just as a blank does.
    """
    out = []
    where = []
    prev_space = False
    for lineno, line in enumerate(lines, 1):
        if lineno - 1 in boundaries:
            # A break, not a skip: the line's own text still has to be read.
            # The previous line's newline already collapsed to a space, so
            # promote that space rather than adding a second separator.
            if out and out[-1] == " ":
                out[-1] = "\n"
            else:
                out.append("\n")
                where.append(lineno)
            prev_space = True
        if not line.strip():
            out.append("\n")
            where.append(lineno)
            prev_space = True
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


def headings_of(path):
    """{slug: line} for the real `§slug` headings of a file.

    Taken from the parse, so markdown's own leeway holds: a heading may carry
    up to three spaces of indentation, and one shown inside a fenced example
    is a sample rather than a section.
    """
    found = {}
    tokens = MarkdownIt("commonmark").parse(read(path))
    for i, token in enumerate(tokens):
        if token.type != "heading_open" or not token.map:
            continue
        if token.tag != "h2":
            # The convention is a `## §slug` section; any other level is not
            # one, and resolving a pointer to it would bless a target the
            # contract does not define.
            continue
        inline = tokens[i + 1] if i + 1 < len(tokens) else None
        if inline is None or inline.type != "inline":
            continue
        m = HEADING_TEXT.match(inline.content.strip())
        if m:
            found.setdefault(m.group(1), token.map[0] + 1)
    return found


def check_pointers(skill_dir, md_paths):
    pointed = set()
    for path in md_paths:
        lines = read(path).splitlines(True)
        _, _, boundaries = blocks(lines)
        text, where = flattened(unfenced(lines), boundaries)
        for m in POINTER.finditer(text):
            target, slug = m.group(1), m.group(2)
            lineno = where[m.start()]
            pointed.add((target, slug))
            resolved = os.path.join(skill_dir, "references", target)
            if not os.path.isfile(resolved):
                add(
                    path,
                    lineno,
                    "pointers",
                    "references/%s does not exist" % target,
                )
                continue
            if slug not in headings_of(resolved):
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
        for slug, lineno in sorted(headings_of(path).items(), key=lambda h: h[1]):
            if (target, slug) not in pointed:
                add(
                    path,
                    lineno,
                    "pointers",
                    "§%s is referenced by no pointer in this skill" % slug,
                )


# --- drive ------------------------------------------------------------------

try:
    import yaml as yaml_mod
except ImportError:
    print(
        "check-skill-structure.sh: PyYAML is required to validate SKILL.md "
        "frontmatter; install it (pip install pyyaml) and rerun",
        file=sys.stderr,
    )
    sys.exit(2)

try:
    from markdown_it import MarkdownIt
except ImportError:
    print(
        "check-skill-structure.sh: markdown-it-py is required to find "
        "paragraph and code-block spans; install it "
        "(pip install markdown-it-py) and rerun",
        file=sys.stderr,
    )
    sys.exit(2)

try:
    skills = sorted(
        name
        for name in os.listdir(root)
        if os.path.isdir(os.path.join(root, name))
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
        check_frontmatter(entry, skill, read(entry).splitlines(True), yaml_mod)

    for path in md_paths:
        check_paragraphs(path, read(path).splitlines(True))

    check_flags(skill_dir, scripts, md_paths)
    check_pointers(skill_dir, md_paths)

for path, line, message in sorted(findings, key=lambda f: (f[0], f[1], f[2])):
    print("%s:%d: %s" % (path, line, message))

if findings:
    print(
        "skill structure: %d finding(s), %d file(s) scanned"
        % (len(findings), scanned)
    )
    sys.exit(1)
print("skill structure: clean (%d file(s) scanned)" % scanned)
PY
