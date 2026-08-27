# Writing for Humans: Research Basis

This file explains the evidence behind the `communication` section in
`canonical-sections.md`. It helps maintainers revise that section and isn't
copied into projects.

Evidence has two grades:

- **Replicated:** supported by peer-reviewed research or repeated findings
  across studies.
- **Directional:** supported by industry data or established practice, but
  with weaker direct evidence.

## How People Read on Screens

**Replicated: people scan and read selectively.** A Nielsen Norman Group
analysis compared page-view time for about 45,000 visits with a reading-speed
model. It wasn't an eye-tracking study. The analysis estimated that visitors
could read at most 28% of a page's words, and more realistically about 20%.
See [How Little Do Users Read?](https://www.nngroup.com/articles/how-little-do-users-read/).

Separate eye-tracking studies found an F-shaped pattern in unformatted text.
Readers focus on early lines and the left edge, while much of the middle gets
less attention. The pattern was first described in 2006 and
[revalidated in 2017](https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content/)
on desktop and mobile.

**Replicated: useful headings improve scanning.** Informative headings produce
a layer-cake pattern. Readers scan the headings, then sample the relevant
text. In a 1997 study, Morkes and Nielsen rewrote the same content in several
ways. Usability improved by 58% with concise text, 47% with a scannable layout,
and 27% with objective language. Combining all three improved it by 124%.
See [Concise, Scannable, and Objective](https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/).

**Replicated: experts also prefer plain language.** Domain experts prefer
short, scannable, plain text, just like other readers. See
[Plain Language Is for Everyone, Even Experts](https://www.nngroup.com/articles/plain-language-experts/).

These findings support **Lead with the bottom line**, **Front-load each unit**,
and the section's plain-language requirement.

## Attention and Memory

**Replicated: working memory is small.** Under conditions that limit rehearsal
and grouping, people hold about four items in working memory. See Cowan's 2001
paper, [The Magical Number 4 in Short-Term Memory](https://philpapers.org/rec/COWTMN).

Serial-position studies also show that people recall the first and last items
better than the middle. These findings support **Ask about three questions per
round** and the placement rules. A reader may silently lose questions from a
long list.

## Warning Fatigue

**Replicated: repeated warnings lose attention.** Brain-imaging research found
that visual response drops sharply after the first exposure to a security
warning. A [2015 study](https://dl.acm.org/doi/10.1145/2702123.2702322)
measured the initial effect. A
[2017 study](https://dl.acm.org/doi/10.1145/3025453.3025896) confirmed it
across five days. Warnings that changed appearance resisted this decline
better.

**Replicated: frequent alerts are often ignored.** A
[systematic review](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7400042/)
found average medication-alert override rates from 46.2% to 96.2%. The share
of appropriate overrides varied by alert type. One
[drug-interaction study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8864797/)
found that clinicians overrode 88.2% of very severe interaction alerts.

Applying these results to agent output is an inference. An agent that flags
everything teaches the reader to ignore all flags. This supports **Reserve
flags for meaningful risk**, including a visibly different treatment for rare
critical warnings.

## Reliance on AI Output

**Replicated: people can follow incorrect AI advice.** Explanations alone do
not reliably prevent this. Some methods that force active thought reduced
over-reliance. Examples include deciding before seeing the AI answer, delaying
the recommendation, or revealing advice only after a request.

Buçinca, Malaya, and Gajos tested these methods in
[To Trust or to Think](https://www.eecs.harvard.edu/~kgajos/papers/2021/bucinca21trust.pdf)
(2021). Their explanation and displayed-confidence baselines didn't reduce
reliance on incorrect predictions. A
[Microsoft literature review](https://www.microsoft.com/en-us/research/wp-content/uploads/2022/06/Aether-Overreliance-on-AI-Review-Final-6.21.22.pdf)
summarizes related work.

**Directional: polished output can discourage scrutiny.** Practitioner
reporting says clean, confident AI output may receive less review. See the
[Thoughtworks Technology Radar](https://www.thoughtworks.com/en-us/radar/techniques/complacency-with-ai-generated-code).

These findings support **State uncertainty plainly**. The rule combines honest
verification reporting with the concern that polished prose may hide weak
evidence. Uncertainty displays alone have mixed evidence and remain
directional.

## Other Directional Evidence

- **Bottom line up front:** Military communication and journalism have long
  used the inverted-pyramid structure. Direct controlled comparisons are
  limited, but the practice fits the reading drop-off and serial-position
  findings. See the
  [BLUF overview](<https://en.wikipedia.org/wiki/BLUF_(communication)>).
- **Short, simple email:** Boomerang analyzed 40 million emails, many of them
  sales messages. Messages of 50 to 125 words had the highest response rate,
  about 51%. Messages with one to three questions were 50% more likely to get
  a reply than messages with none. Simpler reading levels also performed
  better. The study wasn't peer-reviewed. See the
  [Boomerang summary](https://blog.boomerangapp.com/2016/02/7-tips-for-getting-more-responses-to-your-emails-with-data/).

## How the Evidence Becomes Rules

The canonical section turns the evidence into six rules:

- **Lead with the bottom line:** reading drop-off and primacy.
- **Front-load each unit:** F-shaped scanning.
- **Layer detail:** readers need a clear skim path without losing the durable
  evidence record.
- **Ask about three questions per round:** working-memory limits and email
  question-count data.
- **Reserve flags for meaningful risk:** warning habituation and alert fatigue.
- **State uncertainty plainly:** polished output can invite complacency, while
  evidence for uncertainty displays alone is mixed.

Revisit this file when new evidence contradicts a graded finding or upgrades a
directional one.
