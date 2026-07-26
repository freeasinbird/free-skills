#!/usr/bin/env bash
# Validation matrix for scripts/check-skill-structure.sh.
#
# Each rule the check enforces gets a positive and a negative case, per the
# AGENTS.md "enumerate once as tests" rule: the boundary cases (a 15- vs a
# 16-line paragraph, --clip against --clip-pad, a pointer wrapped across two
# lines) are where a structural check silently stops working.
#
# Exit codes: 0 all cases passed, 1 any failed.
set -u

CHECK="${SKILL_STRUCTURE_CHECK:-$(cd "$(dirname "$0")" && pwd)/check-skill-structure.sh}"
[ -x "$CHECK" ] || {
  echo "not executable: $CHECK" >&2
  exit 1
}

if ! python3 -c 'import yaml, markdown_it' 2>/dev/null; then
  echo "skill-structure matrix: PyYAML and markdown-it-py are required" \
    "(pip install pyyaml markdown-it-py)" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0
fail=0
skip=0

# tree <slug>: fresh skills root holding one valid skill, "demo"; echoes its
# path. The slug names the fixture and must be unique: `tree` runs in a
# command substitution, so a shared counter would not survive the subshell,
# and a reused directory would leak one case's fixture into the next.
tree() {
  root="$work/$1/skills"
  if [ -e "$work/$1" ]; then
    echo "duplicate fixture slug: $1" >&2
    exit 1
  fi
  mkdir -p "$root/demo"
  {
    printf -- '---\n'
    printf 'name: demo\n'
    printf -- 'description: >-\n'
    printf -- '  Demonstrates a thing: usefully, in a description whose text\n'
    printf -- '  holds a colon-then-space that a plain scalar would choke on.\n'
    printf -- '---\n\n'
    printf -- '# Demo\n\nShort prose.\n'
  } >"$root/demo/SKILL.md"
  echo "$root"
}

# lines <file> <line>...: append literal lines.
lines() {
  file="$1"
  shift
  printf '%s\n' "$@" >>"$file"
}

# repeat <file> <count> <text>: append the same line <count> times.
repeat() {
  file="$1" count="$2" text="$3"
  i=0
  while [ "$i" -lt "$count" ]; do
    printf '%s\n' "$text" >>"$file"
    i=$((i + 1))
  done
}

# t <expected-exit> <description> <root> [regex]: run the check on <root>,
# assert the exit code and, when given, that stdout matches (a leading "!"
# inverts the match).
t() {
  expected="$1" desc="$2" root="$3" pattern="${4:-}"
  out=$("$CHECK" "$root" 2>/dev/null)
  status=$?
  ok=1
  [ "$status" = "$expected" ] || ok=0
  # Patterns start with "--" as often as not, so every grep takes -- first.
  if [ -n "$pattern" ]; then
    case "$pattern" in
      '!'*)
        grep -qE -- "${pattern#!}" <<<"$out" && ok=0
        ;;
      *)
        grep -qE -- "$pattern" <<<"$out" || ok=0
        ;;
    esac
  fi
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ($status != $expected): $desc" >&2
    [ -z "$pattern" ] || echo "  pattern: $pattern" >&2
    printf '%s\n' "$out" | sed 's/^/  | /' >&2
  fi
}

# --- frontmatter ------------------------------------------------------------

t 0 'valid frontmatter passes' "$(tree fm-valid)"

# The reason the convention exists: a plain scalar stops parsing at the
# colon-then-space, so the whole file fails to load.
root=$(tree fm-plain)
printf -- '---\nname: demo\ndescription: Does a thing: usefully.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a plain-scalar description with a colon fails to parse' "$root" \
  'does not parse as YAML'

# One without a colon parses, and is still against the convention.
root=$(tree fm-plain-safe)
printf -- '---\nname: demo\ndescription: Does a thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a parse-safe plain-scalar description is still rejected' "$root" \
  'block scalar'

root=$(tree fm-quoted)
printf -- '---\nname: demo\ndescription: "Does a thing."\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'quoted-scalar description rejected' "$root" 'block scalar'

# ">" folds but keeps the trailing newline; the convention is the strip chip.
root=$(tree fm-fold)
printf -- '---\nname: demo\ndescription: >\n  Does a thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'plain ">" description rejected' "$root" 'block scalar'

