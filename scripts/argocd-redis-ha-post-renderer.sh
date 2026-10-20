#!/usr/bin/env bash
set -euo pipefail

# redis-ha 4.38.0 hardcodes the per-pod announce Services as ClusterIP.
# Without headless Services, config-init resolves the Service VIP and sentinel
# monitors the wrong address. Keep publishNotReadyAddresses and make them headless.
#
# The Redis auth Secret is bootstrap-owned, not rendered by this chart. If it
# changes, the StatefulSet must roll so config-init rewrites redis.conf with the
# new password. Add a checksum to the pod template when a cluster context is
# available; helm template without a context simply omits it.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"

auth_rev="$(kubectl -n argocd get secret argocd-redis -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || true)"
auth_hash=""
if [ -n "$auth_rev" ]; then
  auth_hash="$(printf '%s' "$auth_rev" | sha256sum | cut -c1-16)"
fi

awk -v auth_hash="$auth_hash" '
  /^---[[:space:]]*$/ { announce=0; target=0; print; next }
  /^  name:[[:space:]]+.*-announce-[0-9]+[[:space:]]*$/ { announce=1 }
  /^  name:[[:space:]]+argocd-redis-ha-server[[:space:]]*$/ { target=1 }
  /^spec:[[:space:]]*$/ && announce { print; print "  clusterIP: None"; next }
  /^        checksum\/init-config:/ && target {
    print
    if (auth_hash != "") print "        checksum/redis-auth: " auth_hash
    next
  }
  { print }
' "$tmp"
