# Key Review and Note Triggers to Risk, Not Size

Chose to define "non-trivial" in the managed fresh-eyes rule and
§pre-push-review by a five-condition risk list that reuses the three
refute-first triggers, over a diff-size threshold and over leaving the word
undefined. Agents read the undefined word as size.
A controlled rerun of a merged 147-file rename spent more on its review
round, commit split, and decision note than on the change, and the rename
touched none of the risk conditions.

Risk means a destructive path, a credential-leak surface, a returned-object
trust boundary, a contract change, or untested behavior. The first three are
the §refute-first triggers. A contract change and untested behavior are
broader conditions that call for fresh eyes but not the refute-first pass.
Nothing enforces agreement between the two lists, so a change to one should
check the other, and the qualifiers must match word for word: the
trust-boundary condition reads "returned-object" in the managed bullet,
§pre-push-review, and §refute-first alike.

The mechanical-change exception rests on CI plus a recorded bot reviewer,
not on size alone, and covers only a mechanical change that touches none of
the risk conditions. A rename that also changes a public interface gets the
pass. A large mechanical change in a repository without a bot reviewer still
gets the fresh-eyes pass. A size threshold was rejected
because a small change on a destructive path needs the pass and a large
rename does not.

The skip-notes bullet names large mechanical changes such as renames, so
size does not read as a note trigger either. The refute-first trigger list
and the rest of the decision-note protocol are unchanged.

Revisit when a mechanical change covered by CI and a bot reviewer ships a
defect the fresh-eyes pass would have caught, or when review effort on
mechanical changes stays high after this wording lands downstream.