root=$(tree fm-no-name)
printf -- '---\ndescription: >-\n  Does a thing.\n---\n' >"$root/demo/SKILL.md"
t 1 'missing name rejected' "$root" 'no name key'

root=$(tree fm-name-mismatch)
printf -- '---\nname: other\ndescription: >-\n  Does a thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'name not matching the directory rejected' "$root" 'does not match'

root=$(tree fm-unterminated)
printf -- '---\nname: demo\ndescription: >-\n  Does a thing.\n' \
  >"$root/demo/SKILL.md"
t 1 'unterminated frontmatter rejected' "$root" 'no closing'

root=$(tree fm-no-entry)
rm "$root/demo/SKILL.md"
t 1 'skill directory without SKILL.md rejected' "$root" 'no SKILL.md'

# An adversarial pass over the frontmatter input space. Validity is the
# parser's answer now, so these cases pin two things: that malformed
# frontmatter reaches the parser rather than being swallowed, and that the
# two conventions the parser cannot know (name matches the directory,
# description is a `>-` block scalar) are read from the source.
for spec in \
  'fm-flow-unclosed:extra: [1, 2' \
  'fm-colon-plain:owner: a: b' \
  'fm-unbalanced-quote:owner: "a' \
  'fm-bad-escape:owner: "a\q"' \
  'fm-bad-block-indicator:notes: >10'; do
  root=$(tree "${spec%%:*}")
  printf -- '---\nname: demo\ndescription: >-\n  A thing.\n%s\n---\n' \
    "${spec#*:}" >"$root/demo/SKILL.md"
  t 1 "malformed YAML is rejected: ${spec#*:}" "$root" 'does not parse as YAML'
done

# The round-6 case: a body that contradicts the header's explicit
# indentation indicator. No structural rule modelled this, which is what
# ended the parser-free design.
root=$(tree fm-indicator-mismatch)
printf -- '---\nname: demo\ndescription: >-\n  A thing.\nnotes: >3\n  Two spaces only.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a body contradicting the indentation indicator is rejected' "$root" \
  'does not parse as YAML'

root=$(tree fm-block-dedent)
printf -- '---\nname: demo\ndescription: >-\n  A thing.\n A dedented line.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a block-scalar body that dedents is rejected' "$root" 'does not parse as YAML'

root=$(tree fm-not-mapping)
printf -- '---\n- a list, not a mapping\n---\n' >"$root/demo/SKILL.md"
t 1 'frontmatter that is not a mapping is rejected' "$root" 'not a mapping'

root=$(tree fm-duplicate-key)
printf -- '---\nname: demo\nname: demo\ndescription: >-\n  Does a thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a duplicate key is rejected' "$root" 'duplicate key name'

# YAML allows whitespace before the colon, so the loader sees one key twice
# while a tight-colon scan sees two different lines and neither as a
# duplicate. The loader keeps the last, which is how a wrong name hides.
root=$(tree fm-duplicate-spaced)
printf -- '---\nname : wrong\nname: demo\ndescription: >-\n  Does a thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a duplicate key written with a spaced colon is rejected' "$root" \
  'duplicate key name'

# A comment after the block-scalar header is still that block scalar.
# A quoted key is the same key to a loader, so the source-style lookup has
# to find it or the description rule fires on valid frontmatter.
root=$(tree fm-quoted-description-key)
printf -- "---\nname: demo\n'description': >-\n  A thing.\n---\n" \
  >"$root/demo/SKILL.md"
t 0 'a quoted description key passes' "$root"

root=$(tree fm-commented-description)
printf -- '---\nname: demo\ndescription: >- # folded and stripped\n  A thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'an inline comment after the description header passes' "$root"

# Valid YAML the old subset could not model now simply passes.
for spec in \
  'fm-flow-valid:extra: [1, 2]' \
  'fm-anchor:extra: &a value' \
  'fm-valid-escape:owner: "a\\nb"' \
  'fm-block-indicators:notes: >2' \
  'fm-deeper-body:owner: plain'; do
  root=$(tree "${spec%%:*}")
  printf -- '---\nname: demo\ndescription: >-\n  A thing.\n%s\n  A body.\n---\n' \
    "${spec#*:}" >"$root/demo/SKILL.md" 2>/dev/null
  printf -- '---\nname: demo\ndescription: >-\n  A thing.\n%s\n---\n' \
    "${spec#*:}" >"$root/demo/SKILL.md"
  t 0 "valid YAML passes: ${spec#*:}" "$root"
