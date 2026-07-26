#!/usr/bin/env bash
# Validation matrix for scripts/check-skill-structure.sh.
#
# Two kinds of case, per the AGENTS.md "enumerate once as tests" rule:
# boundaries of each rule (a 15- vs a 16-line paragraph, --clip against
# --clip-pad, a pointer wrapped across two lines), and the deliberate
# under-reports, which are pinned as passing cases so nobody "fixes" one into
# a false finding later.
#
# Exit codes: 0 all cases passed, 1 any failed.
set -u

CHECK="${SKILL_STRUCTURE_CHECK:-$(cd "$(dirname "$0")" && pwd)/check-skill-structure.sh}"
[ -x "$CHECK" ] || {
  echo "not executable: $CHECK" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0
fail=0

# tree <slug>: fresh skills root holding one valid skill, "demo"; echoes its
# path. The slug names the fixture and must be unique: `tree` runs in a
# command substitution, so a counter would not survive the subshell, and a
# reused directory would leak one case's fixture into the next.
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

lines() { # lines <file> <line>...
  file="$1"
  shift
  printf '%s\n' "$@" >>"$file"
}

repeat() { # repeat <file> <count> <text>
  file="$1" count="$2" text="$3"
  i=0
  while [ "$i" -lt "$count" ]; do
    printf '%s\n' "$text" >>"$file"
    i=$((i + 1))
  done
}

demo_sh() { # demo_sh <root> <case-arm>...
  root="$1"
  shift
  {
    printf '#!/usr/bin/env bash\ncase "$1" in\n'
    printf '  %s) ;;\n' "$@"
    printf 'esac\n'
  } >"$root/demo/demo.sh"
}

demo_ref() { # demo_ref <root> <section-slug>...
  root="$1"
  shift
  mkdir -p "$root/demo/references"
  {
    printf '# Hazards\n\n'
    printf '## §%s\n\nText.\n\n' "$@"
  } >"$root/demo/references/haz.md"
}

# t <expected-exit> <description> <root> [regex]: run the check on <root>,
# assert the exit code and, when given, that stdout matches.
t() {
  expected="$1" desc="$2" root="$3" pattern="${4:-}"
  out=$("$CHECK" "$root" 2>/dev/null)
  status=$?
  ok=1
  [ "$status" = "$expected" ] || ok=0
  # Patterns start with "--" as often as not, so grep takes -- first. A
  # leading "!" inverts the match.
  case "$pattern" in
    '') ;;
    '!'*) grep -qE -- "${pattern#!}" <<<"$out" && ok=0 ;;
    *) grep -qE -- "$pattern" <<<"$out" || ok=0 ;;
  esac
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

for spec in \
  'fm-plain:description: Does a thing.' \
  'fm-colon:description: Does a thing: usefully.' \
  'fm-quoted:description: "Does a thing."' \
  'fm-fold:description: >'; do
  root=$(tree "${spec%%:*}")
  printf -- '---\nname: demo\n%s\n  Body.\n---\n' "${spec#*:}" \
    >"$root/demo/SKILL.md"
  t 1 "description rejected: ${spec#*:}" "$root" 'block scalar'
done

# A comment after the header is still that block scalar.
root=$(tree fm-commented-description)
printf -- '---\nname: demo\ndescription: >- # folded and stripped\n  A thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'an inline comment after the description header passes' "$root"

# A quoted key is the same key, and a quoted or commented name value loads to
# the same string, so neither may read as a mismatch.
root=$(tree fm-quoted-key)
printf -- "---\nname: demo # the directory name\n'description': >-\n  A thing.\n---\n" \
  >"$root/demo/SKILL.md"
t 0 'a quoted key and a commented name pass' "$root"

root=$(tree fm-quoted-name)
printf -- "---\nname: 'demo'\ndescription: >-\n  A thing.\n---\n" \
  >"$root/demo/SKILL.md"
t 0 'a quoted name matching the directory passes' "$root"

root=$(tree fm-name-mismatch)
printf -- "---\nname: 'other'\ndescription: >-\n  A thing.\n---\n" \
  >"$root/demo/SKILL.md"
t 1 'a name not matching the directory is rejected' "$root" 'does not match'

root=$(tree fm-no-name)
printf -- '---\ndescription: >-\n  A thing.\n---\n' >"$root/demo/SKILL.md"
t 1 'missing name rejected' "$root" 'no name key'

root=$(tree fm-unterminated)
printf -- '---\nname: demo\ndescription: >-\n  A thing.\n' >"$root/demo/SKILL.md"
t 1 'unterminated frontmatter rejected' "$root" 'no closing'

root=$(tree fm-no-open)
printf -- '# Demo\n\nNo frontmatter at all.\n' >"$root/demo/SKILL.md"
t 1 'missing frontmatter rejected' "$root" 'does not open'

root=$(tree fm-no-entry)
rm "$root/demo/SKILL.md"
t 1 'skill directory without SKILL.md rejected' "$root" 'no SKILL.md'

