#!/usr/bin/env bash
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for f in manifests/monitoring/*.yaml; do
  out="$work/$(basename "$f" .yaml).rules.yml"
  yq eval '.data | to_entries[] | select(.value | test("^groups:")) | .value' "$f" > "$out"
  if [ ! -s "$out" ]; then
    rm -f "$out"
  fi
done

if find "$work" -type f -size +0 | grep -q .; then
  promtool check rules "$work"/*.rules.yml
else
  echo "no Prometheus rule ConfigMaps found"
fi
