#!/usr/bin/env bash
# Regenerate manifests/duwende/context.yaml: the Hermes knowledge-base
# ConfigMap from the local homelab-context docs. CREDENTIALS.md is excluded.
#
#   ./scripts/generate-duwende-context.sh
#   HOMELAB_CONTEXT_DIR=/path/to/homelab-context ./scripts/generate-duwende-context.sh
set -euo pipefail

SRC="${HOMELAB_CONTEXT_DIR:-$HOME/projects/homelab-context}"
OUT="${1:-manifests/duwende/context.yaml}"
DOCS=(AGENTS.md INVENTORY.md KNOWN-ISSUES.md MEDIA.md NEXT-STEPS.md PLATFORM-MIGRATION.md README.md RUNBOOK.md SYSTEM.md)

{
  printf '%s\n' \
    '# Homelab context for the Hermes agent. GENERATED; do not edit by hand.' \
    '# Source: ~/projects/homelab-context (CREDENTIALS.md excluded).' \
    '# Regenerate: scripts/generate-duwende-context.sh' \
    'apiVersion: v1' \
    'kind: ConfigMap' \
    'metadata:' \
    '  name: homelab-context' \
    '  namespace: duwende' \
    'data:'
  for f in "${DOCS[@]}"; do
    if [ ! -f "$SRC/$f" ]; then echo "missing $SRC/$f" >&2; exit 1; fi
    printf '  %s: |\n' "$f"
    sed 's/^/    /' "$SRC/$f"
  done
} > "$OUT"

echo "wrote $OUT ($(wc -l <"$OUT") lines, ${#DOCS[@]} docs)"