# A mapping indented consistently still loads, so rejecting it would fail a
# valid skill: prettier leaves this shape alone and PyYAML reads it.
root=$(tree fm-indented-mapping)
printf -- '---\n  name: demo\n  description: >-\n    A thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'a consistently indented frontmatter mapping passes' "$root"

# YAML forbids tabs for indentation, so a tab-indented mapping does not load
# and its keys are not keys. Accepting the base indentation must not bless it.
root=$(tree fm-tab-indented)
printf -- '---\n\tname: demo\n\tdescription: >-\n\t\tA thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a tab-indented mapping is rejected' "$root" 'no name key'

# A `>-` header promises a folded block, so an unindented body means nothing
# loads: completing that rule, not validating YAML at large.
root=$(tree fm-unindented-body)
printf -- '---\nname: demo\ndescription: >-\nA thing at column zero.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'an unindented description body is rejected' "$root" 'not indented past its key'

# A body line that dedents to the mapping's own indentation ends the block
# with something no loader accepts, wherever in the block it happens.
# An indentless sequence under a key loads fine, so its items are content
# rather than stray lines: extensible metadata must not be blocked.
root=$(tree fm-indentless-sequence)
printf -- '---\nname: demo\ndescription: >-\n  A thing.\ntags:\n- one\n- two\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'an indentless sequence passes' "$root"

root=$(tree fm-dedented-body)
printf -- '---\nname: demo\ndescription: >-\n  first line\nback at column zero\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a later dedented body line is rejected' "$root" 'neither a key'

root=$(tree fm-tab-body)
printf -- '---\nname: demo\ndescription: >-\n  first line\n\tsecond line\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a tab-indented body line is rejected' "$root" 'tab'

# A comment says nothing about the mapping's indentation, so it must not set
# the base and hide both keys.
root=$(tree fm-indented-after-comment)
printf -- '---\n# A comment at column zero.\n  name: demo\n  description: >-\n    A thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 0 'a comment before an indented mapping does not hide its keys' "$root"

# ...and the rules still apply at that indentation.
root=$(tree fm-indented-mismatch)
printf -- '---\n  name: other\n  description: >-\n    A thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'an indented name still has to match the directory' "$root" 'does not match'

# A quote must be closed by its own kind: `'name": demo` is not the key
# `name`, and reading it as one would call broken frontmatter clean.
for spec in "mixed:'name\": demo" 'unclosed:"name: demo' "trailing:name': demo"; do
  root=$(tree "fm-quote-${spec%%:*}")
  printf -- '---\n%s\ndescription: >-\n  A thing.\n---\n' "${spec#*:}" \
    >"$root/demo/SKILL.md"
  t 1 "a mismatched key quote is not a key: ${spec#*:}" "$root" 'no name key'
done

# The loader keeps the last value, so a duplicate is how a wrong name hides.
# YAML allows whitespace before the colon, and both spellings are one key.
root=$(tree fm-duplicate)
printf -- '---\nname : wrong\nname: demo\ndescription: >-\n  A thing.\n---\n' \
  >"$root/demo/SKILL.md"
t 1 'a duplicate key written either way is rejected' "$root" 'duplicate key name'

# --- paragraph length -------------------------------------------------------

root=$(tree para-15)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 15 'A line of ordinary prose.'
t 0 'a 15-line paragraph passes' "$root"

root=$(tree para-16)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 16 'A line of ordinary prose.'
t 1 'a 16-line paragraph is a finding' "$root" 'paragraph: 16 lines'

# Bold and code spans open real paragraphs; treating their punctuation as a
# list or fence marker would have cost four of the twelve findings this rule
# was built from.
for lead in '**Bold lead.** A line of prose.' '`code` then a line of prose.'; do
  root=$(tree "para-lead-$(printf '%s' "$lead" | tr -cd 'a-z' | cut -c1-6)")
  lines "$root/demo/SKILL.md" ''
  repeat "$root/demo/SKILL.md" 16 "$lead"
  t 1 "a paragraph opening with markup counts: $lead" "$root" 'paragraph: 16 lines'
done

# The finding anchors to the paragraph's first line.
root=$(tree para-anchor)
lines "$root/demo/SKILL.md" '' '```sh' 'echo hi' '```' ''
repeat "$root/demo/SKILL.md" 16 'A line of ordinary prose.'
t 1 'the finding anchors to the first prose line' "$root" 'SKILL.md:16: paragraph'

# A paragraph running to EOF with no trailing blank still counts.
root=$(tree para-eof)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 15 'A line of ordinary prose.'
printf 'A sixteenth line with no trailing newline.' >>"$root/demo/SKILL.md"
t 1 'a paragraph running to EOF is flushed' "$root" 'paragraph: 16 lines'

# Structures the rule refuses to measure. Each is a construct where deciding
# what markdown renders needs a parser, so the rule skips it: a miss costs a
# review comment, a false finding costs whoever hits it a debugging pass.
# These pass by design, not by accident.
root=$(tree para-list)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 20 '- A bullet, with its own body text.'
t 0 'a 20-bullet list passes' "$root"

root=$(tree para-list-body)
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

