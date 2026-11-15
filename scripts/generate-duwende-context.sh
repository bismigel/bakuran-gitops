#!/usr/bin/env bash
# Regenerate manifests/base/duwende/context.yaml: the Hermes knowledge-base
# ConfigMap from the local homelab-context docs. CREDENTIALS.md is excluded.
#
#   ./scripts/generate-duwende-context.sh
#   HOMELAB_CONTEXT_DIR=/path/to/homelab-context ./scripts/generate-duwende-context.sh
set -euo pipefail

SRC="${HOMELAB_CONTEXT_DIR:-$HOME/projects/homelab-context}"
OUT="${1:-manifests/base/duwende/context.yaml}"
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
  README.md AGENTS.md OPERATIONS.md
  docs/reference/system.md docs/reference/inventory.md docs/reference/media.md
  docs/plans/platform-migration.md
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
  if ! diff -q "$tmp" "manifests/base/duwende/context.yaml" >/dev/null; then
    echo "FAIL: manifests/base/duwende/context.yaml is stale - run scripts/generate-duwende-context.sh" >&2
    diff -u "manifests/base/duwende/context.yaml" "$tmp" | head -20 >&2
    exit 1
  fi
  echo "context bundle is current ($(grep -c '' manifests/base/duwende/context.yaml) lines, ${#DOCS[@]} docs)"
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
    # A ConfigMap key may only contain [-._a-zA-Z0-9], so a leading path with slashes is not a legal key. Flatten it and
    # REFUSE anything still illegal: illegal keys fail admission, which makes the whole sync fail silently as a retry loop.
    # That is how this bundle sat stale from the KNOWN-ISSUES split until 2026-11-15 while --check reported it current.
    key=$(printf '%s' "$f" | tr '/' '_')
    case "$key" in
      *[!A-Za-z0-9._-]*) echo "illegal ConfigMap key for $f: $key" >&2; exit 1 ;;
      "") echo "empty ConfigMap key for $f" >&2; exit 1 ;;
    esac
    printf '  %s: |\n' "$key"
    sed 's/^/    /' "$SRC/$f"
  done
} > "$OUT"

echo "wrote $OUT ($(wc -l <"$OUT") lines, ${#DOCS[@]} docs)"
