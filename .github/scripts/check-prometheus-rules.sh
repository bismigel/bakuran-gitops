#!/usr/bin/env bash
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for f in manifests/monitoring/*.yaml; do
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