done

root=$(tree fm-nested-mapping)
printf -- '---\nname: demo\ndescription: >-\n  A thing.\nnested:\n  a: 1\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'a nested mapping passes' "$root"

root=$(tree fm-subset-ok)
printf -- '---\n# A comment is fine.\nname: demo\ndescription: >-\n  A thing.\nowner: "a: b"\nempty:\nnotes: |\n  A literal block.\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'comments, quoted values, empty values, and block scalars pass' "$root"

# The name comparison reads the loaded value, so quoting and an inline
# comment are not a mismatch, while a genuinely different name still is.
root=$(tree fm-quoted-name)
printf -- "---\nname: 'demo'\ndescription: >-\n  A thing.\n---\n" \
  >"$root/demo/SKILL.md"
t 0 'a quoted name matching the directory passes' "$root"

root=$(tree fm-commented-name)
printf -- '---\nname: demo # the directory name\ndescription: >-\n  A thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'an inline comment after the name is not a mismatch' "$root"

root=$(tree fm-quoted-name-wrong)
printf -- "---\nname: 'other'\ndescription: >-\n  A thing.\n---\n" \
  >"$root/demo/SKILL.md"
t 1 'a quoted name not matching the directory is rejected' "$root" 'does not match'

# --- paragraph length -------------------------------------------------------

root=$(tree para-15)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 15 'A line of ordinary prose.'
t 0 'a 15-line paragraph passes' "$root"

root=$(tree para-16)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 16 'A line of ordinary prose.'
t 1 'a 16-line paragraph is a finding' "$root" 'paragraph: 16 lines'

root=$(tree para-list)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 20 '- A bullet, with its own body text.'
t 0 'a 20-bullet list passes' "$root"

root=$(tree para-bullet-body)
lines "$root/demo/SKILL.md" '' '- A bullet that wraps:'
repeat "$root/demo/SKILL.md" 20 '  a continuation line of that bullet.'
t 0 'a 20-line indented bullet body passes' "$root"

root=$(tree para-fence)
lines "$root/demo/SKILL.md" '' '```sh'
repeat "$root/demo/SKILL.md" 20 'echo a line of code'
lines "$root/demo/SKILL.md" '```'
t 0 'a 20-line fenced block passes' "$root"

root=$(tree para-table)
lines "$root/demo/SKILL.md" '' '| Col | Col |' '| --- | --- |'
repeat "$root/demo/SKILL.md" 20 '| a   | b   |'
t 0 'a 20-row table passes' "$root"

# A paragraph that runs to EOF with no trailing blank line still counts.
root=$(tree para-eof)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 15 'A line of ordinary prose.'
printf 'A sixteenth line with no trailing newline.' >>"$root/demo/SKILL.md"
t 1 'a paragraph running to EOF is flushed' "$root" 'paragraph: 16 lines'

# The finding anchors to the paragraph's first line, not the file's.
root=$(tree para-anchor)
lines "$root/demo/SKILL.md" '' '```sh' 'echo hi' '```' ''
repeat "$root/demo/SKILL.md" 16 'A line of ordinary prose.'
t 1 'the finding anchors to the first prose line' "$root" 'SKILL.md:16: paragraph'

# Markdown renders one to three leading spaces as prose, so indentation is
# not an exemption: it would otherwise be an invisible way past the ceiling.
root=$(tree para-indented-prose)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 16 '  An indented line of ordinary prose.'
t 1 'lightly indented prose counts toward the ceiling' "$root" 'paragraph: 16 lines'

# A marker matched too loosely exempts prose. Markdown needs a space (or the
# line's end) after one to six hashes for a heading, and a tag-shaped opener
# for an HTML block, so neither `#hashtag` nor `<3` starts a block.
for lead in '#hashtag prose about a topic.' '<3 is how the sentence starts.' \
  '####### seven hashes are not a heading.'; do
  root=$(tree "para-lookalike-$(printf '%s' "$lead" | tr -cd 'a-z' | cut -c1-8)")
  lines "$root/demo/SKILL.md" ''
  repeat "$root/demo/SKILL.md" 16 "$lead"
  t 1 "a block-marker lookalike counts as prose: $lead" "$root" 'paragraph: 16 lines'
