#!/usr/bin/env bash
# Dogfood check: free-skills' own AGENTS.md must stay byte-identical to
# the canonical source (modulo the nested project:done-checks block,
# which is project-specific by design). Thin strict-mode wrapper over
# the comparator shipped with the agent-setup skill.
set -euo pipefail
cd "$(dirname "$0")/.."
exec skills/agent-setup/scripts/compare-managed-blocks.sh --require-all AGENTS.md
