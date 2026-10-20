#!/usr/bin/env bash
set -euo pipefail

# redis-ha 4.38.0 hardcodes the per-pod announce Services as ClusterIP.
# Without headless Services, config-init resolves the Service VIP and sentinel
# monitors the wrong address. Keep publishNotReadyAddresses and make them headless.
awk '
  /^---[[:space:]]*$/ { announce=0; print; next }
  /^  name:[[:space:]]+.*-announce-[0-9]+[[:space:]]*$/ { announce=1 }
  /^spec:[[:space:]]*$/ && announce { print; print "  clusterIP: None"; next }
  { print }
'