done

# An unindented block marker ends a list without needing a blank line, so
# the indented lines after it are prose, not list body. The paragraph scanner
# and the fence scanner share one implementation of this rule now, after they
# were fixed one at a time and drifted apart.
root=$(tree para-list-ended-by-heading)
lines "$root/demo/SKILL.md" '' '- An item' '# A heading'
repeat "$root/demo/SKILL.md" 16 '  indented prose after the heading'
t 1 'a heading ends the list, so indented prose counts' "$root" \
  'paragraph: 16 lines'

# A leading pipe is not a table: without a delimiter row it is prose.
root=$(tree para-pipe-prose)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 16 '| ordinary prose line'
t 1 'pipe-prefixed lines with no delimiter row count as prose' "$root" \
  'paragraph: 16 lines'

# Tag shape is not an HTML block: `<span>` opens a paragraph, and only the
# block-level tags, a comment, a declaration, or a tag alone on its line
# start a block.
root=$(tree para-inline-html)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 16 '<span>ordinary prose line'
t 1 'a line opening with inline HTML counts as prose' "$root" \
  'paragraph: 16 lines'

# GFM tables need no outer pipes, and a long one must not read as prose.
root=$(tree para-table-no-outer-pipes)
lines "$root/demo/SKILL.md" '' 'Name | Value' '--- | ---'
repeat "$root/demo/SKILL.md" 16 'a | b'
t 0 'a table without outer pipes passes' "$root"

# A block quote does not stop its contents from being a paragraph, so the
# ceiling has to see through the container.
root=$(tree para-blockquote)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 16 '> A quoted line of ordinary prose.'
t 1 'a paragraph inside a block quote counts' "$root" 'paragraph: 16 lines'

# The real markers still break a paragraph.
for lead in '# A heading' '<div>'; do
  root=$(tree "para-marker-$(printf '%s' "$lead" | tr -cd 'a-z' | cut -c1-8)")
  lines "$root/demo/SKILL.md" ''
  repeat "$root/demo/SKILL.md" 16 "$lead"
  t 0 "a real block marker is not prose: $lead" "$root"
done

# Indentation cannot interrupt a paragraph already in progress: four spaces
# under an open paragraph is a lazy continuation, not a code block.
root=$(tree para-indented-continuation)
lines "$root/demo/SKILL.md" '' 'An opening line of prose.'
repeat "$root/demo/SKILL.md" 15 '    a four-space continuation line'
t 1 'indented continuation lines stay in the paragraph' "$root" \
  'paragraph: 16 lines'

# A tag-terminated HTML block ends at its closing tag, not at the next blank
# line, so the prose after it is measured.
root=$(tree para-script-block)
lines "$root/demo/SKILL.md" '' '<script>' 'var x = 1;' '</script>'
repeat "$root/demo/SKILL.md" 16 'a line of ordinary prose'
t 1 'prose after a script block is measured' "$root" 'paragraph: 16 lines'

# A setext heading is a heading, not two prose lines joined to what follows.
root=$(tree para-setext)
lines "$root/demo/SKILL.md" '' 'A setext heading' '================' ''
repeat "$root/demo/SKILL.md" 14 'a line of ordinary prose'
t 0 'a setext heading does not join the paragraph under it' "$root"

# An HTML block runs to the next blank line, so its interior is not prose:
# counting it would reject valid documentation markup.
root=$(tree para-html-block)
lines "$root/demo/SKILL.md" '' '<div>'
repeat "$root/demo/SKILL.md" 15 'raw html content line'
lines "$root/demo/SKILL.md" '</div>'
t 0 'the interior of an HTML block is not prose' "$root"

# Four spaces is an indented code block, not prose.
root=$(tree para-indented-code)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 16 '    echo an indented code line'
t 0 'a 16-line indented code block passes' "$root"

# A lazy continuation (an unindented wrapped line inside a bullet) keeps the
# list block open, so the bullet body that follows is still list content.
# Found by running the new rule against the real tree, where a wrapped `gh
# api` command sits at column 0 inside a bullet.
root=$(tree para-lazy-continuation)
lines "$root/demo/SKILL.md" '' '- A bullet whose command wraps:' \
  '  `gh api' '"repos/owner/name/rules"`, whose output'
