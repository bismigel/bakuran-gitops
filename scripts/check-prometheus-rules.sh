#!/usr/bin/env bash
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Rules live in the shared base since the base/overlay split (2026-10-29).
# Guard the glob: a path that matches nothing must say so, not fail with a
# confusing yq error when the tree moves again.
shopt -s nullglob
files=(manifests/base/monitoring/*.yaml)
shopt -u nullglob
if [ "${#files[@]}" -eq 0 ]; then
  echo "ERROR: no manifests/base/monitoring/*.yaml — did the tree move again?" >&2
  exit 1
fi
for f in "${files[@]}"; do
  base="$(basename "$f" .yaml)"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    out="$work/${base}-$(printf '%s' "$key" | tr -c 'A-Za-z0-9' '_').rules.yml"
    yq eval ".data[\"$key\"]" "$f" > "$out"
    if ! grep -q '^groups:' "$out"; then
      rm -f "$out"
    fi
  done < <(yq eval '.data | keys[]' "$f")
done

mapfile -t files < <(find "$work" -type f -size +0)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no Prometheus rule ConfigMaps found"
  exit 0
fi

promtool check rules "${files[@]}"

# The scrape config is a second embedded document, and it is the one that broke on
# 2026-11-02: a target went in two spaces short, the whole prometheus.yml stopped parsing,
# and Prometheus crashlooped (exit 2) while `yq` on the *outer* ConfigMap was perfectly
# happy. Rules were validated; the rest of the config was not.
scrape=$(mktemp)
yq eval -r '.data."prometheus.yml" // ""' manifests/base/monitoring/monitoring.yaml > "$scrape"
[ -s "$scrape" ] || { echo "no prometheus.yml in monitoring.yaml — renamed?"; exit 1; }
promtool check config "$scrape"
