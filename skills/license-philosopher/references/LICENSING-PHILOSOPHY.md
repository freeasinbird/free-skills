# Licensing Philosophy

We believe the knowledge embedded in source code belongs to everyone. Our licenses protect that belief. What you build with this shared knowledge is yours.

Software is a communal craft. Every project depends on work that came before it — on other people's ideas, discoveries, creations, and generosity. We choose licenses that keep that chain of knowledge open, so anyone who comes after us can learn from, use, and improve what we've built.

The moat in software is execution — infrastructure, platform, service, craft. It doesn't need to be at the level of ideas. If someone builds something valuable using our work, that value belongs to them. But if someone improves the knowledge itself — fixes a bug, refines an algorithm, extends a pattern — that improvement belongs to everyone.

## How we choose licenses

We match the license to the type of work.

**Knowledge artifacts** (prompts, agent skills, patterns, documentation) are licensed under **CC BY-SA 4.0**. As pure knowledge, they should remain free permanently — and anyone who builds on them should extend the same freedom. Attribution keeps the chain of origin visible.

**Libraries** are licensed under **LGPL-3.0**. The source code — the knowledge — stays free. You can build whatever you want with it, but modifications to the library itself return to the commons. Our rule is to use the strongest weak-copyleft license the target ecosystem can actually honor — **LGPL-3.0** where it can be honored cleanly, and **MPL-2.0** where static linking or bundling would make LGPL unworkable. An unenforceable license protects nothing, so we choose the tightest copyleft that holds.

**Standalone applications and tools** are licensed under **GPL-3.0** or **AGPL-3.0**, depending on how the software reaches its users. Tools that run locally use GPL-3.0 — modifications must be shared when the modified software is distributed. Tools deployed as network services use AGPL-3.0 — because serving software over a network doesn't change the nature of the knowledge it contains. In both cases, modifications to source code are new knowledge, and knowledge belongs to everyone.