repeat "$root/demo/SKILL.md" 16 '  is read one field at a time.'
t 0 'a lazy continuation keeps the list block open' "$root"

# But a blank line then an unindented line does end the list.
root=$(tree para-after-list)
lines "$root/demo/SKILL.md" '' '- A bullet.' ''
repeat "$root/demo/SKILL.md" 16 'A line of prose after the list.'
t 1 'a paragraph after a list is counted' "$root" 'paragraph: 16 lines'

# Frontmatter is not prose: a long description is not a paragraph finding.
root=$(tree para-description)
printf -- '---\nname: demo\ndescription: >-\n' >"$root/demo/SKILL.md"
repeat "$root/demo/SKILL.md" 20 '  A line of the description.'
lines "$root/demo/SKILL.md" '---' '' '# Demo'
t 0 'a 20-line description is not a paragraph finding' "$root"

# --- flag parity ------------------------------------------------------------

# demo_sh <root> <arm>...: a shell script whose case arms parse the arms.
demo_sh() {
  root="$1"
  shift
  {
    printf '#!/usr/bin/env bash\ncase "$1" in\n'
    printf '  %s) ;;\n' "$@"
    printf 'esac\n'
  } >"$root/demo/demo.sh"
}

root=$(tree flags-documented)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr <n>` to name the PR.'
t 0 'a documented parsed flag passes' "$root"

root=$(tree flags-undocumented)
demo_sh "$root" '--pr'
t 1 'an undocumented parsed flag is a finding' "$root" 'demo.sh:3: flags: --pr'

root=$(tree flags-multi-arm)
demo_sh "$root" '--pr|--repo'
lines "$root/demo/SKILL.md" '' 'Pass `--pr <n>` to name the PR.'
t 1 'both halves of a multi-flag arm are checked' "$root" 'flags: --repo'

# Prose anywhere under the skill counts as documentation, references
# included, since the reader following a pointer lands there too.
root=$(tree flags-reference-doc)
demo_sh "$root" '--pr'
mkdir -p "$root/demo/references"
printf -- '# Ref\n\nPass `--pr <n>` to name the PR.\n' \
  >"$root/demo/references/ref.md"
lines "$root/demo/SKILL.md" '' 'See `references/ref.md`.'
t 0 'documentation in a reference file counts' "$root"

# --clip must not be satisfied by a --clip-pad mention: the check matches on
# a right boundary, or a prefix flag can hide an undocumented one.
root=$(tree flags-prefix)
demo_sh "$root" '--clip'
lines "$root/demo/SKILL.md" '' 'Pass `--clip-pad 12` for padding.'
t 1 '--clip-pad does not document --clip' "$root" 'flags: --clip '

root=$(tree flags-prefix-ok)
demo_sh "$root" '--clip' '--clip-pad'
lines "$root/demo/SKILL.md" '' 'Pass `--clip` and `--clip-pad 12`.'
t 0 'both flags documented passes' "$root"

# .mjs: the option map and an explicit comparison both count as parsing.
root=$(tree flags-mjs)
{
  printf 'const keyOf = {\n'
  printf "  '--url': 'url',\n"
  printf '};\n'
  printf "if (opt === '--dark') raw.dark = true;\n"
  printf "const CHROME = ['--disable-gpu', '--mute-audio'];\n"
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--url` and `--dark`.'
t 0 'mjs map key and comparison are parsed flags' "$root"

# A Chrome passthrough default in an array literal is not a flag the script
# accepts, so it must not demand documentation.
t 0 'an array-literal flag is not a parsed flag' "$root" '!disable-gpu'

root=$(tree flags-mjs-undocumented)
{
  printf 'const keyOf = {\n'
  printf "  '--url': 'url',\n"
  printf '};\n'
} >"$root/demo/capture.mjs"
t 1 'an undocumented mjs flag is a finding' "$root" 'capture.mjs:2: flags: --url'

# Reverse direction: a fenced invocation may only pass flags the script parses.
root=$(tree flags-fence-invent)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Run it:' '' '```sh' \
  './demo.sh --pr 46 --bogus' '```'
t 1 'a fenced example may not invent a flag' "$root" '--bogus is passed to demo.sh'

# The invocation is a logical command: a flag on a continuation line counts.
root=$(tree flags-continuation)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' '```sh' './demo.sh --pr 46 \' '  --bogus' '```'
t 1 'a continuation line is part of the invocation' "$root" '--bogus is passed'

