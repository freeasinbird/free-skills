# Philosophy Libraries lead: name both licenses

Mirrors freeasinbird.com's lead-sentence fix into this repo's philosophy.
The Libraries paragraph opened "**Libraries** are licensed under **LGPL-3.0**."
— asserting LGPL as the sole license before the following sentences qualified
it with the LGPL/MPL split. Lead now reads "**LGPL-3.0** or **MPL-2.0**,
depending on the target ecosystem."

## Decision

- Parallels the **Standalone** paragraph's existing "**GPL-3.0** or
  **AGPL-3.0**, depending on how the software reaches its users." Libraries
  was the odd one out.
- Default/override nuance unchanged — still carried by the "strongest
  weak-copyleft … LGPL where it can be honored cleanly, and MPL where static
  linking or bundling would make LGPL unworkable" sentence.

## Scope

- Both byte-identical philosophy copies (`LICENSING-PHILOSOPHY.md` and the
  skill reference) got the same edit. SKILL.md needs no change — its selection
  table already lists both via the dynamic-link / static-link rows.
