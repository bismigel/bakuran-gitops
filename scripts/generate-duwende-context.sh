#!/usr/bin/env bash
# Regenerate manifests/duwende/context.yaml: the Hermes knowledge-base
# ConfigMap from the local homelab-context docs. CREDENTIALS.md is excluded.
#
#   ./scripts/generate-duwende-context.sh
#   HOMELAB_CONTEXT_DIR=/path/to/homelab-context ./scripts/generate-duwende-context.sh
set -euo pipefail

SRC="${HOMELAB_CONTEXT_DIR:-$HOME/projects/homelab-context}"
OUT="${1:-manifests/duwende/context.yaml}"
# The agent's context, chosen rather than globbed. Rules for this list:
#   * entry points and reference docs, not the archive: `docs/history/` and `docs/records/` are dated accounts of what was
#     true then, and handing an agent those as context is how it quotes a five-week-old fact as current;
#   * `known-issues.md` (live list) and `conditions.md` (what the agent can RUN) over their retired predecessors — the
#     tombstones for KNOWN-ISSUES.md and NEXT-STEPS.md are 9 and 12 lines and would only waste bytes;
#   * RUNBOOK.md is gone: it was renamed OPERATIONS.md, and this list was not updated when it was, which broke the generator
#     silently for weeks because nothing ran it (found 2026-11-14 by story 11.6).
# The guides OPERATIONS routes to are included too: an index inside the bundle that points at files the bundle does not carry
# is worse than no index. `OPERATIONS.md` itself stays, as the router.
DOCS=(
  README.md AGENTS.md SYSTEM.md INVENTORY.md
  OPERATIONS.md MEDIA.md PLATFORM-MIGRATION.md
  docs/reference/known-issues.md docs/reference/conditions.md
  docs/guides/cluster.md docs/guides/hosts.md docs/guides/backups.md
  docs/guides/cloudflare.md docs/guides/media-troubleshooting.md
)

# `--check` must be handled BEFORE anything is written: the first version sat after the write block, so
# `--check` created a file literally named `--check` in the repository root and then ran the comparison anyway.
# `--check` is what CI runs: regenerate into a temporary file and compare, so "the bundle is current" is a fact rather than a
# hope. A generated file nobody regenerates is a copy that silently drifts from its source - this one held the retired
# KNOWN-ISSUES and NEXT-STEPS for weeks.
if [ "${OUT}" = "--check" ]; then
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  "${BASH_SOURCE[0]}" "$tmp" >/dev/null
  if ! diff -q "$tmp" "manifests/duwende/context.yaml" >/dev/null; then
    echo "FAIL: manifests/duwende/context.yaml is stale - run scripts/generate-duwende-context.sh" >&2
    diff -u "manifests/duwende/context.yaml" "$tmp" | head -20 >&2
    exit 1
  fi
  echo "context bundle is current ($(grep -c '' manifests/duwende/context.yaml) lines, ${#DOCS[@]} docs)"
  exit 0
fi


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