# Other commands in the same fence are not the script's business, and neither
# is prose: only fenced commands naming the script are checked in reverse.
root=$(tree flags-foreign)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' '```sh' 'gh pr view --json number,url' \
  './demo.sh --pr 46' '```' '' 'Read it with `gh pr checks --watch`.'
t 0 'foreign commands and prose flags are ignored' "$root"

# A flag-shaped token is a value when it follows a flag the script parses:
# `--chrome-flag --no-sandbox` passes a Chrome flag through, and calling the
# value an invented option would forbid documenting a supported invocation.
root=$(tree flags-passthrough-value)
demo_sh "$root" '--chrome-flag'
lines "$root/demo/SKILL.md" '' 'Pass extra Chrome flags:' '' '```sh' \
  './demo.sh --chrome-flag --no-sandbox' '```'
t 0 'a passthrough value is not read as an invented flag' "$root"

# The --flag=value form carries its own value, so the next token is still
# checked, and an invented flag written that way is still a finding.
root=$(tree flags-equals-form)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' '```sh' './demo.sh --pr=46 --bogus=1' '```'
t 1 'an invented --flag=value is still a finding' "$root" '--bogus is passed'

# Reverse parity applies to the segment that *runs* the script: a command
# that merely names it as an argument owns its own flags.
root=$(tree flags-named-not-run)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`. Copy it first:' '' '```sh' \
  'cp demo.sh /tmp --preserve' '```'
t 0 'a command that merely names the script is not an invocation' "$root"

# A launcher in front of the script still counts as running it.
root=$(tree flags-launcher)
{
  printf 'const keyOf = {\n'
  printf "  '--url': 'url',\n"
  printf '};\n'
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--url`:' '' '```sh' \
  'node capture.mjs --url http://x --bogus' '```'
t 1 'a launcher in front of the script still invokes it' "$root" '--bogus is passed'

# A launcher's own options belong to the launcher, not to the script it
# runs: only the tokens after the script token are the script's.
root=$(tree flags-launcher-option)
{
  printf 'const keyOf = {\n'
  printf "  '--url': 'url',\n"
  printf '};\n'
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--url`:' '' '```sh' \
  'node --no-warnings capture.mjs --url http://x' '```'
t 0 "a launcher's own option is not read as the script's" "$root"

# Segments are split on shell operators, so a neighbouring command in the
# same line keeps its own flags.
root=$(tree flags-pipeline)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  'gh pr view --json number && ./demo.sh --pr 46 | jq --raw-output .x' '```'
t 0 'flags of neighbouring commands in a pipeline are ignored' "$root"

# `&` is a control operator like `|` and `;`: what follows it is another
# command with its own flags.
root=$(tree flags-background)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh --pr 1 & gh pr view --bogus' '```'
t 0 'a backgrounded command does not absorb the next one'"'"'s flags' "$root"

# A launcher option may take a separate value, and its arity is unknowable
# from here, so the script is the next token bearing its name.
root=$(tree flags-launcher-value)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  'env -u OLD ./demo.sh --bogus' '```'
t 1 'a launcher option value does not hide the script' "$root" '--bogus is passed'

# Reverse parity is about fenced invocations; an indented block is prose
# formatting and must not fail otherwise valid documentation.
root=$(tree flags-indented-block)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`. An indented example:' '' \
  '    ./demo.sh --bogus'
t 0 'an indented code block is not an invocation' "$root"

# A backslash inside a comment is commented out too, so the next line is a
# separate command rather than a continuation of this one.
root=$(tree flags-comment-continuation)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh --pr 1 # note \' './demo.sh --bogus' '```'
t 1 'a comment does not continue onto the next command' "$root" '--bogus is passed'

# Documentation a reader cannot see is not documentation.
root=$(tree flags-commented-out)
demo_sh "$root" '--pr|--danger'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`.' '' '<!-- TODO: document --danger -->'
t 1 'a flag mentioned only in an HTML comment is undocumented' "$root" \
  '--danger is parsed here'

# A control operator inside quotes is data. Splitting the raw text before
# lexing put the script in one fragment and its flags in another, so the
# parity check saw neither.
root=$(tree flags-quoted-operator)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh "a|b" --bogus' '```'
t 1 'a quoted operator does not hide an invented flag' "$root" '--bogus is passed'

# A shell comment inside a documented invocation passes no arguments.
root=$(tree flags-shell-comment)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh --pr 1 # --bogus is not passed' '```'
t 0 'a shell comment is not read as arguments' "$root"

# --- reference pointers -----------------------------------------------------

# demo_ref <root> <heading-slug>...: a reference file with those sections.
demo_ref() {
  root="$1"
  shift
  mkdir -p "$root/demo/references"
  {
    printf '# Hazards\n\n'
    printf '## §%s\n\nText.\n\n' "$@"
  } >"$root/demo/references/haz.md"
}

root=$(tree ptr-resolve)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' 'A tag can shadow (`references/haz.md` §tag-shadow).'
t 0 'a resolving pointer passes' "$root"

# The regression fixture: prose wraps at ~76 columns, so a pointer routinely
# splits between the file name and the slug. A line-oriented match would
# report §tag-shadow as unreferenced, and the "fix" for a false unreferenced
# reading is deleting a section that is very much in use.
root=$(tree ptr-wrapped)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' 'A tag can shadow the branch name (`references/haz.md`' \
  '§tag-shadow), so pass the fully qualified ref instead.'
t 0 'a pointer wrapped across two lines still counts' "$root"

root=$(tree ptr-dangling)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §no-such-section).'
t 1 'a dangling slug is a finding' "$root" 'no .## §no-such-section. heading'

