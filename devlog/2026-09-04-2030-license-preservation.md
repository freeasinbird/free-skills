# Preserve License Choices and Correct the Linking Rationale

The [earlier library decision](2026-06-28-1151-library-mpl-override.md) chose
LGPL as the default and MPL for ecosystems where relinking is burdensome.
Its claim that static linking makes LGPL unenforceable was incorrect.
[The owner accepted correcting that premise in #234](https://github.com/freeasinbird/free-skills/issues/234)
while retaining the licensing choices.

The [GNU linking FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#LGPLStaticVsDynamic)
describes providing application object files for relinking.
[LGPLv3 section 4](https://spdx.org/licenses/LGPL-3.0-only.html)
provides relinking and shared-library routes. The skill and philosophy now
explain the choice through compliance and distribution burden. The philosophy
stays general; the skill names the ecosystems that guide its recommendation.

Keep exact project declarations separate from canonical license fetch keys.
[SPDX's GPL notes](https://spdx.org/licenses/GPL-3.0-only.html) distinguish
the version policies through the project notice. A fetch key or example
notice cannot justify changing `-only` to `-or-later`, and the same rule
governs the notice the skill hands back: an `-only` project drops the
canonical notice's or-later clause. Retention therefore
carries the declaration, evidence, file paths, and companion roles through
README output, without fetching or rewriting license files and notices.

Rejected a fixed GNU suffix and fixed retained filenames because either can
silently change the user's choice. New GNU declarations need an explicit
choice or stated project policy. Missing or conflicting evidence earns a
focused question.

Revisit when the owner changes the licensing policy or a concrete project
requires a license expression outside the five supported families.
