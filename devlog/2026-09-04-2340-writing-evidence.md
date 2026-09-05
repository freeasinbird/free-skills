# Preserve Evidence in Rewrite Examples

Chose faithful rewrites over silently adding facts to make examples more
concrete. Several rewrite-table rows supplied checks, counts, reasons, or
certainty absent from their source. This contradicted write-plainly's
existing correctness-over-brevity rule.

The review-status row retains a concrete rewrite with explicit supplied
context immediately before the table. Other affected rows preserve only
their source's meaning. A blanket assumption that the writer knows more
would hide the defect instead of teaching factual preservation.

The preservation fixtures grade facts separately from readability. A
supported-checks control catches the opposite mistake: deleting evidence
that was supplied. The small comparison gives directional observations;
it does not establish general reliability.

This keeps the decisions in
[the original skill note](2026-08-28-0801-write-plainly-skill.md): general
writing guidance, examples outside the entry point, and correctness ahead
of brevity. It changes neither the skill's trigger nor its voice.

Revisit when faithful examples still produce invented evidence, or when
repeated comparisons show that the entry-point rules need to change.