root=$(tree ptr-missing-file)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' 'See (`references/gone.md` §tag-shadow).'
t 1 'a missing target file is a finding' "$root" 'references/gone.md does not exist'

root=$(tree ptr-orphan)
demo_ref "$root" 'tag-shadow' 'orphan'
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §tag-shadow).'
t 1 'an unreferenced section is a finding' "$root" '§orphan is referenced by no pointer in this skill'

# Four spaces makes a fence marker an indented code line, not an opener, so
# it must not blank the rest of the file: that would hide real headings from
# the reverse pointer check and real prose from the ceiling.
root=$(tree ptr-indented-fence)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n'
  printf 'An indented code line, not a fence:\n\n    ```\n\n'
  printf '## §orphan\n\nText.\n'
} >"$root/demo/references/haz.md"
t 1 'an indented code marker does not hide the rest of a file' "$root" \
  '§orphan is referenced by no pointer'

# A delimiter indented four spaces past the opener is fenced content, not a
# closer: closing there would expose the sample markdown after it, and a
# pointer at a sample heading would resolve to a section nobody can read.
root=$(tree ptr-overindented-closer)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n## §real\n\nText.\n\n'
  printf '```md\nan example:\n    ```\n## §sample\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real) and' \
  '(`references/haz.md` §sample).'
t 1 'an over-indented delimiter does not close a fence' "$root" \
  'no .## §sample. heading'

# An unindented block marker ends a list even with no blank line before it,
# so the four-space fence after it is indented code again.
root=$(tree ptr-list-ended-by-heading)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n## §real\n\nText.\n\n'
  printf -- '- An item\n# A heading\n\n    ```\n\n## §orphan\n\nText.\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real).'
t 1 'a heading ends the list, so the indented fence stays code' "$root" \
  '§orphan is referenced by no pointer'

# A closer carries no trailing content: with any, the line is fenced
# content, and closing on it would expose the sample after it.
root=$(tree ptr-closer-trailing)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n## §real\n\nText.\n\n'
  printf '```md\nan example:\n``` not a closer\n## §sample\n```\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real) and' \
  '(`references/haz.md` §sample).'
t 1 'a delimiter with trailing content does not close a fence' "$root" \
  'no .## §sample. heading'

# Flattening joins wrapped lines, not paragraphs: a file name ending one
# paragraph must not pair with a slug in the next, or a genuinely orphaned
# section reads as used.
root=$(tree ptr-flatten-boundary)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §orphan\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'Read `references/haz.md`' '' \
  '§orphan is a topic we discuss.'
t 1 'a pointer is not assembled across a blank line' "$root" \
  '§orphan is referenced by no pointer'

# Outside a list the closer limit is absolute: markdown allows a closing
# fence at most three spaces from the margin, whatever the opener's own
# indentation.
root=$(tree ptr-closer-absolute)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n## §real\n\nText.\n\n'
  printf '   ```md\nexample\n    ```\n## §sample\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real) and' \
  '(`references/haz.md` §sample).'
