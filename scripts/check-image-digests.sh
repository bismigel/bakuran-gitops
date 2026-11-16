#!/usr/bin/env bash
# Fail if a manifest in this repo names a container image by tag alone.
#
# Why: on 2026-10-30, 44 of 71 distinct image references in the cluster were
# tag-only. A tag is a mutable pointer — the registry can repoint `:3.20` at a
# different image at any time, and the next pod that pulls it runs code nobody
# reviewed. A digest cannot move. This check exists because the manifests are the
# only place we can decide that; chart-provided images (longhorn, cert-manager,
# cilium, argo-cd, ...) never appear in this repo, so they are out of scope here
# and are pinned by their chart's `appVersion` instead.
#
# What it accepts:  image: repo/name:tag@sha256:<64 hex>
# What it rejects:  image: repo/name:tag        image: repo/name@sha256:<tag>
#                   image: repo/name:latest
#
# Exceptions go in .github/image-digest-allowlist with a reason per line, in the
# form `<path>:<image-ref>  # reason`. An exception without a reason is a bug:
# if the image cannot be pinned, say why on the line.
#
# Usage: check-image-digests.sh [root]   (default root: .)
set -euo pipefail

root="${1:-.}"
allowlist="$root/.github/image-digest-allowlist"

# A reference is fine if it carries @sha256:<64>. Anything else is reported.
# Trailing comments are stripped before the test so a commented example cannot
# pass by accident.
fail=0
report=()

while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  lineno="${rest%%:*}"
  text="${rest#*:}"

  ref="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*image:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
  [ -n "$ref" ] || continue

  # Skip anything already pinned, and skip quoted or templated values (a chart
  # value like {{ .Values.image }} is not a reference this check can judge).
  case "$ref" in
    *"@sha256:"*) continue ;;
    *'{{'*) continue ;;
    '""') continue ;;
  esac

  if [ -f "$allowlist" ] && grep -qsF "$file:$ref" "$allowlist"; then
    continue
  fi

  report+=("$file:$lineno  $ref")
done < <(grep -rn --include='*.yaml' --include='*.yml' -E '^[[:space:]]*image:[[:space:]]*[^[:space:]]' "$root/manifests" "$root/clusters" 2>/dev/null || true)

if [ "${#report[@]}" -gt 0 ]; then
  fail=1
  echo "::error::unpinned container image(s) in manifests — a tag can be repointed at different code"
  for r in "${report[@]}"; do
    echo "  $r"
  done
  echo
  echo "Pin the digest that is deployed (the tag stays, for humans):"
  echo "  skopeo inspect --format '{{.Digest}}' docker://<repo>:<tag>"
  echo "  image: <repo>:<tag>@sha256:<digest>"
  echo
  echo "If an image genuinely cannot be pinned, add '<path>:<ref>  # reason' to"
  echo "$allowlist ."
else
  echo "OK: every image reference in manifests/ and clusters/ is pinned by digest."
fi

exit "$fail"