root=$(tree para-quote)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 20 '> A quoted line of prose.'
t 0 'a quoted block is skipped, by design' "$root"

root=$(tree para-html)
lines "$root/demo/SKILL.md" '' '<div>'
repeat "$root/demo/SKILL.md" 20 'raw html content line'
lines "$root/demo/SKILL.md" '</div>'
t 0 'a raw HTML block is skipped, by design' "$root"

root=$(tree para-indented)
lines "$root/demo/SKILL.md" ''
repeat "$root/demo/SKILL.md" 20 '  an indented line of prose'
t 0 'an indented block is skipped, by design' "$root"

# Frontmatter is not prose: a long description is not a paragraph finding.
root=$(tree para-description)
printf -- '---\nname: demo\ndescription: >-\n' >"$root/demo/SKILL.md"
repeat "$root/demo/SKILL.md" 20 '  A line of the description.'
lines "$root/demo/SKILL.md" '---' '' '# Demo'
t 0 'a 20-line description is not a paragraph finding' "$root"

# --- flag parity ------------------------------------------------------------

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

# Prose anywhere under the skill counts, references included, since the
# reader following a pointer lands there too.
root=$(tree flags-reference-doc)
demo_sh "$root" '--pr'
mkdir -p "$root/demo/references"
printf -- '# Ref\n\nPass `--pr <n>` to name the PR.\n' \
  >"$root/demo/references/ref.md"
lines "$root/demo/SKILL.md" '' 'See the reference for details.'
t 0 'documentation in a reference file counts' "$root"

# An unterminated comment hides the rest of the file, so a flag left in an
# unfinished note documents nothing.
root=$(tree flags-unterminated-comment)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' '<!-- TODO: document `--pr` properly'
t 1 'a flag in an unterminated comment is undocumented' "$root" 'flags: --pr'

# A mention of a longer option does not document a shorter one: `--api_key`
# is not `--api`, so the boundary has to know underscores too.
root=$(tree flags-underscore-boundary)
demo_sh "$root" '--api'
lines "$root/demo/SKILL.md" '' 'Pass `--api_key` for the credential.'
t 1 'a longer underscored option does not document a shorter one' "$root" \
  'flags: --api '

# Underscores are legal in a long option, in both parity directions.
root=$(tree flags-underscore)
demo_sh "$root" '--api_key'
t 1 'an underscored parsed flag is checked' "$root" 'flags: --api_key'

root=$(tree flags-underscore-invented)
demo_sh "$root" '--api_key'
lines "$root/demo/SKILL.md" '' 'Pass `--api_key`:' '' '```sh' \
  './demo.sh --api_key x --other_flag' '```'
t 1 'an underscored invented flag is reported' "$root" '--other_flag is passed'

# Documentation a reader cannot see is not documentation.
root=$(tree flags-commented-out)
demo_sh "$root" '--pr|--danger'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`.' '' '<!-- TODO: document --danger -->'
t 1 'a flag mentioned only in an HTML comment is undocumented' "$root" \
  '--danger is parsed here'

# --clip must not be satisfied by a --clip-pad mention: the match needs a
# right boundary, or a prefix flag hides an undocumented one.
root=$(tree flags-prefix)
demo_sh "$root" '--clip'
lines "$root/demo/SKILL.md" '' 'Pass `--clip-pad 12` for padding.'
t 1 '--clip-pad does not document --clip' "$root" 'flags: --clip '

# .mjs: the option map and an explicit comparison both count as parsing, and
# a passthrough default in an array literal does not.
# Both JavaScript quote styles parse, in both forms.
root=$(tree flags-mjs)
{
  printf 'const keyOf = {\n'
  printf "  '--url': 'url',\n"
  printf '  "--out": "out",\n'
  printf '};\n'
  printf "if (opt === '--dark') raw.dark = true;\n"
  printf 'if (opt === "--quiet") raw.quiet = true;\n'
  printf "const CHROME = ['--disable-gpu', '--mute-audio'];\n"
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--url`, `--out`, `--dark`, `--quiet`.'
t 0 'mjs map keys and comparisons parse in either quote style' "$root"
t 0 'an array-literal flag is not a parsed flag' "$root" '!disable-gpu'

