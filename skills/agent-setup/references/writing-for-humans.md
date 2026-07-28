# Writing for humans: research basis

Evidence behind the canonical `communication` section ("Writing for
humans") in `canonical-sections.md`. This file is maintainer
material for revising that section; it is not copied into projects.
Findings are graded: **replicated** (peer-reviewed or repeatedly
observed across studies) versus **directional** (industry data or
practice-based, useful but weaker).

## How humans read on screens

**Replicated.** A Nielsen Norman Group analysis of instrumented
browsing data (page-view durations for ~45,000 page views against a
reading-speed model; explicitly not an eye-tracking study) estimates
users have time to read at most 28% of the words on a page during
an average visit, more realistically about 20% ([How Little Do Users
Read?](https://www.nngroup.com/articles/how-little-do-users-read/),
2008). Separate eye-tracking studies show unformatted text is
scanned in an F-pattern: the first lines and the left edge get
attention, the middle is skipped (first described 2006, revalidated
on desktop and mobile in
[2017](https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content/)).

Structure changes the behavior: with informative headings, scanning
shifts to a "layer-cake" pattern where headings are read and body
text is sampled. In the Morkes & Nielsen 1997 study
([Concise, Scannable, and
Objective](https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/)),
rewriting the same content improved measured usability 58% from
concision, 47% from scannable layout, and 27% from objective
language; combined, 124%.

Plain language holds for expert audiences: NN/g studies with domain
experts found they prefer succinct, scannable, plain text like
everyone else ([Plain Language Is for Everyone, Even
Experts](https://www.nngroup.com/articles/plain-language-experts/)).

These findings back **Bottom line first**, **Front-load every
unit**, and the plain-language stance.

## Attention and memory limits

**Replicated.** Working memory holds about four chunks when
rehearsal and chunking are restricted (Cowan, ["The magical number 4
in short-term memory"](https://philpapers.org/rec/COWTMN), Behavioral
and Brain Sciences 2001). Classic serial-position results add that
first and last items are recalled best; the middle of a long list or
message is lost first. These back **Few asks per round** and the
placement rules: a human handed many simultaneous open questions
drops most of them silently, not deliberately.

## Warning habituation and alert fatigue

**Replicated.** fMRI work on security warnings shows the brain's
visual processing response drops sharply by the second exposure to
the same warning, with further decline after (Anderson et al.,
[CHI 2015](https://dl.acm.org/doi/10.1145/2702123.2702322); a
[CHI 2017 longitudinal
study](https://dl.acm.org/doi/10.1145/3025453.3025896) confirmed the
effect across a five-day week). Warnings that vary their appearance
("polymorphic") resist habituation substantially.

In clinical
decision support, a systematic review found average medication-alert
override rates of 46.2–96.2% across studies, with the share of
overrides judged appropriate varying widely by alert type
([Appropriateness of Overridden Alerts in CPOE: Systematic
Review](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7400042/));
individual drug-interaction studies sit at the high end (88.2% of
very severe interaction alerts overridden in one
[DDI evaluation](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8864797/)).

The transfer to agent output is an inference, but a direct one: an
agent that hedges and caveats everywhere trains its reader to skip
all flags, including the one that matters. This backs **Ration
flags, and calibrate them**, including making rare critical warnings
look different from routine text.

## Over-reliance on AI output

**Replicated.** Humans over-rely on AI recommendations, following
them even when wrong, and explanations alone do not fix it.
Cognitive forcing functions that compel engagement (deciding before
seeing the AI's answer, a delayed recommendation, advice gated
behind an explicit request) reduced over-reliance on incorrect
predictions where explanation-style baselines, including a
displayed confidence prompt, did not (Buçinca, Malaya & Gajos,
["To Trust or to
Think"](https://www.eecs.harvard.edu/~kgajos/papers/2021/bucinca21trust.pdf),
CSCW 2021; [Microsoft's over-reliance literature
review](https://www.microsoft.com/en-us/research/wp-content/uploads/2022/06/Aether-Overreliance-on-AI-Review-Final-6.21.22.pdf),
2022). Practitioner reporting adds that cleanly formatted,
confident AI output receives less scrutiny, not more
([Thoughtworks Technology
Radar](https://www.thoughtworks.com/en-us/radar/techniques/complacency-with-ai-generated-code)).

The **Surface uncertainty; don't polish past it** rule leans on the
complacency finding (polish suppresses scrutiny) and on stating
verification state honestly. Direct evidence that displaying
uncertainty by itself curbs over-reliance is mixed: Buçinca et
al.'s uncertainty-display baseline did not protect against
incorrect predictions, and the Microsoft review surveys varied
results for confidence displays. Grade uncertainty display alone as
directional, not replicated.

## Directional evidence

- **BLUF / inverted pyramid**: long institutional practice in
  military communication and journalism
  ([overview](<https://en.wikipedia.org/wiki/BLUF_(communication)>)).
  Direct controlled comparisons are thin; the mechanism is consistent
  with the drop-off and serial-position findings above.
- **Boomerang email study** (40M emails, sales-heavy, not
  peer-reviewed): 50–125 word messages got the best response rates
  (~51%); messages asking 1–3 questions were 50% likelier to get a
  reply than those asking none; simpler reading levels outperformed
  college-level prose
  ([summary](https://blog.boomerangapp.com/2016/02/7-tips-for-getting-more-responses-to-your-emails-with-data/)).

## From evidence to rules

The canonical section compresses to six rules: bottom line first
(drop-off, primacy), front-load every unit (F-pattern), layer rather
than shrink (the artifact is also the durable record; skimmability
must not cost the evidence trail), few asks per round with defaults
(working memory, question-count data), ration and calibrate flags
(habituation, alert fatigue), and surface uncertainty (polish
breeds complacency; direct uncertainty-display evidence is mixed,
see above). Revisit this file when new evidence contradicts a graded
finding or upgrades a directional one.
