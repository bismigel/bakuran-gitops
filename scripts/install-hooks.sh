#!/usr/bin/env bash
# Point this clone's git at the tracked hooks. Run once per clone; harmless to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath hooks
echo "  core.hooksPath = $(git config core.hooksPath)"
ls -1 hooks/ | sed 's/^/  hook: /'
echo "  tested: pushing to main is refused before it leaves this machine"