# A flag named only in a comment is not parsed, so demanding documentation
# for it would fail valid work. Both comment styles, several spans on one
# line, and a URL is not a comment.
root=$(tree flags-mjs-comments)
{
  printf 'const keyOf = {\n'
  printf '  "--url": "url",  // the page to open, e.g. http://example.com\n'
  printf '};\n'
  printf "// Previously: opt === '--legacy'\n"
  printf '/* also gone:\n'
  printf "   opt === '--ancient'\n"
  printf '*/\n'
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--url`.'
t 0 'flags named only in JavaScript comments are not parsed' "$root"

# A label may mix a short alias with a long option, or attach a value.
# Rejecting the whole label would both miss the flags it parses and report a
# documented example as inventing them.
root=$(tree flags-mixed-label)
{
  printf '#!/usr/bin/env bash\ncase "$1" in\n'
  printf '  -h|--help) ;;\n'
  printf '  --output=*) ;;\n'
  printf '  *) ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--help` or `--output=<path>`:' '' '```sh' \
  './demo.sh --help' './demo.sh --output=/tmp/x' '```'
t 0 'long options are extracted from a mixed case label' "$root"

# ...and they are still required to be documented.
root=$(tree flags-mixed-label-undocumented)
{
  printf '#!/usr/bin/env bash\ncase "$1" in\n'
  printf '  -h|--help) ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
t 1 'a long option behind a short alias is still checked' "$root" 'flags: --help'

# An arm may share the opener's line, and that label is read. A *second*
# arm on the same line is not: finding it meant splitting on `;;`, which a
# quoted terminator then turned into a false finding. One label per line is
# the trade, and it is the safe direction.
root=$(tree flags-inline-arm)
{
  printf '#!/usr/bin/env bash\n'
  printf 'case "$1" in --secret) ;; --other) ;; esac\n'
} >"$root/demo/demo.sh"
t 1 'the label on the opener line is parsed' "$root" 'flags: --secret'

# Bash accepts spaces around the alternation and an optional leading
# parenthesis. Rejecting either both hid the flags and reported a documented
# example as inventing them.
for spec in 'spaced:  --one | --two) ;;' 'parens:  (--one|--two) ;;'; do
  root=$(tree "flags-label-${spec%%:*}")
  {
    printf '#!/usr/bin/env bash\ncase "$1" in\n'
    printf '%s\n' "${spec#*:}"
    printf 'esac\n'
  } >"$root/demo/demo.sh"
  lines "$root/demo/SKILL.md" '' 'Pass `--one`:' '' '```sh' \
    './demo.sh --one value' '```'
  t 1 "a ${spec%%:*} label parses its alternatives" "$root" 'flags: --two'
done

# A long option may carry any letter case, in both parity directions.
root=$(tree flags-mixed-case)
demo_sh "$root" '--API-key'
t 1 'a mixed-case parsed flag is checked' "$root" 'flags: --API-key'

root=$(tree flags-mixed-case-invented)
demo_sh "$root" '--API-key'
lines "$root/demo/SKILL.md" '' 'Pass `--API-key`:' '' '```sh' \
  './demo.sh --API-key x --Other' '```'
t 1 'a mixed-case invented flag is reported' "$root" '--Other is passed'

# A quoted `;;` or a quoted label inside an arm body invents nothing.
root=$(tree flags-quoted-terminator)
{
  printf '#!/usr/bin/env bash\ncase "$1" in\n'
  printf "  --ok) printf '%%s\\\\n' ';; --legacy)' ;;\n"
  printf 'esac\n'
} >"$root/demo/demo.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--ok`.'
t 0 'a quoted arm terminator does not invent a label' "$root"

# A key or a switch label may share its line with other code.
# A `//` comment may follow a colon with no space, which is not a URL.
# A comment may follow a colon with no space at all, and a URL inside a
# string is still not a comment.
root=$(tree flags-mjs-nospace-comment)
{
  printf 'const config = {\n'
  printf '  home: "http://example.com/x",\n'
  printf "  fallback://if (opt == '--legacy')\n"
  printf '};\n'
} >"$root/demo/capture.mjs"
t 0 'a no-space comment after a colon is not executable code' "$root"

root=$(tree flags-mjs-colon-comment)
{
  printf 'const config = {\n'
  printf '  home: "http://example.com/x",\n'
  printf "  fallback:// if (opt === '--legacy')\n"
  printf '};\n'
} >"$root/demo/capture.mjs"
t 0 'a comment after a colon is not executable code' "$root"

root=$(tree flags-mjs-inline)
{
  printf "const handlers = { '--secret': fn, \"--other\": fn };\n"
  printf "switch (opt) { case '--third': break; }\n"
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--secret` or `--other`.'
t 1 'inline keys and switch labels are parsed flags' "$root" 'flags: --third'

# A comparison may be loose or strict, in either operand order.
root=$(tree flags-mjs-loose)
{
  printf "if (opt == '--secret') raw.secret = true;\n"
  printf 'if ("--other" == opt) raw.other = true;\n'
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--secret`.'
t 1 'a loose comparison is a parsed flag' "$root" 'flags: --other'

# A switch arm parses a flag as surely as a comparison does, in either
# quote style.
root=$(tree flags-mjs-switch)
{
  printf 'switch (opt) {\n'
  printf "  case '--secret':\n    break;\n"
  printf '  case "--other":\n    break;\n'
  printf '}\n'
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--secret`.'
t 1 'a switch arm is a parsed flag' "$root" 'flags: --other'

# A comparison may put the flag literal on either side of ===.
root=$(tree flags-mjs-reversed)
{
  printf 'if ("--secret" === opt) raw.secret = true;\n'
  printf "if ('--other' === opt) raw.other = true;\n"
} >"$root/demo/capture.mjs"
lines "$root/demo/SKILL.md" '' 'Pass `--secret`.'
t 1 'a reversed comparison is a parsed flag' "$root" 'flags: --other'

# A redirection takes one operand and the command continues after it.
# A non-shell fence holds a sample of something else, so its lines are not
# invocations and must not fail valid documentation.
# A session transcript prefixes its commands with a prompt.
# Once a transcript uses prompts, its unprompted lines are output, not
# commands, so text in the output that looks like one is not an invocation.
root=$(tree flags-transcript-output)
demo_sh "$root" '--ok'
lines "$root/demo/SKILL.md" '' 'Pass `--ok`:' '' '```console' \
  '$ ./demo.sh --ok' 'usage seen elsewhere: ./demo.sh --bogus' '```'
t 0 'transcript output is not parsed as a command' "$root"

root=$(tree flags-prompt)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```console' \
  '$ ./demo.sh --pr 1 --bogus' '```'
t 1 'a prompt-prefixed command is still an invocation' "$root" '--bogus is passed'

root=$(tree flags-nonshell-fence)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`. Rendered elsewhere as:' '' '```markdown' \
  './demo.sh --bogus' '```'
t 0 'a non-shell fence is not scanned for invocations' "$root"

# An attached redirection ends the token it is attached to.
# A redirection may carry its operand and sit before the command.
# A redirection may carry a file descriptor as well as its operand.
root=$(tree flags-fd-redirection)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  '2>/tmp/log ./demo.sh --bogus' '```'
t 1 'a numbered prefix redirection does not hide the command' "$root" \
  '--bogus is passed'

root=$(tree flags-prefix-redirection)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  '>/tmp/demo.log ./demo.sh --bogus' '```'
t 1 'a prefix redirection does not hide the command' "$root" '--bogus is passed'

root=$(tree flags-attached-redirection)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh --bogus>/tmp/log' '```'
t 1 'an attached redirection does not hide the flag' "$root" '--bogus is passed'

root=$(tree flags-redirection)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh > /tmp/log --bogus' '```'
t 1 'a redirection does not hide later arguments' "$root" '--bogus is passed'

# ...and the redirection operand itself is not read as an argument.
root=$(tree flags-redirection-operand)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh --pr 1 > /tmp/log' '```'
t 0 'a redirection operand is not an argument' "$root"

# `case` and its `in` may sit on separate lines. Missing that ignored every
# arm, which both hid undocumented flags and reported documented ones as
# invented.
root=$(tree flags-split-case-opener)
{
  printf '#!/usr/bin/env bash\ncase "$1"\n'
  printf 'in\n'
  printf '  --pr) ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
t 1 'a case opener split across lines still parses its arms' "$root" 'flags: --pr'

# ...and a documented example against that layout is not read as inventing.
root=$(tree flags-split-case-documented)
{
  printf '#!/usr/bin/env bash\ncase "$1"\n'
  printf 'in\n'
  printf '  --pr) ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' './demo.sh --pr 1' '```'
t 0 'a documented flag from a split opener is not invented' "$root"

# A command substitution closing inside an arm body is not an arm boundary,
# and neither is one on a body line with no label at all.
root=$(tree flags-substitution-body)
{
  printf '#!/usr/bin/env bash\ncase "$1" in\n'
  printf '  run) echo "$(printf -- --legacy)" ;;\n'
  printf '  --pr)\n'
  printf '    echo "$(printf -- --ancient)"\n'
  printf '    ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--pr`.'
t 0 'a command substitution in an arm body is not a label' "$root"

# When the opener splits, its `in` may lead the line the first arm sits on.
root=$(tree flags-split-in-arm)
{
  printf '#!/usr/bin/env bash\ncase "$1"\n'
  printf 'in --secret) ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
t 1 'an arm on the split `in` line is parsed' "$root" 'flags: --secret'

# A comment mentioning the word case is not an opener.
root=$(tree flags-case-in-comment)
{
  printf '#!/usr/bin/env bash\n'
  printf '# Handle each case in turn:\n'
  printf '  --legacy)\n'
  printf 'true\n'
} >"$root/demo/demo.sh"
t 0 'a comment mentioning case does not open a case block' "$root"

# A case pattern may be quoted, in either style, individually per
# alternative. The flag is the same flag.
root=$(tree flags-quoted-case)
{
  printf '#!/usr/bin/env bash\ncase "$1" in\n'
  printf '  "--secret"|\x27--other\x27) ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--secret`.'
t 1 'a quoted case pattern is a parsed flag' "$root" 'flags: --other'

# An arm may read its value on a later line, so arity is read from the whole
# arm. Missing that rejected a valid example as passing an unknown flag.
root=$(tree flags-multiline-arm)
{
  printf '#!/usr/bin/env bash\ncase "$1" in\n'
  printf '  --out)\n'
  printf '    out="$2"\n'
  printf '    shift 2\n'
  printf '    ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--out`:' '' '```sh' \
  './demo.sh --out --filename-starting-with-dashes' '```'
t 0 'a multiline arm still consumes its value' "$root"

# An even run of trailing backslashes is escaped literals, not a
# continuation: the command ends there, and the next line is its own.
root=$(tree flags-escaped-backslash)
demo_sh "$root" '--ok'
lines "$root/demo/SKILL.md" '' 'Pass `--ok`:' '' '```sh' \
  './demo.sh --ok \\' 'echo --bogus' '```'
t 0 'an escaped trailing backslash does not continue the line' "$root"

# Reverse direction: a fenced invocation may only pass flags the script parses.
root=$(tree flags-invented)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Run it:' '' '```sh' './demo.sh --pr 46 --bogus' '```'
t 1 'a fenced example may not invent a flag' "$root" '--bogus is passed to demo.sh'

root=$(tree flags-continuation)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' '```sh' './demo.sh --pr 46 \' '  --bogus' '```'
t 1 'a continuation line is part of the invocation' "$root" '--bogus is passed'

# A flag-shaped token after a known flag is that flag's value:
# `--chrome-flag --no-sandbox` passes a Chrome flag through, and reading the
# value as an invented option would forbid documenting a real invocation.
root=$(tree flags-passthrough)
demo_sh "$root" '--chrome-flag'
lines "$root/demo/SKILL.md" '' 'Pass `--chrome-flag`:' '' '```sh' \
  './demo.sh --chrome-flag --no-sandbox' '```'
t 0 'a passthrough value is not read as an invented flag' "$root"

# Only the segment that runs the script is checked, and only the tokens after
# the script's own token: neighbouring commands, launcher options, and a
# command that merely names the script all own their own flags.
root=$(tree flags-neighbours)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  'gh pr view --json number && ./demo.sh --pr 46 | jq --raw-output .x' \
  './demo.sh --pr 1 & gh pr view --state open' \
  'cp demo.sh /tmp --preserve' \
  'env -u OLD ./demo.sh --pr 2' \
  './demo.sh --pr 1 # --bogus is not passed' \
  '```'
t 0 "neighbouring commands and launcher options keep their own flags" "$root"

# A launcher runs the next plain token. When that is another command, the
# script is only an operand and its flags are not the script's, so the
# segment is skipped: `env cp demo.sh /tmp --preserve` is valid and must not
# be reported.
root=$(tree flags-launcher-other-command)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`. Copy it first:' '' '```sh' \
  'env cp demo.sh /tmp --preserve' '```'
t 0 'a launcher running another command is not an invocation' "$root"

# `env NAME=VALUE ./script` is env's documented signature, so the assignment
# must not stop the scan before the script.
# Launchers nest, and each may carry its own options and assignments.
root=$(tree flags-nested-launchers)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  'sudo env MODE=test ./demo.sh --bogus' '```'
t 1 'nested launchers do not hide the script' "$root" '--bogus is passed'

root=$(tree flags-env-assignment)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  'env MODE=test ./demo.sh --bogus' '```'
t 1 'an env assignment does not hide the script' "$root" '--bogus is passed'

# The cost of that rule, accepted deliberately: a launcher option taking a
# separate value hides the invocation. A missed check, not a false one.
root=$(tree flags-launcher-value-hidden)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  'env -u OLD ./demo.sh --bogus' '```'
t 0 'a launcher option value hides the invocation, by design' "$root"

root=$(tree flags-quoted-operator)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh "a|b" --bogus' '```'
t 1 'a quoted operator does not hide an invented flag' "$root" '--bogus is passed'

# A backslash inside a comment is commented out too, so the next line is a
# separate command rather than a continuation.
root=$(tree flags-comment-continuation)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' '```sh' './demo.sh --pr 1 # note \' \
  './demo.sh --bogus' '```'
t 1 'a comment does not continue onto the next command' "$root" '--bogus is passed'

# Two scripts in one skill may share a basename. Checking each one's
# invocations against the other's flags would report both as inventing the
# other's options, so only the skill-relative path identifies them.
root=$(tree flags-shared-basename)
mkdir -p "$root/demo/a" "$root/demo/b"
for side in a:--one b:--two; do
  {
    printf '#!/usr/bin/env bash\ncase "$1" in\n'
    printf '  %s) ;;\n' "${side#*:}"
    printf 'esac\n'
  } >"$root/demo/${side%%:*}/run.sh"
done
lines "$root/demo/SKILL.md" '' 'Pass `--one` or `--two`:' '' '```sh' \
  './a/run.sh --one' './b/run.sh --two' '```'
t 0 'scripts sharing a basename are told apart' "$root"

# An absolute path is somebody else's command even when the basename matches,
# so its flags are not the skill's and a valid example is not rejected.
# An unrelated relative path sharing a basename is not the skill's script
# either, so its flags are not the skill's.
root=$(tree flags-relative-path)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`. Elsewhere in the tree:' '' '```sh' \
  '../tools/demo.sh --bogus' '```'
t 0 "an unrelated relative path is not the skill's script" "$root"

# The skill-relative spelling is, with or without a leading ./
root=$(tree flags-relative-own)
mkdir -p "$root/demo/scripts"
{
  printf '#!/usr/bin/env bash\ncase "$1" in\n  --pr) ;;\nesac\n'
} >"$root/demo/scripts/run.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './scripts/run.sh --pr 1 --bogus' '```'
t 1 "the skill-relative spelling is the skill's script" "$root" '--bogus is passed'

root=$(tree flags-absolute-path)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`. Elsewhere on the system:' '' '```sh' \
  '/opt/tools/demo.sh --bogus' '```'
t 0 "an absolute path sharing a basename is not the skill's script" "$root"

# A relative or placeholder-prefixed spelling still is, which is how every
# real invocation in this repo is written. Angle brackets in a documented
# path are not redirections: reading them as such split the command so the
# script was never its command word, and this rule was silently inert for
# every skill that writes `<skill-dir>/…`.
root=$(tree flags-placeholder-path)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  '<skill-dir>/demo.sh --pr 1 --bogus' '```'
t 1 'a placeholder-prefixed invocation is checked' "$root" '--bogus is passed'

# ...and an invented flag is still attributed to the right one.
root=$(tree flags-shared-basename-invented)
mkdir -p "$root/demo/a" "$root/demo/b"
for side in a:--one b:--two; do
  {
    printf '#!/usr/bin/env bash\ncase "$1" in\n'
    printf '  %s) ;;\n' "${side#*:}"
    printf 'esac\n'
  } >"$root/demo/${side%%:*}/run.sh"
done
lines "$root/demo/SKILL.md" '' 'Pass `--one` or `--two`:' '' '```sh' \
  './a/run.sh --bogus' './b/run.sh --two' '```'
t 1 'an invented flag is attributed to the right script' "$root" \
  '--bogus is passed to run.sh'

# A case pattern outside a case block is just text. Heredoc bodies and
# printed help are full of option-shaped lines, and demanding documentation
# for them would fail valid skills.
root=$(tree flags-heredoc)
{
  printf '#!/usr/bin/env bash\n'
  printf 'usage() {\n'
  printf '  cat <<EOF\n'
  printf 'Options once supported:\n'
  printf '  --legacy)\n'
  printf 'EOF\n'
  printf '}\n'
  printf 'case "$1" in\n'
  printf '  --pr) ;;\n'
  printf 'esac\n'
} >"$root/demo/demo.sh"
lines "$root/demo/SKILL.md" '' 'Pass `--pr`.'
t 0 'an option-shaped line outside a case block is not a flag' "$root"

# Every recognized flag consumes the token after it, which is what a
# passthrough option needs. The cost, taken deliberately after six review
# rounds spent trying to tell boolean flags from value-taking ones: an
# invented flag written directly after a known flag is not reported. Deciding
# arity needs more of shell and JavaScript than a text scan can hold.
root=$(tree flags-arity-blind-spot)
demo_sh "$root" '--dark'
lines "$root/demo/SKILL.md" '' 'Pass `--dark`:' '' '```sh' \
  './demo.sh --dark --bogus' '```'
t 0 'an option after a known flag is its value, by design' "$root"

# A bare `--` ends option parsing, so what follows is data rather than flags.
root=$(tree flags-end-of-options)
demo_sh "$root" '--pr'
lines "$root/demo/SKILL.md" '' 'Pass `--pr`:' '' '```sh' \
  './demo.sh --pr 1 -- --not-a-flag' '```'
t 0 'a bare -- ends option scanning' "$root"

# --- reference pointers -----------------------------------------------------

root=$(tree ptr-resolve)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' 'A tag can shadow (`references/haz.md` §tag-shadow).'
t 0 'a resolving pointer passes' "$root"

# The regression fixture: prose wraps at ~76 columns, so a pointer routinely
# splits between the file name and the slug. A line-oriented match would call
# §tag-shadow unreferenced, and the "fix" for a false unreferenced reading is
# deleting a section that is very much in use.
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
t 1 'an unreferenced section is a finding' "$root" '§orphan is referenced by no pointer'

# The convention is a level-two section; another level is not a target.
root=$(tree ptr-heading-level)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n### §deep\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §deep).'
t 1 'a level-three heading does not resolve a pointer' "$root" 'no .## §deep. heading'

# Neither a pointer nor a section counts when a reader cannot reach it: a
# fenced example is a sample, and an inline comment is invisible.
root=$(tree ptr-fenced)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' '```md' 'See (`references/haz.md` §tag-shadow).' '```'
t 1 'a pointer inside a fence does not count as a reference' "$root" \
  '§tag-shadow is referenced by no pointer'

root=$(tree ptr-comment)
demo_ref "$root" 'tag-shadow'
lines "$root/demo/SKILL.md" '' 'Text <!-- `references/haz.md` §tag-shadow -->'
t 1 'a pointer inside an inline comment does not count' "$root" \
  '§tag-shadow is referenced by no pointer'

# A comment marker shown inside a fenced sample opens and closes nothing.
# Treating an unmatched one as real hid every live heading after the fence,
# and treating markers in two separate samples as a pair hid the heading
# between them.
# The inverse: a fence marker inside a comment does not open a fence, so the
# comment still closes and live content after it stays visible.
# A four-space fence marker is an indented code line, not an opener. Reading
# it as one swallowed the rest of the file and hid a live heading, which is
# why over-counting fenced lines is not the harmless direction.
# An indented code sample holds pointer-shaped text as text, so it neither
# keeps a section alive nor invents a missing file.
# An unmatched opener inside an indented code sample is literal text, so it
# must not blank the live content after it.
root=$(tree ptr-indented-comment-opener)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\nAn indented sample:\n\n    <!-- unfinished\n\n'
  printf '## §real\n\nText.\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real).'
t 0 'an indented comment opener does not hide later content' "$root"

root=$(tree ptr-indented-code)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §orphan\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'An indented sample:' '' \
  '    See (`references/haz.md` §orphan).'
t 1 'a pointer in indented code does not count' "$root" \
  '§orphan is referenced by no pointer'

# ...while a wrapped pointer inside a list item, which is also indented, does.
# An indented block continues past its first line, blanks included.
# A loose list keeps its blank-separated indented paragraph as prose, so a
# pointer there is live. This is the case that makes "blank then four spaces
# is code" too blunt on its own.
root=$(tree ptr-loose-list)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §live\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' '1. Read this step.' '' \
  '    See (`references/haz.md` §live).'
t 0 'a pointer in a loose list continuation stays live' "$root"

root=$(tree ptr-indented-code-multiline)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §hidden\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'An indented sample:' '' \
  '    first line of the sample' '' \
  '    See (`references/haz.md` §hidden).'
t 1 'a pointer on a later indented line does not count' "$root" \
  '§hidden is referenced by no pointer'

root=$(tree ptr-indented-list)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §real\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' '1. A numbered step:' \
  '   - a bullet naming `references/haz.md`' '     §real for the detail.'
t 0 'a wrapped pointer inside a list still counts' "$root"

# A four-space marker inside a fence does not close it, so the sample after
# it stays code and its heading cannot satisfy a pointer.
root=$(tree ptr-indented-closer)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n## §real\n\nText.\n\n'
  printf '```md\nsample\n    ```\n## §fake\n```\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real) and' \
  '(`references/haz.md` §fake).'
t 1 'an over-indented marker does not close a fence' "$root" \
  'no .## §fake. heading'

root=$(tree ptr-indented-fence-marker)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\nAn indented sample:\n\n    ```\n\n'
  printf '## §live\n\nText.\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §live).'
t 0 'an indented fence marker does not hide later content' "$root"

root=$(tree ptr-comment-holding-fence)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\n<!-- hidden sample\n```md\nnot a real fence\n-->\n\n'
  printf '## §live\n\nText.\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §live).'
t 0 'a fence marker inside a comment does not hide later content' "$root"

root=$(tree ptr-fenced-comment-opener)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\nAn example of an opener:\n\n```md\n<!-- unfinished\n```\n\n'
  printf '## §real\n\nText.\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §real).'
t 0 'a fenced comment opener does not hide later content' "$root"

root=$(tree ptr-fenced-comment-pair)
mkdir -p "$root/demo/references"
{
  printf '# Hazards\n\nAn opener:\n\n```md\n<!--\n```\n\n'
  printf '## §live\n\nText.\n\nA closer:\n\n```md\n-->\n```\n'
} >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' 'See (`references/haz.md` §live).'
t 0 'fenced comment markers do not pair across live content' "$root"

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

# A block boundary need not be blank: a heading ends one too, so a file name
# closing a heading must not pair with a slug opening the prose under it.
root=$(tree ptr-heading-boundary)
mkdir -p "$root/demo/references"
printf '# Hazards\n\n## §orphan\n\nText.\n' >"$root/demo/references/haz.md"
lines "$root/demo/SKILL.md" '' '## See `references/haz.md`' \
  '§orphan is a topic we discuss.'
t 1 'a pointer is not assembled across a heading' "$root" \
  '§orphan is referenced by no pointer'

# --- usage ------------------------------------------------------------------

usage_case() { # usage_case <description> <arg>...
  desc="$1"
  shift
  status=0
  "$CHECK" "$@" >/dev/null 2>&1 || status=$?
  if [ "$status" = 2 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ($status != 2): $desc" >&2
  fi
}

usage_case 'an unknown option is a usage error' --bogus
usage_case 'a second positional is a usage error' skills skills
usage_case 'a missing directory is an environment error' "$work/no-such-dir"

# A relative root belongs to the caller's directory. Resolving it after the
# cd into this repository would check this repository and report it clean,
# so a broken fixture would pass while appearing to have been validated.
root=$(tree root-relative)
printf -- '---\nname: demo\ndescription: Does a thing.\n---\n' >"$root/demo/SKILL.md"
out=$(cd "$(dirname "$root")" && "$CHECK" skills 2>/dev/null)
status=$?
if [ "$status" = 1 ] && grep -q 'block scalar' <<<"$out"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL ($status != 1): a relative root resolves against the caller" >&2
  printf '%s\n' "$out" | sed 's/^/  | /' >&2
fi

echo "skill-structure matrix: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
