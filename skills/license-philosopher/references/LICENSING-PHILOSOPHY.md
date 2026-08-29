# Licensing Philosophy

We believe the knowledge embedded in source code belongs to everyone. Our licenses protect that belief. What you build with this shared knowledge is yours.

Software is a communal craft. Every project depends on work that came before it: on other people's ideas, discoveries, creations, and generosity. We choose licenses that keep that chain of knowledge open, so anyone who comes after us can learn from, use, and improve what we've built.

The moat in software is execution: infrastructure, platform, service, craft. It doesn't need to be at the level of ideas. If someone builds something valuable using our work, that value belongs to them. But if someone improves the knowledge itself (fixes a bug, refines an algorithm, extends a pattern), that improvement belongs to everyone.

## How We Choose Licenses

We match the license to the type of work.

| Work type                                              | License      |
| ------------------------------------------------------ | ------------ |
| Knowledge artifacts                                    | CC BY-SA 4.0 |
| Libraries where relinking can be honored               | LGPL-3.0     |
| Libraries where static linking or bundling is the norm | MPL-2.0      |
| Standalone applications and tools that run locally     | GPL-3.0      |
| Tools served over a network                            | AGPL-3.0     |

Knowledge artifacts are pure knowledge, so they should remain free
permanently. Anyone who builds on them should extend the same freedom.
Attribution keeps the chain of origin visible.

Library source code is knowledge. You can build whatever you want with it,
but modifications to the library itself return to the commons.

Use the strongest weak-copyleft license the target ecosystem can honor. Use
LGPL-3.0 where relinking can be honored cleanly. Use MPL-2.0 where static
linking or bundling would make LGPL unworkable. An unenforceable license
protects nothing, so choose the tightest copyleft that holds.

Standalone applications and tools that run locally use GPL-3.0. Modifications
must be shared when the modified software is distributed.

Choose between GPL-3.0 and AGPL-3.0 based on how the software reaches its
users.

Tools served over a network use AGPL-3.0. Serving software over a network
doesn't change the nature of the knowledge it contains.

In both cases, modifications to source code are new knowledge, and knowledge
belongs to everyone.