t 1 'a four-space closer does not close a three-space opener' "$root" \
  'no .## §sample. heading'

# A backtick anywhere in a backtick fence's info string means no fence
# opens, so what follows is ordinary markdown rather than hidden content.
root=$(tree ptr-backtick-info)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n```lang`bad\n## §orphan\n\nText.\n' \
  >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'Nothing points at it.'
t 1 'a backtick in the info string opens no fence' "$root" \
  '§orphan is referenced by no pointer'

# A block boundary need not be a blank line: a heading ends one too, so a
# file name closing a heading must not pair with a slug opening the prose
# under it.
root=$(tree ptr-heading-boundary)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §orphan\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' '## See `references/haz.md`' \
  '§orphan is a topic we discuss.'
t 1 'a pointer is not assembled across a heading' "$root" \
  '§orphan is referenced by no pointer'

# A pointer hidden in an inline comment reaches no reader, so it cannot
# keep a section alive. Markdown parses that line as a paragraph, so the
# comment spans are blanked separately from raw HTML blocks.
root=$(tree ptr-inline-comment)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §orphan\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'Text <!-- `references/haz.md` §orphan -->'
t 1 'a pointer inside an inline comment does not count' "$root" \
  '§orphan is referenced by no pointer'

# The convention is a level-two section, so another level is not a target.
root=$(tree ptr-heading-level)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n### §deep\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §deep).'
t 1 'a level-three heading does not resolve a pointer' "$root" \
  'no .## §deep. heading'

# Markdown allows a heading up to three spaces of indentation, and the
# headings come from the parse, so a pointer at one resolves.
root=$(tree ptr-indented-heading)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n   ## §cleanup\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §cleanup).'
t 0 'an indented reference heading resolves a pointer' "$root"

# A fence indented inside a list item is still a fence.
root=$(tree ptr-list-fence)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n## §real\n\nText.\n\n'
  printf -- '- A bullet with an example:\n\n  ```md\n  ## §sample\n  ```\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real).'
t 0 'a fence indented inside a list item still fences' "$root"

# A pointer shown inside a fenced example is a sample, not a consumer.
root=$(tree ptr-fenced)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' '```md' 'See (`references/haz.md` §tag-shadow).' '```'
t 1 'a pointer inside a fence does not count as a reference' "$root" \
  '§tag-shadow is referenced by no pointer in this skill'

# A heading shown inside a fenced example is a sample, not a section, so a
# pointer at it resolves to nothing in the rendered document.
root=$(tree ptr-fenced-heading)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n## §real\n\nText.\n\n'
  printf 'An example section header:\n\n```md\n## §sample\n```\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real) and' \
  '(`references/haz.md` §sample).'
t 1 'a heading inside a fence does not resolve a pointer' "$root" \
  'no .## §sample. heading'

# --- usage ------------------------------------------------------------------

# A relative root belongs to the caller's directory. Resolving it after a cd
# into this repository would check this repository and report it clean, so a
# broken fixture would pass while appearing to have been validated.
root=$(tree root-relative)
printf -- '---\nname: demo\ndescription: Does a thing: usefully.\n---\n' \
  >"$root/demo/SKILL.md"
out=$(cd "$(dirname "$root")" && "$CHECK" skills 2>/dev/null)
status=$?
if [ "$status" = 1 ] && grep -q 'frontmatter' <<<"$out"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL ($status != 1): a relative root resolves against the caller" >&2
  printf '%s\n' "$out" | sed 's/^/  | /' >&2
fi


status=0
"$CHECK" --bogus >/dev/null 2>&1 || status=$?
if [ "$status" = 2 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL ($status != 2): an unknown option is a usage error" >&2
fi

status=0
"$CHECK" skills skills >/dev/null 2>&1 || status=$?
if [ "$status" = 2 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL ($status != 2): a second positional is a usage error" >&2
fi

status=0
"$CHECK" "$work/no-such-dir" >/dev/null 2>&1 || status=$?
if [ "$status" = 2 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL ($status != 2): a missing directory is an environment error" >&2
fi

note=""
[ "$skip" -eq 0 ] || note=", $skip skipped (see SKIP above)"
echo "skill-structure matrix: $pass passed, $fail failed$note"
[ "$fail" -eq 0 ]
